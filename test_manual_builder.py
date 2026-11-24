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
TRACK_FIXTURE = os.path.join(ROOT, 'frontend', 'src', 'mocks', 'fixtures', 'manual-tracks.json')

from src import loader, manual_builder as mb, package_store  # noqa: E402

FAILURES: list[str] = []


def check(label, ok, detail=None):
    print(f"  {'ok  ' if ok else 'FAIL'} {label}" + ('' if ok or detail is None else f'\n       {str(detail)[:600]}'))
    if not ok:
        FAILURES.append(label)


CAT = mb.catalog()


def db_module():
    from src import db
    return db
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
    short, _ = mb.to_archetype({'name': 'Ten minutes', 'modality': 'max_strength', 'blocks': [SESSION['blocks'][1]]},
                               mb.new_session_id(prefix, 'Ten minutes', []), CAT)
    alone = package_store.install(user, mb.compose([short], prefix, CAT))
    check('a short session alone is a package too (the validator wants twenty minutes of room)',
          short['duration_estimate_minutes'] < 20 and alone.get('installed'), alone.get('problems', [])[:2])
    on_a_track, _ = mb.read_track({'name': 'Short', 'phases': [{'name': 'P', 'kind': 'build', 'weeks': 2,
                                   'template': [[{'sessions': [short['id']]}] + [REST] * 6]}]}, 'short', [short], CAT)
    laid = package_store.install(user, mb.compose([short], prefix, CAT, [on_a_track]))
    check('and so is a program of it', laid.get('installed')
          and mb.described_track(on_a_track, [short], prefix, CAT)['startWith']['session_time_minutes'] == 20,
          laid.get('problems', [])[:2])
    package_store.remove(user, mb.package_id(prefix))


REST = {'sessions': []}


def week(**days):
    """A template week: week(mon=[...], wed={...}) → seven days."""
    names = ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')
    return [({'sessions': days[n]} if isinstance(days.get(n), list) else days.get(n) or REST) for n in names]


def track_of(a: str, b: str) -> dict:
    """Two phases, a lighter week every fourth, one day of two sessions."""
    return {'name': 'Strength block', 'deload_every': 4, 'phases': [
        {'name': 'Build', 'kind': 'build', 'weeks': 4, 'template': [
            week(mon=[a], wed=[b], fri=[a, b]),
            week(mon=[a], thu={'sessions': [b], 'light': True})]},
        {'name': 'Peak', 'kind': 'peak', 'weeks': 2, 'template': [week(tue=[a], sat=[b])]}]}


def test_tracks():
    print('a program laid out by hand is a track of the same package')
    user = 'user-cat'
    prefix = package_store.owner_prefix(user)
    archetypes = []
    for session in (SESSION, {**SESSION, 'name': 'Second', 'blocks': SESSION['blocks'][1:2]}):
        aid = mb.new_session_id(prefix, session['name'], [a['id'] for a in archetypes])
        archetypes.append(mb.to_archetype(session, aid, CAT)[0])
    a, b = (x['id'] for x in archetypes)
    track, problems = mb.read_track(track_of(a, b), mb.new_track_id('Strength block', []), archetypes, CAT)
    check('reads, with ids given', track is not None and track['id'] == 'strength_block'
          and [p['id'] for p in track['phases']] == ['build', 'peak'], problems)
    files = mb.compose(archetypes, prefix, CAT, [track])
    check('the Library track gives way to it', [t['id'] for t in __import__('yaml').safe_load(files['philosophy.yaml'])['tracks']]
          == ['strength_block'])
    check('read back from the files as it was sent', mb.stored_tracks(files, prefix) == [track],
          mb.stored_tracks(files, prefix))
    check('and composed again to the same files', mb.compose(archetypes, prefix, CAT, mb.stored_tracks(files, prefix)) == files)
    result = package_store.install(user, files)
    check('it installs through every gate', result.get('installed'), result.get('problems', [])[:4])

    with loader.overlay(package_store.overlay_for(user)):
        from src.generator import generate
        from src.goals import philosophy_to_goal
        d = mb.described_track(track, archetypes, prefix)
        goal = philosophy_to_goal(mb.package_id(prefix), list(loader.load_all_frameworks().values()), track_id=track['id'])
        constraints = {**d['startWith'], 'training_level': 'intermediate', 'injury_flags': [],
                       'equipment': sorted(CAT['equipment']), 'preferred_days': [2, 4, 6, 7]}
        raw = generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints, num_weeks=6, output_format='dict')
    weeks = raw['weeks']
    days = [sorted(w['schedule']) for w in weeks]
    check('sessions fall on the days they were laid on, whatever the preferred days',
          days == [[1, 3, 5], [1, 4], [1, 3, 5], [1, 4], [2, 6], [2, 6]], days)
    friday = weeks[0]['schedule'][5][0]
    check('a day of two sessions is one session of both', friday['archetype']['name'] == 'Squat day + Second'
          and len(friday.get('pieces') or []) == 2, friday['archetype']['name'])

    def squat(w, day):
        return next(e['load'] for e in weeks[w]['schedule'][day][0]['exercises']
                    if (e.get('exercise') or {}).get('id') == 'back_squat')
    kgs = [squat(0, 1)['weight_kg'], squat(1, 1)['weight_kg'], squat(2, 1)['weight_kg'], squat(3, 1)['weight_kg'],
           squat(4, 2)['weight_kg'], squat(5, 2)['weight_kg']]
    check('the weight steps on through the phases, and the fourth week is lighter',
          kgs == [80, 82.5, 85, 68, 90, 92.5], kgs)
    check('the lighter week is a deload week of light days', weeks[3]['is_deload']
          and all(s.get('light') for day in weeks[3]['schedule'].values() for s in day)
          and not weeks[2]['is_deload'])
    check('the server says the same numbers before anything is generated',
          [(x['week'], x['text'], x['light']) for x in d['forecast'][0]['weeks']][:5]
          == [(1, '3 × 5 @ 80 kg', False), (2, '3 × 5 @ 82.5 kg', False), (3, '3 × 5 @ 85 kg', False),
              (4, '3 × 5 @ 68 kg', True), (5, '3 × 5 @ 90 kg', False)], d['forecast'][0]['weeks'][:5])
    check('and describes each phase', d['totalWeeks'] == 6 and d['phases'][0]['lighterWeeks'] == [4]
          and d['phases'][0]['sessionsPerWeek'] == 2.5 and d['phases'][1]['firstWeek'] == 5
          and d['phases'][0]['weeksDescribed'][0][4]['sessions'][1]['name'] == 'Second'
          and d['startWith']['session_time_minutes'] == d['phases'][0]['weeksDescribed'][0][4]['minutes'], d['phases'][0])

    print('what stops a program is said at its phase, week and day')
    base = track_of(a, b)
    def refused(change, **at):
        t = json.loads(json.dumps(base))
        change(t)
        got, problems = mb.read_track(t, 'x', archetypes, CAT)
        ok = got is None and any(all(p[k] == v for k, v in at.items()) and p['message'] for p in problems)
        check(f'refused at {at}', ok, problems)
    refused(lambda t: t.update(name=''), field='name')
    refused(lambda t: t.update(deload_every=1), field='deload_every')
    refused(lambda t: t.update(phases=[]), phase=None)
    refused(lambda t: t['phases'][0].update(kind='nope'), phase=0, field='kind')
    refused(lambda t: t['phases'][1].update(weeks=0), phase=1, field='weeks')
    refused(lambda t: t['phases'][0]['template'].__setitem__(0, week()), phase=0, week=0)
    refused(lambda t: t['phases'][0]['template'][0].__setitem__(0, {'sessions': ['gone']}), phase=0, week=0, day=0)
    refused(lambda t: t['phases'][0]['template'][0].__setitem__(4, {'sessions': [a, b, a]}), phase=0, week=0, day=4)
    check('a session on a day is named by the programs that place it', mb.tracks_placing([track], a) == ['Strength block']
          and mb.tracks_placing([track], 'other') == [])
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

    print('the track routes')
    empty = client.get('/api/manual/tracks').get_json()
    check('no program yet, and the kinds a phase may take', empty['tracks'] == [] and {'id': 'build', 'label': 'Build',
          'excludesMaxEffort': False} in empty['kinds'] and empty['limits']['phases'] == mb.MAX_PHASES, empty)
    plan = track_of(sid, second['id'])
    seen = client.post('/api/manual/tracks/preview', json={'track': plan}).get_json()
    check('a draft is described without being stored', seen['ok'] and seen['track']['totalWeeks'] == 6
          and client.get('/api/manual/tracks').get_json()['tracks'] == [], seen)
    wrong = client.post('/api/manual/tracks', json={'track': {**plan, 'name': ''}})
    check('a program that cannot be saved is refused, 422', wrong.status_code == 422 and wrong.get_json()['problems'])
    made_track = client.post('/api/manual/tracks', json={'track': plan})
    tid = ((made_track.get_json() or {}).get('track') or {}).get('id')
    check('saved', made_track.status_code == 200 and tid == 'strength_block', made_track.get_json())
    renamed = client.put(f'/api/manual/sessions/{sid}', json={'session': {**edited, 'name': 'Squat day, heavy'}})
    kept_tracks = client.get('/api/manual/tracks').get_json()['tracks']
    check('saving a session keeps the program', renamed.status_code == 200 and [t['id'] for t in kept_tracks] == [tid]
          and kept_tracks[0]['phases'][0]['template'] == made_track.get_json()['track']['phases'][0]['template'])
    held_session = client.delete(f'/api/manual/sessions/{sid}')
    check('a session a program places cannot be deleted', held_session.status_code == 409
          and held_session.get_json()['error'] == 'in_track' and held_session.get_json()['tracks'] == ['Strength block'],
          held_session.get_json())
    change = client.put(f'/api/manual/tracks/{tid}', json={'track': {**plan, 'name': 'Strength block II', 'deload_every': None}})
    check('edited in place', change.status_code == 200 and change.get_json()['track']['id'] == tid
          and change.get_json()['track']['name'] == 'Strength block II'
          and change.get_json()['track']['phases'][0]['lighterWeeks'] == [], change.get_json())
    check('an unknown program is 404', client.put('/api/manual/tracks/zz', json={'track': plan}).status_code == 404
          and client.delete('/api/manual/tracks/zz').status_code == 404)
    start = change.get_json()['track']
    built = client.post('/api/programs/generate', json={
        'philosophy_id': listed['packageId'], 'track_id': tid, 'num_weeks': 6, 'persist': False,
        'constraints': {**constraints, **start['startWith'], 'preferred_days': [2, 4, 6]}}).get_json()
    laid = [sorted(w['schedule']) for w in built.get('weeks') or []]
    check('the program generates on the laid days through the API',
          laid[:2] == [['Friday', 'Monday', 'Wednesday'], ['Monday', 'Thursday']]
          and built['weeks'][0].get('framework') == start['frameworkId'], laid)
    methods = client.get('/api/methods').get_json()['methods']
    check('the package is marked as composed by hand', [m['composed'] for m in methods if m['name'] == mb.PACKAGE_NAME] == [True])
    tracks_answer = client.get('/api/manual/tracks').get_json()
    db_real = db_module().get_user_program
    db_module().get_user_program = lambda user_id: {'weeks': [{'framework': start['frameworkId']}]}
    try:
        running = client.delete(f'/api/manual/tracks/{tid}')
        check('a program the athlete is running cannot be deleted', running.status_code == 409
              and running.get_json()['error'] == 'in_use', running.get_json())
    finally:
        db_module().get_user_program = db_real
    check('deleted, and the Library track is back', client.delete(f'/api/manual/tracks/{tid}').status_code == 200
          and client.get('/api/manual/tracks').get_json()['tracks'] == []
          and client.post('/api/programs/generate', json={'philosophy_id': listed['packageId'], 'constraints': constraints,
                                                          'num_weeks': 1, 'persist': False}).get_json().get('weeks'))

    if write:
        with open(TRACK_FIXTURE, 'w', encoding='utf-8') as fh:
            json.dump({'list': tracks_answer, 'preview': seen}, fh, indent=1, ensure_ascii=False)
            fh.write('\n')
        print(f'  wrote {os.path.relpath(TRACK_FIXTURE, ROOT)}')
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
    if not os.path.exists(TRACK_FIXTURE):
        check('the tracks recorded (run with --write)', False)
        return
    with open(TRACK_FIXTURE, encoding='utf-8') as fh:
        tracks = json.load(fh)
    keys = {'id', 'name', 'description', 'deload_every', 'phases', 'totalWeeks', 'frameworkId', 'equipment',
            'forecast', 'startWith'}
    check('a described program has the keys the web reads', set(tracks['preview']['track']) == keys
          and all(set(t) == keys for t in tracks['list']['tracks']), sorted(set(tracks['preview']['track']) ^ keys))


if __name__ == '__main__':
    write = '--write' in sys.argv
    test_round_trip()
    test_problems()
    test_package()
    test_tracks()
    test_routes(write)
    test_fixture_is_current()
    print(f"\n{'FAILED: ' + ', '.join(FAILURES) if FAILURES else 'all passed'}")
    sys.exit(1 if FAILURES else 0)
