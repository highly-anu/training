"""Results on the standards — `performance_logs` (migrations/011_standard_results.sql).

Writers raise: the routes answer 503 and the client keeps what was typed. The
old writer swallowed its error and the route answered "saved" over an insert
that had failed. Readers degrade to empty (analytics and Today must not fail
when the table is missing) but log why.

The table predates migrations/ (supabase/schema.sql); `_ensure_schema` creates
it where it is missing — a test database, local dev — with a TEXT user id, and
adds 011's columns where 011 has not run. The flag is set only after the DDL
returns (program_history's rule). Production's user_id is UUID: never join it
to a TEXT-keyed table in SQL.
"""
from __future__ import annotations

import json
import logging

import psycopg2.extras as _pg_extras

_log = logging.getLogger(__name__)

_SCHEMA_READY = False

_TABLE = '''
CREATE TABLE IF NOT EXISTS performance_logs (
    id           BIGSERIAL PRIMARY KEY,
    user_id      TEXT        NOT NULL,
    benchmark_id TEXT        NOT NULL,
    value        REAL        NOT NULL,
    logged_at    TIMESTAMPTZ NOT NULL
)
'''

# migrations/011, statement by statement, so a refused one is named.
_COLUMNS = (
    "ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS source      TEXT NOT NULL DEFAULT 'manual'",
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS session_uid TEXT',
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS session_key TEXT',
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS workout_id  TEXT',
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS note        TEXT',
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS input       JSONB',
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS logged_on   DATE',
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()',
    'ALTER TABLE performance_logs ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()',
    'CREATE INDEX IF NOT EXISTS idx_performance_logs_user_standard '
    'ON performance_logs (user_id, benchmark_id, logged_at)',
    'CREATE UNIQUE INDEX IF NOT EXISTS uq_performance_logs_user_standard_session '
    'ON performance_logs (user_id, benchmark_id, session_uid) WHERE session_uid IS NOT NULL',
)

_READ = ('id, benchmark_id, value, logged_at, logged_on, source, note, input, '
         'session_uid, session_key, workout_id')


def _ensure_schema() -> bool:
    global _SCHEMA_READY
    if _SCHEMA_READY:
        return True
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    if conn is None:
        return False
    try:
        with conn.cursor() as cur:
            cur.execute(_TABLE)
            for ddl in _COLUMNS:
                cur.execute(ddl)
        _SCHEMA_READY = True
        return True
    except Exception as e:                                  # pragma: no cover
        _log.warning('performance_logs DDL failed: %s', e)
        return False
    finally:
        conn.close()


def _row(r: dict) -> dict:
    return {
        'id': r['id'], 'value': r['value'], 'date': str(r['logged_at']),
        'loggedOn': r['logged_on'].isoformat() if r.get('logged_on') else None,
        'source': r.get('source') or 'manual', 'note': r.get('note'),
        'input': r.get('input'), 'sessionUid': r.get('session_uid'),
        'sessionKey': r.get('session_key'), 'workoutId': r.get('workout_id'),
    }


def list_results(user_id: str) -> dict:
    """{benchmarkId: [entry, …]} oldest first, by the athlete's day."""
    if not _ensure_schema():
        return {}
    from src.db import read_conn
    conn = read_conn()
    if conn is None:
        return {}
    try:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            cur.execute(f'SELECT {_READ} FROM performance_logs WHERE user_id = %s '
                        'ORDER BY logged_at, id', (user_id,))
            rows = cur.fetchall()
    except Exception as e:
        _log.warning('performance_logs read failed: %s', e)
        return {}
    out: dict[str, list[dict]] = {}
    for r in rows:
        out.setdefault(r['benchmark_id'], []).append(_row(r))
    for entries in out.values():
        # The athlete's day decides the order; a legacy row without one keeps
        # its timestamp's place.
        entries.sort(key=lambda e: (e['loggedOn'] or e['date'][:10], e['date'], e['id']))
    return out


def get_result(user_id: str, entry_id: int) -> dict | None:
    if not _ensure_schema():
        raise RuntimeError('no database')
    from src.db import read_conn
    conn = read_conn()
    with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
        cur.execute(f'SELECT {_READ} FROM performance_logs WHERE user_id = %s AND id = %s',
                    (user_id, entry_id))
        r = cur.fetchone()
    return {**_row(r), 'benchmarkId': r['benchmark_id']} if r else None


def add_result(user_id: str, benchmark_id: str, value: float, *, logged_at: str, logged_on: str,
               source: str = 'manual', note: str | None = None, input_: dict | None = None,
               session_uid: str | None = None, session_key: str | None = None,
               workout_id: str | None = None) -> int:
    """Store one result and return its id. Raises."""
    if not _ensure_schema():
        raise RuntimeError('no database')
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    try:
        with conn.cursor() as cur:
            cur.execute(
                'INSERT INTO performance_logs (user_id, benchmark_id, value, logged_at, logged_on, source, '
                'note, input, session_uid, session_key, workout_id) '
                'VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING id',
                (user_id, benchmark_id, value, logged_at, logged_on, source, note,
                 json.dumps(input_) if input_ is not None else None, session_uid, session_key, workout_id))
            return int(cur.fetchone()[0])
    finally:
        conn.close()


_EDITABLE = {'value', 'logged_on', 'note', 'input'}


def update_result(user_id: str, entry_id: int, fields: dict) -> bool:
    """Change a result's value, day, note or input. False when it is not the
    athlete's (or does not exist). Raises on a failed write."""
    sets = {k: v for k, v in fields.items() if k in _EDITABLE}
    if not sets:
        return get_result(user_id, entry_id) is not None
    if not _ensure_schema():
        raise RuntimeError('no database')
    cols = ', '.join(f'{k} = %s' for k in sets)
    params = [json.dumps(v) if k == 'input' and v is not None else v for k, v in sets.items()]
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    try:
        with conn.cursor() as cur:
            cur.execute(f'UPDATE performance_logs SET {cols}, updated_at = NOW() '
                        'WHERE user_id = %s AND id = %s', (*params, user_id, entry_id))
            return cur.rowcount > 0
    finally:
        conn.close()


def delete_result(user_id: str, entry_id: int) -> bool:
    """Delete one result. False when it is not the athlete's. Raises."""
    if not _ensure_schema():
        raise RuntimeError('no database')
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    try:
        with conn.cursor() as cur:
            cur.execute('DELETE FROM performance_logs WHERE user_id = %s AND id = %s', (user_id, entry_id))
            return cur.rowcount > 0
    finally:
        conn.close()


def delete_series(user_id: str, benchmark_id: str) -> int:
    """Every result on one standard — the old `DELETE /health/performance/<id>`,
    kept for installed builds; no screen offers it any more."""
    if not _ensure_schema():
        raise RuntimeError('no database')
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    try:
        with conn.cursor() as cur:
            cur.execute('DELETE FROM performance_logs WHERE user_id = %s AND benchmark_id = %s',
                        (user_id, benchmark_id))
            return cur.rowcount
    finally:
        conn.close()
