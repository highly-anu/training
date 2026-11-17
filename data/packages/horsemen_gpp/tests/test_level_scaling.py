#!/usr/bin/env python
"""Horsemen at every level: the operator's workouts as written for the elite,
the commons' shares below, a novice taken in with the hardest movements
scaled (I3; src/level_scaling.py).

    .venv/bin/python data/packages/horsemen_gpp/tests/test_level_scaling.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')


def _program(level: str) -> dict:
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), 'four_month_macro')
    c = dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=120, training_level=level)
    return generate(None, c, num_weeks=16, goal_dict=goal, output_format='dict')


def _sessions(p: dict) -> list:
    return [s for w in p['weeks'] for ss in w['schedule'].values() for s in ss]


def test_a_novice_does_half_of_every_workout():
    p = _program('novice')
    sessions = _sessions(p)
    assert len(sessions) == 96 and not p.get('validation_errors'), p.get('validation_errors')
    # Every slot filled; the hardest movements scaled to what a novice does.
    assert all(e.get('exercise') or e.get('meta') for s in sessions for e in s['exercises'])
    done = {e['exercise']['id'] for s in sessions for e in s['exercises'] if e.get('exercise')}
    assert not done & {'snatch', 'clean_and_jerk', 'squat_clean', 'power_snatch', 'rope_climb',
                       'handstand_push_up'}, done
    # A rep ladder rung by rung, a fixed weight halved, a % of today's max as written.
    bench = next(e for s in sessions if s['archetype']['id'] == 'hm_winter_in_august'
                 for e in s['exercises'] if e['exercise']['id'] == 'bench_press')
    assert bench['load']['reps'] == '13-10-8-5-3' and bench['load']['weight_kg'] == 30.0, bench['load']
    press = next(e for s in sessions for e in s['exercises']
                 if (e.get('exercise') or {}).get('id') == 'strict_press' and '%' in (e['load'].get('load_note') or ''))
    assert 'weight_kg' not in press['load'], press['load']
    # The PT test is a protocol, for intermediates and up: a novice's week says so.
    assert {t['reason'] for w in p['weeks'] for t in w.get('tests_skipped') or []} == {'level'}


def test_the_elite_runs_the_macro_as_written():
    sessions = _sessions(_program('elite'))
    assert not any('rx' in (e.get('load') or {}) or e.get('scaled_from') for s in sessions for e in s['exercises'])


if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
