"""GET /api/user/today-session: completion flags and tomorrow's preview.

The watch glance fills its ring from `completed` and previews `tomorrow` on a
rest day or once the day is done. No database: the program, session logs and
matches are stubbed. Run with SUPABASE_URL='' so the route runs as local-dev-user.
"""
import os
import sys

os.environ.setdefault('SUPABASE_URL', '')

import api  # noqa: E402
import src.db  # noqa: E402


def _session(name, modality='max_strength', minutes=50):
    return {'modality': modality,
            'archetype': {'id': name.lower(), 'name': name, 'duration_estimate_minutes': minutes},
            'exercises': []}


def _ruck():
    s = _session('Ruck', 'aerobic_base', 90)
    s['archetype']['category'] = 'conditioning'
    s['exercises'] = [{'exercise': {'id': 'ruck_march', 'name': 'Ruck March'},
                       'slot_type': 'time_domain', 'role': 'ruck', 'load': {}},
                      {'injury_skip': True, 'slot_type': 'sets_reps', 'role': 'carry'}]
    return s


PROGRAM = {
    'programStartDate': '2026-10-05',          # a Monday
    'currentProgram': {'weeks': [{
        'week_number': 1,
        'schedule': {
            'Friday': [_session('Strength A'), _session('PT Prep', 'strength_endurance', 25)],
            'Saturday': [_ruck()],
        },
    }]},
}


def run():
    failures = []

    def check(cond, msg):
        if not cond:
            failures.append(msg)

    src.db.get_user_program = lambda uid: PROGRAM
    api._health.get_session_logs = lambda uid: {
        '1-Friday-0': {'completedAt': '2026-10-09T08:00:00Z'},
    }
    api._health.get_matches = lambda uid: [
        {'sessionKey': '1-Friday-1', 'matchConfidence': 'rejected'},
    ]

    def no_bio(*a, **k):
        raise RuntimeError('no bio in this test')
    api._bio_for_scoring = no_bio

    client = api.app.test_client()

    body = client.get('/api/user/today-session?date=2026-10-09').get_json()
    check(body['status'] == 'ok', f"status {body.get('status')}")
    done = [s['completed'] for s in body['sessions']]
    check(done == [True, False], f"completed flags {done} (a rejected match is not done)")
    t = body['tomorrow']
    check(t and t['sessionCount'] == 1 and t['archetypeName'] == 'Ruck'
          and t['estimatedMinutes'] == 90, f"tomorrow {t}")
    # The glance card's icon and "1 ex": the injury-skipped slot is not sent.
    check(t.get('archetypeCategory') == 'conditioning' and t.get('exerciseCount') == 1,
          f"tomorrow's category and exercise count {t}")

    # progress: this week's sessions done of those due (Friday's two; Saturday's
    # is ahead) and of all three, the program so far, and no headline until the
    # analytics document has been cached.
    api._health.get_progression_snapshot = lambda uid, key, kind: None
    p = client.get('/api/user/today-session?date=2026-10-09').get_json()['progress']
    check(p['week'] == {'number': 1, 'of': 1, 'done': 1, 'due': 2, 'sessions': 3}, f"week {p['week']}")
    check(p['program'] == {'done': 1, 'due': 2, 'pct': 50}, f"program {p['program']}")
    check('headline' not in p, 'no headline without a cached document')
    seen = {}

    def snapshot(uid, key, kind):
        seen['key'] = (key, kind)
        return {'data': {'methodologies': [{'headlineSummary': {
            'label': 'Load on the bar', 'text': 'Back squat 102.5kg', 'trendText': '+1.2% per session',
            'status': 'on_track', 'value': 102.5}}]}}
    api._health.get_progression_snapshot = snapshot
    p = client.get('/api/user/today-session?date=2026-10-09').get_json()['progress']
    check(p.get('headline') == {'label': 'Load on the bar', 'text': 'Back squat 102.5kg',
                                'trendText': '+1.2% per session', 'status': 'on_track'},
          f"headline {p.get('headline')}")
    check(seen.get('key') == ('2026-10-05:-', 'program'), f"snapshot key {seen.get('key')}")

    # A match that is not rejected completes the session too.
    api._health.get_matches = lambda uid: [
        {'sessionKey': '1-Friday-1', 'matchConfidence': 'high'},
    ]
    body = client.get('/api/user/today-session?date=2026-10-09').get_json()
    done = [s['completed'] for s in body['sessions']]
    check(done == [True, True], f"matched session not completed: {done}")

    # An earlier program's match on the same key does not complete today's
    # session; one on this version's uid does.
    import src.program_history as ph
    real_active = ph.active_version_id
    ph.active_version_id = lambda uid: 'vNEW'
    api._health.get_matches = lambda uid: [
        {'sessionKey': '1-Friday-1', 'sessionUid': 'vOLD:w0-Friday-1', 'matchConfidence': 'high'},
    ]
    body = client.get('/api/user/today-session?date=2026-10-09').get_json()
    done = [s['completed'] for s in body['sessions']]
    check(done == [True, False], f"another version's match completed today: {done}")
    api._health.get_matches = lambda uid: [
        {'sessionKey': '1-Friday-1', 'sessionUid': 'vNEW:w0-Friday-1', 'matchConfidence': 'high'},
    ]
    body = client.get('/api/user/today-session?date=2026-10-09').get_json()
    done = [s['completed'] for s in body['sessions']]
    check(done == [True, True], f"this version's match not completed: {done}")
    ph.active_version_id = real_active

    # Saturday: tomorrow (Sunday) is a rest day.
    body = client.get('/api/user/today-session?date=2026-10-10').get_json()
    check(body['tomorrow'] == {'dayName': 'Sunday', 'sessionCount': 0}, f"rest tomorrow {body['tomorrow']}")

    # Sunday of the last week: there is no tomorrow in the program.
    body = client.get('/api/user/today-session?date=2026-10-11').get_json()
    check(body['isRestDay'] and body['tomorrow'] is None, f"end of program {body.get('tomorrow')}")

    # ?spec=1: the package screens ride along; without it the keys are the
    # ones builds before 1.4 parse.
    plain = client.get('/api/user/today-session?date=2026-10-09').get_json()
    check('specVersion' not in plain and not ({'packageId', 'watch', 'screens'} & set(plain['sessions'][0])),
          f"spec keys without ?spec: {sorted(plain['sessions'][0])}")
    spec = client.get('/api/user/today-session?date=2026-10-09&spec=1').get_json()
    check(isinstance(spec.get('specVersion'), int), f"specVersion {spec.get('specVersion')}")
    s0 = spec['sessions'][0]
    check({'packageId', 'watch', 'screens'} <= set(s0), f"session keys {sorted(s0)}")
    check(set(s0) - {'packageId', 'watch', 'screens'} == set(plain['sessions'][0]),
          'the spec payload must only add keys')
    # The Apple Watch's zone alerts read the server's max HR; the Garmin's own.
    check(isinstance(spec.get('maxHR'), int) and 'maxHR' not in plain,
          f"maxHR {spec.get('maxHR')} with ?spec=1, {plain.get('maxHR')} without")

    # ?week=1: today and the days after it, inside the program, in the demo's
    # day shape; without it there is no `days` key.
    check('days' not in plain, 'days without ?week=1')
    wk = client.get('/api/user/today-session?date=2026-10-09&week=1').get_json()
    days = wk.get('days') or []
    check([d['offset'] for d in days] == [0, 1, 2], f"week offsets {[d['offset'] for d in days]} (program ends Sunday)")
    check([d['title'] for d in days] == ['Strength A +1', 'Ruck', 'Rest'], f"week titles {[d['title'] for d in days]}")
    check([d['date'] for d in days] == ['2026-10-09', '2026-10-10', '2026-10-11'], 'week dates')
    check(days and [s['sessionId'] for s in days[0]['sessions']] == [s['sessionId'] for s in wk['sessions']],
          "day 0 is today's sessions")
    check(days and 'screens' not in days[0]['sessions'][0], 'the week carries no screen specs')
    # A week fetched mid-week reaches into the next only while the program lasts.
    wk = client.get('/api/user/today-session?date=2026-10-05&week=1').get_json()
    check(len(wk.get('days') or []) == 7, f"Monday's week {len(wk.get('days') or [])} days")

    failures += fixture_check(client, write='--write' in sys.argv)

    for f in failures:
        print('FAIL', f)
    print('ok' if not failures else f'{len(failures)} failure(s)')
    return 0 if not failures else 1


# --- The Apple Watch's fixture --------------------------------------------------
# What the phone relays to the Apple Watch is this route's ?spec=1&week=1 body,
# as it is; ios/TrainingCompanionTests/WatchDayTests.swift decodes this file.
# A change to the encoder that the fixture does not carry fails here, so the
# watch's model is tested against what the server sends:
#     SUPABASE_URL='' .venv/bin/python test_today_session.py --write
FIXTURE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'watch_day_fixture.json')


def _ex(eid, name, slot_type, load, **slot):
    return {'exercise': {'id': eid, 'name': name, 'category': 'barbell'},
            'slot_type': slot_type, 'load': load, **slot}


FIXTURE_PROGRAM = {
    'programStartDate': '2026-10-12',          # a Monday
    'currentProgram': {'weeks': [{
        'week_number': 3, 'phase': 'build',
        'schedule': {
            'Monday': [
                {'modality': 'max_strength', 'archetype': {'id': 'ss_a', 'name': 'Strength A',
                                                           'duration_estimate_minutes': 60},
                 'exercises': [
                     _ex('back_squat', 'Back Squat', 'sets_reps',
                         {'sets': 3, 'reps': 5, 'weight_kg': 102.5, 'target_rpe': 7.5},
                         slot_role='primary_squat', rest_sec=180),
                     _ex('band_pull_apart', 'Band Pull-Apart', 'sets_reps', {'sets': 2, 'reps': '12-15'},
                         slot_role='accessory', injury_skip=True),
                 ]},
                {'modality': 'combat_sport', 'archetype': {'id': 'bjj_class', 'name': 'BJJ Class',
                                                           'duration_estimate_minutes': 75},
                 'exercises': [
                     {'meta': True, 'slot_role': 'positional_sparring', 'slot_type': 'time_domain',
                      'load': {'duration_minutes': 5, 'target_rounds': 4}},
                     _ex('bike_easy', 'Easy Bike', 'time_domain',
                         {'duration_minutes': 22.5, 'zone_target': 'Zone 1–2 (conversational pace)'},
                         slot_role='flush'),
                 ]},
                {'modality': 'aerobic_base', 'archetype': {'id': 'gj_row_test', 'name': '2 km Row Test',
                                                           'duration_estimate_minutes': 30},
                 'exercises': [
                     _ex('rower', 'Rowing', 'for_time', {'distance_m': 2000},
                         slot_role='test', standard={'id': 'row_2km_minutes', 'result': 'duration'}),
                 ]},
                # A timed kettlebell set: the athlete counts its reps and
                # enters them at the end (`logs`: its cadence).
                {'modality': 'kettlebell', 'archetype': {'id': 'kb_snatch_set', 'name': 'Snatch Set',
                                                         'duration_estimate_minutes': 15},
                 'exercises': [
                     {'exercise': {'id': 'kb_snatch', 'name': 'Kettlebell Snatch', 'category': 'kettlebell'},
                      'slot_type': 'time_domain', 'slot_role': 'snatch', 'load': {'duration_minutes': 10}},
                 ]},
            ],
            'Wednesday': [
                {'modality': 'aerobic_base', 'archetype': {'id': 'easy_run', 'name': 'Easy Run',
                                                           'duration_estimate_minutes': 40},
                 'exercises': [
                     _ex('run', 'Run', 'time_domain', {'duration_minutes': 40, 'zone_lower': 2, 'zone_upper': 2},
                         slot_role='main'),
                 ]},
            ],
        },
    }]},
}


def fixture_check(client, write=False):
    import src.db
    import src.last_time
    import src.program_history as ph
    saved = (src.db.get_user_program, src.db.get_user_profile, src.last_time.last_by_exercise,
             ph.active_version_id, api._get_user_max_hr, api._bio_for_scoring, api._compute_readiness,
             api._standards_context, api._health.get_session_logs, api._health.get_session_logs_by_uid,
             api._health.get_matches, api._health.get_performance_logs, api._health.get_progression_snapshot)
    src.db.get_user_program = lambda uid: FIXTURE_PROGRAM
    src.db.get_user_profile = lambda uid: {}
    src.last_time.last_by_exercise = lambda logs, today, tz=None: {'back_squat': '100kg × 5'}
    ph.active_version_id = lambda uid: None
    api._get_user_max_hr = lambda uid: 186
    api._bio_for_scoring = lambda uid, days=14: ([], {})
    api._compute_readiness = lambda *a, **k: {'score': 72, 'status': 'green', 'flags': [],
                                              'components': {'rhr': 30, 'hrv': 22, 'sleep': 8, 'fatigue': 6, 'tsb': 6}}
    api._standards_context = lambda uid: ('male', None)
    api._health.get_session_logs = lambda uid: {'3-Monday-0': {'completedAt': '2026-10-12T07:40:00Z'}}
    api._health.get_session_logs_by_uid = lambda uid: {}
    api._health.get_matches = lambda uid: []
    api._health.get_performance_logs = lambda uid: {'row_2km_minutes': [
        {'id': 1, 'value': 7.8, 'date': '2026-09-01', 'loggedOn': '2026-09-01', 'source': 'manual', 'note': None}]}
    api._health.get_progression_snapshot = lambda uid, key, kind: {'data': {'methodologies': [{'headlineSummary': {
        'label': 'Load on the bar', 'text': 'Back squat 102.5kg', 'trendText': None, 'status': 'on_track'}}]}}
    try:
        body = client.get('/api/user/today-session?date=2026-10-12&spec=1&week=1').get_json()
    finally:
        (src.db.get_user_program, src.db.get_user_profile, src.last_time.last_by_exercise,
         ph.active_version_id, api._get_user_max_hr, api._bio_for_scoring, api._compute_readiness,
         api._standards_context, api._health.get_session_logs, api._health.get_session_logs_by_uid,
         api._health.get_matches, api._health.get_performance_logs, api._health.get_progression_snapshot) = saved

    import json
    text = json.dumps(body, indent=2, sort_keys=True, ensure_ascii=False) + '\n'
    if write:
        with open(FIXTURE, 'w', encoding='utf-8') as f:
            f.write(text)
        print('wrote', FIXTURE)
        return []
    try:
        with open(FIXTURE, encoding='utf-8') as f:
            committed = json.load(f)
    except FileNotFoundError:
        return [f'{FIXTURE} missing: run with --write']
    if committed != json.loads(text):
        return ['data/watch_day_fixture.json is not what the route sends: rerun with --write '
                'and check WatchDayTests (the Apple Watch decodes it)']
    # What the fixture must exercise, or the Swift tests prove less than they say.
    exercises = [e for x in body['sessions'] for e in x['exercises']]
    problems = []
    if not any(e.get('exerciseId') is None for e in exercises):
        problems.append('fixture lost its meta block (no exerciseId)')
    if not any(e.get('standard') for e in exercises):
        problems.append("fixture lost its test step's standard")
    if not any(e.get('logs') == ['reps'] for e in exercises):
        problems.append("fixture lost its timed kettlebell set's logs (reps asked at the end)")
    if any(e.get('logs') for e in exercises if e.get('standard')):
        problems.append('a test step asks for its result, never for logs')
    if len(body.get('days') or []) != 7:
        problems.append('fixture lost its week ahead')
    if body.get('maxHR') != 186 or not (body.get('readiness') or {}).get('score'):
        problems.append('fixture lost maxHR or readiness')
    return problems


if __name__ == '__main__':
    sys.exit(run())
