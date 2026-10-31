#!/usr/bin/env python
"""CrossFit's template weeks: Glassman's cycle and the Girls as written.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_week_template.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_week_template.py on 2026-10-31.

    .venv/bin/python data/packages/crossfit/tests/test_week_template.py
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


def test_crossfit_runs_glassmans_cycle_and_the_girls_as_written():
    # R1, R3, R5-R8: three on, one off, the days cycling through one, two and
    # three elements, Table 4's workouts first; R10, R11: the Girls in the
    # pools as written, each a selectable test of its standard.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), 'constantly_varied')
    c = dict(equipment=list(ALL_EQUIPMENT) + ['rings'], days_per_week=6, session_time_minutes=60,
             training_level='intermediate')
    p = generate(None, c, num_weeks=12, goal_dict=goal, output_format='dict')
    days = [(w['week_number'], d, s) for w in p['weeks'] for d, ss in sorted(w['schedule'].items()) for s in ss]
    cycle = ['m', 'gw', 'triplet', None, 'g', 'wm', 'triplet', None, 'w', 'mg', 'triplet', None]
    for wk, d, s in days:
        assert s.get('category') == cycle[(7 * (wk - 1) + d - 1) % 12], (wk, d, s.get('category'))
    rest = {(w['week_number'], d) for w in p['weeks'] for d in range(1, 8) if d not in w['schedule']}
    assert all(cycle[(7 * (wk - 1) + d - 1) % 12] is None for wk, d in rest), 'rest falls on every fourth day'
    names = [s['archetype']['id'] for _, _, s in days]
    assert names[:6] == ['cf_run_10k', 'cf_hspu_deadlift_couplet', 'cf_run_pull_thruster_triplet',
                         'cf_handstand_practice', 'cf_bench_row_couplet', 'cf_lunge_press_row_triplet'], names[:6]
    assert {'cf_fran', 'cf_cindy', 'cf_helen'} <= set(names) and len(set(names)) >= 35, len(set(names))
    fran = next(s for _, _, s in days if s['archetype']['id'] == 'cf_fran')
    head = next(e for e in fran['exercises'] if e.get('standard'))
    assert head['exercise']['id'] == 'thruster' and head['standard']['id'] == 'wod_fran_minutes'
    assert '95 lb' in head['load']['load_note'] and head['load']['target_rounds'] == 3
    # 21-15-9 as written, on both movements: never a single count a round.
    pull = next(e for e in fran['exercises'] if e['exercise']['id'] == 'pull_up')
    for e in (head, pull):
        assert e['load'].get('rep_scheme') == [21, 15, 9] and 'reps_per_round' not in e['load'], e['load']
    cindy = next(s for _, _, s in days if s['archetype']['id'] == 'cf_cindy')
    assert cindy['exercises'][0]['load'].get('reps_per_round') == 5, cindy['exercises'][0]['load']
    deadlift = next(s for _, _, s in days if s['archetype']['id'] == 'cf_deadlift_5_3_3_2')
    assert deadlift['exercises'][0]['load']['reps'] == '5-3-3-2-2-2-1-1-1'
    assert not any(w['is_deload'] for w in p['weeks']), 'no deload: the rest day is the rest (R14)'

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
