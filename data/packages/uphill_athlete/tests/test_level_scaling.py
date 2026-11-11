#!/usr/bin/env python
"""Uphill at every level: the volume is the source's own by level (R6, I3),
a novice running the full program from the untrained hours (I12) — nothing
is scaled (docs/logic/levels.md).

    .venv/bin/python data/packages/uphill_athlete/tests/test_level_scaling.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')

UPHILL_GYM = ['barbell', 'rack', 'plates', 'pull_up_bar', 'kettlebell', 'box', 'open_space']


def _uphill(level: str, weeks: int = 29):
    from src import goals, loader, training_contract as tc
    from src.generator import generate
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()))
    c = dict(equipment=UPHILL_GYM, days_per_week=6, session_time_minutes=360, training_level=level)
    p = generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict')
    tc.verify(p, goal['training_contract'], c)
    return p


def _aerobic_minutes(week):
    return sum(e['load']['duration_minutes'] for ss in week['schedule'].values() for s in ss for e in s['exercises']
               if e['slot_role'] in ('long_day_long', 'aerobic_aerobic', 'zone_3_zone_3'))


def test_a_novice_starts_at_the_untrained_hours():
    # R6: about 5 hours over six days untrained, strength included; less about
    # 1.5 hours of strength, 210 aerobic minutes (I3). The program is the
    # same: General Strength first, max strength from Base (I12).
    novice = _uphill('novice')
    assert not novice.get('validation_errors') and len(novice['weeks']) == 29
    assert _aerobic_minutes(novice['weeks'][0]) == 210
    archetypes = [s['archetype']['id'] for w in novice['weeks'] for ss in w['schedule'].values() for s in ss]
    assert 'general_strength_circuit' in archetypes and 'me_max_strength_gym' in archetypes


def test_every_level_ramps_from_its_own_first_week():
    first = {lv: _aerobic_minutes(_uphill(lv, weeks=1)['weeks'][0])
             for lv in ('novice', 'intermediate', 'advanced', 'elite')}
    assert first == {'novice': 210, 'intermediate': 330, 'advanced': 420, 'elite': 510}, first


def test_nothing_is_scaled():
    # The source writes each level's volume: no prescription carries an Rx.
    p = _uphill('novice', weeks=12)
    assert not any('rx' in (e.get('load') or {}) for w in p['weeks'] for ss in w['schedule'].values()
                   for s in ss for e in s['exercises'])


if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
