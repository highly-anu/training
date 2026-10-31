#!/usr/bin/env python
"""Gym Jones' template weeks: its two months as written.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_week_template.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_week_template.py on 2026-10-31.

    .venv/bin/python data/packages/gym_jones/tests/test_week_template.py
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


def test_gym_jones_runs_its_two_months_as_written():
    # R4, R9: each plan's 28 days in order, six a week and the seventh rest;
    # R10: a novice with no track named gets Soldier of Steel and cannot take
    # Operator Fitness; R12: no deload week.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    frameworks = list(loader.load_all_frameworks().values())

    def month(level, track=None):
        goal = goals.philosophy_to_goal(PKG, frameworks, track, level)
        c = dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=120, training_level=level)
        return generate(None, c, num_weeks=4, goal_dict=goal, output_format='dict'), goal

    for level, track, prefix in (('intermediate', 'operator_fitness', 'gj_of_d'), ('novice', None, 'gj_sos_d')):
        p, goal = month(level, track)
        assert goal['track']['id'] == (track or 'soldier_of_steel'), goal['track']['id']
        ids = [[s['archetype']['id'] for d in range(1, 8) for s in w['schedule'].get(d, [])] for w in p['weeks']]
        assert ids == [[f'{prefix}{7 * k + d:02d}' for d in range(1, 7)] for k in range(4)], ids
        assert all(7 not in w['schedule'] for w in p['weeks']), 'the seventh day rests'
        assert not any(w['is_deload'] for w in p['weeks'])
    p, _ = month('intermediate', 'operator_fitness')
    hike = p['weeks'][0]['schedule'][6][0]['exercises'][0]
    assert hike['exercise']['id'] == 'ruck' and '20-30 lb' in hike['load']['load_note'], hike['load']
    p, _ = month('novice', 'operator_fitness')
    assert not p['weeks'], 'Operator Fitness is not written for the newly training'

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
