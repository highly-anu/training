"""daily_wellness persistence (migrations/009_wellness.sql).

`upsert` raises on failure: the route answers 503 and the watch keeps the
reading for its next attempt. Every store writer that swallowed its error has
lost data here before (CLAUDE.md, *A match write must not touch a NOT NULL
column it does not fill*). The readers degrade to empty, because readiness
must not fail when this table is missing.

A watch may post the same day several times — on every app open, and from the
morning background run. A repeat merges column by column:

- the lowest heart rate and Body Battery low keep the lowest value seen, and
  the Body Battery high the highest, because the watch's history covers only
  the last few hours and a later read has already lost the night;
- every other value comes from the newest reading (by `read_at`), falling back
  to what is stored where the newer one has none.

So posting one payload twice leaves the row as it was.

Recovery time counts down, so readiness needs *when it was read*, not the
row's `read_at` (the newest post's time, which a later post without recovery
time moves on). `recovery_read_at` (migrations/010) is the time of the post
the stored `recovery_time_h` came from, and the two always change together.
"""
from __future__ import annotations

import logging

from src import wellness

_log = logging.getLogger(__name__)

_TABLE_READY = False

_DDL = '''
CREATE TABLE IF NOT EXISTS daily_wellness (
    user_id              TEXT        NOT NULL,
    date                 DATE        NOT NULL,
    source               TEXT        NOT NULL DEFAULT 'garmin_ciq',
    resting_hr           INTEGER,
    resting_hr_7d_avg    INTEGER,
    hr_min               INTEGER,
    hr_low5              REAL,
    hr_samples           INTEGER,
    body_battery_max     INTEGER,
    body_battery_min     INTEGER,
    body_battery_latest  INTEGER,
    recovery_time_h      INTEGER,
    vo2max               INTEGER,
    stress               INTEGER,
    part_number          TEXT,
    firmware             TEXT,
    read_at              TIMESTAMPTZ,
    received_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, date, source)
)
'''

# Added after 009 (migrations/010_wellness_recovery_read_at.sql); ensured
# lazily. None: not tried yet; False: the DDL was refused, so the store runs
# without it and readiness falls back to the row's read_at.
_RECOVERY_COLUMN_READY: bool | None = None

_LOWEST = ('hr_min', 'hr_low5', 'body_battery_min')
_HIGHEST = ('body_battery_max',)
_COLUMNS = [c for c, *_ in wellness.FIELDS.values()] + [c for c, _ in wellness.TEXT_FIELDS.values()]
_READ = ['date', 'source', *_COLUMNS, 'read_at', 'received_at', 'recovery_read_at']


def _select() -> str:
    """The read columns, without recovery_read_at where the DDL was refused."""
    return ', '.join(c for c in _READ if c != 'recovery_read_at' or _RECOVERY_COLUMN_READY)


def _ensure_table() -> bool:
    """Create the table when 009 has not been run. No RLS here — a test
    database has no `auth` schema; the migration is the authority on that.
    The flag is set only after the DDL returns (program_history's rule)."""
    global _TABLE_READY
    if _TABLE_READY:
        return True
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    if conn is None:
        return False
    try:
        with conn.cursor() as cur:
            cur.execute(_DDL)
            _ensure_recovery_column(cur)
        _TABLE_READY = True
        return True
    except Exception as e:                                  # pragma: no cover
        _log.warning('daily_wellness DDL failed: %s', e)
        return False
    finally:
        conn.close()


def _ensure_recovery_column(cur) -> bool:
    """Add recovery_read_at when 010 has not been run (the way
    health_store._ensure_metrics_column mirrors 007). Never fatal."""
    global _RECOVERY_COLUMN_READY
    if _RECOVERY_COLUMN_READY is None:
        try:
            cur.execute('ALTER TABLE daily_wellness ADD COLUMN IF NOT EXISTS recovery_read_at TIMESTAMPTZ')
            _RECOVERY_COLUMN_READY = True
        except Exception as e:                              # pragma: no cover
            _log.warning('daily_wellness.recovery_read_at DDL failed: %s', e)
            _RECOVERY_COLUMN_READY = False
    return _RECOVERY_COLUMN_READY


# The incoming post carries recovery time and is at least as new as the one
# the stored recovery time came from.
_NEWER_RECOVERY = ('(EXCLUDED.recovery_time_h IS NOT NULL AND (t.recovery_read_at IS NULL '
                   'OR EXCLUDED.recovery_read_at IS NULL OR EXCLUDED.recovery_read_at >= t.recovery_read_at))')


def _newer() -> str:
    # True when the incoming reading is at least as new as the stored one.
    return ('(EXCLUDED.read_at IS NULL OR t.read_at IS NULL '
            'OR EXCLUDED.read_at >= t.read_at)')


def _set_clause(col: str) -> str:
    if col == 'recovery_time_h' and _RECOVERY_COLUMN_READY:
        return (f'recovery_time_h = CASE WHEN {_NEWER_RECOVERY} THEN EXCLUDED.recovery_time_h '
                'ELSE t.recovery_time_h END')
    if col in _LOWEST:
        return f'{col} = LEAST(t.{col}, EXCLUDED.{col})'
    if col in _HIGHEST:
        return f'{col} = GREATEST(t.{col}, EXCLUDED.{col})'
    return (f'{col} = CASE WHEN {_newer()} THEN COALESCE(EXCLUDED.{col}, t.{col}) '
            f'ELSE COALESCE(t.{col}, EXCLUDED.{col}) END')


def upsert(user_id: str, row: dict) -> None:
    """Write one validated reading (`wellness.validate`'s row). Raises."""
    if not _ensure_table():
        raise RuntimeError('no database')
    cols = ['user_id', 'date', 'source', *_COLUMNS, 'read_at']
    values = [user_id, row['date'], wellness.SOURCE, *(row.get(c) for c in _COLUMNS), row.get('read_at')]
    extra_sets = []
    if _RECOVERY_COLUMN_READY:
        cols.append('recovery_read_at')
        values.append(row.get('read_at') if row.get('recovery_time_h') is not None else None)
        # Decided against the stored row before recovery_time_h is replaced:
        # every SET reads the old row, so the two stay a pair.
        extra_sets.append(f'recovery_read_at = CASE WHEN {_NEWER_RECOVERY} '
                          'THEN EXCLUDED.recovery_read_at ELSE t.recovery_read_at END')
    sets = ',\n            '.join(
        [_set_clause(c) for c in _COLUMNS] + extra_sets
        + ['read_at = GREATEST(t.read_at, EXCLUDED.read_at)', 'received_at = NOW()'])
    sql = f'''
        INSERT INTO daily_wellness AS t ({', '.join(cols)})
        VALUES ({', '.join(['%s'] * len(cols))})
        ON CONFLICT (user_id, date, source) DO UPDATE SET
            {sets}
    '''
    from src.db import get_conn
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, values)
        conn.commit()


def _rows(sql: str, params) -> list[dict]:
    if not _ensure_table():
        return []
    from src.db import get_conn
    import psycopg2.extras
    try:
        with get_conn() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(sql, params)
                rows = cur.fetchall()
    except Exception as e:
        _log.warning('daily_wellness read failed: %s', e)
        return []
    out = []
    for r in rows:
        d = {k: r[k] for k in _READ if r.get(k) is not None}
        for k in ('date', 'read_at', 'received_at', 'recovery_read_at'):
            if k in d:
                d[k] = d[k].isoformat()
        out.append(d)
    return out


def recent(user_id: str, days: int = 14) -> list[dict]:
    """Rows of the last `days` days, newest first, snake_case like
    health_store.get_recent_bio_logs."""
    if not _ensure_table():
        return []
    return _rows(
        f'SELECT {_select()} FROM daily_wellness '
        "WHERE user_id = %s AND date >= CURRENT_DATE - %s::interval "
        'ORDER BY date DESC',
        (user_id, f'{days} days'))


def latest(user_id: str) -> dict | None:
    if not _ensure_table():
        return None
    rows = _rows(
        f'SELECT {_select()} FROM daily_wellness '
        'WHERE user_id = %s ORDER BY date DESC, read_at DESC NULLS LAST LIMIT 1',
        (user_id,))
    return rows[0] if rows else None
