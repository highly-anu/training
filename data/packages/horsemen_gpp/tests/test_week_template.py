#!/usr/bin/env python
"""Horsemen GPP's 4-Month Macro, generated as written from its week templates.

A package's own tests live in its folder (data/packages/<id>/tests/): the
checks find them there (tools/run_checks.py), and a fidelity rule cites one as
`test:tests/test_week_template.py::<test>`. The package is this folder's — `PKG` — so the
tests follow a renamed package. Moved from test_week_template.py on 2026-10-31.

    .venv/bin/python data/packages/horsemen_gpp/tests/test_week_template.py
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


_EQUIPMENT = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'rings', 'box',
              'sandbag', 'medicine_ball', 'rower', 'ghd', 'rope', 'sled', 'tire', 'jump_rope', 'open_space']


def _horsemen(**overrides):
    from src import goals, loader
    from src.generator import generate
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), 'four_month_macro')
    c = dict(equipment=list(_EQUIPMENT),
             days_per_week=6, session_time_minutes=120, training_level='intermediate')
    c.update(overrides)
    return generate(None, c, num_weeks=16, goal_dict=goal, output_format='dict'), goal


def test_horsemen_runs_the_source_weeks_as_written():
    p, goal = _horsemen()
    assert len(p['weeks']) == 16, p.get('validation_errors')
    first = p['weeks'][0]
    cats = [first['schedule'][d][0].get('category') for d in sorted(first['schedule'])]
    assert cats == ['strength', 'job_specific_long', 'power_endurance', 'smmf', 'strength', 'recovery'], cats
    named = {s['archetype']['id'] for w in p['weeks'] for ss in w['schedule'].values() for s in ss}
    assert len(named) >= 40, f'the rotation reaches {len(named)} workouts in 16 weeks'
    for w in p['weeks']:
        for ss in w['schedule'].values():
            for s in ss:
                for ea in s['exercises']:
                    load = ea.get('load') or {}
                    assert 'weight_kg' not in load, 'no load is computed: the source writes it'
    tests = [(w['week_number'], s['test']['archetype']) for w in p['weeks'] for ss in w['schedule'].values()
             for s in ss if s.get('test')]
    assert tests == [(2, 'horsemen_pt_test'), (16, 'horsemen_pt_test')], tests


def test_horsemen_without_the_equipment_passes_workouts_over():
    p, _ = _horsemen(equipment=['kettlebell', 'pull_up_bar', 'open_space'], days_per_week=4,
                     session_time_minutes=60)
    assert len(p['weeks']) == 16, p.get('validation_errors')
    from src import loader
    arch = {a['id']: a for a in loader.load_all_archetypes()}
    for w in p['weeks']:
        assert len(w['schedule']) <= 4
        for ss in w['schedule'].values():
            for s in ss:
                for piece in s.get('pieces') or []:
                    need = set(arch[piece['archetype_id']].get('required_equipment') or []) - {'open_space'}
                    assert need <= {'kettlebell', 'pull_up_bar'}, (piece, need)
    assert any('leaves out' in c for c in p['compromises']), p['compromises'][:5]


def test_a_regenerate_from_mid_track_carries_on_the_rotation():
    # "From tomorrow": the tail starts at a later week and must plan exactly
    # what the whole track planned there, warm-ups included.
    def picks(week):
        return [(d, [p['archetype_id'] for p in s.get('pieces') or []], (s.get('warm_up') or {}).get('archetype_id'))
                for d, ss in sorted(week['schedule'].items()) for s in ss]
    whole, _ = _horsemen()
    for phase, week, index in (('strength', 3, 2), ('power_endurance', 2, 5), ('job_specific', 1, 8), ('maintenance', 4, 15)):
        tail, _ = _horsemen(start_phase=phase, periodization_week=week)
        assert picks(tail['weeks'][0]) == picks(whole['weeks'][index]), (phase, week)

if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
