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
    assert not any(s['is_deload'] for s in sessions(p)), "Wildman's sixteen weeks have no deload week"
    assert [e['reps_per_round'] for e in working[:8]] == [6, 8, 10, 12, 14, 16, 18, 20]
    assert loads[0]['target_rounds'] == 10
    # The next stage is not tied to a phase date.
    assert any(e['target_rounds'] == 20 for e in loads)
    assert not any(e['exercise']['id'] in {'wk_kb_snatch', 'kb_jerk_single', 'kb_jerk_double'}
                   for s in sessions(p) for e in s['exercises'])
    assert all(not e['conditional'] for e in loads[:1])
    assert loads[1]['conditional']
    assert all('weight_kg' not in e for e in loads)
    assert p['module_state']['swing']['completed'] == 0


def test_swing_recommends_repeating_after_a_layoff_and_never_enforces_it():
    # Nerd Math PDF, "Tracking your progress": repeat workouts after more than a
    # week away. The owner's decision (2026-10-21): recommend, never enforce.
    p, g, c = plan(weeks=2)
    advice = next(m for m in g['training_contract']['modules'] if m['id'] == 'swing')['advice']
    assert all(advice in e['load_note'] for e in swings(p)), 'every swing session says it'
    prep = [e['load'] for s in sessions(p) for e in s['exercises'] if e['slot_role'] == 'swing_prep']
    assert prep and not any(advice in (e.get('load_note') or '') for e in prep), 'only the block that advances'
    assert [e['reps_per_round'] for e in swings(p)] == [6, 8, 10, 12], 'the cursor is the same with or without it'


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



def test_general_practice_runs_wildmans_phase_two():
    # The Nerd Math swing program's four approaches in order, then a heavier
    # bell; the other Phase II programs stack in as the session time allows;
    # the snatch waits until it is confirmed.
    p, g, c = plan(weeks=16, session_time_minutes=40)
    tc.verify(p, g['training_contract'], c)
    stages = [(e['target_rounds'], e['work_sec']) for e in swings(p)]
    assert stages[:8] == [(10, 60)] * 8 and stages[8:16] == [(20, 60)] * 8, stages[:16]
    assert stages[16:24] == [(10, 90)] * 8 and stages[24:] == [(20, 90)] * 8, stages[16:]
    assert all('Start/stop' in e['focus'] for e in swings(p)[16:])
    ids = {m['id'] for s in sessions(p) for m in s['modules']}
    assert {'swing', 'clean_press', 'getup', 'deck_squat'} <= ids and 'snatch' not in ids, ids
    assert any('Nerd Math Snatch joins' in line for line in p['compromises']), p['compromises']
    # Thirty-minute sessions take Approach 3 where Approach 4 would not fit.
    short, g, c = plan(weeks=16, session_time_minutes=30)
    tc.verify(short, g['training_contract'], c)
    assert {(e['target_rounds'], e['work_sec']) for e in swings(short)[24:]} == {(10, 90)}
    # With the snatch confirmed and the days for it, it joins the week.
    sn, g, c = plan(weeks=2, days_per_week=4, session_time_minutes=60,
                    mastered_exercises=['wk_kb_snatch'])
    tc.verify(sn, g['training_contract'], c)
    assert any(m['id'] == 'snatch' for s in sessions(sn) for m in s['modules'])
    assert tc.load_contract('wildman_kettlebell', 'general_practice')['modules']
    reqs = constraint_requirements = __import__('src.constraint_impact', fromlist=['x']).contract_requirements
    assert 'wk_kb_snatch' not in (reqs(g, 'intermediate').get('mastered_exercises') or [])



def test_one_tap_confirmation_earns_the_exposure():
    # A watch-recorded or linked session logs no per-exercise outcome; the
    # athlete's "done as written" writes the prescribed rounds with clean and
    # RPE, which is what confirmed_state counts — and a "not clean" never is.
    p, g, _ = plan()
    first = next(s for w in p['weeks'] for ss in w['schedule'].values() for s in ss
                 if s['modules'][0]['id'] == 'swing')
    logged = {'wk_kb_swing_two_hand': {'sets': [{'setIndex': 0, 'weightKg': 16}]}}
    out = tc.confirmation_outcomes(first, True, 7, logged)
    swing = out['wk_kb_swing_two_hand']
    assert swing['rounds'] == 10 and swing['clean'] is True and swing['rpe'] == 7
    assert swing['sets'] == logged['wk_kb_swing_two_hand']['sets'], 'what was logged is kept'
    day = next(d for d, ss in p['weeks'][0]['schedule'].items() if ss[0] is first)
    key = f"1-{['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][day - 1]}-0"
    log = {'completedAt': '2026-10-21', 'exercises': out}
    assert tc.confirmed_state(p, {key: log}, g['training_contract'])['swing']['completed'] == 1
    log['exercises'] = tc.confirmation_outcomes(first, False, 7)
    assert tc.confirmed_state(p, {key: log}, g['training_contract'])['swing']['completed'] == 0
    log['exercises'] = tc.confirmation_outcomes(first, True, 9)
    assert tc.confirmed_state(p, {key: log}, g['training_contract'])['swing']['completed'] == 0, 'above RPE 7'



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
    # The contract seeds an intermediate's clean and press: nothing to confirm.
    assert req['intermediate'] == []
    pent = tracks['pentathlon']['entry_requirements']['mastered_exercises_by_level']
    assert set(pent['intermediate']) == {'wk_kb_clean_single', 'wk_kb_long_cycle_press', 'kb_jerk_single',
                                         'wk_kb_half_snatch', 'wk_kb_push_press_single'}
    assert tracks['double_bell_practice']['entry_requirements']['kettlebell_count'] == 2



BJJ_GYM = ['barbell', 'rack', 'plates', 'pull_up_bar', 'dumbbell', 'box', 'open_space']


def _bjj(weeks=4, **overrides):
    goal = goals.philosophy_to_goal('bjj', list(loader.load_all_frameworks().values()))
    c = dict(equipment=BJJ_GYM, days_per_week=5, session_time_minutes=60, training_level='intermediate')
    c.update(overrides)
    return generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict'), goal, c


def _by_archetype(week):
    out = {}
    for ss in week['schedule'].values():
        for s in ss:
            out.setdefault(s['archetype']['id'], []).append(s)
    return out


def _variants(week):
    return [m.get('variant') for d, ss in sorted(week['schedule'].items()) for s in ss
            for m in s['modules'] if m['id'] == 'grappling_strength']


def test_bjj_mat_time_leads_the_week():
    # Mat first (StrengthLog, BJJEE): classes outnumber strength sessions at every
    # week size; StrengthLog's two workouts from five days, one up to four (I5).
    for days, classes, strength in ((3, 2, 1), (4, 3, 1), (5, 3, 2), (6, 4, 2), (7, 5, 2)):
        p, g, c = _bjj(weeks=2, days_per_week=days, session_time_minutes=90)
        tc.verify(p, g['training_contract'], c)
        week = _by_archetype(p['weeks'][0])
        assert len(week['bjj_class']) == classes and len(week.get('grappling_sc', [])) == strength, \
            (days, {k: len(v) for k, v in week.items()})
        assert all(s['modality'] == 'combat_sport' for s in week['bjj_class'])
        assert all(s['modality'] == 'max_strength' for s in week['grappling_sc'])
    p, _, _ = _bjj(weeks=1, days_per_week=5)
    days = {d: ss[0]['archetype']['id'] for d, ss in p['weeks'][0]['schedule'].items()}
    order = [days[d] for d in sorted(days)]
    assert all(not (a != 'bjj_class' and b != 'bjj_class') for a, b in zip(order, order[1:])), \
        f'strength days are not back to back: {order}'


def test_bjj_strength_runs_strengthlogs_cycle_and_the_mat_carries_on():
    # StrengthLog (R3, R4, R6–R8): Workout 1 and 2, six weeks of strength, a deload
    # week of its own workouts, five weeks of power; the cycle repeats (I3). No
    # source deloads the mat.
    p, g, c = _bjj(weeks=13)
    tc.verify(p, g['training_contract'], c)
    ids = lambda s: [e['exercise']['id'] for e in s['exercises'] if e.get('exercise')]
    full_class = ['bjj_shrimp_drill', 'bjj_drilling', 'bjj_positional_sparring', 'bjj_live_rolling']
    expected = {**{w: ['strength_1', 'strength_2'] for w in (1, 2, 3, 4, 5, 6, 13)},
                7: ['deload_1', 'deload_2'], **{w: ['power_1', 'power_2'] for w in (8, 9, 10, 11, 12)}}
    for w in p['weeks']:
        week = _by_archetype(w)
        assert _variants(w) == expected[w['week_number']], (w['week_number'], _variants(w))
        assert not w['is_deload'], 'the week is not a deload: the classes carry on'
        assert all(ids(s) == full_class and not s['is_deload'] for s in week['bjj_class']), w['week_number']
        assert all(s['is_deload'] == (w['week_number'] == 7) for s in week['grappling_sc']), w['week_number']
    loads = lambda w, variant: {e['exercise']['id']: e['load'] for s in _by_archetype(p['weeks'][w - 1])['grappling_sc']
                                for e in s['exercises'] if e.get('exercise') and s['modules'][0]['variant'] == variant
                                and e['slot_role'].startswith('grappling_strength')}
    one = loads(1, 'strength_1')
    assert [(k, v['sets'], v['reps']) for k, v in one.items()] == [
        ('trap_bar_deadlift', 4, 5), ('pull_up', 3, 'max'), ('bulgarian_split_squat', 3, 8),
        ('barbell_row', 4, 8), ('farmer_carry', 3, '20 m'), ('hanging_leg_raise', 3, '12-15')], one
    # The weights are the athlete's: no effort target, StrengthLog's rule instead.
    assert not any('target_rpe' in l for w in range(1, 14) for v in ('strength_1', 'power_1')
                   for l in loads(w, v).values())
    assert 'add weight next time' in one['trap_bar_deadlift']['load_note']
    # The deload week is StrengthLog's own two workouts, as written.
    deload = loads(7, 'deload_1')
    assert [(k, v['sets'], v['reps']) for k, v in deload.items()] == [
        ('front_squat', 2, 10), ('pull_up', 2, 10), ('box_jump', 2, 10), ('hanging_leg_raise', 2, 12)], deload
    assert '50–60 %' in deload['front_squat']['load_note']
    power = loads(8, 'power_1')
    assert (power['trap_bar_deadlift']['sets'], power['trap_bar_deadlift']['reps']) == (5, 3)
    assert '75 %' in power['trap_bar_deadlift']['load_note']
    # A deload week advances nothing: the rotation picks up where it stopped.
    steps = [s['modules'][0]['forecast_step'] for w in p['weeks'] for s in _by_archetype(w)['grappling_sc']]
    assert steps == list(range(12)) + [12, 12] + list(range(12, 24)), steps
    # One workout a week (four days) alternates week to week; the deload week runs Workout 1's.
    q, g, c = _bjj(weeks=9, days_per_week=4, session_time_minutes=90)
    tc.verify(q, g['training_contract'], c)
    assert [v for w in q['weeks'] for v in _variants(w)] == [
        'strength_1', 'strength_2'] * 3 + ['deload_1', 'power_1', 'power_2']
    # Attending moves the rotation on: a regenerate after two sessions starts at the third.
    logs = {f"1-{SS_DAYS[d - 1]}-0": {'completedAt': '2026-10-21'} for d in p['weeks'][0]['schedule']}
    state = tc.confirmed_state(p, logs, g['training_contract'])
    assert state['grappling_strength']['completed'] == 2 and state['mat_class']['completed'] == 0
    # Fatigue deloads everything: the class drops live rolling and keeps the drilling.
    tired, g, c = _bjj(weeks=1, fatigue_state='overreached')
    tc.verify(tired, g['training_contract'], c)
    light = _by_archetype(tired['weeks'][0])['bjj_class'][0]
    assert tired['weeks'][0]['is_deload'] and ids(light) == full_class[:3]
    drill = next(e for e in light['exercises'] if (e.get('exercise') or {}).get('id') == 'bjj_drilling')
    assert drill['load']['duration_minutes'] == 20, 'drilling is not cut on a deload'
    assert _variants(tired['weeks'][0]) == ['strength_1', 'strength_2'], 'a held cursor still alternates'


def test_bjj_substitutes_are_declared_and_refusals_name_the_way_out():
    # No pull-up bar: inverted rows stand in for the pull-ups and the row (I4);
    # the hanging leg raise has no substitute, so the track refuses and says so.
    no_bar = [e for e in BJJ_GYM if e != 'pull_up_bar']
    bare, _, _ = _bjj(weeks=1, equipment=no_bar)
    assert not bare['weeks'] and 'pull_up_bar' in str(bare['validation_errors']), bare.get('validation_errors')
    # A declared substitute takes a ruled-out lift's place: inverted rows for the
    # barbell row, split squats for the front squat, a dead hang for the pinch.
    _, g, c = _bjj(weeks=1)
    module = next(m for m in g['training_contract']['modules'] if m['id'] == 'grappling_strength')
    catalog = loader.load_all_exercises()[1]['bjj']
    for role, out, sub in (('row', 'barbell_row', 'bjj_inverted_row'), ('front_squat', 'front_squat', 'bulgarian_split_squat'),
                           ('pinch', 'plate_pinch', 'dead_hang')):
        block = next(b for b in module['blocks'] if b['role'] == role)
        assert tc._choose(block, module, catalog, c, ({out}, set())) == sub, role
    # StrengthLog's lifts are essential: an injury one has no substitute for
    # refuses, naming it (the box jump under a knee flag, the presses under a shoulder's).
    for flag in ('patellar_tendinopathy', 'shoulder_instability'):
        hurt, _, _ = _bjj(weeks=1, injury_flags=[flag])
        assert not hurt['weeks'], flag
    lumbar, _, _ = _bjj(weeks=1, injury_flags=['lumbar_disc'])
    assert not lumbar['weeks'] and 'none of' in lumbar['validation_errors'][0]['message']


def test_bjj_conditioning_is_optional_and_never_outnumbers_the_mat():
    # A competitor's conditioning (Vitruve's pre-competition circuits, Chad Wesley
    # Smith's rounds): once a week beside a strength day, never on a class day,
    # never more sessions than the mat, cut in the deload week and gone for a novice.
    p, g, c = _bjj(weeks=7, days_per_week=4, session_time_minutes=90)
    tc.verify(p, g['training_contract'], c)
    tc.verify_phase_rules(p, g)
    for w in p['weeks']:
        days = {d: {m['id'] for s in ss for m in s['modules']} for d, ss in w['schedule'].items()}
        cond = [d for d, ms in days.items() if 'competition_conditioning' in ms]
        assert all('mat_class' not in days[d] for d in cond), days
        assert len(cond) == 1, days
    ids = {e['exercise']['id'] for ss in p['weeks'][0]['schedule'].values() for s in ss
           for e in s['exercises'] if e.get('exercise') and e['slot_role'].startswith('competition_conditioning')}
    assert ids == {'bjj_takedown_practice', 'bjj_sprawl_interval', 'bjj_shuttle_sprint', 'bjj_bear_crawl'}, ids
    deload = p['weeks'][6]
    kept = {e['exercise']['id'] for ss in deload['schedule'].values() for s in ss
            for e in s['exercises'] if e.get('exercise') and e['slot_role'].startswith('competition_conditioning')}
    assert kept <= {'bjj_takedown_practice'}, kept
    for overrides in ({'session_time_minutes': 60}, {'training_level': 'novice', 'session_time_minutes': 90}):
        q, _, _ = _bjj(weeks=1, days_per_week=4, **overrides)
        assert not any(m['id'] == 'competition_conditioning' for ss in q['weeks'][0]['schedule'].values()
                       for s in ss for m in s['modules']), overrides


SS_GYM = ['barbell', 'rack', 'plates', 'bench', 'pull_up_bar', 'open_space']
SS_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def _ss(weeks=2, track=None, level='novice', **overrides):
    goal = goals.philosophy_to_goal('starting_strength', list(loader.load_all_frameworks().values()),
                                    track, level=level)
    c = dict(equipment=SS_GYM, days_per_week=3, session_time_minutes=90, training_level=level)
    c.update(overrides)
    return generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict'), goal, c


def _ss_sessions(p):
    """(log key, session) in program order."""
    return [(f"{w['week_number']}-{SS_DAYS[d - 1]}-0", ss[0]) for w in p['weeks'] for d, ss in sorted(w['schedule'].items())]


def _lifts(session):
    return {e['exercise']['id']: e['load'] for e in session['exercises'] if e.get('exercise')}


def test_ss_alternates_a_and_b_across_weeks():
    # Rippetoe, "Who Wants to Be a Novice? You Do": A and B alternate, A-B-A
    # one week and B-A-B the next; the squat every session, the deadlift in A,
    # the clean in B, chin-ups after A.
    p, g, c = _ss(weeks=2, starting_loads_kg={'back_squat': 60})
    tc.verify(p, g['training_contract'], c)
    order = [s['archetype']['id'] for _, s in _ss_sessions(p)]
    assert order == ['3x5_linear', '3x5_linear_b'] * 3, order
    assert [s['archetype']['name'] for _, s in _ss_sessions(p)][:2] == ['Workout A', 'Workout B']
    for _, s in _ss_sessions(p):
        ids = list(_lifts(s))
        assert ids[0] == 'back_squat' and _lifts(s)['back_squat']['sets'] == 3 and _lifts(s)['back_squat']['reps'] == 5
        if s['archetype']['id'] == '3x5_linear':
            assert ids == ['back_squat', 'strict_press', 'deadlift', 'chin_up'], ids
            assert _lifts(s)['deadlift']['sets'] == 1 and _lifts(s)['chin_up']['reps'] == 'max'
        else:
            assert ids == ['back_squat', 'bench_press', 'power_clean'], ids
            assert (_lifts(s)['power_clean']['sets'], _lifts(s)['power_clean']['reps']) == (5, 3)
    days = sorted(p['weeks'][0]['schedule'])
    assert len(days) == 3 and min(b - a for a, b in zip(days, days[1:])) >= 2
    assert not any(w['is_deload'] for w in p['weeks']), 'no deload week in the novice program'


def test_ss_adds_weight_each_confirmed_session():
    # Every lift goes up every time it is made; a missed lift repeats its
    # weight and holds no other lift back.
    starts = {'back_squat': 60, 'deadlift': 80, 'strict_press': 35, 'bench_press': 50, 'power_clean': 40}
    p, g, c = _ss(weeks=2, starting_loads_kg=starts)
    first = _ss_sessions(p)
    assert _lifts(first[0][1])['back_squat']['weight_kg'] == 65, 'the next session adds to the last made'
    assert [_lifts(s)['back_squat']['weight_kg'] for _, s in first] == [65, 70, 75, 80, 85, 90]
    assert _lifts(first[1][1])['back_squat']['conditional'], 'a later session is a forecast'
    logs = {}
    (k0, s0), (k1, s1) = first[0], first[1]
    logs[k0] = {'completedAt': '2026-10-19', 'exercises': tc.confirmation_outcomes(s0, True, None)}
    logs[k1] = {'completedAt': '2026-10-21', 'exercises': tc.confirmation_outcomes(
        s1, False, None, lifts={'back_squat': {'made': False}})}
    state = tc.confirmed_state(p, logs, g['training_contract'])['novice_lp']
    assert state['completed'] == 2
    assert state['lifts']['back_squat']['next_kg'] == 70, 'the missed squat repeats 70'
    assert state['lifts']['bench_press']['next_kg'] == 55, 'the bench went on'
    q, _, _ = _ss(weeks=1, module_progression_state={'novice_lp': state})
    tc.verify(q, g['training_contract'], c)
    nxt = _ss_sessions(q)[0][1]
    assert nxt['archetype']['id'] == '3x5_linear', 'the rotation carries on: A after B'
    assert _lifts(nxt)['back_squat']['weight_kg'] == 70 and _lifts(nxt)['strict_press']['weight_kg'] == 40


def test_ss_stall_resets_lightens_the_squat_then_triples():
    # Alter, "The Reset": missed at one weight twice in a row, reset 5 % and
    # climb in smaller jumps, and the week's second squat becomes a light day
    # (80 % of the first day's, 2×5); stalled again, reset and the squat, bench
    # and press run 5×3; stalled after that, the lift's novice progression is over.
    module = tc.load_contract('starting_strength', 'linear_progression')['modules'][0]
    lift = {'next_kg': 100, 'exposures': 10}
    tc.apply_lift_outcome(module, 'back_squat', lift, False, 100)
    assert lift['next_kg'] == 100 and lift['failures'] == 1
    tc.apply_lift_outcome(module, 'back_squat', lift, False, 100)
    assert lift['next_kg'] == 95 and lift['resets'] == 1 and lift['failures'] == 0
    once = deepcopy(lift)

    # After the first reset: the week's second squat is light and moves nothing.
    p, g, c = _ss(weeks=2, module_progression_state={'novice_lp': {'completed': 0, 'lifts': {'back_squat': once}}})
    tc.verify(p, g['training_contract'], c)
    squats = [_lifts(s)['back_squat'] for _, s in _ss_sessions(p)]
    assert [q['weight_kg'] for q in squats] == [95, 76.25, 96.25, 97.5, 77.5, 98.75], [q['weight_kg'] for q in squats]
    light = squats[1]
    assert (light['sets'], light['reps'], light['advances_module']) == (2, 5, False)
    assert [(q['sets'], q['reps']) for q in squats[::3]] == [(3, 5), (3, 5)]
    assert [s['modules'][0].get('light_day') for _, s in _ss_sessions(p)] == [None, 'back_squat', None] * 2
    logs = {k: {'completedAt': '2026-10-19', 'exercises': tc.confirmation_outcomes(s, True, None)}
            for k, s in _ss_sessions(p)[:2]}
    state = tc.confirmed_state(p, logs, g['training_contract'])['novice_lp']
    assert state['completed'] == 2 and state['lifts']['back_squat']['next_kg'] == 96.25, \
        'the light day is attended, not progressed'

    tc.apply_lift_outcome(module, 'back_squat', lift, True, 95)
    assert lift['next_kg'] == 96.25, 'a step smaller after a reset'
    for _ in range(2):
        tc.apply_lift_outcome(module, 'back_squat', lift, False, 96.25)
    assert lift['resets'] == 2 and lift['next_kg'] == 91.25

    # After the second: the squat, bench and press run 5×3; the light day stays.
    bench = {'next_kg': 60, 'exposures': 12, 'resets': 2}
    deadlift = {'next_kg': 120, 'exposures': 12, 'resets': 2}
    p, g, c = _ss(weeks=1, module_progression_state={'novice_lp': {'completed': 0, 'lifts': {
        'back_squat': deepcopy(lift), 'bench_press': bench, 'deadlift': deadlift}}})
    tc.verify(p, g['training_contract'], c)
    (_, a1), (_, b1), (_, a2) = _ss_sessions(p)
    assert (_lifts(a1)['back_squat']['sets'], _lifts(a1)['back_squat']['reps']) == (5, 3)
    assert (_lifts(b1)['back_squat']['sets'], _lifts(b1)['back_squat']['reps']) == (2, 5)
    assert (_lifts(b1)['bench_press']['sets'], _lifts(b1)['bench_press']['reps']) == (5, 3)
    assert (_lifts(a1)['deadlift']['sets'], _lifts(a1)['deadlift']['reps']) == (1, 5), 'not the deadlift'
    assert _lifts(a1)['back_squat']['duration_minutes'] == 20, 'the same minutes'

    for _ in range(2):
        tc.apply_lift_outcome(module, 'back_squat', lift, False, 91.25)
    assert lift.get('stalled') and lift['next_kg'] == 91.25
    p, _, _ = _ss(weeks=1, module_progression_state={'novice_lp': {'completed': 0, 'lifts': {'back_squat': lift}}})
    squat = _lifts(_ss_sessions(p)[0][1])['back_squat']
    assert squat['stalled'] and 'Texas Method' in squat['load_note']


def test_ss_first_session_works_up():
    # "Start with an empty bar doing sets of 5, and go up in small jumps":
    # with no weights entered, the first session works up and records.
    p, g, c = _ss(weeks=1)
    tc.verify(p, g['training_contract'], c)
    key, s0 = _ss_sessions(p)[0]
    squat = _lifts(s0)['back_squat']
    assert squat.get('work_up') and 'weight_kg' not in squat and 'empty bar' in squat['load_note']
    logs = {key: {'completedAt': '2026-10-19', 'exercises': tc.confirmation_outcomes(
        s0, True, None, lifts={'back_squat': {'made': True, 'weightKg': 62.5},
                               'strict_press': {'made': True, 'weightKg': 30},
                               'deadlift': {'made': True, 'weightKg': 80}})}}
    state = tc.confirmed_state(p, logs, g['training_contract'])['novice_lp']
    assert state['lifts']['back_squat']['next_kg'] == 67.5 and state['lifts']['deadlift']['next_kg'] == 87.5


def test_ss_refuses_with_the_unblocking_constraint():
    bare, _, _ = _ss(weeks=1, equipment=['pull_up_bar', 'open_space'])
    assert not bare['weeks'] and 'equipment' in bare['validation_errors'][0]['message']
    lp, _, _ = _ss(weeks=1, track='linear_progression', level='intermediate')
    assert not lp['weeks'] and 'Texas Method' in lp['validation_errors'][0]['message']
    elite, _, _ = _ss(weeks=1, level='elite')
    assert not elite['weeks'] and 'no track of this program is written for elite' in elite['validation_errors'][0]['message']
    two, _, _ = _ss(weeks=1, days_per_week=2)
    assert not two['weeks'], 'three sessions a week, 48 hours apart: two days cannot hold them'
    short, _, _ = _ss(weeks=1, session_time_minutes=45)
    assert not short['weeks'] and 'minutes' in short['validation_errors'][0]['message']
    no_bar, g, c = _ss(weeks=1, equipment=['barbell', 'rack', 'plates', 'bench'])
    tc.verify(no_bar, g['training_contract'], c)
    assert any('Chin-Up left out' in line for line in no_bar['compromises']), no_bar['compromises']


def test_ss_intermediate_routes_to_texas_method():
    frameworks = list(loader.load_all_frameworks().values())
    assert goals.philosophy_to_goal('starting_strength', frameworks, level='intermediate')['track']['id'] == 'texas_method'
    assert goals.philosophy_to_goal('starting_strength', frameworks, level='novice')['track']['id'] == 'linear_progression'
    assert goals.philosophy_to_goal('starting_strength', frameworks)['track']['id'] == 'linear_progression'
    import api
    r = api.app.test_client().post('/api/programs/generate', json={
        'philosophy_id': 'starting_strength', 'num_weeks': 1,
        'constraints': {'training_level': 'intermediate', 'days_per_week': 3, 'session_time_minutes': 90,
                        'equipment': SS_GYM, 'injury_flags': []}})
    assert r.status_code == 200, r.get_json()
    assert r.get_json()['goal']['track']['id'] == 'texas_method'


def test_texas_method_volume_light_intensity_week():
    # Rippetoe, "The Texas Method": Monday 5×5 at about 90 % of the five-rep
    # max and one heavy deadlift; Wednesday squat 2×5 at 80 % of Monday, the
    # other press lighter, chin-ups; Friday a new five-rep max and power
    # cleans. The press and bench swap Mondays.
    five = {'back_squat': 100, 'strict_press': 50, 'bench_press': 80, 'deadlift': 140, 'power_clean': 70}
    p, g, c = _ss(weeks=2, level='intermediate', session_time_minutes=90, starting_loads_kg=five)
    tc.verify(p, g['training_contract'], c)
    week = [s for _, s in _ss_sessions(p)]
    assert [s['archetype']['id'] for s in week] == ['tm_volume', 'tm_light', 'tm_intensity'] * 2
    mon, wed, fri, mon2 = (_lifts(s) for s in week[:4])
    assert (mon['back_squat']['sets'], mon['back_squat']['reps'], mon['back_squat']['weight_kg']) == (5, 5, 90)
    assert mon['strict_press']['weight_kg'] == 45 and mon['deadlift']['weight_kg'] == 142.5
    assert (wed['back_squat']['sets'], wed['back_squat']['weight_kg']) == (2, 72.5)
    assert 'bench_press' in wed and wed['chin_up']['reps'] == 'max'
    assert fri['back_squat']['weight_kg'] == 102.5 and fri['strict_press']['weight_kg'] == 51.25
    assert (fri['power_clean']['sets'], fri['power_clean']['reps']) == (5, 3)
    assert 'bench_press' in mon2 and 'strict_press' not in mon2, 'the bench takes the second Monday'
    assert mon2['back_squat']['weight_kg'] == 92.5, "90 % of Friday's new five-rep max"


def test_confirm_route_records_each_lift():
    import api
    p, _, _ = _ss(weeks=1, starting_loads_kg={'back_squat': 60, 'strict_press': 35, 'deadlift': 80})
    day, first = next((d, ss[0]) for d, ss in p['weeks'][0]['schedule'].items())
    name = SS_DAYS[day - 1]
    stored = {'currentProgram': {'weeks': [{'schedule': {name: [first]}}]}}
    saved = {}

    def upsert(_user, log):
        saved.clear()
        saved.update(log)
        return {'exercises': log['exercises'], 'completed_at': log.get('completedAt'), 'session_uid': 'v:w0',
                'session_key': log['sessionKey'], 'source': log['source']}
    client = api.app.test_client()
    with patch('src.program_history.active_session_uid', return_value='v:w0'), \
         patch('src.program_history.resolve_session',
               return_value={'week_index': 0, 'day_name': name, 'session_index': 0}), \
         patch('src.db.get_user_program', return_value=stored), \
         patch.object(api._health, 'get_session_log', return_value={}), \
         patch.object(api._health, 'upsert_session_log', side_effect=upsert), \
         patch('src.standard_results.after_session_log', return_value=None):
        url = f'/api/health/sessions/1-{name}-0/confirm'
        assert client.post(url, json={'clean': False}).status_code == 422, 'say which lifts were missed'
        r = client.post(url, json={'clean': False, 'lifts': {'back_squat': {'made': False, 'weightKg': 65}}})
        assert r.status_code == 200, r.get_json()
        squat, press = saved['exercises']['back_squat'], saved['exercises']['strict_press']
        assert squat['made'] is False and squat['weightKg'] == 65
        assert all(not s['completed'] for s in squat['sets']) and len(squat['sets']) == 3
        assert press['made'] is True, 'only the named lift was missed'
        r = client.post(url, json={'clean': True})
        assert r.status_code == 200
        assert saved['exercises']['back_squat']['made'] and saved['exercises']['back_squat']['weightKg'] == 65
        assert saved['exercises']['back_squat']['sets'][0]['repsActual'] == 5
        assert client.post(url, json={'clean': True, 'lifts': {'back_squat': {'made': 'yes'}}}).status_code == 422
        assert client.post(url, json={'clean': False, 'lifts': {}}).status_code == 422, 'naming nothing missed nothing'
    # A first session's work-up made with no weight would leave the lift where it was.
    q, _, _ = _ss(weeks=1)
    day, first = next((d, ss[0]) for d, ss in q['weeks'][0]['schedule'].items())
    name = SS_DAYS[day - 1]
    stored = {'currentProgram': {'weeks': [{'schedule': {name: [first]}}]}}
    with patch('src.program_history.active_session_uid', return_value='v:w0'), \
         patch('src.program_history.resolve_session',
               return_value={'week_index': 0, 'day_name': name, 'session_index': 0}), \
         patch('src.db.get_user_program', return_value=stored), \
         patch.object(api._health, 'get_session_log', return_value={}), \
         patch.object(api._health, 'upsert_session_log', side_effect=upsert), \
         patch('src.standard_results.after_session_log', return_value=None):
        url = f'/api/health/sessions/1-{name}-0/confirm'
        r = client.post(url, json={'clean': True})
        assert r.status_code == 422 and 'worked up to' in r.get_json()['detail'], r.get_json()
        weights = {'back_squat': 60, 'strict_press': 30, 'deadlift': 80}
        r = client.post(url, json={'clean': True, 'lifts': {k: {'made': True, 'weightKg': v} for k, v in weights.items()}})
        assert r.status_code == 200, r.get_json()


def test_legacy_ss_program_seeds_loads():
    # A program from before the contract (the old 3×5 sessions, logged by
    # sets): each lift starts from the last weight its sets made.
    module = tc.load_contract('starting_strength', 'linear_progression')['modules'][0]

    def session(*lifts):
        return {'exercises': [{'exercise': {'id': eid}, 'load': {'sets': 3, 'reps': 5}} for eid in lifts]}
    old = {'weeks': [{'week_number': 1, 'schedule': {'Monday': [session('back_squat', 'strict_press')],
                                                     'Wednesday': [session('back_squat', 'bench_press')]}}]}
    sets = lambda kg, n=3: [{'weightKg': kg, 'repsActual': 5, 'completed': True} for _ in range(n)]
    logs = {'1-Monday-0': {'exercises': {'back_squat': {'sets': sets(80)}, 'strict_press': {'sets': sets(40)}}},
            '1-Wednesday-0': {'exercises': {'back_squat': {'sets': sets(82.5, 2) + [{'weightKg': 82.5, 'repsActual': 3, 'completed': True}]}}}}
    seeded = tc.seed_lifts(old, logs, module)
    assert seeded['back_squat']['next_kg'] == 82.5, 'the last squat missed reps: it repeats'
    assert seeded['strict_press']['next_kg'] == 42.5
    assert 'bench_press' not in seeded, 'no sets logged, no weight'
    p, g, c = _ss(weeks=1, module_progression_state={'novice_lp': {'completed': 0, 'lifts': seeded}})
    tc.verify(p, g['training_contract'], c)
    assert _lifts(_ss_sessions(p)[0][1])['back_squat']['weight_kg'] == 82.5


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
    for level in ('novice', 'advanced', 'elite'):
        suite.addTest(unittest.FunctionTestCase(lambda level=level: test_source_cycle_retains_movements_and_spacing(level),
                                               description=f'full track: {level}'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
