#!/usr/bin/env python
"""BJJ at every level: StrengthLog's strength and BJJEE's conditioning as
written for the elite, the commons' shares below; a class is a class at every
level (I9; training_contract.with_level).

    .venv/bin/python data/packages/bjj/tests/test_level_scaling.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')

BJJ_GYM = ['barbell', 'rack', 'plates', 'pull_up_bar', 'dumbbell', 'box', 'open_space']


def _bjj(level: str, weeks: int = 12):
    from src import goals, loader, training_contract as tc
    from src.generator import generate
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()))
    c = dict(equipment=BJJ_GYM, days_per_week=5, session_time_minutes=60, training_level=level)
    p = generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict')
    assert p['weeks'], p.get('validation_errors')
    tc.verify(p, goal['training_contract'], c)       # the contract's own checks agree with the scale
    return p


def _rows(p, module: str) -> list:
    return [e for w in p['weeks'] for ss in w['schedule'].values() for s in ss for e in s['exercises']
            if e['load'].get('module_id') == module]


def test_a_novice_does_half_the_strength_and_a_whole_class():
    p = _bjj('novice')
    deadlift = next(e for e in _rows(p, 'grappling_strength') if e['exercise']['id'] == 'trap_bar_deadlift')
    assert deadlift['load']['sets'] == 2 and deadlift['load']['rx'] == {'sets': 4}, deadlift['load']
    assert 'Your weight' in deadlift['load']['load_note']                 # the weight the athlete's (I2)
    assert all('rx' not in e['load'] for e in _rows(p, 'mat_class'))      # a class is a class
    assert {e['load']['duration_minutes'] for e in _rows(p, 'mat_class') if e['exercise']['id'] == 'bjj_drilling'} == {20}


def test_the_elite_runs_strengthlog_as_written():
    assert all('rx' not in e['load'] for e in _rows(_bjj('elite', weeks=4), 'grappling_strength'))


if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
