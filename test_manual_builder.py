"""Sessions composed by hand (src/manual_builder.py) and their routes.

A session is blocks of existing exercises; it is written as an archetype the
engine already runs, read back as the session it was, and every session of an
athlete is one package of theirs that passes the gates.

    SUPABASE_URL='' .venv/bin/python test_manual_builder.py
    SUPABASE_URL='' .venv/bin/python test_manual_builder.py --write   # the web's fixture
"""
from __future__ import annotations

import json
import os
import sys
import tempfile

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
os.environ.pop('PACKAGE_BUILDER', None)
os.environ['TRAINING_USER_PACKAGES_DIR'] = tempfile.mkdtemp(prefix='manual-sessions-')

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
FIXTURE = os.path.join(ROOT, 'frontend', 'src', 'mocks', 'fixtures', 'manual-sessions.json')

from src import loader, manual_builder as mb, package_store  # noqa: E402

FAILURES: list[str] = []


def check(label, ok, detail=None):
    print(f"  {'ok  ' if ok else 'FAIL'} {label}" + ('' if ok or detail is None else f'\n       {str(detail)[:600]}'))
    if not ok:
        FAILURES.append(label)


CAT = mb.catalog()
EX = CAT['exercises']
ROW = next(i for i, e in sorted(EX.items()) if 'row' in i and 'aerobic_base' in (e.get('modality') or []))
HOLD = next(i for i, e in sorted(EX.items()) if 'plank' in i)
RUN = next(i for i, e in sorted(EX.items()) if 'run' in i and 'aerobic_base' in (e.get('modality') or []))

SESSION = {'name': 'Squat day', 'modality': 'max_strength', 'notes': 'Belt on for the top sets.', 'blocks': [
    {'kind': 'practice', 'stage': 'prep', 'minutes': 5, 'movements': [{'exercise_id': 'squat_air'}]},
    {'kind': 'sets', 'stage': 'main', 'intensity': 'heavy', 'movements': [
        {'exercise_id': 'back_squat', 'sets': 3, 'reps': 5, 'start_kg': 80, 'rest_sec': 180,
         'progress': {'add_kg': 2.5}, 'note': 'Below parallel.'}]},
    {'kind': 'superset', 'stage': 'main', 'rounds': 3, 'rest_sec': 90, 'movements': [
        {'exercise_id': 'pull_up', 'reps': 'max'},
        {'exercise_id': 'push_up', 'reps': 12, 'progress': {'add_reps': 1, 'top_reps': 15}}]},
    {'kind': 'amrap', 'stage': 'finisher', 'minutes': 20, 'movements': [
        {'exercise_id': 'pull_up', 'reps': 5}, {'exercise_id': 'push_up', 'reps': 10},
        {'exercise_id': 'squat_air', 'reps': 15}]},
    {'kind': 'timed', 'stage': 'cooldown', 'minutes': 30, 'intensity': 'zone2', 'movements': [{'exercise_id': ROW}]},
]}

EVERY_KIND = {'name': 'Everything', 'modality': 'mixed_modal_conditioning', 'blocks': [
    {'kind': 'sets', 'movements': [{'exercise_id': 'back_squat', 'sets': 5, 'reps': '5-3-1', 'load_text': 'work up'}]},
    {'kind': 'alternate', 'rounds': 4, 'movements': [{'exercise_id': 'pull_up', 'reps': 5},
                                                    {'exercise_id': 'push_up', 'reps': 10}]},
    {'kind': 'rounds', 'rounds': 3, 'rest_sec': 60, 'note': 'Smooth.', 'progress': {'add_rounds': 1}, 'movements': [
        {'exercise_id': 'push_up', 'reps': 10}, {'exercise_id': RUN, 'distance_m': 200}]},
    {'kind': 'for_time', 'rounds': 3, 'cap_min': 10, 'movements': [
        {'exercise_id': 'squat_air', 'rep_scheme': [21, 15, 9], 'start_kg': 43},
        {'exercise_id': 'pull_up', 'rep_scheme': '21-15-9'}]},
    {'kind': 'emom', 'minutes': 10, 'movements': [{'exercise_id': 'push_up', 'reps': 8}]},
    {'kind': 'interval', 'rounds': 8, 'work_sec': 20, 'rest_sec': 60, 'rest_until_hr_pct': 70, 'intensity': 'zone4',
     'movements': [{'exercise_id': ROW, 'seconds': 20}]},
    {'kind': 'distance', 'rest_sec': 90, 'intensity': 'zone3', 'movements': [
        {'exercise_id': RUN, 'distance_m': 400, 'sets': 4, 'progress': {'add_m': 100}}]},
    {'kind': 'hold', 'rest_sec': 30, 'stage': 'finisher', 'movements': [
        {'exercise_id': HOLD, 'sets': 3, 'hold_sec': 30, 'progress': {'add_sec': 5}}]},
]}


def test_round_trip():
    print('a session is written as an archetype and read back as itself')
    for session in (SESSION, EVERY_KIND):
        arch, problems = mb.to_archetype(session, 'u1_ms_x', CAT)
        check(f"{session['name']}: reads", arch is not None, problems)
        if arch is None:
            continue
        back = mb.from_archetype(arch)
        again, problems = mb.to_archetype(back, 'u1_ms_x', CAT)
        check(f"{session['name']}: the session read back writes the same archetype", again == arch, problems)
        check(f"{session['name']}: every block keeps its kind and stage",
              [(b['kind'], b['stage']) for b in back['blocks']]
              == [(b['kind'], b.get('stage', 'main')) for b in session['blocks']],
              [(b['kind'], b['stage']) for b in back['blocks']])
    arch, _ = mb.to_archetype(SESSION, 'u1_ms_x', CAT)
    by_role = {s['role']: s for s in arch['slots']}
    check('a piece is its first movement, the others its children',
          by_role['b4']['slot_type'] == 'amrap' and by_role['b4']['duration_sec'] == 1200
          and [by_role[r].get('parent_slot_role') for r in ('b4_2', 'b4_3')] == ['b4', 'b4'], by_role.get('b4'))
    check('a superset is slots sharing a group',
          by_role['b3_1']['group'] == by_role['b3_2']['group'] == {'id': 'b3', 'kind': 'superset'}
          and by_role['b3_1']['sets'] == 3)
    check('every slot names its exercise, first as written, and its stage',
          all(s['exercise_filter'] == {'exercise_ids': s['exercise_filter']['exercise_ids'], 'ordered': True}
              and s['stage'] in mb.STAGES for s in arch['slots']))
    check('the weight and its steps are the slot\'s own',
          by_role['b2']['start_kg'] == 80 and by_role['b2']['progress'] == {'add_kg': 2.5})
    check('equipment, minutes and the as-written mark are derived',
          'barbell' in arch['required_equipment'] and arch['pool_only'] and arch['duration_estimate_minutes'] >= 60, arch)


def test_problems():
    print('what stops a session is said at its block')
    cases = [
        ({**SESSION, 'name': ' '}, 'name', None),
        ({**SESSION, 'modality': 'nope'}, 'modality', None),
        ({**SESSION, 'blocks': []}, None, None),
        ({**SESSION, 'blocks': [{'kind': 'sets', 'movements': [{'exercise_id': 'no_such', 'sets': 3, 'reps': 5}]}]},
         'exercise_id', 0),
        ({**SESSION, 'blocks': [{'kind': 'sets', 'movements': [{'exercise_id': 'back_squat', 'reps': 5}]}]}, 'sets', 0),
        ({**SESSION, 'blocks': [{'kind': 'amrap', 'movements': [{'exercise_id': 'pull_up', 'reps': 5}]}]}, 'minutes', 0),
        ({**SESSION, 'blocks': [SESSION['blocks'][1], {'kind': 'timed', 'movements': [{'exercise_id': ROW}]}]},
         'minutes', 1),
        ({**SESSION, 'blocks': [{'kind': 'superset', 'rounds': 3, 'movements': [{'exercise_id': 'pull_up', 'reps': 5}]}]},
         None, 0),
        ({**SESSION, 'blocks': [{'kind': 'interval', 'rounds': 5, 'work_sec': 20, 'rest_until_hr_pct': 70,
                                 'movements': [{'exercise_id': ROW, 'seconds': 20}]}]}, 'rest_sec', 0),
    ]
    for session, field, block in cases:
        arch, problems = mb.to_archetype(session, 'u1_ms_x', CAT)
        check(f'refused: {field or "structure"} (block {block})',
              arch is None and any(p['field'] == field and p['block'] == block and p['message'] for p in problems),
              problems)


def test_package():
    print('every session of an athlete is one package that passes the gates')
    user = 'user-ann'
    prefix = package_store.owner_prefix(user)
    archetypes = []
    for session in (SESSION, EVERY_KIND, {**SESSION, 'name': 'Squat day'}, {**EVERY_KIND, 'name': 'Fourth'}):
        aid = mb.new_session_id(prefix, session['name'], [a['id'] for a in archetypes])
        arch, problems = mb.to_archetype(session, aid, CAT)
        assert arch, problems
        archetypes.append(arch)
    check('ids carry the owner\'s prefix and never collide',
          [a['id'][len(prefix):] for a in archetypes] == ['ms_squat_day', 'ms_everything', 'ms_squat_day_2', 'ms_fourth'],
          [a['id'] for a in archetypes])
    files = mb.compose(archetypes, prefix, CAT)
    result = package_store.install(user, files)
    check('it installs through every gate', result.get('installed') and result['ran'][-1] == 'provenance',
          {'problems': result.get('problems', [])[:4], 'skipped': result.get('skipped')})
    check('with no warning about its own sessions', not result.get('warnings'), result.get('warnings'))
    stored = package_store.get_package(user, mb.package_id(prefix))
    check('and reads back in the order composed', mb.stored_archetypes(stored['files']) == archetypes)
    with loader.overlay(package_store.overlay_for(user)):
        d = mb.described(archetypes[0])
        check('the server words the first weeks of what moves',
              d['forecast'][0] == {'role': 'b2', 'exercise': EX['back_squat']['name'],
                                   'weeks': ['3 × 5 @ 80 kg', '3 × 5 @ 82.5 kg', '3 × 5 @ 85 kg', '3 × 5 @ 87.5 kg']},
              d['forecast'])
        check('and derives the blocks every client draws',
              [b['shape'] for b in d['preview']] == ['practice', 'sets', 'sets', 'sets', 'amrap', 'timed']
              and d['preview'][2]['group'] == {'id': 'b3', 'kind': 'superset'}
              and [b['stage'] for b in d['preview']] == ['prep', 'main', 'main', 'main', 'finisher', 'cooldown'],
              [(b['shape'], b['stage']) for b in d['preview']])
    package_store.remove(user, mb.package_id(prefix))


def test_routes(write: bool = False):
    print('the routes (local dev: every request is local-dev-user)')
    import api
    client = api.app.test_client()
    listed = client.get('/api/manual/sessions').get_json()
    check('nothing yet', listed['sessions'] == [] and listed['limits']['sessions'] == mb.MAX_SESSIONS, listed)
    draft = client.post('/api/manual/preview', json={'session': SESSION}).get_json()
    check('a draft is previewed without being stored', draft['ok'] and draft['session']['preview']
          and draft['session']['minutes'] and client.get('/api/manual/sessions').get_json()['sessions'] == [], draft)
    half = client.post('/api/manual/preview', json={'session': {**SESSION, 'blocks': [
        {'kind': 'sets', 'movements': [{'exercise_id': 'back_squat', 'reps': 5}]}]}}).get_json()
    check('a draft that cannot be saved says why, at its block', not half['ok'] and half['problems'][0]['block'] == 0, half)
    bad = client.post('/api/manual/sessions', json={'session': {**SESSION, 'name': ''}})
    check('saving one is refused the same way, 422', bad.status_code == 422 and bad.get_json()['problems'], bad.get_json())
    made = client.post('/api/manual/sessions', json={'session': SESSION})
    saved = (made.get_json() or {}).get('session') or {}
    check('saved', made.status_code == 200 and saved.get('id', '').endswith('ms_squat_day') and saved['preview'],
          made.get_json())
    sid = saved.get('id')
    second = client.post('/api/manual/sessions', json={'session': EVERY_KIND}).get_json()['session']
    listed = client.get('/api/manual/sessions').get_json()
    check('listed in the order made', [s['id'] for s in listed['sessions']] == [sid, second['id']], listed)
    check('and read back as the session sent',
          listed['sessions'][0]['blocks'][1]['movements'][0]['progress'] == {'add_kg': 2.5}
          and listed['sessions'][0]['notes'] == SESSION['notes'])
    edited = {**SESSION, 'name': 'Squat day, heavy', 'blocks': SESSION['blocks'][:2]}
    put = client.put(f'/api/manual/sessions/{sid}', json={'session': edited})
    check('edited in place: the id stays, the name and blocks change', put.status_code == 200
          and put.get_json()['session']['id'] == sid and put.get_json()['session']['name'] == 'Squat day, heavy'
          and len(put.get_json()['session']['blocks']) == 2, put.get_json())
    check('an unknown id is 404', client.put('/api/manual/sessions/zz', json={'session': SESSION}).status_code == 404
          and client.delete('/api/manual/sessions/zz').status_code == 404)
    check('the package is one of the athlete\'s, by its name',
          any(p['name'] == mb.PACKAGE_NAME for p in client.get('/api/packages').get_json()['packages']))

    constraints = {'days_per_week': 3, 'session_time_minutes': 90, 'training_level': 'intermediate',
                   'equipment': [e['id'] for e in api.loader.load_equipment()], 'injury_flags': []}
    weights = []
    for week in (1, 3):
        got = client.post('/api/sessions/generate', json={
            'modality': 'max_strength', 'phase': 'build', 'archetype_id': sid, 'add': True,
            'week_in_phase': week, 'constraints': constraints})
        body = got.get_json() or {}
        squat = next((e for e in body.get('exercises') or [] if (e.get('exercise') or {}).get('id') == 'back_squat'), {})
        weights.append((squat.get('load') or {}).get('weight_kg'))
        if week == 1:
            check('it can be added to a day: the session, as written, with its blocks', got.status_code == 200
                  and body.get('added') and (body.get('archetype') or {}).get('id') == sid and body.get('blocks'),
                  (got.status_code, str(body)[:300]))
    check('the weight is the one written, and week 3 the one it steps to', weights == [80, 85], weights)

    program = client.post('/api/programs/generate', json={
        'philosophy_id': listed['packageId'], 'constraints': constraints, 'num_weeks': 2, 'persist': False}).get_json()
    names = [s.get('archetype', {}).get('name') for w in program.get('weeks') or []
             for day in (w.get('schedule') or {}).values() for s in day]
    check('and a program generates from the package', 'Squat day, heavy' in names and 'Everything' in names, names)

    if write:
        with open(FIXTURE, 'w', encoding='utf-8') as fh:
            json.dump({'list': client.get('/api/manual/sessions').get_json(),
                       'preview': client.post('/api/manual/preview', json={'session': SESSION}).get_json(),
                       'refused': half}, fh, indent=1, ensure_ascii=False)
            fh.write('\n')
        print(f'  wrote {os.path.relpath(FIXTURE, ROOT)}')

    from src import db
    real = db.get_user_program
    db.get_user_program = lambda user_id: {'weeks': [{'schedule': {'Monday': [{'archetype': {'id': sid}}]}}]}
    try:
        held = client.delete(f'/api/manual/sessions/{sid}')
        check('a session on a day of the program cannot be deleted', held.status_code == 409
              and held.get_json()['error'] == 'in_use', held.get_json())
    finally:
        db.get_user_program = real
    check('deleted', client.delete(f'/api/manual/sessions/{sid}').status_code == 200
          and [s['id'] for s in client.get('/api/manual/sessions').get_json()['sessions']] == [second['id']])
    check('the last one takes the package with it', client.delete(f"/api/manual/sessions/{second['id']}").status_code == 200
          and client.get('/api/manual/sessions').get_json()['sessions'] == []
          and client.get('/api/packages').get_json()['packages'] == [])

    os.environ['PACKAGE_BUILDER'] = 'off'
    try:
        check('behind the builder\'s gate: off, they answer 403',
              client.get('/api/manual/sessions').status_code == 403
              and client.post('/api/manual/preview', json={'session': SESSION}).status_code == 403
              and client.post('/api/manual/sessions', json={'session': SESSION}).status_code == 403)
    finally:
        os.environ.pop('PACKAGE_BUILDER', None)


def test_fixture_is_current():
    print("the web's recorded answers have the server's shape")
    if not os.path.exists(FIXTURE):
        check('recorded (run with --write)', False)
        return
    with open(FIXTURE, encoding='utf-8') as fh:
        recorded = json.load(fh)
    arch, _ = mb.to_archetype(SESSION, 'x_ms_draft', CAT)
    now = mb.described(arch, CAT)
    was = recorded['preview']['session']
    check('the described session has the same keys', set(was) == set(now), sorted(set(was) ^ set(now)))
    check('and its blocks the same', [set(b) for b in was['preview']] == [set(b) for b in now['preview']])


if __name__ == '__main__':
    write = '--write' in sys.argv
    test_round_trip()
    test_problems()
    test_package()
    test_routes(write)
    test_fixture_is_current()
    print(f"\n{'FAILED: ' + ', '.join(FAILURES) if FAILURES else 'all passed'}")
    sys.exit(1 if FAILURES else 0)
