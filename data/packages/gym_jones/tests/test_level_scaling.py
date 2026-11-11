#!/usr/bin/env python
"""Gym Jones at every level: Operator Fitness as written for the operator,
the commons' shares below (I7); Soldier of Steel, the newly training's own
plan, never scaled (src/level_scaling.py).

    .venv/bin/python data/packages/gym_jones/tests/test_level_scaling.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')


def _program(track: str, level: str) -> dict:
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), track)
    c = dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=120, training_level=level)
    return generate(None, c, num_weeks=4, goal_dict=goal, output_format='dict')


def _day(program: dict, archetype_id: str) -> dict:
    return next(s for w in program['weeks'] for ss in w['schedule'].values() for s in ss
                if s['archetype']['id'] == archetype_id)


def _by_exercise(session: dict, exercise_id: str) -> dict:
    return next(e for e in session['exercises'] if (e.get('exercise') or {}).get('id') == exercise_id)


def test_operator_fitness_is_written_for_the_operator():
    day1 = _day(_program('operator_fitness', 'elite'), 'gj_of_d01')
    deadlift = _by_exercise(day1, 'deadlift')
    assert deadlift['load']['sets'] == 5 and 'rx' not in deadlift['load'], deadlift['load']


def test_an_intermediate_does_the_commons_share_of_each_day():
    p = _program('operator_fitness', 'intermediate')
    # Several sets: the sets go, each set stays the written one; the % of 1RM stays.
    deadlift = _by_exercise(_day(p, 'gj_of_d01'), 'deadlift')
    assert deadlift['load']['sets'] == 4 and deadlift['load']['reps'] == 3, deadlift['load']
    assert deadlift['load']['rx'] == {'sets': 5}
    assert '80 % of 1RM' in deadlift['load']['load_note'], deadlift['load']
    # A fixed weight scaled to a bell's size, the hike's minutes to 70 %.
    swing = _by_exercise(_day(p, 'gj_of_d03'), 'kb_swing_two_hand')
    assert swing['load']['weight_kg'] == 16.0 and swing['load']['rx']['weight_kg'] == 24.0, swing['load']
    hike = _by_exercise(_day(p, 'gj_of_d06'), 'ruck')
    assert hike['load']['duration_minutes'] == 74 and hike['load']['rx'] == {'duration_minutes': 105}
    assert hike['load']['level_scaled']['sources']['time'] == 'commons'


def test_soldier_of_steel_is_never_scaled():
    # The newly training's own plan: its beginner versions are the source's words.
    for level in ('novice', 'intermediate'):
        p = _program('soldier_of_steel', level)
        for w in p['weeks']:
            for ss in w['schedule'].values():
                for s in ss:
                    for e in s['exercises']:
                        assert 'rx' not in (e.get('load') or {}), (level, s['archetype']['id'], e.get('load'))


if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
