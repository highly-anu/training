#!/usr/bin/env python
"""Marcus Filly's training contract: the sample weeks in cycles and a bridge week.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_contract.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_training_contract.py on 2026-10-31.

    .venv/bin/python data/packages/marcus_filly/tests/test_contract.py
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


FBB_GYM = ['barbell', 'rack', 'plates', 'dumbbell', 'pull_up_bar', 'resistance_band', 'cable_machine', 'open_space']


def _filly(track=None, weeks=13, **overrides):
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), track)
    c = dict(equipment=FBB_GYM, days_per_week=3, session_time_minutes=60, training_level='intermediate')
    c.update(overrides)
    return generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict'), goal, c


def test_filly_runs_the_sample_weeks_in_cycles_and_a_bridge_week():
    # R3, R4, R6: each track's three sample days as printed, about an hour each;
    # R8, R9: two six-week cycles of them, then the Bridge week at RPE 6–7, the
    # work kept (I1: the published week repeats).
    for track in ('functional_bodybuilding', 'pump_lift'):
        p, g, c = _filly(track, weeks=14)
        tc.verify(p, g['training_contract'], c)
        days = lambda w: [s for _, ss in sorted(w['schedule'].items()) for s in ss]
        for w in p['weeks']:
            assert [s['modules'][0]['variant'] for s in days(w)] == ['day_1', 'day_2', 'day_3'], (track, w['week_number'])
            assert all(50 <= s['archetype']['duration_estimate_minutes'] <= 60 for s in days(w)), track
            assert all(s['is_deload'] == (w['week_number'] == 13) for s in days(w)), (track, w['week_number'])
        ids = lambda s: [e['exercise']['id'] for e in s['exercises'] if e.get('exercise')]
        first = days(p['weeks'][0])
        assert ids(first[0])[0] == 'fbb_warm_up' and ids(first[0])[-1] == 'fbb_cooldown'
        assert ('fbb_conditioning' in ids(first[0])) == (track == 'functional_bodybuilding'), 'Pump Lift has no conditioning (R4)'
        bridge = days(p['weeks'][12])
        assert [ids(s) for s in bridge] == [ids(s) for s in first], 'the Bridge week keeps the work'
        assert all('RPE 6–7' in e['load']['load_note'] for s in bridge for e in s['exercises'] if e.get('exercise'))
    p, g, c = _filly(weeks=1)
    row = next(e for s in p['weeks'][0]['schedule'][1] for e in s['exercises'] if e['slot_role'] == 'persist_session_tripod_row')
    assert (row['load']['sets'], row['load']['reps'], row['load']['target_rpe']) == (6, '10', 7)
    assert '@20X1' in row['slot']['notes']
    # Without a cable machine the sample's barbell options stand in (I5).
    no_cable, g, c = _filly(weeks=1, equipment=[e for e in FBB_GYM if e != 'cable_machine'])
    tc.verify(no_cable, g['training_contract'], c)
    day_3 = [e['exercise']['id'] for s in no_cable['weeks'][0]['schedule'][5] for e in s['exercises'] if e.get('exercise')]
    assert 'barbell_skull_crusher' in day_3 and 'barbell_bicep_curl' in day_3, day_3
    novice, _, _ = _filly(weeks=1, training_level='novice')
    assert not novice['weeks'], 'no novice track (I6)'

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
