#!/usr/bin/env python
"""ATG's template weeks: its programs as written.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_week_template.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_week_template.py on 2026-10-31.

    .venv/bin/python data/packages/atg/tests/test_week_template.py
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


def test_atg_runs_its_programs_as_written():
    # R1-R3: each program's workouts on their days, every week the same; R1:
    # Zero needs no equipment; R4, R5: the sled leads, the upper body comes
    # last, and walking backward stands in for the sled; R7: no deload.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    frameworks = list(loader.load_all_frameworks().values())

    def block(level, track, days, equipment=ALL_EQUIPMENT, minutes=60):
        goal = goals.philosophy_to_goal(PKG, frameworks, track, level)
        c = dict(equipment=list(equipment), days_per_week=days, session_time_minutes=minutes, training_level=level)
        return generate(None, c, num_weeks=4, goal_dict=goal, output_format='dict'), goal

    def week_ids(w):
        return {d: [s['archetype']['id'] for s in w['schedule'].get(d, [])] for d in range(1, 8) if w['schedule'].get(d)}

    for level, track, days, equipment, want in (
            ('novice', None, 3, (), {1: ['atg_zero'], 3: ['atg_zero'], 5: ['atg_zero']}),
            ('intermediate', None, 2, ALL_EQUIPMENT, {1: ['atg_p2_w1'], 4: ['atg_p2_w2']}),
            ('advanced', None, 4, ALL_EQUIPMENT,
             {1: ['atg_pro_mon'], 2: ['atg_pro_tue'], 4: ['atg_pro_thu'], 5: ['atg_pro_fri']})):
        p, goal = block(level, track, days, equipment)
        assert len(p['weeks']) == 4, (goal['track']['id'], p.get('validation'))
        assert all(week_ids(w) == want for w in p['weeks']), [week_ids(w) for w in p['weeks']]
        assert not any(w['is_deload'] for w in p['weeks'])
    p, _ = block('intermediate', 'program', 2)
    roles = [ea['slot']['role'] for ea in p['weeks'][0]['schedule'][1][0]['exercises']]
    assert roles[0] == 'sled' and roles[-1] == 'shoulder_press', roles
    sled = p['weeks'][0]['schedule'][1][0]['exercises'][0]
    assert sled['exercise']['id'] == 'sled_forward_backward', sled['exercise']['id']
    p, _ = block('intermediate', 'program', 2, [e for e in ALL_EQUIPMENT if e != 'sled'])
    assert p['weeks'][0]['schedule'][1][0]['exercises'][0]['exercise']['id'] == 'backward_walk'
    p, _ = block('novice', 'knee_ability_pro', 4)
    assert not p['weeks'], 'Knee Ability Pro is written for trained athletes'

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
