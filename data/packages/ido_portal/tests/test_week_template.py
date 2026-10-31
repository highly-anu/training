#!/usr/bin/env python
"""Ido Portal's template weeks: the Floreio routines at each level.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_week_template.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_week_template.py on 2026-10-31.

    .venv/bin/python data/packages/ido_portal/tests/test_week_template.py
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


def test_ido_portal_runs_the_floreio_routines_at_each_level():
    # R1: the routines in the PDF's order, each at the athlete's level (R2);
    # R3: the preparation opens every routine; R6: no deload.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    frameworks = list(loader.load_all_frameworks().values())
    goal = goals.philosophy_to_goal(PKG, frameworks, None, 'novice')
    suffix = {'novice': ('_b', '_bi', 'w3'), 'intermediate': ('_i', '_bi', 'w3'), 'advanced': ('_a', 'w3')}
    for level, ends in suffix.items():
        c = dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=90, training_level=level)
        p = generate(None, c, num_weeks=3, goal_dict=goal, output_format='dict')
        ids = [s['archetype']['id'] for w in p['weeks'] for d in range(1, 8) for s in w['schedule'].get(d, [])]
        assert len(ids) == 18 and all(i.endswith(ends) for i in ids), (level, ids)
        assert len(set(ids[:13])) == 13, ('thirteen routines before one repeats', level, ids)
        assert all(7 not in w['schedule'] for w in p['weeks'])
        assert not any(w['is_deload'] for w in p['weeks'])
        first = p['weeks'][0]['schedule'][1][0]['exercises'][0]['exercise']['id']
        assert first in ('jump_rope', 'joint_mobility'), first
    order = [s['archetype']['id'] for d in range(1, 7)
             for s in generate(None, dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=90,
                                          training_level='novice'), num_weeks=1, goal_dict=goal,
                               output_format='dict')['weeks'][0]['schedule'][d]]
    assert order == ['ido_basic_b', 'ido_w1_b', 'ido_w2_bi', 'ido_w3', 'ido_w4_b', 'ido_w5_b'], order

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
