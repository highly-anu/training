"""An athlete's own packages: kept in Postgres, laid out as folders for the loader.

A package written at runtime (the LLM package builder, docs/roadmap.md item
20) cannot live where the shipped ones do: the image's disk is lost on every
deploy. It is kept as a file map in `user_packages`
(migrations/013_user_packages.sql) — text YAML, a few hundred KB at most —
and laid out on disk only so the loader can read it as it reads any package:

    <base>/<owner>.<set revision>/<package id>/…      (an overlay: loader.overlay)

`overlay_for(user_id)` names that directory, building it when it is not
there. It is a function of the athlete's installed packages and nothing else,
so every process (and every machine) builds the same one from the same rows;
a changed set is a new directory, built beside the old and swapped in by a
rename, so a reader never sees half of one. Each process asks the database
for an athlete's set at most once a minute; an install or a removal here is
seen at once.

`install` is the only way in: the files pass the limits below, are laid out
with the athlete's other packages in a scratch overlay, and go through every
gate (src/package_gate.py, with the owner's id prefix) before a row is
written. A package that fails is not stored; its problems are the answer.

Private: every read takes the user id, and the table's row security lets an
athlete read only their own rows through PostgREST. Without a database (local
dev) the rows are JSON files under <base>/_rows.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import shutil
import tempfile
import threading
import time

_log = logging.getLogger(__name__)

MAX_FILES = 200
MAX_BYTES = 512 * 1024
MAX_PACKAGES = 20
# What a package folder may hold (src/portability.FILES), all YAML. Records,
# dossiers and tests belong to a package that ships in the repository.
_TOP_LEVEL = {'philosophy.yaml', 'exercises.yaml', 'exercise_media.yaml', 'level_seeds.yaml', 'analytics.yaml',
              'watch.yaml', 'training_contract.yaml', 'standards.yaml', 'vocabulary.yaml', 'fidelity.yaml'}
_NESTED = re.compile(r'^(frameworks/[a-z0-9_]+|archetypes/([a-z0-9_]+/){0,3}[a-z0-9_]+)\.yaml$')
_ID = re.compile(r'^[a-z][a-z0-9_]{2,63}$')
_TTL_SECONDS = 60

_SCHEMA_READY = False
_LOCK = threading.RLock()
_SETS: dict[str, tuple[float, str | None]] = {}   # user id → (asked at, overlay dir or None)
# Until when the table is known not to exist (a write clears it).
_NO_TABLE = {'until': 0.0}
_NO_TABLE_SECONDS = 600

_TABLE = '''
CREATE TABLE IF NOT EXISTS user_packages (
    user_id     TEXT        NOT NULL,
    package_id  TEXT        NOT NULL,
    revision    INTEGER     NOT NULL DEFAULT 1,
    name        TEXT,
    files       JSONB       NOT NULL,
    status      TEXT        NOT NULL DEFAULT 'installed',
    problems    JSONB,
    engine_rev  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMPTZ,
    PRIMARY KEY (user_id, package_id)
)
'''
_RLS = 'ALTER TABLE user_packages ENABLE ROW LEVEL SECURITY'


class StoreError(Exception):
    """A write that did not happen (the routes answer 503)."""


# ── Where things live ─────────────────────────────────────────────────────────

def base_dir() -> str:
    return os.environ.get('TRAINING_USER_PACKAGES_DIR') or os.path.join(tempfile.gettempdir(), 'training-user-packages')


def owner_key(user_id: str) -> str:
    """Eight hex digits of the user id: the owner in a directory name and in
    every id the athlete's packages declare."""
    return hashlib.sha256(str(user_id).encode()).hexdigest()[:8]


def owner_prefix(user_id: str) -> str:
    """The prefix every id an athlete's package declares must carry
    (package_gate.check_package(owner_prefix=))."""
    return f'u{owner_key(user_id)}_'


# ── Limits ────────────────────────────────────────────────────────────────────

def file_problems(files) -> list[dict]:
    """Why a file map cannot be a package, before anything is laid out."""
    def problem(code, message, file=None):
        return {'stage': 'files', 'code': code, 'file': file, 'message': message}
    if not isinstance(files, dict) or not files:
        return [problem('no_files', 'files must be a map of path → YAML text')]
    out = []
    if len(files) > MAX_FILES:
        out.append(problem('too_many_files', f'{len(files)} files; a package holds at most {MAX_FILES}'))
    total = 0
    for path, content in files.items():
        if not isinstance(path, str) or not (path in _TOP_LEVEL or _NESTED.match(path)):
            out.append(problem('path_not_allowed', 'not a file a package holds (philosophy.yaml, exercises.yaml, '
                               'frameworks/<id>.yaml, archetypes/<…>/<id>.yaml, analytics.yaml, watch.yaml, '
                               'training_contract.yaml, standards.yaml, vocabulary.yaml, level_seeds.yaml, '
                               'exercise_media.yaml, fidelity.yaml; lower-case names)', str(path)))
        elif not isinstance(content, str):
            out.append(problem('not_text', 'a file is YAML text', path))
        else:
            total += len(content.encode('utf-8'))
    if total > MAX_BYTES:
        out.append(problem('too_large', f'{total} bytes; a package holds at most {MAX_BYTES}'))
    if 'philosophy.yaml' not in files:
        out.append(problem('no_philosophy', 'no philosophy.yaml', 'philosophy.yaml'))
    return out


def _package_id(files: dict) -> str | None:
    import yaml
    try:
        doc = yaml.safe_load(files.get('philosophy.yaml') or '')
    except yaml.YAMLError:
        return None
    return doc.get('id') if isinstance(doc, dict) and isinstance(doc.get('id'), str) else None


def _name(files: dict) -> str | None:
    import yaml
    try:
        doc = yaml.safe_load(files.get('philosophy.yaml') or '')
    except yaml.YAMLError:
        return None
    return doc.get('name') if isinstance(doc, dict) else None


# ── Rows ──────────────────────────────────────────────────────────────────────

def _conn():
    from src import db
    return db.new_conn(autocommit=True)


def _ensure_schema(conn) -> None:
    """The table where 013 has not run (a test database, local dev): row
    security on and no policy, deny-by-default — the migration adds the
    per-user policy. The flag is set only after the DDL returns."""
    global _SCHEMA_READY
    if _SCHEMA_READY:
        return
    with conn.cursor() as cur:
        cur.execute(_TABLE)
        cur.execute(_RLS)
    _SCHEMA_READY = True


def _rows_dir() -> str:
    return os.path.join(base_dir(), '_rows')


def _rows_path(user_id: str) -> str:
    return os.path.join(_rows_dir(), f'{hashlib.sha256(str(user_id).encode()).hexdigest()[:32]}.json')


def _file_rows(user_id: str) -> dict:
    try:
        with open(_rows_path(user_id), encoding='utf-8') as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _write_file_rows(user_id: str, rows: dict) -> None:
    os.makedirs(_rows_dir(), exist_ok=True)
    tmp = _rows_path(user_id) + f'.{os.getpid()}.{threading.get_ident()}.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(rows, fh)
    os.replace(tmp, _rows_path(user_id))


def _public(row: dict, with_files: bool = False) -> dict:
    out = {'id': row['package_id'], 'name': row.get('name'), 'revision': row['revision'],
           'status': row.get('status') or 'installed', 'problems': row.get('problems'),
           'updatedAt': str(row.get('updated_at') or '') or None}
    if with_files:
        out['files'] = row['files']
    return out


def _live_rows(user_id: str) -> list[dict]:
    """The athlete's packages that are not removed, by id. Raises StoreError
    when the database cannot be read."""
    from src import db
    # The thread's own read connection, never a new one: this runs once a
    # minute for every athlete who asks for a reference route, and production
    # has fifteen pooler slots.
    conn = db.read_conn()
    if conn is None:
        rows = [r for r in _file_rows(user_id).values() if not r.get('deleted_at')]
        return sorted(rows, key=lambda r: r['package_id'])
    if time.monotonic() < _NO_TABLE['until']:
        return []
    try:
        import psycopg2.errors
        import psycopg2.extras
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            try:
                cur.execute('SELECT package_id, revision, name, files, status, problems, updated_at '
                            'FROM user_packages WHERE user_id = %s AND deleted_at IS NULL ORDER BY package_id',
                            (str(user_id),))
            except psycopg2.errors.UndefinedTable:
                # Nobody has installed one here yet (a write, or migration 013,
                # makes the table). Not asked again for a while: every athlete's
                # first reference request would otherwise fail a query a minute.
                _NO_TABLE['until'] = time.monotonic() + _NO_TABLE_SECONDS
                return []
            return [dict(r) for r in cur.fetchall()]
    except Exception as e:
        raise StoreError(f'user_packages not read: {e}') from e


def list_packages(user_id: str) -> list[dict]:
    return [_public(r) for r in _live_rows(user_id)]


def get_package(user_id: str, package_id: str) -> dict | None:
    row = next((r for r in _live_rows(user_id) if r['package_id'] == package_id), None)
    return _public(row, with_files=True) if row else None


def _upsert(user_id: str, package_id: str, files: dict, name: str | None) -> int:
    conn = _conn()
    if conn is None:
        rows = _file_rows(user_id)
        revision = int((rows.get(package_id) or {}).get('revision') or 0) + 1
        rows[package_id] = {'package_id': package_id, 'revision': revision, 'name': name, 'files': files,
                            'status': 'installed', 'problems': None, 'updated_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                            'deleted_at': None}
        _write_file_rows(user_id, rows)
        return revision
    try:
        _ensure_schema(conn)
        _NO_TABLE['until'] = 0.0
        with conn.cursor() as cur:
            cur.execute('''
                INSERT INTO user_packages (user_id, package_id, revision, name, files, status, problems, engine_rev)
                VALUES (%s, %s, 1, %s, %s::jsonb, 'installed', NULL, %s)
                ON CONFLICT (user_id, package_id) DO UPDATE SET
                    revision = user_packages.revision + 1, name = EXCLUDED.name, files = EXCLUDED.files,
                    status = 'installed', problems = NULL, engine_rev = EXCLUDED.engine_rev,
                    updated_at = NOW(), deleted_at = NULL
                RETURNING revision''', (str(user_id), package_id, name, json.dumps(files), engine_rev()))
            return int(cur.fetchone()[0])
    except Exception as e:
        raise StoreError(f'user_packages not written: {e}') from e
    finally:
        conn.close()


def _mark_deleted(user_id: str, package_id: str) -> bool:
    conn = _conn()
    if conn is None:
        rows = _file_rows(user_id)
        row = rows.get(package_id)
        if not row or row.get('deleted_at'):
            return False
        row['deleted_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        _write_file_rows(user_id, rows)
        return True
    try:
        _ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute('UPDATE user_packages SET deleted_at = NOW(), updated_at = NOW() '
                        'WHERE user_id = %s AND package_id = %s AND deleted_at IS NULL', (str(user_id), package_id))
            return cur.rowcount > 0
    except Exception as e:
        raise StoreError(f'user_packages not written: {e}') from e
    finally:
        conn.close()


def engine_rev() -> str:
    """A digest of what a package is checked against — the schemas and the
    commons — so a package installed under an older one can be found and
    checked again after a deploy."""
    from src import loader
    store = loader.view_store('package_store.engine_rev')
    if 'rev' not in store:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        h = hashlib.sha256()
        for folder in (os.path.join(root, 'docs', 'schemas'), os.path.join(root, 'data', 'commons')):
            for base, _dirs, names in sorted(os.walk(folder)):
                for name in sorted(names):
                    if name.endswith(('.json', '.yaml')):
                        with open(os.path.join(base, name), 'rb') as fh:
                            h.update(name.encode() + b'\0' + fh.read())
        store['rev'] = h.hexdigest()[:16]
    return store['rev']


# ── On disk ───────────────────────────────────────────────────────────────────

def _set_revision(rows: list[dict]) -> str:
    return hashlib.sha256(json.dumps([[r['package_id'], r['revision']] for r in rows]).encode()).hexdigest()[:12]


def _lay_out(target: str, rows: list[dict]) -> None:
    """Write `rows` as package folders into `target`, which appears whole or
    not at all: built beside it, then renamed."""
    if os.path.isdir(target):
        return
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='.building-', dir=os.path.dirname(target))
    try:
        for row in rows:
            for rel, content in (row['files'] or {}).items():
                path = os.path.join(tmp, row['package_id'], *rel.split('/'))
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'w', encoding='utf-8') as fh:
                    fh.write(content)
        try:
            os.replace(tmp, target)
        except OSError:
            if not os.path.isdir(target):   # another thread or process did not build it first
                raise
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _sweep(user_id: str, keep: str | None) -> None:
    """Remove the athlete's older overlays, keeping the current one and the
    one before it (a request that started on it may still be reading)."""
    from src import loader
    base, mine = base_dir(), f'{owner_key(user_id)}.'
    try:
        dirs = sorted((os.path.join(base, d) for d in os.listdir(base) if d.startswith(mine)), key=os.path.getmtime)
    except OSError:
        return
    for old in [d for d in dirs if d != keep][:-1]:
        loader.forget_overlay(old)
        shutil.rmtree(old, ignore_errors=True)


def overlay_for(user_id: str | None) -> str | None:
    """The athlete's overlay directory, or None when they have no package of
    their own (or the store cannot be read: the shipped packages alone)."""
    if not user_id:
        return None
    now = time.monotonic()
    with _LOCK:
        known = _SETS.get(user_id)
        if known and now - known[0] < _TTL_SECONDS and (known[1] is None or os.path.isdir(known[1])):
            return known[1]
    try:
        rows = _live_rows(user_id)
    except StoreError as e:
        _log.warning('%s', e)
        return known[1] if known else None
    path = None
    if rows:
        path = os.path.join(base_dir(), f'{owner_key(user_id)}.{_set_revision(rows)}')
        _lay_out(path, rows)
    with _LOCK:
        _SETS[user_id] = (now, path)
    return path


def forget(user_id: str) -> None:
    """The athlete's set changed here: ask again on the next read."""
    with _LOCK:
        _SETS.pop(user_id, None)


# ── In and out ────────────────────────────────────────────────────────────────

def check(user_id: str, files, *, smoke: bool = True) -> dict:
    """The gate's answer for a file map as this athlete's package, with their
    other packages beside it; nothing is stored. → the gate's result, plus
    `package` (its id) and `prefix`."""
    from src import loader, package_gate
    prefix = owner_prefix(user_id)
    problems = file_problems(files)
    package_id = _package_id(files) if not problems else None
    if not problems and not (package_id and _ID.match(package_id)):
        problems.append({'stage': 'files', 'code': 'bad_id', 'file': 'philosophy.yaml',
                         'message': "philosophy.yaml needs an id of lower-case letters, digits and underscores "
                                    f"starting with '{prefix}'"})
    if problems:
        return {'package': package_id, 'prefix': prefix, 'ok': False, 'problems': problems, 'warnings': [],
                'ran': ['files'], 'skipped': [{'stage': s, 'why': 'the files are not a package yet'}
                                              for s in package_gate.STAGES[1:]], 'tracks': [], 'seconds': 0}
    others = [r for r in _live_rows(user_id) if r['package_id'] != package_id]
    if len(others) >= MAX_PACKAGES:
        return {'package': package_id, 'prefix': prefix, 'ok': False, 'warnings': [], 'ran': ['files'], 'skipped': [],
                'tracks': [], 'seconds': 0, 'problems': [{
                    'stage': 'files', 'code': 'too_many_packages', 'file': None,
                    'message': f'an athlete keeps at most {MAX_PACKAGES} packages; remove one first'}]}
    stage = tempfile.mkdtemp(prefix='.checking-', dir=_ensure_base())
    try:
        _lay_out(os.path.join(stage, 'overlay'), others + [{'package_id': package_id, 'files': files}])
        overlay = os.path.join(stage, 'overlay')
        with loader.overlay(overlay):
            result = package_gate.check_package(os.path.join(overlay, package_id), smoke=smoke, owner_prefix=prefix)
    finally:
        loader.forget_overlay(os.path.join(stage, 'overlay'))
        shutil.rmtree(stage, ignore_errors=True)
    return {**result, 'package': package_id, 'prefix': prefix}


def _ensure_base() -> str:
    os.makedirs(base_dir(), exist_ok=True)
    return base_dir()


def install(user_id: str, files) -> dict:
    """Check, and store when every gate passes. → check()'s result plus
    `installed` and, when stored, `revision`. Raises StoreError when the
    write fails."""
    result = check(user_id, files)
    if not result['ok']:
        return {**result, 'installed': False}
    revision = _upsert(user_id, result['package'], files, _name(files))
    forget(user_id)
    _sweep(user_id, overlay_for(user_id))
    return {**result, 'installed': True, 'revision': revision}


def remove(user_id: str, package_id: str) -> bool:
    """Remove one package (kept as a row, no longer laid out). False when the
    athlete has none by that id. Raises StoreError when the write fails."""
    done = _mark_deleted(user_id, package_id)
    if done:
        forget(user_id)
        _sweep(user_id, overlay_for(user_id))
    return done
