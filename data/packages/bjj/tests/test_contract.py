#!/usr/bin/env python
"""BJJ's training contract: the mat leads the week, StrengthLog's cycle carries the strength work.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_contract.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_training_contract.py on 2026-10-31.

    .venv/bin/python data/packages/bjj/tests/test_contract.py
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


BJJ_GYM = ['barbell', 'rack', 'plates', 'pull_up_bar', 'dumbbell', 'box', 'open_space']


def _bjj(weeks=4, **overrides):
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()))
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
    catalog = loader.load_all_exercises()[1][PKG]
    for role, out, sub in (('row', 'barbell_row', 'bjj_inverted_row'), ('front_squat', 'front_squat', 'bulgarian_split_squat'),
                           ('pinch', 'plate_pinch', 'dead_hang')):
        block = next(b for b in module['blocks'] if b['role'] == role)
        assert tc._choose(block, module, catalog, c, ({out}, set())) == sub, role
    # A lift an injury rules out, with no substitute, is left out and said; the
    # rest of the workout runs (the owner's call, 2026-10-21).
    hurt, g, c = _bjj(weeks=1, injury_flags=['shoulder_instability'])
    tc.verify(hurt, g['training_contract'], c)
    left = [line for line in hurt['compromises'] if 'your injury rules it out' in line]
    assert all(any(name in line for line in left) for name in ('Bench Press', 'Overhead Press', 'Hanging Leg Raise')), left
    lifts = {e['exercise']['id'] for ss in hurt['weeks'][0]['schedule'].values() for s in ss for e in s['exercises']
             if e.get('exercise') and e['slot_role'].startswith('grappling_strength')}
    assert 'trap_bar_deadlift' in lifts and not lifts & {'bench_press', 'overhead_press', 'hanging_leg_raise'}, lifts
    # Rolling, positional work and drilling all ruled out leave no class: refused.
    knee, _, _ = _bjj(weeks=1, injury_flags=['patellar_tendinopathy'])
    assert not knee['weeks'] and 'mat_class' in knee['validation_errors'][0]['message']
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
    # The output review (2026-10-22): a deload frees time, but adds no session
    # the build weeks had no room for — at 60 minutes, no conditioning in week 7.
    short, _, _ = _bjj(weeks=7)
    assert not any(m['id'] == 'competition_conditioning' for w in short['weeks']
                   for ss in w['schedule'].values() for s in ss for m in s['modules'])


SS_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
