#!/usr/bin/env python
"""End-to-end dedup against a real PostgreSQL, not just the pure logic.

test_workout_dedupe.py covers the decisions; this covers the SQL that acts on
them — the batched candidate query, the field-promotion UPDATE, the canonical_id
marking, and the fact that merged-away rows disappear from reads while their
ids still resolve.

Needs a local PostgreSQL. Skips cleanly (exit 0) when there isn't one, so it is
safe to run anywhere:

    brew services start postgresql@14
    createdb training_test
    .venv/bin/python test_dedupe_sql.py

Override the target with TEST_DATABASE_URL. The schema is created fresh and the
test user's rows are removed afterwards; it never touches the production tables
(and refuses to run against a DATABASE_URL that looks like Supabase).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

TEST_DSN = os.environ.get('TEST_DATABASE_URL',
                          'postgresql://localhost:5432/training_test?sslmode=disable')

if 'supabase' in TEST_DSN or 'pooler' in TEST_DSN:
    print('Refusing to run against what looks like a production database.')
    sys.exit(1)

try:
    import psycopg2
    _probe = psycopg2.connect(TEST_DSN)
    _probe.close()
except Exception as exc:
    print(f'No local PostgreSQL available ({exc.__class__.__name__}) — skipping.')
    print('  brew services start postgresql@14 && createdb training_test')
    sys.exit(0)

# src.db reads DATABASE_URL at import time.
os.environ['DATABASE_URL'] = TEST_DSN
os.environ['SUPABASE_URL'] = ''
sys.path.insert(0, str(Path(__file__).parent))

from src import health_store  # noqa: E402

USER = '11111111-1111-1111-1111-111111111111'

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


def raw(sql: str, params=()):
    conn = psycopg2.connect(TEST_DSN)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall() if cur.description else None
    conn.close()
    return rows


def setup_schema() -> None:
    # The production schema minus the auth.users FK, which needs Supabase.
    raw('''
        DROP TABLE IF EXISTS workout_matches;
        DROP TABLE IF EXISTS workout_match_suggestions;
        DROP TABLE IF EXISTS workouts;
        CREATE TABLE workouts (
          id TEXT NOT NULL, user_id UUID NOT NULL, source TEXT NOT NULL,
          date DATE NOT NULL, start_time TIMESTAMPTZ NOT NULL,
          end_time TIMESTAMPTZ NOT NULL, duration_minutes INTEGER NOT NULL,
          activity_type TEXT NOT NULL, inferred_modality_id TEXT,
          hr_avg REAL, hr_max REAL, hr_min REAL, calories INTEGER,
          distance_value REAL, distance_unit TEXT,
          raw_data JSONB NOT NULL DEFAULT '{}', gps_track JSONB,
          elevation_gain INTEGER, elevation_loss INTEGER, hr_samples JSONB,
          PRIMARY KEY (id, user_id)
        );
        CREATE TABLE workout_matches (
          imported_workout_id TEXT NOT NULL, user_id UUID NOT NULL,
          session_key TEXT NOT NULL, match_confidence TEXT NOT NULL,
          matched_at TIMESTAMPTZ NOT NULL,
          PRIMARY KEY (imported_workout_id, user_id)
        );
    ''')
    # Deliberately NOT adding dedupe_key/canonical_id — _ensure_dedupe_columns
    # must add them itself, which is how a deployment that hasn't run migration
    # 003 behaves.
    health_store._DEDUPE_COLUMNS_READY = None


def workout(source, start='2026-03-28T08:00:00+00:00', duration=60,
            modality='aerobic_base', **extra):
    w = {
        'id': f'{source}-run1',
        'source': source,
        'date': start[:10],
        'startTime': start,
        'endTime': '2026-03-28T09:00:00+00:00',
        'durationMinutes': duration,
        'activityType': 'Running',
        'inferredModalityId': modality,
        'heartRate': {},
        'rawData': {},
    }
    w.update(extra)
    return w


def test_columns_are_created() -> None:
    print('\nSchema self-healing')
    health_store.upsert_workouts(USER, [workout('strava')])
    cols = {r[0] for r in raw(
        "SELECT column_name FROM information_schema.columns WHERE table_name='workouts'")}
    check('dedupe_key was added on first write', 'dedupe_key' in cols)
    check('canonical_id was added on first write', 'canonical_id' in cols)
    key = raw("SELECT dedupe_key FROM workouts WHERE id='strava-run1'")[0][0]
    check('dedupe_key is populated', bool(key), repr(key))


def test_four_sources_collapse() -> None:
    print('\nOne run, four sources')
    raw('DELETE FROM workouts WHERE user_id = %s', (USER,))

    health_store.upsert_workouts(USER, [workout('strava', calories=500)])
    health_store.upsert_workouts(USER, [
        workout('garmin', '2026-03-28T08:00:10+00:00', 59,
                gpsTrack=[{'lat': 1.0, 'lng': 2.0}], calories=520)])
    health_store.upsert_workouts(USER, [
        workout('apple_health', '2026-03-28T08:00:00+00:00', 60)])
    health_store.upsert_workouts(USER, [
        workout('fit_file', '2026-03-28T08:00:05+00:00', 60,
                heartRate={'avg': 152.0, 'max': 176.0,
                           'samples': [{'timestamp': 't', 'bpm': 152}]})])

    total = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    check('all four rows are stored', total == 4, str(total))

    visible = health_store.get_workouts(USER)
    check('only one is visible to readers', len(visible) == 1, str(len(visible)))
    check('the visible row is the one that arrived first',
          visible and visible[0]['id'] == 'strava-run1',
          visible[0]['id'] if visible else '(none)')

    canonical = visible[0]
    check('the GPS track was promoted onto it', bool(canonical.get('gpsTrack')))
    check('the richest source won on calories', canonical.get('calories') == 520,
          str(canonical.get('calories')))
    check('HR samples arrived from the fit file',
          bool(canonical['heartRate'].get('samples')))
    check('HR average arrived too', canonical['heartRate'].get('avg') == 152.0,
          str(canonical['heartRate'].get('avg')))

    marked = raw('SELECT count(*) FROM workouts WHERE user_id = %s AND canonical_id = %s',
                 (USER, 'strava-run1'))[0][0]
    check('the other three point at the canonical row', marked == 3, str(marked))

    check('a merged-away id still resolves',
          health_store.get_workout(USER, 'garmin-run1') is not None)


def test_unrelated_and_idempotent() -> None:
    print('\nUnrelated workouts and replays')
    raw('DELETE FROM workouts WHERE user_id = %s', (USER,))

    health_store.upsert_workouts(USER, [workout('garmin')])
    health_store.upsert_workouts(USER, [
        workout('garmin', '2026-03-28T14:00:00+00:00', 45, id='garmin-run2')])
    check('an afternoon session is its own row', len(health_store.get_workouts(USER)) == 2)

    health_store.upsert_workouts(USER, [workout('garmin')])
    health_store.upsert_workouts(USER, [workout('garmin')])
    total = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    check('replaying the same webhook adds nothing', total == 2, str(total))

    print('\nDifferent activities at the same time')
    raw('DELETE FROM workouts WHERE user_id = %s', (USER,))
    health_store.upsert_workouts(USER, [workout('garmin', modality='aerobic_base')])
    health_store.upsert_workouts(USER, [
        workout('fit_file', modality='max_strength')])
    check('a run and a lift starting together stay separate',
          len(health_store.get_workouts(USER)) == 2,
          str(len(health_store.get_workouts(USER))))


def test_dedupe_can_be_disabled() -> None:
    print('\ndedupe=False')
    raw('DELETE FROM workouts WHERE user_id = %s', (USER,))
    health_store.upsert_workouts(USER, [workout('strava')], dedupe=False)
    health_store.upsert_workouts(USER, [workout('garmin')], dedupe=False)
    check('both rows stay visible when dedup is off',
          len(health_store.get_workouts(USER)) == 2)


def test_raise_on_error() -> None:
    print('\nraise_on_error')
    bad = [{'id': 'broken'}]   # missing required keys
    try:
        health_store.upsert_workouts(USER, bad)
        check('a bad write is swallowed by default', True)
    except Exception as e:
        check('a bad write is swallowed by default', False, repr(e))

    try:
        health_store.upsert_workouts(USER, bad, raise_on_error=True)
        check('raise_on_error propagates the failure', False, 'no exception raised')
    except Exception:
        check('raise_on_error propagates the failure', True)


if __name__ == '__main__':
    setup_schema()
    try:
        test_columns_are_created()
        test_four_sources_collapse()
        test_unrelated_and_idempotent()
        test_dedupe_can_be_disabled()
        test_raise_on_error()
    finally:
        raw('DELETE FROM workouts WHERE user_id = %s', (USER,))

    if _failures:
        print(f'\n{len(_failures)} dedup SQL test(s) failed.')
        sys.exit(1)
    print('\nAll dedup SQL tests passed.')
