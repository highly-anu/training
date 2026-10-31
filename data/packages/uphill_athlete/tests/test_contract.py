#!/usr/bin/env python
"""Uphill Athlete's training contract: the volume ramp, the strength phases, the long day.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_contract.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_training_contract.py on 2026-10-31.

    .venv/bin/python data/packages/uphill_athlete/tests/test_contract.py
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


UPHILL_GYM = ['barbell', 'rack', 'plates', 'pull_up_bar', 'kettlebell', 'box', 'open_space']


def _uphill(weeks=29, **overrides):
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()))
    c = dict(equipment=UPHILL_GYM, days_per_week=6, session_time_minutes=360, training_level='intermediate')
    c.update(overrides)
    return generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict'), goal, c


def _aerobic_minutes(week):
    """The week's minutes on its volume blocks: the long day, the easy days, the Zone 3 itself."""
    return sum(e['load']['duration_minutes'] for ss in week['schedule'].values() for s in ss for e in s['exercises']
               if e['slot_role'] in ('long_day_long', 'aerobic_aerobic', 'zone_3_zone_3'))


def _module_minutes(week, role):
    return [e['load']['duration_minutes'] for ss in week['schedule'].values() for s in ss for e in s['exercises']
            if e['slot_role'] == role]


def test_uphill_volume_ramps_recovers_and_holds():
    # Training for Mountaineering (R3, R4, R7): three build weeks, an easy week at
    # half the hardest, the long day half the week's aerobic time; about 10 % a
    # week (R5); the ramp holds through Specific and the taper halves it (R17, R19).
    p, g, c = _uphill()
    tc.verify(p, g['training_contract'], c)
    tc.verify_phase_rules(p, g)
    weeks = {w['week_number']: w for w in p['weeks']}
    total = {n: _aerobic_minutes(w) for n, w in weeks.items()}
    for n in (2, 3, 6, 7):
        assert abs(total[n] / total[n - 1] - 1.1) < 0.03, (n, total[n - 1], total[n])
    assert abs(total[4] - total[3] / 2) <= 2 and weeks[4]['is_deload'], (total[3], total[4])
    assert abs(total[5] - total[2]) <= 2, 'the next block starts one step above the last'
    for n in (1, 9, 19):
        long_day = _module_minutes(weeks[n], 'long_day_long')[0]
        assert abs(long_day - total[n] / 2) <= 2, (n, long_day, total[n])
    held = total[19]
    assert all(abs(total[n] - held) <= 4 for n in (21, 22, 23, 25, 26, 27)), [total[n] for n in range(21, 28)]
    assert abs(total[29] - held / 2) <= 4 and weeks[29]['phase_id'] == 'taper'
    # No Zone 3 before week 13 (R8); one a week in Base, two in Specific (R10, R17).
    z3 = {n: len(_module_minutes(w, 'zone_3_zone_3')) for n, w in weeks.items()}
    assert all(z3[n] == 0 for n in range(1, 13)) and z3[13] == 1 and z3[21] == 2, z3
    assert abs(_module_minutes(weeks[13], 'zone_3_zone_3')[0] - 0.05 * total[13]) <= 2
    # No pack for four weeks, then 5 % (R7); never on the long day.
    notes = lambda n, role: {e['slot']['notes'] for ss in weeks[n]['schedule'].values() for s in ss
                             for e in s['exercises'] if e['slot_role'] == role}
    assert all('No pack yet.' in t for t in notes(1, 'aerobic_aerobic'))
    assert all('5 % of your bodyweight' in t for t in notes(5, 'aerobic_aerobic'))
    assert all('Pack' not in t for t in notes(9, 'long_day_long'))
    # Specific's long days back to back (pod_spec, R20); the Zone 3 days stay 48 h apart.
    for n in (21, 24, 27):
        days = {m: [d for d, ss in weeks[n]['schedule'].items() for s in ss for x in s['modules'] if x['id'] == m]
                for m in ('long_day', 'aerobic', 'zone_3')}
        assert abs(days['aerobic'][0] - days['long_day'][0]) == 1, (n, days)
        assert days['zone_3'][1] - days['zone_3'][0] >= 2, (n, days)


def test_uphill_strength_goes_general_max_then_muscular_endurance():
    # R11, R12, R14: the General Strength circuit's laps in Transition, heavy
    # lifting in Base, the ME workouts in order in Specific, the tenth held.
    p, g, c = _uphill()
    by_week = {w['week_number']: [m.get('variant') or m['id'] for ss in sorted(w['schedule'].items())
                                  for s in ss[1] for m in s['modules']] for w in p['weeks']}
    strength = lambda n, prefix: [v for v in by_week[n] if v.startswith(prefix)]
    assert [strength(n, 'gs_') for n in (1, 3, 5, 7)] == [['gs_1'] * 2, ['gs_2'] * 2, ['gs_3'] * 2, ['gs_4'] * 2]
    assert sorted(strength(9, 'squat') + strength(9, 'deadlift')) == ['deadlift', 'squat']
    assert not any(v.startswith('gs_') for n in range(9, 30) for v in by_week[n])
    me = [v for n in range(21, 29) for v in by_week[n] if v.startswith('me_')]
    assert me == ['me_1', 'me_2', 'me_3', 'me_4', 'me_4', 'me_5', 'me_6', 'me_7'], me
    week = next(w for w in p['weeks'] if w['week_number'] == 22)
    loads = {e['exercise']['id']: e['load'] for ss in week['schedule'].values() for s in ss for e in s['exercises']
             if e.get('exercise') and e['slot_role'].startswith('muscular_endurance')}
    assert (loads['box_step_up']['sets'], loads['box_step_up']['reps']) == (6, '10/leg')
    assert 'Bodyweight only' in loads['box_step_up']['load_note']
    # After the tenth workout the rotation holds on it.
    late, g, c = _uphill(weeks=23, start_phase='specific',
                         module_progression_state={'muscular_endurance': {'completed': 9}})
    tc.verify(late, g['training_contract'], c)
    assert [m['variant'] for w in late['weeks'] for ss in w['schedule'].values() for s in ss for m in s['modules']
            if m['id'] == 'muscular_endurance'][:3] == ['me_10', 'me_10', 'me_10']


def test_uphill_caps_the_long_day_and_refuses_what_it_is_not_for():
    # I4: a 120-minute athlete gets the long day capped, and is told.
    p, g, c = _uphill(weeks=2, session_time_minutes=120)
    tc.verify(p, g['training_contract'], c)
    assert _module_minutes(p['weeks'][0], 'long_day_long') == [120]
    assert any('capped at your longest day, 120 minutes' in line for line in p['compromises'])
    # A long day goes where the athlete has the time.
    q, g, c = _uphill(weeks=1, session_time_minutes=240, day_configs={d: {'minutes': 90} for d in range(1, 7)})
    tc.verify(q, g['training_contract'], c)
    long_days = [d for d, ss in q['weeks'][0]['schedule'].items() for s in ss
                 for m in s['modules'] if m['id'] == 'long_day']
    assert long_days == [7], long_days
    # No novice track yet; fewer than six days refuse with the reason.
    novice, _, _ = _uphill(weeks=1, training_level='novice')
    assert not novice['weeks'] and 'intermediate, advanced and elite athletes' in novice['validation_errors'][0]['message']
    five, _, _ = _uphill(weeks=1, days_per_week=5)
    assert not five['weeks'], 'six days a week (R2)'

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
