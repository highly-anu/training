"""The pre-workout briefing (src/briefing.py, src/briefing_spec.py): pure.

Sessions are the generator's own (a Wildman General Practice program, a
Starting Strength one, a templated one), the logs written by hand.
"""
from __future__ import annotations

import copy
import os
from datetime import date, timedelta

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''

import api  # noqa: E402
from src import briefing, briefing_spec, training_contract  # noqa: E402

EQUIPMENT = ['kettlebell', 'barbell', 'rack', 'plates', 'pull_up_bar', 'bench', 'open_space', 'rower',
             'dumbbell', 'jump_rope', 'box', 'rings', 'medicine_ball']
START = date(2026, 11, 2)   # a Monday
DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
_PROGRAMS: dict = {}


def program(philosophy: str, level: str, days: int = 4, weeks: int = 4) -> dict:
    key = (philosophy, level, days, weeks)
    if key not in _PROGRAMS:
        r = api.app.test_client().post('/api/programs/generate', json={
            'philosophy_id': philosophy, 'num_weeks': weeks, 'persist': False,
            'constraints': {'training_level': level, 'days_per_week': days, 'session_time_minutes': 60,
                            'equipment': EQUIPMENT, 'injury_flags': []}})
        body = r.get_json()
        assert r.status_code == 200 and body['weeks'], (philosophy, body.get('validation'))
        _PROGRAMS[key] = body
    return copy.deepcopy(_PROGRAMS[key])


def sessions(prog: dict) -> list[dict]:
    """Every session in calendar order: {date, key, session}."""
    out = []
    for wi, w in enumerate(prog['weeks']):
        for day in DAYS:
            for i, s in enumerate((w['schedule'].get(day) or [])):
                out.append({'date': str(START + timedelta(days=wi * 7 + DAYS.index(day))),
                            'key': f"{w['week_number']}-{day}-{i}", 'session': s, 'current': True})
    return out


def with_module(rows: list[dict], module: str) -> list[dict]:
    return [r for r in rows if any(m['id'] == module for m in r['session'].get('modules') or [])]


def confirm(row: dict, clean: bool = True, rpe: int = 6, weight: float | None = None) -> dict:
    outcomes = training_contract.confirmation_outcomes(row['session'], clean, rpe)
    if weight:
        for o in outcomes.values():
            o['weightKg'] = weight
    return dict(row, log={'completedAt': row['date'] + 'T07:00:00Z', 'exercises': outcomes})


def wildman_modules() -> dict:
    by_id = training_contract.modules_for('wildman_kettlebell', ['swing'], 'general_practice')
    return {k: {'name': m['name'], 'progression': m['progression']} for k, m in by_id.items()}


def item(doc: dict, ident: str) -> dict:
    return next(i for i in doc['items'] if i['id'] == ident)


def swing_briefing(history_of, at: int = 3):
    rows = sessions(program('wildman_kettlebell', 'intermediate'))
    swings = with_module(rows, 'swing')
    target = swings[at]
    doc = briefing.build(target['session'], date=target['date'], key=target['key'],
                         history=history_of(swings[:at], rows), modules=wildman_modules())
    return doc, swings, target


# ── The spec ──────────────────────────────────────────────────────────────────

def test_wildman_declares_its_briefing_and_the_defaults_follow():
    spec = briefing_spec.spec_for('wildman_kettlebell')
    assert spec['source'] == 'declared'
    ids = [e['id'] for e in spec['entries']]
    assert ids[:2] == ['density', 'technique'] and ids[-1] == 'default_exercise'


def test_a_package_without_the_file_gets_the_defaults():
    spec = briefing_spec.spec_for('starting_strength')
    assert spec['source'] == 'default'
    assert [e['id'] for e in spec['entries']] == [e['id'] for e in briefing_spec.DEFAULT_ENTRIES]
    assert briefing_spec.spec_for(None)['source'] == 'default'


def test_scope_keys_all_have_to_hold():
    entry = briefing_spec._normal({'id': 'x', 'same_as': 'module',
                                   'scope': {'progression_models': ['density_cycle'], 'slot_types': ['emom']}})
    assert briefing_spec.matches(entry, {'progression_model': 'density_cycle', 'slot_type': 'emom'})
    assert not briefing_spec.matches(entry, {'progression_model': 'density_cycle', 'slot_type': 'sets_reps'})
    named = briefing_spec._normal({'id': 'n', 'same_as': 'archetype', 'scope': {'named_workout': True}})
    assert not briefing_spec.matches(named, {'named_workout': False})


def test_spec_errors_name_what_the_package_lacks():
    doc = {'id': 'other', 'entries': [
        {'id': 'a', 'same_as': 'module', 'scope': {'modules': ['swing', 'nope'], 'exercises': ['ghost']}},
        {'id': 'a', 'same_as': 'exercise'}]}
    problems = briefing_spec.spec_errors(doc, 'pkg', modules={'swing'}, archetypes=set(), exercises=set())
    assert len(problems) == 4, problems


# ── Wildman: a density cycle ─────────────────────────────────────────────────

def test_the_swing_module_is_one_item_and_its_blocks_around_it_none():
    doc, _, target = swing_briefing(lambda swings, rows: [])
    ids = [i['id'] for i in doc['items']]
    assert 'module:swing' in ids
    assert not any('kb_deadlift' in i['exerciseIds'] or 'wk_kb_halo' in i['exerciseIds'] for i in doc['items'])
    swing = item(doc, 'module:swing')
    assert swing['title'] == 'Nerd Math Two-Hand Swing' and swing['entry'] == 'density'
    assert swing['today']['text'] == '10 × 12 · on the minute', swing['today']
    assert swing['cycle'] == {'step': 4, 'of': 32, 'stage': 1, 'stages': 4, 'text': 'Step 4 of 32 · stage 1 of 4'}
    assert swing['history'] == [] and swing['last'] is None and 'suggestion' not in swing
    assert swing['metric']['id'] == 'total_reps' and swing['today']['values']['total_reps'] == 120
    assert doc['headline'] == 'Nerd Math Two-Hand Swing · 10 × 12 · on the minute'
    assert doc['spec'] == 'declared' and doc['session']['key'] == target['key']


def test_clean_sessions_are_the_history_and_the_step_is_worded():
    doc, swings, _ = swing_briefing(lambda swings, rows: [confirm(r, weight=24) for r in swings])
    swing = item(doc, 'module:swing')
    assert [h['status'] for h in swing['history']] == ['clean'] * 3
    assert [h['values']['reps_per_round'] for h in swing['history']] == [6, 8, 10]
    assert swing['history'][-1]['text'] == '10 × 10 · 24 kg · RPE 6', swing['history'][-1]
    assert swing['last']['date'] == swings[2]['date'] and swing['times'] == 3
    assert swing['suggestion']['kind'] == 'next_step'
    assert swing['suggestion']['text'].startswith('2 more a round than '), swing['suggestion']
    assert doc['pending'] == []


def test_an_unconfirmed_session_is_said_first():
    def history(swings, rows):
        done = [confirm(r) for r in swings[:2]]
        return done + [dict(swings[2], log={'completedAt': swings[2]['date'] + 'T07:00:00Z', 'exercises': {}})]
    doc, swings, _ = swing_briefing(history)
    swing = item(doc, 'module:swing')
    assert [h['status'] for h in swing['history']] == ['clean', 'clean', 'unconfirmed']
    assert swing['suggestion']['kind'] == 'confirm_pending'
    assert 'not confirmed as clean' in swing['suggestion']['text']
    assert [p['sessionKey'] for p in doc['pending']] == [swings[2]['key']]


def test_a_linked_workout_counts_as_done_but_unconfirmed_and_a_missed_day_as_nothing():
    doc, _, _ = swing_briefing(lambda swings, rows: [dict(swings[0], matched=True), dict(swings[1])])
    swing = item(doc, 'module:swing')
    assert [h['status'] for h in swing['history']] == ['unconfirmed'] and swing['times'] == 1


def test_a_session_that_was_not_clean_is_logged_not_clean():
    doc, _, _ = swing_briefing(lambda swings, rows: [confirm(swings[0], clean=False, rpe=9)], at=1)
    swing = item(doc, 'module:swing')
    assert swing['history'][0]['status'] == 'logged'
    assert swing['suggestion']['kind'] == 'confirm_pending'


def test_history_crosses_programs_by_module_and_keeps_to_the_entry_s_count():
    earlier = sessions(program('wildman_kettlebell', 'intermediate'))
    old = []
    for n, row in enumerate(with_module(earlier, 'swing')[:7]):
        on = str(START - timedelta(days=70 - n * 3))
        old.append(dict(confirm(dict(row, date=on)), current=False, key=None))
    doc, _, _ = swing_briefing(lambda swings, rows: old, at=0)
    swing = item(doc, 'module:swing')
    assert swing['times'] == 7 and len(swing['history']) == 6           # the file's `history: 6`
    assert all(h['sessionKey'] is None for h in swing['history'])
    assert doc['pending'] == [] and swing['suggestion']['kind'] == 'next_step'
    assert [h['date'] for h in swing['history']] == sorted(h['date'] for h in swing['history'])


def test_the_last_step_of_a_cycle_says_so():
    rows = sessions(program('wildman_kettlebell', 'intermediate'))
    target = copy.deepcopy(with_module(rows, 'swing')[0])
    for m in target['session']['modules']:
        if m['id'] == 'swing':
            m['forecast_step'] = 31
    doc = briefing.build(target['session'], date=target['date'], history=[], modules=wildman_modules())
    swing = item(doc, 'module:swing')
    assert swing['cycle']['step'] == 32 and swing['suggestion']['kind'] == 'cycle_end'


def test_two_modules_on_one_day_are_two_items_each_with_its_own_history():
    rows = sessions(program('wildman_kettlebell', 'intermediate'))
    shared = [r for r in rows if len(r['session'].get('modules') or []) > 1]
    assert shared, 'the program shares no day'
    target = shared[-1]
    doc = briefing.build(target['session'], date=target['date'], key=target['key'], modules=wildman_modules(),
                         history=[confirm(r) for r in rows if r['date'] < target['date']])
    mods = [m['id'] for m in target['session']['modules']]
    assert [i['id'] for i in doc['items']] == [f'module:{m}' for m in mods]
    for m in mods:
        assert item(doc, f'module:{m}')['times'] == len(
            [r for r in with_module(rows, m) if r['date'] < target['date']])


def test_a_module_of_two_exercises_is_read_exercise_by_exercise():
    rows = sessions(program('wildman_kettlebell', 'intermediate'))
    cp = with_module(rows, 'clean_press')
    done = [confirm(r) for r in cp[:2]]
    done[0]['log']['exercises']['wk_kb_clean_single']['weightKg'] = 20
    done[0]['log']['exercises']['wk_kb_press_single']['weightKg'] = 16
    target = cp[2]
    doc = briefing.build(target['session'], date=target['date'], history=done, modules=wildman_modules())
    it = item(doc, 'module:clean_press')
    assert [e['exerciseId'] for e in it['exercises']] == ['wk_kb_clean_single', 'wk_kb_press_single']
    clean, press = it['exercises']
    assert clean['today']['text'] == '5 × 3 · on the minute', clean['today']
    assert [h['text'] for h in clean['history']] == ['5 × 1 · 20 kg · RPE 6', '5 × 2 · RPE 6'], clean['history']
    assert [h['text'] for h in press['history']] == ['5 × 1 · 16 kg · RPE 6', '5 × 2 · RPE 6'], press['history']
    assert all(h['status'] == 'clean' for h in clean['history'] + press['history'])
    # The item's own row is one exercise's line, never the two joined.
    assert ';' not in it['history'][0]['text'] and 'Kettlebell' not in it['history'][0]['text']


def test_a_new_stage_is_said_as_one_not_as_a_sum_of_differences():
    rows = sessions(program('wildman_kettlebell', 'intermediate'))
    cp = with_module(rows, 'clean_press')
    last, target = copy.deepcopy(cp[0]), copy.deepcopy(cp[1])
    for row, (rounds, reps) in ((last, (5, 5)), (target, (10, 1))):
        for ea in row['session']['exercises']:
            if ea['load'].get('advances_module'):
                ea['load'].update(target_rounds=rounds, reps_per_round=reps)
        for m in row['session']['modules']:
            m['rounds'] = rounds
            m['requirements'] = {e: {'rounds': rounds, 'duration_sec': 0} for e in m['exercise_ids']}
    doc = briefing.build(target['session'], date=target['date'], history=[confirm(last)], modules=wildman_modules())
    text = item(doc, 'module:clean_press')['suggestion']['text']
    assert text.startswith('A new stage: 10 × 1. ') and text.endswith(' was 5 × 5.'), text
    assert 'fewer' not in text and 'more' not in text


# ── A loaded lift, a named workout, a standard ───────────────────────────────

def _lift_rows():
    rows = sessions(program('starting_strength', 'novice', days=3))
    squats = [r for r in rows if any(ea['exercise']['id'] == 'back_squat' for ea in r['session']['exercises'])]
    return rows, squats


def test_a_lift_is_followed_by_exercise_across_workouts_a_and_b():
    _, squats = _lift_rows()
    first, second = squats[0], squats[1]
    made = dict(first, log={'completedAt': first['date'] + 'T07:00:00Z', 'exercises': {
        'back_squat': {'made': True, 'weightKg': 60}}})
    doc = briefing.build(second['session'], date=second['date'], history=[made])
    squat = item(doc, 'exercise:back_squat')
    assert squat['entry'] == 'default_lift' and doc['spec'] == 'default'
    assert squat['history'][0]['status'] == 'made' and squat['history'][0]['values']['weight'] == 60
    missed = dict(made, log={'completedAt': made['log']['completedAt'], 'exercises': {
        'back_squat': {'made': False, 'weightKg': 60}}})
    assert item(briefing.build(second['session'], date=second['date'], history=[missed]),
                'exercise:back_squat')['history'][0]['status'] == 'missed'
    # The accessory that carries no progress makes no item.
    assert not any(i['id'] == 'exercise:chin_up' for i in doc['items'])


def test_a_lift_with_no_weight_yet_is_a_work_up():
    _, squats = _lift_rows()
    doc = briefing.build(squats[0]['session'], date=squats[0]['date'], history=[])
    assert item(doc, 'exercise:back_squat')['suggestion'] == {
        'kind': 'next_load', 'text': 'No weight yet: work up to a heavy set today and log it.'}


def test_a_named_workout_is_followed_by_its_archetype_and_its_warm_up_left_out():
    rows = sessions(program('horsemen_gpp', 'intermediate', days=5))
    target = next(r for r in rows if r['session'].get('pieces'))
    piece = target['session']['pieces'][0]
    earlier = dict(copy.deepcopy(target), date=str(START - timedelta(days=30)), current=False, key=None)
    lead = next(ea for ea in earlier['session']['exercises']
                if not str(ea.get('slot_role')).startswith('warm_up__'))
    earlier['log'] = {'completedAt': earlier['date'] + 'T07:00:00Z',
                      'exercises': {lead['exercise']['id']: {'rounds': 7}}}
    doc = briefing.build(target['session'], date=target['date'], history=[earlier])
    named = item(doc, f"archetype:{piece['archetype_id']}")
    assert named['title'] == piece['name'] and named['entry'] == 'default_named'
    assert named['history'][0]['status'] == 'logged'
    # Many movements have many numbers: none of them is "the number to beat".
    assert 'suggestion' not in named
    assert [e['exerciseId'] for e in named['exercises']] == named['exerciseIds'] and len(named['exercises']) > 1
    warm = (target['session'].get('warm_up') or {}).get('archetype_id')
    assert warm is None or not any(i['id'] == f'archetype:{warm}' for i in doc['items'])


def test_a_workout_with_one_result_has_a_number_to_beat():
    session = {'modality': 'conditioning', 'pieces': [{'category': 'girls', 'archetype_id': 'w_fran', 'name': 'Fran'}],
               'archetype': {'id': 'w_fran', 'name': 'Fran', '_package': 'p'},
               'exercises': [
                   {'exercise': {'id': 'thruster', 'name': 'Thruster'}, 'slot_type': 'for_time', 'slot_role': 'thruster',
                    'load': {'target_rounds': 3}},
                   {'exercise': {'id': 'pull_up', 'name': 'Pull-Up'}, 'slot_type': 'amrap_movement',
                    'slot_role': 'pull_up', 'load': {}}]}
    earlier = {'date': '2026-10-01', 'session': copy.deepcopy(session), 'current': False,
               'log': {'completedAt': '2026-10-01T07:00:00Z', 'exercises': {'thruster': {'durationSec': 372}}}}
    fran = item(briefing.build(session, date='2026-11-10', history=[earlier]), 'archetype:w_fran')
    assert fran['entry'] == 'default_named' and fran['suggestion']['kind'] == 'beat_last', fran
    assert fran['suggestion']['text'].endswith('on 1 Oct — the number to beat.'), fran['suggestion']


def test_a_contract_session_with_nothing_to_earn_is_read_as_written():
    rows = sessions(program('bjj', 'elite', days=5))
    strength = [r for r in rows if any(ea['exercise']['id'] == 'trap_bar_deadlift' for ea in r['session']['exercises'])]
    first, again = strength[0], next(r for r in strength[1:] if r['session']['modules'][0].get('variant')
                                     == strength[0]['session']['modules'][0].get('variant'))
    done = dict(first, log={'completedAt': first['date'] + 'T07:00:00Z', 'exercises': {
        'trap_bar_deadlift': {'sets': [{'setIndex': k, 'repsActual': 5, 'weightKg': 100, 'completed': True}
                                       for k in range(4)]}}})
    doc = briefing.build(again['session'], date=again['date'], history=[done])
    it = next(i for i in doc['items'] if 'trap_bar_deadlift' in i['exerciseIds'])
    assert it['entry'] == 'default_as_written' and it['kind'] == 'module'
    assert 'suggestion' not in it and doc['pending'] == []        # nothing to confirm, nothing to earn
    lift = next(e for e in it['exercises'] if e['exerciseId'] == 'trap_bar_deadlift')
    assert lift['today']['text'] == '4 × 5' and lift['history'][-1]['text'] == '4 × 5 · 100 kg', lift
    pull = next(e for e in it['exercises'] if e['exerciseId'] == 'pull_up')
    assert pull['today']['text'] == '3 × max', pull['today']          # the source's own words for the reps


def test_a_made_lift_says_the_next_weight_the_stored_program_does_not_carry_yet():
    _, squats = _lift_rows()
    first, second = copy.deepcopy(squats[0]), copy.deepcopy(squats[1])
    for row in (first, second):
        for ea in row['session']['exercises']:
            if ea['exercise']['id'] == 'back_squat':
                ea['load'].pop('weight_kg', None)
                ea['load']['work_up'] = False
    step = next(ea['load']['increment_kg'] for ea in first['session']['exercises']
                if ea['exercise']['id'] == 'back_squat')
    made = dict(first, log={'completedAt': first['date'] + 'T07:00:00Z', 'exercises': {
        'back_squat': {'made': True, 'weightKg': 60}}})
    text = item(briefing.build(second['session'], date=second['date'], history=[made]),
                'exercise:back_squat')['suggestion']['text']
    assert text.endswith(f'with the usual {step:g} kg step, {60 + step:g} kg today.'), text


def test_a_scored_slot_says_its_standard():
    session = {'modality': 'conditioning', 'archetype': {'id': 'row_test', 'name': '2 km row', '_package': 'p'},
               'exercises': [{'exercise': {'id': 'row', 'name': 'Row'}, 'slot_type': 'for_time',
                              'slot_role': 'main', 'standard': {'id': 'row_2k', 'result': 'duration'},
                              'load': {'distance_m': 2000}}]}
    doc = briefing.build(session, date='2026-11-10', history=[],
                         standards={'row_2k': {'id': 'row_2k', 'name': '2 km row', 'best': '7:40',
                                               'target': '7:30 for intermediate'}})
    row = item(doc, 'exercise:row')
    assert row['standard']['best'] == '7:40'
    assert row['suggestion'] == {'kind': 'standard_target', 'text': 'Your best is 7:40; 7:30 for intermediate.'}


def test_nothing_after_the_day_or_on_it_is_history():
    doc, _, target = swing_briefing(
        lambda swings, rows: [confirm(dict(r, date=target_date)) for r, target_date in
                              zip(swings[:2], ['2099-01-01', '2026-11-12'])], at=3)
    assert item(doc, 'module:swing')['times'] <= 1


# ── The route ─────────────────────────────────────────────────────────────────

def test_the_route_answers_from_the_stored_program():
    from src import db
    prog = program('wildman_kettlebell', 'intermediate')
    rows = sessions(prog)
    swings = with_module(rows, 'swing')
    logs = {r['key']: confirm(r, weight=24)['log'] for r in swings[:2]}
    stored = {'programStartDate': str(START), 'currentProgram': prog}
    keep = (db.get_user_program, api._health.get_session_logs, api._health.get_session_logs_by_uid,
            api._health.get_matches, api._today_for, api._active_version_or_none)
    db.get_user_program = lambda uid: stored
    api._health.get_session_logs = lambda uid: logs
    api._health.get_session_logs_by_uid = lambda uid: {}
    api._health.get_matches = lambda uid: []
    api._today_for = lambda tz: date.fromisoformat(swings[2]['date'])
    api._active_version_or_none = lambda uid: None
    try:
        client = api.app.test_client()
        r = client.get(f"/api/sessions/briefing?key={swings[2]['key']}")
        assert r.status_code == 200, r.get_data(as_text=True)
        doc = r.get_json()
        swing = item(doc, 'module:swing')
        assert swing['title'] == 'Nerd Math Two-Hand Swing' and swing['cycle']['step'] == 3
        assert [h['status'] for h in swing['history']] == ['clean', 'clean']
        assert doc['session']['date'] == swings[2]['date'] and doc['session']['packageId'] == 'wildman_kettlebell'
        assert client.get('/api/sessions/briefing?key=99-Monday-0').status_code == 404
        assert client.get('/api/sessions/briefing').status_code == 404
    finally:
        (db.get_user_program, api._health.get_session_logs, api._health.get_session_logs_by_uid,
         api._health.get_matches, api._today_for, api._active_version_or_none) = keep


if __name__ == '__main__':
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            try:
                fn()
                print(f'ok    {name}')
            except Exception as e:  # noqa: BLE001
                failed += 1
                print(f'FAIL  {name}: {type(e).__name__}: {e}')
    raise SystemExit(1 if failed else 0)
