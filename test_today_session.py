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


PROGRAM = {
    'programStartDate': '2026-10-05',          # a Monday
    'currentProgram': {'weeks': [{
        'week_number': 1,
        'schedule': {
            'Friday': [_session('Strength A'), _session('PT Prep', 'strength_endurance', 25)],
            'Saturday': [_session('Ruck', 'aerobic_base', 90)],
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

    for f in failures:
        print('FAIL', f)
    print('ok' if not failures else f'{len(failures)} failure(s)')
    return 0 if not failures else 1


if __name__ == '__main__':
    sys.exit(run())
