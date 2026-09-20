#!/usr/bin/env python
"""The Garmin webhook, end to end, without a Garmin developer account.

This is the test that makes Phase 3 shippable while the Developer Program
application is pending. It stands up a local HTTP server serving one of the
repo's real .fit files, points GARMIN_API_BASE at it, inserts a fake token row,
and fires a ping fixture at the real endpoint — exercising authorisation, the
queue, the worker, the FIT parse, the upsert, dedup and matching.

Needs a local PostgreSQL; skips cleanly (exit 0) without one.

    brew services start postgresql@14 && createdb training_test
    .venv/bin/python test_garmin_webhook.py
"""
from __future__ import annotations

import json
import os
import sys
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).parent
TEST_DSN = os.environ.get('TEST_DATABASE_URL',
                          'postgresql://localhost:5432/training_test?sslmode=disable')

if 'supabase' in TEST_DSN or 'pooler' in TEST_DSN:
    print('Refusing to run against what looks like a production database.')
    sys.exit(1)

try:
    import psycopg2
    psycopg2.connect(TEST_DSN).close()
except Exception as exc:
    print(f'No local PostgreSQL available ({exc.__class__.__name__}) — skipping.')
    print('  brew services start postgresql@14 && createdb training_test')
    sys.exit(0)

FIT_FILES = sorted(REPO.glob('data/*.fit'))
if not FIT_FILES:
    print('No .fit fixture in data/ — skipping.')
    sys.exit(0)
FIT_NAME = FIT_FILES[0].name

# --- A stand-in for Garmin's API, so no approval is needed ------------------
_httpd = ThreadingHTTPServer(
    ('127.0.0.1', 0), partial(SimpleHTTPRequestHandler, directory=str(REPO / 'data')))
STUB_PORT = _httpd.server_address[1]
threading.Thread(target=_httpd.serve_forever, daemon=True).start()
STUB_BASE = f'http://127.0.0.1:{STUB_PORT}'

WEBHOOK_SECRET = 'test-webhook-secret'
os.environ['DATABASE_URL'] = TEST_DSN
os.environ['SUPABASE_URL'] = ''          # auth bypass for the authed routes
os.environ['GARMIN_API_BASE'] = STUB_BASE
os.environ['GARMIN_WEBHOOK_SECRET'] = WEBHOOK_SECRET
os.environ['GARMIN_CLIENT_ID'] = 'test-client'
os.environ['GARMIN_CLIENT_SECRET'] = 'test-secret'

sys.path.insert(0, str(REPO))

import api                                        # noqa: E402
from src import garmin_connect, garmin_worker, health_store  # noqa: E402

USER = '22222222-2222-2222-2222-222222222222'
GARMIN_USER = 'FAKEGARMINUSER'

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


def setup() -> None:
    raw('''
        DROP TABLE IF EXISTS garmin_webhook_events;
        DROP TABLE IF EXISTS garmin_activities;
        DROP TABLE IF EXISTS garmin_tokens;
        DROP TABLE IF EXISTS workout_matches;
        DROP TABLE IF EXISTS workout_match_suggestions;
        DROP TABLE IF EXISTS workouts;
        DROP TABLE IF EXISTS profiles;
        DROP TABLE IF EXISTS user_programs;
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
        CREATE TABLE profiles (
          user_id TEXT PRIMARY KEY, profile_data JSONB NOT NULL DEFAULT '{}',
          created_at TIMESTAMPTZ DEFAULT NOW(), updated_at TIMESTAMPTZ DEFAULT NOW()
        );
    ''')
    for module in (health_store, garmin_connect, garmin_worker):
        for attr in ('_DEDUPE_COLUMNS_READY', '_TABLE_READY', '_SUGGESTION_TABLE_CREATED'):
            if hasattr(module, attr):
                setattr(module, attr, None if attr.endswith('READY') else False)

    # A connected athlete, minted directly — this is the step the real OAuth
    # flow would perform.
    conn = psycopg2.connect(TEST_DSN)
    conn.autocommit = True
    with conn.cursor() as cur:
        garmin_connect._ensure_table(cur)
        cur.execute(
            'INSERT INTO garmin_tokens (user_id, access_token, garmin_user_id) '
            'VALUES (%s, %s, %s) ON CONFLICT (user_id) DO UPDATE SET '
            'garmin_user_id = EXCLUDED.garmin_user_id',
            (USER, 'fake-access-token', GARMIN_USER))
    conn.close()


def ping(summary_id: str = 'abc123', callback: str | None = None) -> dict:
    """A ping shaped like Garmin's Activity notification."""
    return {'activities': [{
        'userId': GARMIN_USER,
        'userAccessToken': 'fake',
        'summaryId': summary_id,
        'callbackURL': callback if callback is not None else f'{STUB_BASE}/{FIT_NAME}',
        # Summary fields, used only when the file can't be fetched.
        'activityType': 'RUNNING',
        'startTimeInSeconds': 1774684800,
        'durationInSeconds': 3600,
        'distanceInMeters': 10000,
        'activeKilocalories': 700,
        'averageHeartRateInBeatsPerMinute': 150,
    }]}


def post_webhook(payload: dict, token: str = WEBHOOK_SECRET, path: str = 'activities'):
    client = api.app.test_client()
    return client.post(f'/api/webhooks/garmin/{path}?t={token}', json=payload)


def settle() -> dict:
    """Wait for the endpoint's own background drain, then drain what's left.

    The handler kicks a worker thread, so asserting straight after the POST
    races it — an event can still be 'processing' when the assertion reads it.
    Production doesn't care (the next webhook or /drain picks it up), but a
    test must be deterministic.
    """
    worker = garmin_worker._worker
    if worker is not None and worker.is_alive():
        worker.join(timeout=30)
    return garmin_worker.drain()


def test_authorization() -> None:
    print('\nWebhook authorisation')
    check('a wrong secret is rejected', post_webhook(ping(), token='wrong').status_code == 401)
    check('a missing secret is rejected',
          api.app.test_client().post('/api/webhooks/garmin/activities',
                                     json=ping()).status_code == 401)
    r = post_webhook(ping('auth-check'))
    check('the right secret is accepted', r.status_code == 200, str(r.status_code))
    settle()   # let this one finish before the next test clears the tables


def test_import() -> None:
    print('\nImporting a pushed activity')
    raw('DELETE FROM workouts WHERE user_id = %s', (USER,))
    raw('DELETE FROM garmin_activities')
    raw('DELETE FROM garmin_webhook_events')

    r = post_webhook(ping('run-1'))
    check('the endpoint acknowledges immediately', r.status_code == 200)

    queued = raw("SELECT count(*) FROM garmin_webhook_events")[0][0]
    check('the event was queued', queued == 1, str(queued))

    # Assert on stored state, not on drain()'s return: the endpoint kicks its
    # own worker, so either that thread or this drain may be the one that does
    # the work. Which of them did it is not the behaviour under test.
    settle()

    rows = raw("SELECT id, source, gps_track IS NOT NULL, hr_samples IS NOT NULL "
               "FROM workouts WHERE user_id = %s", (USER,))
    check('one workout row was created', len(rows) == 1, str(len(rows)))
    if rows:
        check('it is tagged source=garmin', rows[0][1] == 'garmin', rows[0][1])
        check('the GPS track came through', rows[0][2] is True)
        check('the HR samples came through', rows[0][3] is True)
        check('its id is source-tagged', rows[0][0].startswith('garmin-'), rows[0][0])

    status = raw("SELECT status FROM garmin_webhook_events ORDER BY id DESC LIMIT 1")[0][0]
    check('the event is marked done', status == 'done', status)

    ledger = raw("SELECT count(*) FROM garmin_activities WHERE summary_id = 'run-1'")[0][0]
    check('the activity is recorded in the ledger', ledger == 1, str(ledger))


def test_replay_is_idempotent() -> None:
    print('\nReplay')
    before = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    post_webhook(ping('run-1'))
    settle()
    after = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    check('replaying the same ping adds no row', after == before, f'{before} -> {after}')


def test_cross_source_dedup() -> None:
    print('\nThe same activity uploaded by hand as well')
    from src import fit_import
    with open(REPO / 'data' / FIT_NAME, 'rb') as fh:
        manual = fit_import.parse_fit(fh)          # source='fit_file'
    health_store.upsert_workouts(USER, manual)

    total = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    visible = health_store.get_workouts(USER)
    check('both rows exist', total == 2, str(total))
    check('but only one is visible', len(visible) == 1, str(len(visible)))


def test_unknown_athlete_and_bad_payloads() -> None:
    print('\nHostile and unknown input')
    raw('DELETE FROM garmin_webhook_events')

    stranger = {'activities': [dict(ping()['activities'][0], userId='SOMEONE_ELSE')]}
    check('an unknown athlete is still acknowledged',
          post_webhook(stranger).status_code == 200)
    settle()
    status = raw('SELECT status FROM garmin_webhook_events ORDER BY id DESC LIMIT 1')[0][0]
    check('...and the event is ignored, not failed', status == 'ignored', status)

    client = api.app.test_client()
    r = client.post(f'/api/webhooks/garmin/activities?t={WEBHOOK_SECRET}',
                    data='not json', content_type='application/json')
    check('a malformed body is acknowledged, never a 5xx', r.status_code == 200,
          str(r.status_code))

    check('an empty activity list is acknowledged',
          post_webhook({'activities': []}).status_code == 200)


def test_ssrf_guard() -> None:
    print('\nSSRF guard on callbackURL')
    check('an internal host is refused',
          not garmin_connect.is_allowed_callback('http://169.254.169.254/latest/meta-data/'))
    check('localhost on another port is refused',
          not garmin_connect.is_allowed_callback('http://127.0.0.1:1/secret'))
    check('a lookalike domain is refused',
          not garmin_connect.is_allowed_callback('https://apis.garmin.com.evil.test/x'))
    check('a file:// url is refused',
          not garmin_connect.is_allowed_callback('file:///etc/passwd'))
    check('the configured API base is allowed',
          garmin_connect.is_allowed_callback(f'{STUB_BASE}/{FIT_NAME}'))

    raw('DELETE FROM garmin_webhook_events')
    before = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    post_webhook(ping('ssrf-1', callback='http://169.254.169.254/latest/meta-data/'))
    settle()
    status = raw('SELECT status FROM garmin_webhook_events ORDER BY id DESC LIMIT 1')[0][0]
    check('a ping with a hostile callback is dropped', status == 'ignored', status)
    after = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    # Not even the summary is trusted: a callback we refuse to fetch means the
    # notification did not come from Garmin.
    check('nothing at all is imported from it', after == before, f'{before} -> {after}')
    check('and it is not recorded as imported',
          not raw("SELECT 1 FROM garmin_activities WHERE summary_id = 'ssrf-1'"))


def test_settings_gate() -> None:
    print('\nThe auto-import toggle is enforced server-side')
    raw("INSERT INTO profiles (user_id, profile_data) VALUES (%s, %s::jsonb) "
        "ON CONFLICT (user_id) DO UPDATE SET profile_data = EXCLUDED.profile_data",
        (USER, json.dumps({'integrations': {'autoImport': False,
                                            'sources': {'garmin': {'enabled': True}}}})))
    raw('DELETE FROM garmin_webhook_events')
    before = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]

    post_webhook(ping('gated-1'))
    settle()
    after = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    check('with auto-import off, nothing is imported', after == before,
          f'{before} -> {after}')
    status = raw('SELECT status FROM garmin_webhook_events ORDER BY id DESC LIMIT 1')[0][0]
    check('...and the event is ignored', status == 'ignored', status)

    raw("UPDATE profiles SET profile_data = %s::jsonb WHERE user_id = %s",
        (json.dumps({'integrations': {'autoImport': True,
                                      'sources': {'garmin': {'enabled': False}}}}), USER))
    raw('DELETE FROM garmin_webhook_events')
    post_webhook(ping('gated-2'))
    settle()
    after2 = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    check('with the Garmin source off, nothing is imported', after2 == before,
          f'{before} -> {after2}')

    raw("UPDATE profiles SET profile_data = %s::jsonb WHERE user_id = %s",
        (json.dumps({'integrations': {'autoImport': True,
                                      'sources': {'garmin': {'enabled': True}}}}), USER))
    raw('DELETE FROM garmin_webhook_events')
    post_webhook(ping('gated-3'))
    settle()
    after3 = raw('SELECT count(*) FROM workouts WHERE user_id = %s', (USER,))[0][0]
    # Same activity as before, so dedup folds it — the point is that it ran.
    ledger = raw("SELECT count(*) FROM garmin_activities WHERE summary_id = 'gated-3'")[0][0]
    check('with both switched on, the import runs', ledger == 1, str(ledger))
    check('and dedup still keeps one visible row',
          len(health_store.get_workouts(USER)) == 1)
    del after3


def test_inert_without_credentials() -> None:
    print('\nInert without credentials')
    saved = os.environ.pop('GARMIN_CLIENT_ID', None)
    try:
        import importlib
        from src import garmin_connect as gc
        importlib.reload(gc)
        check('is_configured() is False without a client id', not gc.is_configured())
    finally:
        if saved:
            os.environ['GARMIN_CLIENT_ID'] = saved
        import importlib
        from src import garmin_connect as gc
        importlib.reload(gc)


if __name__ == '__main__':
    setup()
    try:
        test_authorization()
        test_import()
        test_replay_is_idempotent()
        test_cross_source_dedup()
        test_unknown_athlete_and_bad_payloads()
        test_ssrf_guard()
        test_settings_gate()
        test_inert_without_credentials()
    finally:
        raw('DELETE FROM workouts WHERE user_id = %s', (USER,))
        raw('DELETE FROM profiles WHERE user_id = %s', (USER,))
        _httpd.shutdown()

    if _failures:
        print(f'\n{len(_failures)} garmin webhook test(s) failed.')
        sys.exit(1)
    print('\nAll garmin webhook tests passed.')
