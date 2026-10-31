#!/usr/bin/env python
"""CrossFit's benchmark workouts as tests in its pools.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_standard_tests.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_standard_tests.py on 2026-10-31.

    .venv/bin/python data/packages/crossfit/tests/test_standard_tests.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')
import copy
import os
import fixture_packages  # noqa: E402
from src import goals, loader, phases, program_history, standard_tests
from src.generator import generate
from src.selector import select_archetype


FRAMEWORKS = list(loader.load_all_frameworks().values())


ALL_EQUIPMENT = ['barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'open_space', 'rower',
                 'jump_rope', 'ruck_pack', 'sandbag', 'box', 'dumbbell', 'bench']


def _constraints(**over):
    c = {'days_per_week': 5, 'session_time_minutes': 75, 'training_level': 'intermediate',
         'equipment': ALL_EQUIPMENT, 'injury_flags': [], 'periodization_week': 1, 'fatigue_state': 'normal'}
    c.update(over)
    return c


def _gen(phil, track=None, weeks=4, goal=None, **over):
    goal = goal or goals.philosophy_to_goal(phil, FRAMEWORKS, track_id=track)
    if goal.get('training_contract'):
        over.setdefault('mastered_exercises', [eid for m in goal['training_contract']['modules'] for eid in m.get('requires_mastery', [])])
    return generate(goal_id=goal['id'], goal_dict=goal, constraints=_constraints(**over),
                    num_weeks=weeks, output_format='dict')


def _sessions(week):
    return [(day, i, s) for day, ss in sorted(week['schedule'].items()) for i, s in enumerate(ss)]


def test_crossfit_benchmarks_recur_in_its_pools():
    # The Girls recur irregularly among the day's workouts (Benchmark Workouts,
    # 2003), each a selectable test of its standard; one the athlete cannot do
    # as written is passed over.
    raw = _gen(PKG, weeks=12, days_per_week=6, session_time_minutes=60)
    girls = {s['archetype']['id']: s for w in raw['weeks'] for _, _, s in _sessions(w)
             if any(ea.get('standard') for ea in s['exercises'])}
    assert {'cf_fran', 'cf_cindy', 'cf_helen'} <= girls.keys(), sorted(girls)
    archetypes = {a['id']: a for a in loader.load_all_archetypes()}
    assert all(standard_tests.is_test(archetypes[aid]) for aid in girls), 'each a selectable test of its standard'
    no_barbell = _gen(PKG, weeks=12, days_per_week=6, session_time_minutes=60,
                      equipment=['pull_up_bar', 'kettlebell', 'open_space', 'rower', 'jump_rope', 'box'])
    ids = {s['archetype']['id'] for w in no_barbell['weeks'] for _, _, s in _sessions(w)}
    assert 'cf_fran' not in ids and {'cf_cindy', 'cf_helen'} <= ids, ids

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
