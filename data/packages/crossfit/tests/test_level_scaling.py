#!/usr/bin/env python
"""CrossFit at every level: Rx for the elite, the Level 1 guide's half for a
newcomer, the commons' shares between (R15, I7, I8; src/level_scaling.py).

    .venv/bin/python data/packages/crossfit/tests/test_level_scaling.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')


def _program(level: str, sex: str | None = None, weeks: int = 12, equipment_extra=('rings',)) -> dict:
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), 'constantly_varied')
    c = dict(equipment=list(ALL_EQUIPMENT) + list(equipment_extra), days_per_week=6,
             session_time_minutes=60, training_level=level)
    if sex:
        c['sex'] = sex
    return generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict')


def _workout(program: dict, archetype_id: str) -> dict:
    return next(s for w in program['weeks'] for ss in w['schedule'].values() for s in ss
                if s['archetype']['id'] == archetype_id)


def test_a_novice_fran_is_half_the_rx():
    # R15: load first, then volume, by half; the pull-up out of reach is a
    # jumping pull-up (I8), and a scaled Fran is not a Fran result.
    fran = _workout(_program('novice', 'female'), 'cf_fran')
    thruster = next(e for e in fran['exercises'] if e['exercise']['id'] == 'thruster')
    assert thruster['load']['rep_scheme'] == [11, 8, 5], thruster['load']
    assert thruster['load']['weight_kg'] == 15.0, thruster['load']           # the women's 30 kg, halved
    assert thruster['load']['rx'] == {'rep_scheme': [21, 15, 9], 'weight_kg': 30.0}
    assert thruster['load']['level_scaled']['sources']['load'] == 'track'
    assert 'standard' not in thruster and thruster['scaled_standard'] == 'wod_fran_minutes'
    pull = next(e for e in fran['exercises'] if e.get('scaled_from') == 'pull_up')
    assert pull['exercise']['id'] == 'jumping_pull_up' and pull['scale_cause'] == 'level'
    assert pull['load']['rep_scheme'] == [11, 8, 5]


def test_the_elite_does_every_workout_as_written():
    p = _program('elite')
    fran = _workout(p, 'cf_fran')
    thruster = next(e for e in fran['exercises'] if e['exercise']['id'] == 'thruster')
    assert thruster['load']['rep_scheme'] == [21, 15, 9] and thruster['standard']['id'] == 'wod_fran_minutes'
    for w in p['weeks']:
        for ss in w['schedule'].values():
            for s in ss:
                for e in s['exercises']:
                    assert 'rx' not in (e.get('load') or {}) and not e.get('scaled_from'), (s['archetype']['id'], e)


def test_an_intermediate_does_the_commons_share():
    # I7: 70 % of volume and fixed load, a bell rounded to a bell's size.
    p = _program('intermediate')
    fran = _workout(p, 'cf_fran')
    thruster = next(e for e in fran['exercises'] if e['exercise']['id'] == 'thruster')
    assert thruster['load']['rep_scheme'] == [15, 11, 6] and thruster['load']['weight_kg'] == 30.0
    assert thruster['load']['level_scaled']['sources']['volume'] == 'commons'
    helen = _workout(p, 'cf_helen')
    swing = next(e for e in helen['exercises'] if e['exercise']['id'] == 'kb_swing_two_hand')
    assert swing['load']['weight_kg'] == 16.0, swing['load']


def test_a_novice_reaches_every_day_of_the_cycle():
    # Novices were refused until 2026-11 (the old I5); every training day now
    # takes a workout, the hardest movements scaled or passed over.
    p = _program('novice')
    days = [s for w in p['weeks'] for ss in w['schedule'].values() for s in ss]
    elite = [s for w in _program('elite')['weeks'] for ss in w['schedule'].values() for s in ss]
    assert len(days) == len(elite) == 63, (len(days), len(elite))    # 84 days, three on, one off
    ids = {e['exercise']['id'] for s in days for e in s['exercises'] if e.get('exercise')}
    assert not ids & {'muscle_up_ring', 'handstand_push_up', 'snatch', 'clean_and_jerk'}, ids


if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
