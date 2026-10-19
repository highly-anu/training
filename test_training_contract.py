"""Behavioral contract tests: source progression, workload and earned state."""
from copy import deepcopy
from unittest.mock import patch

import unittest

from src import goals, loader, training_contract as tc
from src.generator import generate


def setup(track='general_practice', **overrides):
    goal = goals.philosophy_to_goal('wildman_kettlebell', list(loader.load_all_frameworks().values()), track)
    constraints = dict(equipment=['kettlebell'], days_per_week=4,
                       session_time_minutes=60, training_level='intermediate')
    constraints.update(overrides)
    return goal, constraints


def plan(weeks=16, track='general_practice', **overrides):
    goal, c = setup(track, **overrides)
    result = generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict', include_trace=True)
    return result, goal, c


def sessions(program):
    return [s for w in program['weeks'] for ss in w['schedule'].values() for s in ss]


def swings(program):
    return [e['load'] for s in sessions(program) for e in s['exercises'] if e['slot_role'] == 'swing_main']


def test_source_cycle_retains_movements_and_spacing(level='intermediate'):
    p, g, c = plan(training_level=level)
    assert len(p['weeks']) == 16
    tc.verify(p, g['training_contract'], c)
    loads = swings(p)
    working = [e['load'] for s in sessions(p) if not s['is_deload'] for e in s['exercises'] if e['slot_role'] == 'swing_main']
    assert [e['reps_per_round'] for e in working[:8]] == [6, 8, 10, 12, 14, 16, 18, 20]
    assert loads[0]['target_rounds'] == 10
    # Deloads hold the cursor; the next volume cycle is not tied to a phase date.
    assert any(e['target_rounds'] == 20 for e in loads)
    assert not any(e['exercise']['id'] in {'wk_kb_snatch', 'kb_jerk_single', 'kb_jerk_double'}
                   for s in sessions(p) for e in s['exercises'])
    assert all(not e['conditional'] for e in loads[:1])
    assert loads[1]['conditional']
    assert all('weight_kg' not in e for e in loads)
    assert p['module_state']['swing']['completed'] == 0


def test_real_session_budget_and_deload_are_derived_from_blocks():
    p, g, c = plan(session_time_minutes=30)
    assert p['weeks']
    for s in sessions(p):
        minutes = sum(e['load']['elapsed_sec'] for e in s['exercises']) / 60
        assert minutes == s['archetype']['duration_estimate_minutes'] <= 30
    normal = sessions(p)[0]
    reduced = next(s for s in sessions(p) if s['is_deload'] and s['modules'][0]['id'] == 'swing')
    assert all(e['load']['elapsed_sec'] < normal['exercises'][i]['load']['elapsed_sec']
               for i, e in enumerate(reduced['exercises']))
    broken = deepcopy(p)
    sessions(broken)[0]['archetype']['duration_estimate_minutes'] = 1
    with unittest.TestCase().assertRaises(tc.ContractError):
        tc.verify(broken, g['training_contract'], c)


def test_combined_modules_fit_three_days_or_fail_explicitly():
    p, g, c = plan(days_per_week=3)
    assert p['weeks'] and any(len(s['modules']) == 2 for s in sessions(p))
    tc.verify(p, g['training_contract'], c)
    p, _, _ = plan(days_per_week=3, session_time_minutes=20)
    assert not p['weeks'] and p['validation_errors']


def test_unearned_calendar_time_and_deload_never_advance_confirmed_state():
    p, g, _ = plan()
    assert tc.confirmed_state(p, {}, g['training_contract'])['swing']['completed'] == 0
    # Attendance alone is insufficient.
    log = {'completedAt': '2026-10-20', 'exercises': {}}
    assert tc.confirmed_state(p, {'1-Monday-0': log}, g['training_contract'])['swing']['completed'] == 0
    log['exercises'] = {'wk_kb_swing_two_hand': {'rounds': 10, 'rpe': 6, 'clean': True}}
    state = tc.confirmed_state(p, {'1-Monday-0': log}, g['training_contract'])
    assert state['swing']['completed'] == 1
    p2, _, _ = plan(module_progression_state=state)
    assert swings(p2)[0]['reps_per_round'] == 8
    # Replaying an older exposure cannot count it twice.
    assert tc.confirmed_state(p2, {'1-Monday-0': {'completedAt': 'x'}}, g['training_contract'])['swing']['completed'] == 1
    for bad in ({'clean': False, 'rpe': 6, 'rounds': 10}, {'clean': True, 'rpe': 9, 'rounds': 10},
                {'clean': True, 'rpe': 6, 'rounds': 9}):
        log['exercises']['wk_kb_swing_two_hand'] = bad
        assert tc.confirmed_state(p, {'1-Monday-0': log}, g['training_contract'])['swing']['completed'] == 0


def test_actual_bells_and_mastery_are_not_guessed():
    p, _, _ = plan(kettlebell_weights_kg=[12, 16], module_progression_state={'swing': {'completed': 0, 'weight_kg': 16}})
    assert {e['weight_kg'] for e in swings(p)} == {16}
    p, _, _ = plan(kettlebell_weights_kg=[12, 16], module_progression_state={'swing': {'weight_kg': 12.5}})
    assert not p['weeks']
    p, _, _ = plan(injury_flags=['lumbar_disc'])
    assert not p['weeks']
    p, _, _ = plan(track='pentathlon', session_time_minutes=90)
    assert not p['weeks'] and 'mastery' in p['validation_errors'][0]['message']


def _module_ids(session):
    return [m['id'] for m in session['modules']]


def test_pentathlon_keeps_the_five_events_and_test_protocol():
    # Kettlebell-sport practice, not a Wildman program: volume through the five
    # events capped at the mini pentathlon's four minutes, repeats of three-minute
    # sets, minute intervals on the four fast events, a full practice pentathlon
    # closing Timed Sets and the test closing Competition.
    g, _ = setup('pentathlon')
    mastery = g['training_contract']['modules'][0]['requires_mastery']
    p, g, c = plan(track='pentathlon', weeks=12, session_time_minutes=90, mastered_exercises=mastery)
    assert len(p['weeks']) == 12
    tc.verify(p, g['training_contract'], c)
    for w in p['weeks']:
        mods = sorted(m for ss in w['schedule'].values() for s in ss for m in _module_ids(s))
        assert [m for m in mods if m.startswith('pentathlon_')] == [
            'pentathlon_events', 'pentathlon_intervals', 'pentathlon_repeats'], mods
    for s in sessions(p):
        events = [e for e in s['exercises'] if e['slot_type'] == 'time_domain' and e.get('exercise')]
        if _module_ids(s) == ['pentathlon_events']:
            assert [e['exercise']['id'] for e in events] == mastery
            assert all(e['load']['duration_minutes'] <= (6 if s.get('test') else 4) for e in events)
            assert len([e for e in s['exercises'] if e.get('meta')]) == 4, 'event rests are executable blocks'
        elif _module_ids(s) == ['pentathlon_repeats']:
            assert [e['exercise']['id'] for e in events] == mastery
            assert all(e['load']['duration_minutes'] <= 3 for e in events)
            assert {e['load']['duration_minutes'] for e in s['exercises'] if e.get('meta')} <= {4, 3, 2}
        elif _module_ids(s) == ['pentathlon_intervals']:
            emoms = [e for e in s['exercises'] if e['slot_type'] == 'emom']
            assert [e['exercise']['id'] for e in emoms] == [
                'wk_kb_clean_single', 'kb_jerk_single', 'wk_kb_half_snatch', 'wk_kb_push_press_single']
            assert all(6 <= e['load']['reps_per_round'] <= 10 for e in emoms)
    tests = [(w['week_number'], s) for w in p['weeks'] for ss in w['schedule'].values() for s in ss if s.get('test')]
    assert [n for n, _ in tests] == [10, 12], 'a practice pentathlon ends Timed Sets, the test ends Competition'
    for n, t in tests:
        week = p['weeks'][n - 1]['schedule']
        assert t in week[max(week)], 'a test is the last session of its week'
        assert len([e for e in t['exercises'] if e.get('standard')]) == 5
        assert all(e['load']['duration_minutes'] == 6 for e in t['exercises'] if e.get('standard'))


def test_pentathlon_runs_are_optional_and_take_only_free_days():
    g, _ = setup('pentathlon')
    mastery = g['training_contract']['modules'][0]['requires_mastery']

    def runs(program):
        return [(w['week_number'], d) for w in program['weeks'] for d, ss in w['schedule'].items()
                for s in ss if 'easy_aerobic' in _module_ids(s)]

    five, g, c = plan(track='pentathlon', weeks=4, days_per_week=5, mastered_exercises=mastery)
    tc.verify(five, g['training_contract'], c)
    assert len(runs(five)) == 8 and not five['compromises'], 'two easy runs a week at five days'
    for w in five['weeks']:
        days = {d: _module_ids(s) for d, ss in w['schedule'].items() for s in ss}
        assert all(len(m) == 1 for m in days.values()), 'a run never shares a lifting day'
        events_day = next(d for d, m in days.items() if m == ['pentathlon_events'])
        assert events_day == max(days), 'nothing optional after the volume session'
    run = next(e for s in sessions(five) for e in s['exercises'] if (e.get('exercise') or {}).get('id') == 'run_zone2')
    assert run['load']['zone_upper'] == 2 and run['load']['advances_module'] and 'load_note' not in run['load']

    three, _, _ = plan(track='pentathlon', weeks=2, days_per_week=3, mastered_exercises=mastery)
    assert three['weeks'] and not runs(three), 'three days are the three event sessions'
    assert three['compromises'] == ['Easy Aerobic Run: 0 of 2 weekly sessions — no free training day for it.']

    no_run, _, _ = plan(track='pentathlon', weeks=2, days_per_week=5, mastered_exercises=mastery,
                        avoid_movements=['locomotion'])
    assert no_run['weeks'] and not runs(no_run), 'a run ruled out is left out, not a refusal'
    assert 'conflicts with an active injury restriction' in no_run['compromises'][0]


def test_optional_modules_and_spacing_across_weeks():
    module = {'id': 'm', 'exposures_per_week': 2, 'min_spacing_days': 2}
    assert tc._place_optional(module, 30, [4, 5], 60, {}) == [4], 'adjacent free days fit one'
    assert tc._place_optional(module, 30, [3, 6], 60, {}) == [3, 6]
    assert tc._place_optional(module, 90, [3, 6], 60, {}) == [], 'too long for the day'
    placements = list(tc._placements([{'id': 'a', 'exposures_per_week': 1, 'min_spacing_days': 2}],
                                     {'a': 30}, [1, 3, 5], 60))
    assert [sorted(p) for p in placements] == [[1], [3], [5]], 'every placement, in preference order'


def test_output_gate_catches_corrupt_cycles_and_phase_rules():
    p, g, c = plan()
    swings(p)[0]['reps_per_round'] = 999
    with unittest.TestCase().assertRaises(tc.ContractError):
        tc.verify(p, g['training_contract'], c)
    g['phase_sequence'][0]['checks'] = {'archetypes_forbidden': ['kb_ballistic_session']}
    p = generate(None, c, num_weeks=1, goal_dict=g, output_format='dict')
    assert not p['weeks'] and p['validation_errors']


def test_shared_filters_are_executable():
    from src.selector import _matches_slot_filter
    ex = {'category': 'kettlebell', 'bilateral': False, 'equipment': ['kettlebell']}
    assert not _matches_slot_filter(ex, {'bilateral': True}, set())
    assert not _matches_slot_filter(ex, {'equipment_required': ['barbell']}, set())


def test_api_rejects_failed_contract_without_persisting():
    with patch('src.db._get_pg_conn', return_value=None), patch('src.db.get_user_program', return_value=None), patch('src.db.save_user_program') as save:
        import api
        r = api.app.test_client().post('/api/programs/generate', json={
            'philosophy_id': 'wildman_kettlebell', 'track_id': 'pentathlon', 'persist': True,
            'constraints': setup()[1], 'num_weeks': 1})
    assert r.status_code == 422
    assert not r.get_json()['validation']['feasible']
    save.assert_not_called()


def test_api_regeneration_recovers_clean_work_from_saved_program():
    p, _, c = plan(weeks=1)
    log = {'completedAt': '2026-10-20', 'exercises': {
        'wk_kb_swing_two_hand': {'rounds': 10, 'rpe': 6, 'clean': True, 'weightKg': 16}}}
    with patch('src.db._get_pg_conn', return_value=None):
        import api
    current = deepcopy(p)
    names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    for week in current['weeks']:
        week['schedule'] = {names[d - 1]: ss for d, ss in week['schedule'].items()}
    c['module_progression_state'] = current['module_state']
    with patch('src.db.get_user_program', return_value={'currentProgram': current}), \
         patch('src.health_store.get_session_logs', return_value={'1-Monday-0': log}), \
         patch('src.db.save_user_program') as save:
        response = api.app.test_client().post('/api/programs/generate', json={
            'philosophy_id': 'wildman_kettlebell', 'track_id': 'general_practice',
            'constraints': c, 'num_weeks': 1, 'persist': False})
    assert response.status_code == 200, response.get_json()
    assert response.get_json()['module_state']['swing'] == {'completed': 1, 'weight_kg': 16}
    save.assert_not_called()


def test_additional_tracks_require_real_skills_and_matching_bells():
    p, g, _ = plan(track='double_bell_practice', weeks=12)
    assert not p['weeks'] and 'matching' in p['validation_errors'][0]['message']
    p, _, _ = plan(track='double_bell_practice', weeks=12, kettlebell_count=2)
    assert not p['weeks'] and 'mastery' in p['validation_errors'][0]['message']
    skills = [eid for m in g['training_contract']['modules'] for eid in m.get('requires_mastery', [])]
    p, g, c = plan(track='double_bell_practice', weeks=12, kettlebell_count=2,
                   mastered_exercises=skills, module_progression_state={'double_strength': {'completed': 0, 'weight_kg': 16}})
    assert len(p['weeks']) == 12
    tc.verify(p, g['training_contract'], c)
    assert all('per bell' in e['load']['load_note'] for s in sessions(p) for e in s['exercises']
               if e['load'].get('weight_kg') == 16)


def test_mobility_requires_the_actual_practice_window_for_each_movement():
    g, _ = setup('getup_mobility')
    skills = g['training_contract']['modules'][0]['requires_mastery']
    p, g, _ = plan(track='getup_mobility', weeks=1, mastered_exercises=skills)
    outcomes = {eid: {'durationSec': 240, 'clean': True, 'rpe': 6} for eid in skills}
    logs = {'1-Monday-0': {'completedAt': 'x', 'exercises': outcomes}}
    assert tc.confirmed_state(p, logs, g['training_contract'])['getup_mobility']['completed'] == 0
    outcomes['wk_kb_tgu']['durationSec'] = 360
    assert tc.confirmed_state(p, logs, g['training_contract'])['getup_mobility']['completed'] == 1


def test_builder_requirements_are_scoped_to_the_selected_level():
    import api
    response = api.app.test_client().get('/api/philosophies')
    assert response.status_code == 200
    wildman = next(p for p in response.get_json() if p['id'] == 'wildman_kettlebell')
    tracks = {t['id']: t for t in wildman['tracks']}
    req = tracks['general_practice']['entry_requirements']['mastered_exercises_by_level']
    assert req['novice'] == []
    assert set(req['intermediate']) == {'wk_kb_clean_single', 'wk_kb_press_single'}
    assert tracks['double_bell_practice']['entry_requirements']['kettlebell_count'] == 2


if __name__ == '__main__':
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_'))
    for level in ('novice', 'advanced', 'elite'):
        suite.addTest(unittest.FunctionTestCase(lambda level=level: test_source_cycle_retains_movements_and_spacing(level),
                                               description=f'full track: {level}'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
