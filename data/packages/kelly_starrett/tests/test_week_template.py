#!/usr/bin/env python
"""Kelly Starrett's template weeks: the 21-day challenge as written.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_week_template.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_week_template.py on 2026-10-31.

    .venv/bin/python data/packages/kelly_starrett/tests/test_week_template.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')
import os
import sys
from src import week_template as wt  # noqa: E402


def test_kelly_starrett_runs_the_21_day_challenge_as_written():
    # R1: Days 1-21 in order, every day, needing no equipment; R3: floor
    # sitting every day; R7: then day 21 every day, no deload.
    from src import goals, loader
    from src.generator import generate
    frameworks = list(loader.load_all_frameworks().values())
    goal = goals.philosophy_to_goal(PKG, frameworks, None, 'novice')
    c = dict(equipment=[], days_per_week=7, session_time_minutes=30, training_level='novice')
    p = generate(None, c, num_weeks=5, goal_dict=goal, output_format='dict')
    ids = [s['archetype']['id'] for w in p['weeks'] for d in range(1, 8) for s in w['schedule'].get(d, [])]
    assert ids == [f'btm_d{n:02d}' for n in range(1, 22)] + ['btm_d21'] * 14, ids
    sessions = [s for w in p['weeks'] for d in range(1, 8) for s in w['schedule'].get(d, [])]
    assert all(any(ea['exercise']['id'] == 'floor_sitting' for ea in s['exercises']) for s in sessions)
    assert not any(w['is_deload'] for w in p['weeks'])
    c['days_per_week'] = 5
    assert not generate(None, c, num_weeks=3, goal_dict=goal, output_format='dict')['weeks'], 'the challenge is daily'

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
