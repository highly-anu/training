"""Log ▸ Linking on the server: src/linking.py, the copy of the web's
lib/linking.ts the phone reads through GET /api/health/linking.

The cases are lib/linking.test.ts's, so the two stay one model. The route
runs with the store stubbed. No database.
"""
import os
os.environ.setdefault('SUPABASE_URL', '')

from src import linking

# Starts Monday 2026-10-05.
PROGRAM = {'weeks': [{
    'week_number': 1,
    'schedule': {
        'Monday': [
            {'modality': 'max_strength', 'archetype': {'name': 'Heavy Day', 'duration_estimate_minutes': 60}, 'exercises': []},
            {'modality': 'aerobic_base', 'archetype': {'name': 'Zone 2', 'duration_estimate_minutes': 45}, 'exercises': []},
        ],
        'Wednesday': [
            {'modality': 'aerobic_base', 'archetype': {'name': 'Long Zone 2', 'duration_estimate_minutes': 90}, 'exercises': []},
        ],
        'Saturday': [
            {'modality': 'max_strength', 'archetype': {'name': 'Volume Day', 'duration_estimate_minutes': 60}, 'exercises': []},
        ],
    },
}]}


def workout(id, day, modality, minutes, activity=None):
    return {'id': id, 'source': 'garmin', 'date': day, 'startTime': f'{day}T07:00:00Z',
            'durationMinutes': minutes, 'inferredModalityId': modality,
            'activityType': activity or ('running' if modality == 'aerobic_base' else 'strength_training')}


def match(workout_id, key, **extra):
    return {'importedWorkoutId': workout_id, 'sessionKey': key, 'matchConfidence': 'manual', **extra}


def days(workouts=(), matches=(), pending=(), history=(), version=None, dismissed=frozenset()):
    return linking.build_linking_days(
        workouts=list(workouts), matches=list(matches), pending=list(pending),
        program=PROGRAM, program_start_date='2026-10-05', program_version_id=version,
        history=list(history), today='2026-10-08', dismissed=dismissed)


def on(ds, day):
    return next(d for d in ds if d['date'] == day)


def planned(vid, day, day_name, modality, minutes, name, **extra):
    row = {'sessionUid': f'{vid}:w0-{day_name}-0', 'programVersionId': vid, 'date': day,
           'weekIndex': 0, 'weekNumber': 1, 'dayName': day_name, 'sessionIndex': 0,
           'sessionKey': f'1-{day_name}-0', 'modality': modality, 'archetypeName': name,
           'durationMinutes': minutes}
    row.update(extra)
    return row


HISTORY = [
    planned('old', '2026-09-28', 'Monday', 'aerobic_base', 45, 'Old Zone 2'),
    planned('old', '2026-10-01', 'Thursday', 'max_strength', 60, 'Old Heavy', completedAt='2026-10-01T18:00:00Z'),
    planned('cur', '2026-10-05', 'Monday', 'max_strength', 60, 'Heavy Day'),   # the current version's own
]


def test_program_sessions_on_their_days():
    s = linking.program_sessions(PROGRAM, '2026-10-05', None)
    assert s['1-Monday-1']['date'] == '2026-10-05'
    assert s['1-Wednesday-0']['date'] == '2026-10-07'
    assert s['1-Wednesday-0']['name'] == 'Long Zone 2'
    assert s['1-Wednesday-0']['uid'] is None
    assert linking.program_sessions(PROGRAM, '2026-10-05', 'cur')['1-Wednesday-0']['uid'] == 'cur:w0-Wednesday-0'


def test_suggest_one_to_one_best_first():
    mon = [s for s in linking.program_sessions(PROGRAM, '2026-10-05', None).values() if s['date'] == '2026-10-05']
    run, lift = workout('run', '2026-10-05', 'aerobic_base', 44), workout('lift', '2026-10-05', 'max_strength', 62)
    out = linking.suggest_for_day([run, lift], mon)
    assert sorted((p['workout']['id'], p['session']['key']) for p in out) == [('lift', '1-Monday-0'), ('run', '1-Monday-1')]
    out = linking.suggest_for_day([run], mon, {linking.dismiss_key('run', '1-Monday-1')})
    assert all(p['session']['key'] != '1-Monday-1' for p in out)


def test_one_card_per_day_up_to_today():
    assert [d['date'] for d in days()] == ['2026-10-07', '2026-10-05']   # Saturday is after today


def test_only_suggests_within_the_workouts_day():
    ds = days([workout('tue', '2026-10-06', 'aerobic_base', 88)])
    tue = on(ds, '2026-10-06')
    assert tue['suggestions'] == [] and [w['id'] for w in tue['workouts']] == ['tue'] and tue['needsAttention']
    assert on(ds, '2026-10-07')['suggestions'] == []


def test_pending_suggestion_only_within_the_day():
    tue = workout('tue', '2026-10-06', 'aerobic_base', 88)
    ds = days([tue], pending=[{'importedWorkoutId': 'tue', 'sessionKey': '1-Wednesday-0'}])
    assert all(d['suggestions'] == [] for d in ds)
    run = workout('run', '2026-10-07', 'aerobic_base', 30)
    wed = on(days([run], pending=[{'importedWorkoutId': 'run', 'sessionKey': '1-Wednesday-0'}]), '2026-10-07')
    assert len(wed['suggestions']) == 1 and wed['suggestions'][0]['fromPending'] and wed['sessions'] == []


def test_cross_date_link_on_both_days():
    ds = days([workout('tue', '2026-10-06', 'aerobic_base', 88)], [match('tue', '1-Wednesday-0')])
    assert len(on(ds, '2026-10-06')['links']) == 1
    wed = on(ds, '2026-10-07')
    assert len(wed['links']) == 1 and wed['sessions'] == [] and not wed['needsAttention']


def test_another_versions_match_is_elsewhere():
    ds = days([workout('run', '2026-10-07', 'aerobic_base', 90)],
              [match('run', '1-Wednesday-0', sessionUid='v1:w0-Wednesday-0')], version='v2')
    wed = on(ds, '2026-10-07')
    assert wed['links'] == [] and [e['workout']['id'] for e in wed['elsewhere']] == ['run']
    assert [s['key'] for s in wed['sessions']] == ['1-Wednesday-0']


def test_declined_is_not_suggested():
    wed = on(days([workout('run', '2026-10-07', 'aerobic_base', 90)],
                  [match('run', '', matchConfidence='rejected')]), '2026-10-07')
    assert wed['suggestions'] == [] and [w['id'] for w in wed['declined']] == ['run'] and not wed['needsAttention']


def test_workouts_before_every_program_are_left_out():
    assert all(d['date'] != '2026-09-30' for d in days([workout('old', '2026-09-30', 'aerobic_base', 45)]))


def test_earlier_programs_days():
    ds = days(history=HISTORY, version='cur')
    assert [(d['date'], d['historical']) for d in ds] == [
        ('2026-10-07', False), ('2026-10-05', False), ('2026-10-01', True), ('2026-09-28', True)]
    assert on(ds, '2026-09-28')['programVersionId'] == 'old'
    assert [s['name'] for s in on(ds, '2026-10-05')['sessions']] == ['Heavy Day', 'Zone 2']


def test_a_day_an_earlier_program_ran_is_its_day():
    overlap = [planned('old', '2026-10-05', 'Monday', 'mobility', 30, 'Old Mobility',
                       sessionUid='old:w1-Monday-0', weekIndex=1, weekNumber=2, sessionKey='2-Monday-0')]
    ds = days([workout('lift', '2026-10-05', 'max_strength', 60)],
              [match('lift', '1-Monday-0', sessionUid='cur:w0-Monday-0')], history=overlap, version='cur')
    mon = on(ds, '2026-10-05')
    assert mon['historical'] and [s['name'] for s in mon['sessions']] == ['Old Mobility']
    assert [l['session']['name'] for l in mon['links']] == ['Heavy Day']
    assert not on(ds, '2026-10-07')['historical']


def test_suggests_within_an_earlier_programs_day():
    mon = on(days([workout('run', '2026-09-28', 'aerobic_base', 44)], history=HISTORY, version='cur'), '2026-09-28')
    assert [(p['workout']['id'], p['session']['uid'], p['session']['historical']) for p in mon['suggestions']] == [
        ('run', 'old:w0-Monday-0', True)]


def test_resolves_a_match_by_uid_across_days():
    ds = days([workout('tue', '2026-09-29', 'aerobic_base', 45)],
              [match('tue', '1-Monday-0', sessionUid='old:w0-Monday-0')], history=HISTORY, version='cur')
    assert [l['session']['name'] for l in on(ds, '2026-09-28')['links']] == ['Old Zone 2']
    assert len(on(ds, '2026-09-29')['links']) == 1
    assert on(ds, '2026-10-05')['links'] == []


def test_old_unscoped_match_by_key_on_the_workouts_date():
    thu = on(days([workout('lift', '2026-10-01', 'max_strength', 60)],
                  [match('lift', '1-Thursday-0', inCurrentProgram=False)], history=HISTORY, version='cur'), '2026-10-01')
    assert [l['session']['uid'] for l in thu['links']] == ['old:w0-Thursday-0'] and thu['elsewhere'] == []


def test_wire_is_slim_and_labelled():
    w = dict(workout('run', '2026-09-28', 'aerobic_base', 44), heartRate={'samples': [1] * 500}, gpsTrack=[{}] * 500)
    wire = linking.to_wire(days([w], history=HISTORY, version='cur'), {'old': 'Uphill Athlete'})
    mon = next(d for d in wire if d['date'] == '2026-09-28')
    assert mon['programLabel'] == 'Uphill Athlete'
    sent = mon['suggestions'][0]['workout']
    assert 'heartRate' not in sent and 'gpsTrack' not in sent and sent['id'] == 'run'
    assert mon['suggestions'][0]['session']['uid'] == 'old:w0-Monday-0'
    import json
    json.dumps(wire)


def test_route():
    import api
    from src import db, program_history
    seen = {}
    stubs = {
        (api._health, 'get_workouts'): lambda uid, summary_only=False: [workout('run', '2026-09-28', 'aerobic_base', 44)],
        (api._health, 'get_matches'): lambda uid: [],
        (api._health, 'get_match_suggestions'): lambda uid: [],
        (db, 'get_user_program'): lambda uid: {'currentProgram': PROGRAM, 'programStartDate': '2026-10-05'},
        (program_history, 'active_version_id'): lambda uid: 'cur',
        (program_history, 'list_activations'): lambda uid: [{'versionId': 'old', 'label': 'Old', 'goalName': None}],
        (api, '_planned_sessions_json'): lambda uid, f, t, matches=None: (seen.update(span=(f, t)), HISTORY)[1],
    }
    orig = {k: getattr(*k) for k in stubs}
    for (mod, name), fn in stubs.items():
        setattr(mod, name, fn)
    try:
        c = api.app.test_client()
        body = c.get('/api/health/linking?today=2026-10-08&dismissed=run|old:w0-Monday-0').get_json()
        assert seen['span'] == ('2026-09-28', '2026-10-08'), 'history from the oldest workout to today'
        assert body['programVersionId'] == 'cur'
        mon = next(d for d in body['days'] if d['date'] == '2026-09-28')
        assert mon['suggestions'] == [] and [w['id'] for w in mon['workouts']] == ['run'], 'dismissed'
        assert mon['programLabel'] == 'Old'
        body = c.get('/api/health/linking?today=2026-10-08').get_json()
        mon = next(d for d in body['days'] if d['date'] == '2026-09-28')
        assert len(mon['suggestions']) == 1
        assert c.get('/api/health/linking?today=8.10.2026').status_code == 400
    finally:
        for (mod, name), fn in orig.items():
            setattr(mod, name, fn)


if __name__ == '__main__':
    tests = [v for k, v in dict(globals()).items() if k.startswith('test_')]
    for t in tests:
        t()
        print('ok', t.__name__)
    print(f'all {len(tests)} passed')
