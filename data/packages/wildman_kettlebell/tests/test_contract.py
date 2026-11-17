#!/usr/bin/env python
"""Wildman Kettlebell's training contract: the source's cycles, phases, events and earned state.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_contract.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_training_contract.py on 2026-10-31.

    .venv/bin/python data/packages/wildman_kettlebell/tests/test_contract.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')
from copy import deepcopy
from unittest.mock import patch
import unittest
from src import goals, loader, training_contract as tc
from src.generator import generate


def setup(track='general_practice', **overrides):
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), track)
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
    assert tc.load_contract(PKG, 'general_practice')['modules']
    reqs = constraint_requirements = __import__('src.constraint_impact', fromlist=['x']).contract_requirements
    assert 'wk_kb_snatch' not in (reqs(g, 'intermediate').get('mastered_exercises') or [])


def test_swing_minutes_alternate_hands_unless_the_athlete_keeps_two_hands():
    # The swing PDF's Option C, its most common: minutes alternate two-hand and
    # hand-to-hand swings. The default (owner, 2026-10-31); two-hand only is
    # the athlete's choice, and an option it does not offer is the default.
    goal, _ = setup()
    option = next(o for o in goal['training_contract']['options'] if o['id'] == 'swing_style')
    assert option['default'] == 'alternating' and {c['id'] for c in option['choices']} == {'alternating', 'two_hand'}
    p, _, _ = plan(weeks=2)
    loads = swings(p)
    assert loads and all(l['alternate']['exercise_id'] == 'wk_kb_swing_hand_to_hand' for l in loads)
    assert all(l['load_note'].startswith('Alternate minutes: Kettlebell Swing (Two-Hand), then '
                                         'Kettlebell Swing (Hand-to-Hand).') for l in loads)
    assert [l['reps_per_round'] for l in loads] == [6, 8, 10, 12], 'the cursor is the same either way'
    two, _, _ = plan(weeks=2, contract_options={'swing_style': 'two_hand'})
    assert swings(two) and not any(l.get('alternate') for l in swings(two))
    odd, _, _ = plan(weeks=2, contract_options={'swing_style': 'one_hand_only'})
    assert all(l.get('alternate') for l in swings(odd)), 'an unknown choice is the default'


def test_programs_alternate_on_wildmans_days():
    # "Kettlebell Swings on Monday & Thursday, Clean & Press on Wednesday &
    # Saturday": the two programs alternate, never swing, swing, press, press.
    p, _, _ = plan(weeks=4, days_per_week=4)
    for w in p['weeks']:
        on = {}
        for d, ss in w['schedule'].items():
            for s in ss:
                for r in s['modules']:
                    on.setdefault(r['id'], set()).add(d)
        assert on['swing'] == {1, 4} and on['clean_press'] == {3, 6}, on
    # A placement's spacing: alternating beats two of a kind in a row, and a
    # module's own sessions as far apart as the days allow.
    kb = lambda mid, mod: {'id': mid, 'modality': mod}
    paired = {1: [kb('swing', 'power')], 3: [kb('swing', 'power')],
              5: [kb('press', 'skill')], 7: [kb('press', 'skill')]}
    alternating = {1: [kb('swing', 'power')], 3: [kb('press', 'skill')],
                   5: [kb('swing', 'power')], 7: [kb('press', 'skill')]}
    assert tc._spacing(alternating) > tc._spacing(paired)
    # Back to back on the calendar ranks below anything merely alike.
    assert tc._spacing({1: [kb('a', 'x')], 2: [kb('b', 'x')]}) < tc._spacing({1: [kb('a', 'x')], 4: [kb('b', 'x')]})


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

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    for level in ('novice', 'advanced', 'elite'):
        suite.addTest(unittest.FunctionTestCase(lambda level=level: test_source_cycle_retains_movements_and_spacing(level),
                                               description=f'full track: {level}'))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
