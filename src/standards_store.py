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
    """Delete one result. False when it is not the athlete's. Raises.

    A suggestion it was confirmed from is marked dismissed: the athlete has
    said they do not want it, and a re-saved log must not quietly bring it
    back as "confirmed" with no result behind it."""
    if not _ensure_suggestions():
        raise RuntimeError('no database')
    from src.db import new_conn
    conn = new_conn()
    try:
        with conn, conn.cursor() as cur:
            cur.execute('DELETE FROM performance_logs WHERE user_id = %s AND id = %s', (user_id, entry_id))
            deleted = cur.rowcount > 0
            if deleted:
                cur.execute("UPDATE standard_result_suggestions SET status = 'dismissed', "
                            "performance_log_id = NULL, updated_at = NOW() "
                            'WHERE user_id = %s AND performance_log_id = %s', (user_id, entry_id))
            return deleted
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


# ── suggestions (migrations/012_standard_suggestions.sql) ────────────────────
#
# Results a logged session suggests (src/standard_results.py). A pending row
# is never read as a result; confirm writes the result and marks the row in
# one transaction.

_SUGGESTIONS_READY = False

_SUGGESTIONS_DDL = (
    '''CREATE TABLE IF NOT EXISTS standard_result_suggestions (
        id                 BIGSERIAL   PRIMARY KEY,
        user_id            TEXT        NOT NULL,
        benchmark_id       TEXT        NOT NULL,
        session_uid        TEXT,
        session_key        TEXT,
        workout_id         TEXT,
        log_key            TEXT        GENERATED ALWAYS AS
                               (COALESCE(session_uid, session_key, 'workout:' || workout_id)) STORED,
        exercise_id        TEXT,
        slot_role          TEXT,
        origin             TEXT        NOT NULL,
        source             TEXT        NOT NULL DEFAULT 'session',
        value              REAL        NOT NULL,
        input              JSONB,
        logged_on          DATE,
        status             TEXT        NOT NULL DEFAULT 'pending',
        performance_log_id BIGINT,
        decided_via        TEXT,
        decided_at         TIMESTAMPTZ,
        created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (user_id, benchmark_id, log_key)
    )''',
    'CREATE INDEX IF NOT EXISTS idx_standard_suggestions_user_status '
    'ON standard_result_suggestions (user_id, status)',
    # Deny-by-default without the migration's policy (a test database has no
    # `auth` schema); the server connects as the owner and is not affected.
    'ALTER TABLE standard_result_suggestions ENABLE ROW LEVEL SECURITY',
)

_SUGGESTION_READ = ('id, benchmark_id, session_uid, session_key, workout_id, log_key, exercise_id, '
                    'slot_role, origin, source, value, input, logged_on, status, performance_log_id, '
                    'decided_via, decided_at')


def log_key(session_uid: str | None, session_key: str | None, workout_id: str | None = None) -> str | None:
    """The generated column's value, for querying by it."""
    return session_uid or session_key or (f'workout:{workout_id}' if workout_id else None)


def _ensure_suggestions() -> bool:
    global _SUGGESTIONS_READY
    if _SUGGESTIONS_READY:
        return True
    if not _ensure_schema():
        return False
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    if conn is None:
        return False
    try:
        with conn.cursor() as cur:
            for ddl in _SUGGESTIONS_DDL:
                cur.execute(ddl)
        _SUGGESTIONS_READY = True
        return True
    except Exception as e:                                  # pragma: no cover
        _log.warning('standard_result_suggestions DDL failed: %s', e)
        return False
    finally:
        conn.close()


def _suggestion(r: dict) -> dict:
    return {
        'id': r['id'], 'benchmarkId': r['benchmark_id'], 'sessionUid': r.get('session_uid'),
        'sessionKey': r.get('session_key'), 'workoutId': r.get('workout_id'), 'logKey': r.get('log_key'),
        'exerciseId': r.get('exercise_id'), 'slotRole': r.get('slot_role'), 'origin': r['origin'],
        'source': r.get('source') or 'session', 'value': r['value'], 'input': r.get('input'),
        'loggedOn': r['logged_on'].isoformat() if r.get('logged_on') else None,
        'status': r['status'], 'performanceLogId': r.get('performance_log_id'),
        'decidedVia': r.get('decided_via'),
    }


def upsert_suggestions(user_id: str, rows: list[dict], *, prune_keys: dict[str, set] | None = None) -> None:
    """Write what a log suggests, in one transaction. Raises.

    Each row: benchmarkId, sessionUid, sessionKey, exerciseId, slotRole,
    origin, source, value, input, loggedOn. A pending row takes the new
    value; a confirmed one whose value changed goes back to pending (its
    result is corrected on the next confirm); a dismissed one stays dismissed.
    The day stays the first one seen. A row with `onlyNew` is written only
    where none exists (a GPS best effort never overwrites what the athlete
    logged for that test). `prune_keys` {log_key: {benchmark ids still
    suggested}} deletes the pending rows of those logs that the log no longer
    supports (a value cleared, a set deleted)."""
    if not _ensure_suggestions():
        raise RuntimeError('no database')
    from src.db import new_conn
    conn = new_conn()
    try:
        with conn, conn.cursor() as cur:
            for r in rows:
                cur.execute(f'''
                    INSERT INTO standard_result_suggestions
                        (user_id, benchmark_id, session_uid, session_key, workout_id, exercise_id,
                         slot_role, origin, source, value, input, logged_on)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (user_id, benchmark_id, log_key) DO {'NOTHING' if r.get('onlyNew') else """UPDATE SET
                        value       = EXCLUDED.value,
                        input       = EXCLUDED.input,
                        exercise_id = EXCLUDED.exercise_id,
                        slot_role   = EXCLUDED.slot_role,
                        origin      = EXCLUDED.origin,
                        source      = EXCLUDED.source,
                        logged_on   = COALESCE(standard_result_suggestions.logged_on, EXCLUDED.logged_on),
                        status      = CASE
                            WHEN standard_result_suggestions.status = 'confirmed'
                             AND standard_result_suggestions.value IS DISTINCT FROM EXCLUDED.value
                            THEN 'pending'
                            ELSE standard_result_suggestions.status
                        END,
                        updated_at  = NOW()
                    WHERE standard_result_suggestions.value IS DISTINCT FROM EXCLUDED.value
                       OR standard_result_suggestions.input IS DISTINCT FROM EXCLUDED.input"""}
                ''', (user_id, r['benchmarkId'], r.get('sessionUid'), r.get('sessionKey'), r.get('workoutId'),
                      r.get('exerciseId'), r.get('slotRole'), r['origin'], r.get('source') or 'session',
                      r['value'], json.dumps(r['input']) if r.get('input') is not None else None,
                      r.get('loggedOn')))
            for key, keep in (prune_keys or {}).items():
                cur.execute('''
                    DELETE FROM standard_result_suggestions
                    WHERE user_id = %s AND log_key = %s AND status = 'pending'
                      AND origin IN ('test_slot', 'derived_single')
                      AND NOT (benchmark_id = ANY(%s::text[]))
                ''', (user_id, key, sorted(keep)))
    finally:
        conn.close()


def list_suggestions(user_id: str, *, statuses: tuple = ('pending',),
                     log_keys: list[str] | None = None) -> list[dict]:
    """Suggestions in the given statuses, newest day first; [] when the table
    cannot be read (a screen without suggestions rather than an error)."""
    if not _ensure_suggestions():
        return []
    from src.db import read_conn
    conn = read_conn()
    if conn is None:
        return []
    sql = (f'SELECT {_SUGGESTION_READ} FROM standard_result_suggestions '
           'WHERE user_id = %s AND status = ANY(%s::text[])')
    params: list = [user_id, list(statuses)]
    if log_keys is not None:
        sql += ' AND log_key = ANY(%s::text[])'
        params.append(sorted(set(log_keys)))
    sql += ' ORDER BY logged_on DESC NULLS LAST, id DESC'
    try:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            return [_suggestion(r) for r in cur.fetchall()]
    except Exception as e:
        _log.warning('standard_result_suggestions read failed: %s', e)
        return []


def confirm_suggestion(user_id: str, suggestion_id: int, *, via: str, value: float | None = None,
                       input_: dict | None = None) -> dict | None:
    """Make a suggestion a result, in one transaction; None when it is not
    the athlete's. `value`/`input_` replace what was suggested (the athlete
    corrected it). Idempotent: a confirmed suggestion whose result still
    exists answers that result; a test session's result is unique per
    standard and session (migrations/011), so a second confirm updates it.
    Returns the suggestion with `performanceLogId`. Raises."""
    if not _ensure_suggestions():
        raise RuntimeError('no database')
    from src.db import new_conn
    conn = new_conn()
    try:
        with conn, conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            cur.execute(f'SELECT {_SUGGESTION_READ} FROM standard_result_suggestions '
                        'WHERE user_id = %s AND id = %s FOR UPDATE', (user_id, suggestion_id))
            s = cur.fetchone()
            if s is None:
                return None
            new_value = s['value'] if value is None else value
            new_input = s['input'] if value is None else input_
            rid = None
            if s['performance_log_id']:
                if s['status'] == 'confirmed' and value is None:
                    cur.execute('SELECT id FROM performance_logs WHERE user_id = %s AND id = %s',
                                (user_id, s['performance_log_id']))
                    if cur.fetchone():
                        return _suggestion(s)
                cur.execute('UPDATE performance_logs SET value = %s, input = %s, logged_on = %s, '
                            'updated_at = NOW() WHERE user_id = %s AND id = %s RETURNING id',
                            (new_value, json.dumps(new_input) if new_input is not None else None,
                             s['logged_on'], user_id, s['performance_log_id']))
                hit = cur.fetchone()
                rid = hit['id'] if hit else None
            if rid is None:
                params = (user_id, s['benchmark_id'], new_value, s['logged_on'], s['source'],
                          json.dumps(new_input) if new_input is not None else None,
                          s['session_uid'], s['session_key'], s['workout_id'])
                insert = ('INSERT INTO performance_logs (user_id, benchmark_id, value, logged_at, logged_on, '
                          'source, input, session_uid, session_key, workout_id) '
                          'VALUES (%s, %s, %s, NOW(), %s, %s, %s, %s, %s, %s)')
                if s['session_uid']:
                    insert += (' ON CONFLICT (user_id, benchmark_id, session_uid) WHERE session_uid IS NOT NULL '
                               'DO UPDATE SET value = EXCLUDED.value, input = EXCLUDED.input, '
                               'logged_on = EXCLUDED.logged_on, source = EXCLUDED.source, updated_at = NOW()')
                cur.execute(insert + ' RETURNING id', params)
                rid = cur.fetchone()['id']
            cur.execute(f'''UPDATE standard_result_suggestions
                            SET status = 'confirmed', performance_log_id = %s, value = %s, input = %s,
                                decided_via = %s, decided_at = NOW(), updated_at = NOW()
                            WHERE user_id = %s AND id = %s RETURNING {_SUGGESTION_READ}''',
                        (rid, new_value, json.dumps(new_input) if new_input is not None else None,
                         via, user_id, suggestion_id))
            return _suggestion(cur.fetchone())
    finally:
        conn.close()


def set_suggestion_status(user_id: str, suggestion_id: int, status: str, *, via: str,
                          from_statuses: tuple) -> dict | None:
    """Dismiss (from pending) or reopen (from dismissed) one suggestion. None
    when it is not the athlete's or not in a state that allows it. Raises."""
    if not _ensure_suggestions():
        raise RuntimeError('no database')
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    try:
        with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
            cur.execute(f'''UPDATE standard_result_suggestions
                            SET status = %s, decided_via = %s, decided_at = NOW(), updated_at = NOW()
                            WHERE user_id = %s AND id = %s AND status = ANY(%s::text[])
                            RETURNING {_SUGGESTION_READ}''',
                        (status, via, user_id, suggestion_id, list(from_statuses)))
            r = cur.fetchone()
            return _suggestion(r) if r else None
    finally:
        conn.close()


def get_suggestion(user_id: str, suggestion_id: int) -> dict | None:
    if not _ensure_suggestions():
        raise RuntimeError('no database')
    from src.db import read_conn
    conn = read_conn()
    with conn.cursor(cursor_factory=_pg_extras.RealDictCursor) as cur:
        cur.execute(f'SELECT {_SUGGESTION_READ} FROM standard_result_suggestions '
                    'WHERE user_id = %s AND id = %s', (user_id, suggestion_id))
        r = cur.fetchone()
    return _suggestion(r) if r else None
