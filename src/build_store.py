"""The builds of athletes' own methods: `package_builds`
(migrations/014_package_builds.sql; docs/roadmap.md 21.2).

A build is a row because nothing else survives a deploy: the request, the
draft as written so far, the model conversation, the progress the clients
poll, and in the end a result or an error. A worker claims a row
(`claim_next`) and holds it by a heartbeat; a running row whose heartbeat is
older than the lease is claimed again, at most MAX_ATTEMPTS times, and then
failed as interrupted.

Private: every read takes the user id. Without a database (local dev) the
rows are one JSON file under the user-packages folder, guarded by a lock —
one process, as local dev is.
"""
from __future__ import annotations

import json
import logging
import os
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone

_log = logging.getLogger(__name__)

LEASE_SECONDS = 180          # a running row with no heartbeat for this long is claimed again
MAX_ATTEMPTS = 2
OPEN = ('queued', 'running')
_FIELDS = ('id', 'user_id', 'status', 'request', 'draft_files', 'transcript', 'progress', 'result', 'error',
           'usage', 'attempts', 'cancel_requested', 'heartbeat_at', 'created_at', 'updated_at')
_JSON = ('request', 'draft_files', 'transcript', 'progress', 'result', 'error', 'usage')

_SCHEMA_READY = False
_FILE_LOCK = threading.RLock()

_TABLE = '''
CREATE TABLE IF NOT EXISTS package_builds (
    id               TEXT        PRIMARY KEY,
    user_id          TEXT        NOT NULL,
    status           TEXT        NOT NULL DEFAULT 'queued',
    request          JSONB       NOT NULL,
    draft_files      JSONB       NOT NULL DEFAULT '{}'::jsonb,
    transcript       JSONB       NOT NULL DEFAULT '[]'::jsonb,
    progress         JSONB       NOT NULL DEFAULT '{}'::jsonb,
    result           JSONB,
    error            JSONB,
    usage            JSONB       NOT NULL DEFAULT '{}'::jsonb,
    attempts         INTEGER     NOT NULL DEFAULT 0,
    cancel_requested BOOLEAN     NOT NULL DEFAULT FALSE,
    heartbeat_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
)
'''
_DDL = (
    _TABLE,
    'CREATE INDEX IF NOT EXISTS idx_package_builds_user_created ON package_builds (user_id, created_at DESC)',
    "CREATE INDEX IF NOT EXISTS idx_package_builds_open ON package_builds (created_at) "
    "WHERE status IN ('queued', 'running')",
    'ALTER TABLE package_builds ENABLE ROW LEVEL SECURITY',
)


class StoreError(Exception):
    """A read or write that did not happen (the routes answer 503)."""


# ── Postgres ──────────────────────────────────────────────────────────────────

def _pg():
    """This thread's own connection (autocommit): each statement here is one
    row, and the worker thread and each request thread have their own."""
    from src import db
    return db._get_pg_conn()


def _ensure_schema(conn) -> None:
    """The table where 014 has not run (a test database, local Postgres): row
    security on and no policy, deny-by-default. The flag is set only after
    the DDL returns."""
    global _SCHEMA_READY
    if _SCHEMA_READY:
        return
    with conn.cursor() as cur:
        for ddl in _DDL:
            cur.execute(ddl)
    _SCHEMA_READY = True


def _sql(statement: str, params: tuple = (), *, fetch: str | None = None, ensure: bool = False):
    """One statement on the thread's connection. Only a new build makes the
    table (`ensure`); every other statement finds nothing where it is not
    there yet — production before migration 014 — and makes nothing."""
    conn = _pg()
    try:
        import psycopg2.errors
        import psycopg2.extras
        if ensure:
            _ensure_schema(conn)
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            try:
                cur.execute(statement, params)
            except psycopg2.errors.UndefinedTable:
                return None if fetch == 'one' else [] if fetch == 'all' else 0
            if fetch == 'one':
                row = cur.fetchone()
                return dict(row) if row else None
            if fetch == 'all':
                return [dict(r) for r in cur.fetchall()]
            return cur.rowcount
    except Exception as e:
        raise StoreError(f'package_builds: {e}') from e


# ── Files (no database) ───────────────────────────────────────────────────────

def _path() -> str:
    from src import package_store
    return os.path.join(package_store.base_dir(), '_builds', 'builds.json')


def _file_rows() -> dict:
    try:
        with open(_path(), encoding='utf-8') as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _write_file_rows(rows: dict) -> None:
    os.makedirs(os.path.dirname(_path()), exist_ok=True)
    tmp = _path() + f'.{os.getpid()}.{threading.get_ident()}.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(rows, fh)
    os.replace(tmp, _path())


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _age_seconds(stamp) -> float:
    if not stamp:
        return float('inf')
    then = stamp if isinstance(stamp, datetime) else datetime.fromisoformat(str(stamp))
    if then.tzinfo is None:
        then = then.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - then).total_seconds()


# ── Rows ──────────────────────────────────────────────────────────────────────

def create(user_id: str, request: dict, draft_files: dict | None = None) -> dict:
    """A new build, queued."""
    row = {'id': uuid.uuid4().hex, 'user_id': str(user_id), 'status': 'queued', 'request': request,
           'draft_files': draft_files or {}, 'transcript': [], 'progress': {'stage': 'queued'}, 'result': None,
           'error': None, 'usage': {}, 'attempts': 0, 'cancel_requested': False, 'heartbeat_at': None,
           'created_at': _now(), 'updated_at': _now()}
    if _pg() is None:
        with _FILE_LOCK:
            rows = _file_rows()
            rows[row['id']] = row
            _write_file_rows(rows)
        return row
    _sql('INSERT INTO package_builds (id, user_id, request, draft_files, progress) '
         'VALUES (%s, %s, %s::jsonb, %s::jsonb, %s::jsonb)',
         (row['id'], row['user_id'], json.dumps(request), json.dumps(row['draft_files']), json.dumps(row['progress'])),
         ensure=True)
    return get(user_id, row['id'])


def get(user_id: str | None, build_id: str) -> dict | None:
    """One build; `user_id` None is the worker's own read, any other the
    owner's — another athlete's id finds nothing."""
    if _pg() is None:
        row = _file_rows().get(build_id)
        return row if row and (user_id is None or row['user_id'] == str(user_id)) else None
    if user_id is None:
        return _sql('SELECT * FROM package_builds WHERE id = %s', (build_id,), fetch='one')
    return _sql('SELECT * FROM package_builds WHERE id = %s AND user_id = %s', (build_id, str(user_id)), fetch='one')


def recent(user_id: str, limit: int = 5) -> list[dict]:
    """The athlete's builds, newest first: every open one and the last few."""
    if _pg() is None:
        rows = sorted((r for r in _file_rows().values() if r['user_id'] == str(user_id)),
                      key=lambda r: r['created_at'], reverse=True)
        return [r for i, r in enumerate(rows) if i < limit or r['status'] in OPEN]
    return _sql('''SELECT * FROM (
                       SELECT *, ROW_NUMBER() OVER (ORDER BY created_at DESC) AS n
                       FROM package_builds WHERE user_id = %s) b
                   WHERE n <= %s OR status IN ('queued', 'running') ORDER BY created_at DESC''',
                (str(user_id), limit), fetch='all')


_LIGHT = ('id', 'user_id', 'status', 'request', 'progress', 'result', 'error', 'usage', 'attempts', 'created_at',
          'updated_at')


def history(user_id: str, limit: int = 30) -> list[dict]:
    """The athlete's last builds, newest first, without the draft and the
    transcript (hundreds of kilobytes a build): what a list of them reads."""
    if _pg() is None:
        rows = sorted((r for r in _file_rows().values() if r['user_id'] == str(user_id)),
                      key=lambda r: r['created_at'], reverse=True)
        return [{k: r.get(k) for k in _LIGHT} for r in rows[:limit]]
    return _sql(f"SELECT {', '.join(_LIGHT)} FROM package_builds WHERE user_id = %s ORDER BY created_at DESC LIMIT %s",
                (str(user_id), limit), fetch='all')


def active(user_id: str) -> dict | None:
    """The athlete's build that is queued or running, if any."""
    return next((r for r in recent(user_id, 0) if r['status'] in OPEN), None)


def started_since(user_id: str, hours: float = 24) -> int:
    """How many builds the athlete started in the last `hours` (one cancelled
    before a worker took it does not count)."""
    if _pg() is None:
        return sum(1 for r in _file_rows().values() if r['user_id'] == str(user_id)
                   and _age_seconds(r['created_at']) <= hours * 3600
                   and not (r['status'] == 'cancelled' and not r['attempts']))
    row = _sql("SELECT COUNT(*) AS n FROM package_builds WHERE user_id = %s AND created_at > %s "
               "AND NOT (status = 'cancelled' AND attempts = 0)",
               (str(user_id), datetime.now(timezone.utc) - timedelta(hours=hours)), fetch='one')
    return int(row['n']) if row else 0


def has_open() -> bool:
    """Whether any build is waiting or running (the worker's reason to start)."""
    if _pg() is None:
        return any(r['status'] in OPEN for r in _file_rows().values())
    return _sql("SELECT 1 AS x FROM package_builds WHERE status IN ('queued', 'running') LIMIT 1", fetch='one') is not None


def claim_next() -> dict | None:
    """The oldest build a worker may take — queued, or running with a
    heartbeat older than the lease — marked running with a fresh heartbeat. A
    stale one that has used its attempts is failed as interrupted instead."""
    if _pg() is None:
        with _FILE_LOCK:
            rows = _file_rows()
            for row in sorted(rows.values(), key=lambda r: r['created_at']):
                stale = row['status'] == 'running' and _age_seconds(row['heartbeat_at']) > LEASE_SECONDS
                if row['status'] != 'queued' and not stale:
                    continue
                if stale and row['attempts'] >= MAX_ATTEMPTS:
                    row.update(status='failed', error=_INTERRUPTED, updated_at=_now())
                    continue
                row.update(status='running', attempts=row['attempts'] + 1, heartbeat_at=_now(), updated_at=_now())
                _write_file_rows(rows)
                return dict(row)
            _write_file_rows(rows)
            return None
    lease = datetime.now(timezone.utc) - timedelta(seconds=LEASE_SECONDS)
    _sql("UPDATE package_builds SET status = 'failed', error = %s::jsonb, updated_at = NOW() "
         "WHERE status = 'running' AND heartbeat_at < %s AND attempts >= %s",
         (json.dumps(_INTERRUPTED), lease, MAX_ATTEMPTS))
    return _sql('''UPDATE package_builds SET status = 'running', attempts = attempts + 1,
                          heartbeat_at = NOW(), updated_at = NOW()
                   WHERE id = (SELECT id FROM package_builds
                               WHERE status = 'queued' OR (status = 'running' AND heartbeat_at < %s)
                               ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1)
                   RETURNING *''', (lease,), fetch='one')


_INTERRUPTED = {'code': 'interrupted', 'message': 'The build was interrupted twice and was stopped. Try again.'}


def save(build_id: str, **fields) -> None:
    """Write what changed (progress, draft_files, transcript, usage) and beat
    the heart: the worker's one write per turn."""
    allowed = {k: v for k, v in fields.items() if k in ('progress', 'draft_files', 'transcript', 'usage')}
    if _pg() is None:
        with _FILE_LOCK:
            rows = _file_rows()
            if build_id in rows:
                rows[build_id].update(allowed, heartbeat_at=_now(), updated_at=_now())
                _write_file_rows(rows)
        return
    sets = ', '.join(f'{k} = %s::jsonb' for k in allowed)
    _sql(f"UPDATE package_builds SET {sets + ', ' if sets else ''}heartbeat_at = NOW(), updated_at = NOW() WHERE id = %s",
         (*[json.dumps(v) for v in allowed.values()], build_id))


def finish(build_id: str, status: str, *, result: dict | None = None, error: dict | None = None,
           progress: dict | None = None) -> None:
    """End a build: done with its result, failed with why, or cancelled."""
    if _pg() is None:
        with _FILE_LOCK:
            rows = _file_rows()
            if build_id in rows:
                rows[build_id].update(status=status, result=result, error=error, updated_at=_now(),
                                      **({'progress': progress} if progress is not None else {}))
                _write_file_rows(rows)
        return
    _sql('UPDATE package_builds SET status = %s, result = %s::jsonb, error = %s::jsonb, '
         'progress = COALESCE(%s::jsonb, progress), updated_at = NOW() WHERE id = %s',
         (status, json.dumps(result) if result is not None else None,
          json.dumps(error) if error is not None else None,
          json.dumps(progress) if progress is not None else None, build_id))


def request_cancel(user_id: str, build_id: str) -> dict | None:
    """Ask a build to stop: a queued one is cancelled at once, a running one at
    its next turn. None when the athlete has no such build."""
    row = get(user_id, build_id)
    if row is None:
        return None
    if row['status'] == 'queued':
        finish(build_id, 'cancelled', error={'code': 'cancelled', 'message': 'Cancelled.'})
    elif row['status'] == 'running':
        if _pg() is None:
            with _FILE_LOCK:
                rows = _file_rows()
                rows[build_id].update(cancel_requested=True, updated_at=_now())
                _write_file_rows(rows)
        else:
            _sql('UPDATE package_builds SET cancel_requested = TRUE, updated_at = NOW() WHERE id = %s', (build_id,))
    return get(user_id, build_id)


def cancel_requested(build_id: str) -> bool:
    row = get(None, build_id)
    return bool(row and row.get('cancel_requested'))


def public(row: dict) -> dict:
    """A build as the clients read it: never the draft or the transcript."""
    request = row.get('request') or {}
    return {'id': row['id'], 'status': row['status'], 'progress': row.get('progress') or {},
            'result': row.get('result'), 'error': row.get('error'),
            'description': (request.get('description') or '')[:280],
            'revise': (request.get('revise') or {}).get('packageId'),
            'createdAt': str(row.get('created_at') or '') or None,
            'updatedAt': str(row.get('updated_at') or '') or None}
