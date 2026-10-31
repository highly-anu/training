"""Behavioral contract tests: source progression, workload and earned state.

The engine's, on Wildman's contract. What a package's own contract does is
tested in its folder (data/packages/<id>/tests/test_contract.py).
"""
from copy import deepcopy
from unittest.mock import patch

import unittest

from src import goals, loader, training_contract as tc
from src.generator import generate


BJJ_GYM = ['barbell', 'rack', 'plates', 'pull_up_bar', 'dumbbell', 'box', 'open_space']


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


def test_real_session_budget_and_deload_are_derived_from_blocks():
    p, g, c = plan(session_time_minutes=30)
    assert p['weeks']
    for s in sessions(p):
        minutes = sum(e['load']['elapsed_sec'] for e in s['exercises']) / 60
        assert minutes == s['archetype']['duration_estimate_minutes'] <= 30
    # The swing module's rows, whatever shares its day (Get-up, Deck Squat).
    swing = lambda s: [e for e in s['exercises'] if e['load']['module_id'] == 'swing']
    normal = next(s for s in sessions(p) if not s['is_deload'] and swing(s))
    # General Practice runs Wildman's sixteen weeks without a deload week; an
    # overreached athlete still deloads, and keeps the block's declared share.
    tired, _, _ = plan(session_time_minutes=30, fatigue_state='overreached')
    reduced = next(s for s in sessions(tired) if s['is_deload'] and swing(s))
    assert all(e['load']['elapsed_sec'] < swing(normal)[i]['load']['elapsed_sec']
               for i, e in enumerate(swing(reduced)))
    broken = deepcopy(p)
    sessions(broken)[0]['archetype']['duration_estimate_minutes'] = 1
    with unittest.TestCase().assertRaises(tc.ContractError):
        tc.verify(broken, g['training_contract'], c)


def test_combined_modules_fit_three_days_or_fail_explicitly():
    p, g, c = plan(days_per_week=3)
    assert p['weeks'] and any({'swing', 'clean_press'} <= {m['id'] for m in s['modules']} for s in sessions(p))
    tc.verify(p, g['training_contract'], c)
    p, _, _ = plan(days_per_week=3, session_time_minutes=20)
    assert not p['weeks'] and p['validation_errors']


def test_confirm_route_merges_into_the_session_log():
    import api
    from unittest.mock import patch
    p, _, _ = plan()
    day, first = next((d, ss[0]) for d, ss in p['weeks'][0]['schedule'].items() if ss[0]['modules'][0]['id'] == 'swing')
    name = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1]
    stored = {'currentProgram': {'weeks': [{'schedule': {name: [first]}}]}}
    saved = {}
    def upsert(_user, log):
        saved.update(log)
        return {'exercises': log['exercises'], 'completed_at': log.get('completedAt'), 'session_uid': 'v:w0',
                'session_key': log['sessionKey'], 'source': log['source']}
    client = api.app.test_client()
    with patch('src.program_history.active_session_uid', return_value='v:w0'), \
         patch('src.program_history.resolve_session',
               return_value={'week_index': 0, 'day_name': name, 'session_index': 0}), \
         patch('src.db.get_user_program', return_value=stored), \
         patch.object(api._health, 'get_session_log',
                      return_value={'completedAt': '2026-10-21 05:00:00+00', 'notes': 'felt good', 'source': 'garmin',
                                    'exercises': {'wk_kb_swing_two_hand': {'sets': [{'weightKg': 16}]}}}), \
         patch.object(api._health, 'upsert_session_log', side_effect=upsert), \
         patch('src.standard_results.after_session_log', return_value=None):
        r = client.post(f'/api/health/sessions/1-{name}-0/confirm', json={'clean': True, 'rpe': 7})
        assert r.status_code == 200, r.get_json()
        swing = saved['exercises']['wk_kb_swing_two_hand']
        assert swing == {'sets': [{'weightKg': 16}], 'rounds': 10, 'clean': True, 'rpe': 7}, swing
        assert 'completedAt' not in saved, 'an existing completion is kept'
        assert saved['notes'] == 'felt good' and saved['source'] == 'garmin'
        assert client.post(f'/api/health/sessions/1-{name}-0/confirm', json={'clean': 'yes'}).status_code == 422
        assert client.post(f'/api/health/sessions/1-{name}-0/confirm', json={'clean': True, 'rpe': 11}).status_code == 422
    with patch('src.program_history.active_session_uid', return_value=None), \
         patch('src.db.get_user_program', return_value=stored):
        assert client.post('/api/health/sessions/9-Monday-0/confirm', json={'clean': True, 'rpe': 7}).status_code == 404


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


def test_optional_modules_and_spacing_across_weeks():
    module = {'id': 'm', 'exposures_per_week': 2, 'min_spacing_days': 2}
    assert tc._place_optional(module, 30, [4, 5], {4: 60, 5: 60}) == [4], 'adjacent free days fit one'
    assert tc._place_optional(module, 30, [3, 6], {3: 60, 6: 60}) == [3, 6]
    assert tc._place_optional(module, 90, [3, 6], {3: 60, 6: 60}) == [], 'too long for the day'
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
    # Answered as every infeasible request is (200, `validation.feasible: false`,
    # the reason in `detail`) so both builders show it; never saved.
    assert r.status_code == 200
    assert not r.get_json()['validation']['feasible'] and 'mastery' in r.get_json()['detail']
    save.assert_not_called()


def test_review_fixes_of_2026_10_19():
    # A schedule with a second session on a day sets allow_split_sessions; the
    # contract composes its own days and must not refuse it.
    p, g, c = plan(weeks=2, allow_split_sessions=True)
    assert p['weeks'] and not p.get('validation_errors')
    # Builders ask only for what the level does not already count as known.
    import api
    phils = api.app.test_client().get('/api/philosophies').get_json()
    gp = next(t for ph in phils if ph['id'] == 'wildman_kettlebell' for t in ph['tracks'] if t['id'] == 'general_practice')
    by_level = gp['entry_requirements']['mastered_exercises_by_level']
    assert by_level['intermediate'] == [] and by_level['novice'] == [], by_level
    # A blend is built by the general generator, even when Wildman leads it.
    blend = goals.blend_philosophy_goals(['wildman_kettlebell', 'uphill_athlete'],
                                         {'wildman_kettlebell': 0.7, 'uphill_athlete': 0.3},
                                         list(loader.load_all_frameworks().values()))
    assert 'training_contract' not in blend
    # Rests are budgeted in whole minutes, as the session's minutes are summed.
    module = {'id': 'm', 'name': 'M', 'progression': {'model': 'skill_hold'}, 'blocks': [
        {'role': 'a', 'exercise_id': 'wk_kb_halo', 'slot_type': 'skill_practice', 'duration_sec': 120, 'rest_after_sec': 90}]}
    _, catalogs = loader.load_all_exercises()
    rows = tc._module_rows(module, catalogs['wildman_kettlebell'], {'equipment': ['kettlebell']}, {}, 0, False)
    assert [r['load']['elapsed_sec'] for r in rows] == [120, 120]
    # Swaps and single-session regenerates refuse only for a stored contract program.
    with patch('src.db.get_user_program', return_value={'currentProgram': {'training_contract': {'id': 'x/y@1'}}}):
        r = api.app.test_client().post('/api/exercises/substitute', json={
            'archetype_id': 'kb_ballistic_session', 'slot_role': 'main', 'exercise_id': 'wk_kb_swing_two_hand',
            'modality': 'power', 'constraints': {}, 'philosophy_ids': ['wildman_kettlebell'], 'phase': 'base'})
        assert r.status_code == 422
    with patch('src.db.get_user_program', return_value={'currentProgram': {}}):
        r = api.app.test_client().post('/api/exercises/substitute', json={
            'archetype_id': 'kb_ballistic_session', 'slot_role': 'main', 'exercise_id': 'wk_kb_swing_two_hand',
            'modality': 'power', 'constraints': {}, 'philosophy_ids': ['wildman_kettlebell'], 'phase': 'base'})
        assert r.status_code != 422 or 'fixed training module' not in r.get_json().get('detail', ''), r.get_json()


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


def test_builder_requirements_are_scoped_to_the_selected_level():
    import api
    response = api.app.test_client().get('/api/philosophies')
    assert response.status_code == 200
    wildman = next(p for p in response.get_json() if p['id'] == 'wildman_kettlebell')
    tracks = {t['id']: t for t in wildman['tracks']}
    req = tracks['general_practice']['entry_requirements']['mastered_exercises_by_level']
    assert req['novice'] == []
    # The contract seeds an intermediate's clean and press: nothing to confirm.
    assert req['intermediate'] == []
    pent = tracks['pentathlon']['entry_requirements']['mastered_exercises_by_level']
    assert set(pent['intermediate']) == {'wk_kb_clean_single', 'wk_kb_long_cycle_press', 'kb_jerk_single',
                                         'wk_kb_half_snatch', 'wk_kb_push_press_single'}
    assert tracks['double_bell_practice']['entry_requirements']['kettlebell_count'] == 2


def _bjj(weeks=4, **overrides):
    goal = goals.philosophy_to_goal('bjj', list(loader.load_all_frameworks().values()))
    c = dict(equipment=BJJ_GYM, days_per_week=5, session_time_minutes=60, training_level='intermediate')
    c.update(overrides)
    return generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict'), goal, c


def test_review_fixes_of_pr_175():
    # The module record names what was prescribed (an alternative, not the
    # authored lift), so confirmed_state reads the logs the athlete wrote.
    p, _, _ = plan(weeks=2)
    for s in sessions(p):
        prescribed = {e['exercise']['id'] for e in s['exercises'] if e.get('exercise')}
        for r in s['modules']:
            assert r['exercise_ids'] and set(r['exercise_ids']) <= prescribed, (r, prescribed)
    # Fewer days than the smallest exposures_by_days key refuses.
    short, _, _ = _bjj(weeks=1, days_per_week=2)
    assert not short['weeks'] and short['validation_errors']

if __name__ == '__main__':
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
