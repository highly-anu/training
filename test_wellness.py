#!/usr/bin/env python
"""Daily wellness from the Connect IQ watch: validation, the scoring merge,
the store's same-day merge and the two routes.

The pure half always runs. The SQL half needs a local PostgreSQL and creates
its own throwaway database (never training_test), dropped afterwards; without
a server it skips with exit 0:

    SUPABASE_URL='' .venv/bin/python test_wellness.py

TEST_ADMIN_DSN names the server to create it on (default: localhost, user
postgres).
"""
from __future__ import annotations

import os
import sys
from datetime import date, timedelta
from pathlib import Path

os.environ['SUPABASE_URL'] = ''
sys.path.insert(0, str(Path(__file__).parent))

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


TODAY = date(2026, 10, 6)


def payload(**over):
    body = {'date': '2026-10-06', 'readAt': 1791264900, 'restingHr': 46, 'restingHr7dAvg': 47,
            'hrMin': 42, 'hrLow5': 42.0, 'hrSamples': 360, 'bodyBatteryMax': 95,
            'bodyBatteryMin': 48, 'bodyBatteryLatest': 68, 'recoveryTimeH': 58,
            'vo2max': 45, 'stress': 21, 'partNumber': '006-B4953-00', 'firmware': '6.49'}
    body.update(over)
    return {k: v for k, v in body.items() if v is not None}


# ── validate ──────────────────────────────────────────────────────────────────

def test_validate() -> None:
    from src.wellness import validate
    print('validate')
    row, errors = validate(payload(), today=TODAY)
    check('morning-1 reading passes', errors == [], str(errors))
    check('columns are snake_case', row and row['resting_hr'] == 46 and row['body_battery_max'] == 95
          and row['recovery_time_h'] == 58 and row['part_number'] == '006-B4953-00', str(row))
    check('readAt becomes an ISO timestamp', row and row['read_at'].startswith('2026-10-06'), str(row))
    check('hrLow5 stays a float', row and isinstance(row['hr_low5'], float))

    _, e = validate(payload(date='2026-10-08'), today=TODAY)
    check('two days ahead is refused', any('future' in x for x in e), str(e))
    _, e = validate(payload(date='2026-10-07'), today=TODAY)
    check('one day ahead (a watch east of UTC) passes', e == [], str(e))
    _, e = validate(payload(date='2026-08-01'), today=TODAY)
    check('older than 30 days is refused', any('older' in x for x in e), str(e))
    _, e = validate(payload(date='06/10/2026'), today=TODAY)
    check('a malformed date is refused', any('YYYY-MM-DD' in x for x in e), str(e))
    _, e = validate(payload(restingHr=0), today=TODAY)
    check('resting HR 0 is refused', any('restingHr' in x for x in e), str(e))
    _, e = validate(payload(bodyBatteryMax=101), today=TODAY)
    check('Body Battery 101 is refused', any('bodyBatteryMax' in x for x in e), str(e))
    _, e = validate(payload(recoveryTimeH=True), today=TODAY)
    check('a boolean is not a number', any('recoveryTimeH' in x for x in e), str(e))
    _, e = validate(payload(readAt='yesterday'), today=TODAY)
    check('readAt must be epoch seconds', any('readAt' in x for x in e), str(e))
    _, e = validate({'date': '2026-10-06', 'partNumber': 'x'}, today=TODAY)
    check('a reading with no metric is refused', any('no metric' in x for x in e), str(e))
    row, e = validate(payload(spo2=96, futureKey={'a': 1}), today=TODAY)
    check('unknown keys are ignored', e == [] and 'spo2' not in row, str(e))
    row, e = validate({'date': '2026-10-06', 'recoveryTimeH': 0}, today=TODAY)
    check('recovery time 0 is a value, not missing', e == [] and row['recovery_time_h'] == 0, str(row))
    _, e = validate(['not', 'a', 'dict'], today=TODAY)
    check('a non-object body is refused', e != [])


# ── merge_for_scoring ─────────────────────────────────────────────────────────

def bio(days_ago: int, **vals) -> dict:
    return {'date': (date.today() - timedelta(days=days_ago)).isoformat(), **vals}


def test_merge() -> None:
    from src.wellness import merge_for_scoring
    print('merge_for_scoring')
    apple = [bio(0, resting_hr=52, hrv=60.0, sleep_duration_min=420, source='apple_watch'),
             bio(1, resting_hr=53, hrv=58.0, source='apple_watch'),
             bio(2, resting_hr=51, source='apple_watch'),
             bio(3, hrv=61.0, source='apple_watch')]
    frozen = [dict(b) for b in apple]

    merged, sources = merge_for_scoring(apple, [])
    check('no wellness rows: the list is unchanged', merged == apple)
    check('no wellness rows: rhr from daily_bio', sources == {'rhr': 'daily_bio', 'hrv': 'daily_bio',
                                                              'sleep': 'daily_bio'}, str(sources))

    garmin = [{'date': bio(d)['date'], 'resting_hr': 46 + d} for d in range(5)]
    merged, sources = merge_for_scoring(apple, garmin)
    by = {b['date']: b for b in merged}
    check('more watch readings: rhr from the watch', sources['rhr'] == 'garmin_ciq', str(sources))
    check('…every rhr is the watch\'s', all(by[g['date']]['resting_hr'] == g['resting_hr'] for g in garmin))
    check('…none of Apple\'s survives', all(b.get('resting_hr') in {46, 47, 48, 49, 50} for b in merged
                                            if 'resting_hr' in b), str(merged))
    check('…HRV and sleep stay Apple\'s', by[bio(0)['date']]['hrv'] == 60.0
          and by[bio(0)['date']]['sleep_duration_min'] == 420)
    check('…a watch-only day is added', bio(4)['date'] in by and by[bio(4)['date']]['resting_hr'] == 50)
    check('…newest first', [b['date'] for b in merged] == sorted((b['date'] for b in merged), reverse=True))
    check('inputs are not mutated', apple == frozen)

    tie = [{'date': bio(d)['date'], 'resting_hr': 46} for d in range(3)]
    merged, sources = merge_for_scoring(apple, tie)
    check('a tie goes to daily_bio', sources['rhr'] == 'daily_bio' and merged == apple, str(sources))

    merged, sources = merge_for_scoring([], [{'date': bio(0)['date'], 'resting_hr': 46}])
    check('watch only: rhr from the watch, no hrv source',
          sources == {'rhr': 'garmin_ciq', 'hrv': None, 'sleep': None} and merged[0]['resting_hr'] == 46,
          str(sources))
    merged, sources = merge_for_scoring([], [{'date': bio(0)['date'], 'body_battery_max': 95}])
    check('a watch row without rhr leaves rhr unsourced', sources['rhr'] is None and merged == [])


def test_readiness_unchanged() -> None:
    import api
    from src.wellness import merge_for_scoring
    print('readiness')
    apple = [bio(d, resting_hr=50 + d % 3, hrv=55.0 + d) for d in range(10)]
    before = api._compute_readiness(apple, {}, user_id=None)
    merged, sources = merge_for_scoring(apple, [])
    after = api._compute_readiness(merged, {}, user_id=None, sources=sources)
    check('identical score with no wellness rows', after['score'] == before['score']
          and after['components'] == before['components'], f'{before} vs {after}')
    check('readiness names its sources', after.get('sources', {}).get('rhr') == 'daily_bio')
    check('without sources the shape is the old one', 'sources' not in before)


# ── SQL ───────────────────────────────────────────────────────────────────────

def sql_suite() -> None:
    admin = os.environ.get('TEST_ADMIN_DSN', 'postgresql://postgres@localhost:5432/postgres?sslmode=disable')
    if 'supabase' in admin or 'pooler' in admin:
        print('Refusing to run against what looks like a production database.')
        sys.exit(1)
    try:
        import psycopg2
        conn = psycopg2.connect(admin)
        conn.autocommit = True
    except Exception as exc:
        print(f'No local PostgreSQL available ({exc.__class__.__name__}) — skipping the SQL half.')
        return
    name = f'wellness_test_{os.getpid()}'
    with conn.cursor() as cur:
        cur.execute(f'CREATE DATABASE {name}')
    try:
        dsn = admin.rsplit('/', 1)[0] + f'/{name}?sslmode=disable'
        os.environ['DATABASE_URL'] = dsn
        import importlib
        import src.db
        importlib.reload(src.db)                # it reads DATABASE_URL at import time
        _sql_checks(dsn)
    finally:
        import src.db
        try:
            if src.db._pg_conn is not None:
                src.db._pg_conn.close()
        except Exception:
            pass
        with conn.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS {name} WITH (FORCE)')
        conn.close()


def _sql_checks(dsn: str) -> None:
    import psycopg2
    from src import wellness, wellness_store
    print('store (PostgreSQL)')
    user = 'local-dev-user'
    today = date.today()
    day = today.isoformat()
    t0 = 1_800_000_000

    def row_now():
        c = psycopg2.connect(dsn)
        with c.cursor() as cur:
            cur.execute('SELECT resting_hr, hr_min, body_battery_max, body_battery_min, '
                        'recovery_time_h, read_at FROM daily_wellness WHERE user_id = %s AND date = %s',
                        (user, day))
            r = cur.fetchone()
        c.close()
        return r

    first, e = wellness.validate(payload(date=day, readAt=t0), today=today)
    assert not e, e
    wellness_store.upsert(user, first)
    a = row_now()
    wellness_store.upsert(user, first)
    check('the same reading twice leaves the row as it was', row_now() == a, f'{a} vs {row_now()}')

    later, _ = wellness.validate(payload(date=day, readAt=t0 + 3 * 3600, restingHr=47, hrMin=55,
                                         bodyBatteryMax=80, bodyBatteryMin=30, recoveryTimeH=40), today=today)
    wellness_store.upsert(user, later)
    r = row_now()
    check('a later read keeps the night\'s lowest HR', r[1] == 42, str(r))
    check('…and the higher Body Battery max, the lower min', r[2] == 95 and r[3] == 30, str(r))
    check('…but takes its newer resting HR and recovery time', r[0] == 47 and r[4] == 40, str(r))

    stale, _ = wellness.validate(payload(date=day, readAt=t0 - 3600, restingHr=60, recoveryTimeH=5),
                                 today=today)
    wellness_store.upsert(user, stale)
    r = row_now()
    check('an older reading arriving late does not overwrite', r[0] == 47 and r[4] == 40, str(r))

    sparse, _ = wellness.validate({'date': day, 'readAt': t0 + 4 * 3600, 'stress': 30}, today=today)
    wellness_store.upsert(user, sparse)
    r = row_now()
    check('a newer reading with fewer values keeps the others', r[0] == 47 and r[4] == 40, str(r))

    rows = wellness_store.recent(user, days=14)
    check('recent() reads it back', len(rows) == 1 and rows[0]['resting_hr'] == 47
          and rows[0]['date'] == day, str(rows))
    check('latest() reads it back', (wellness_store.latest(user) or {}).get('part_number') == '006-B4953-00')
    check('another athlete sees nothing', wellness_store.recent('someone-else') == [])

    print('routes (PostgreSQL)')
    import api
    client = api.app.test_client()
    r = client.post('/api/health/wellness', json=payload(date=day))
    check('POST stores a reading', r.status_code == 200 and r.get_json().get('stored') is True,
          f'{r.status_code} {r.get_data(as_text=True)}')
    r = client.post('/api/health/wellness', json=payload(date=day, restingHr=500))
    check('POST answers 422 with the errors', r.status_code == 422
          and any('restingHr' in x for x in r.get_json().get('errors', [])), r.get_data(as_text=True))
    r = client.get('/api/health/wellness/latest')
    body = r.get_json() or {}
    check('latest names the model', (body.get('latest') or {}).get('model') == 'fēnix 9 Pro 47 mm',
          r.get_data(as_text=True))
    r = client.get('/api/health/readiness')
    check('readiness carries sources', r.status_code == 200 and 'sources' in (r.get_json() or {}),
          r.get_data(as_text=True))
    check('…and scores the watch\'s rhr when it is the only series',
          (r.get_json() or {}).get('sources', {}).get('rhr') == 'garmin_ciq', r.get_data(as_text=True))

    saved = api.integration_allows
    api.integration_allows = lambda uid, src: False
    try:
        r = client.post('/api/health/wellness', json=payload(date=day))
        check('Garmin toggle off: 200, nothing stored', r.status_code == 200
              and r.get_json().get('stored') is False, r.get_data(as_text=True))
    finally:
        api.integration_allows = saved

    saved_up = wellness_store.upsert
    def boom(*a, **k):
        raise RuntimeError('disk full')
    wellness_store.upsert = boom
    try:
        r = client.post('/api/health/wellness', json=payload(date=day))
        check('a failed write answers 503 so the watch retries', r.status_code == 503, str(r.status_code))
    finally:
        wellness_store.upsert = saved_up


if __name__ == '__main__':
    test_validate()
    test_merge()
    test_readiness_unchanged()
    sql_suite()
    print()
    if _failures:
        print(f'{len(_failures)} FAILED: ' + '; '.join(_failures))
        sys.exit(1)
    print('all passed')
