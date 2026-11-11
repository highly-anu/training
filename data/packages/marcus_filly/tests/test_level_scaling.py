#!/usr/bin/env python
"""Marcus Filly at every level: the samples as printed for the elite, the
commons' shares of each section's sets and the conditioning's minutes below,
loads by RPE as written (I6; training_contract.with_level).

    .venv/bin/python data/packages/marcus_filly/tests/test_level_scaling.py
"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
PKG = HERE.parents[1].name                      # the package these tests are about: its folder
sys.path.insert(0, str(HERE.parents[4]))        # the checkout (data/packages/<id>/tests/)
os.environ.setdefault('SUPABASE_URL', '')

FBB_GYM = ['barbell', 'rack', 'plates', 'dumbbell', 'pull_up_bar', 'resistance_band', 'cable_machine', 'open_space']


def _filly(level: str, track: str = 'functional_bodybuilding', weeks: int = 14):
    from src import goals, loader, training_contract as tc
    from src.generator import generate
    goal = goals.philosophy_to_goal(PKG, list(loader.load_all_frameworks().values()), track)
    c = dict(equipment=FBB_GYM, days_per_week=3, session_time_minutes=60, training_level=level)
    p = generate(None, c, num_weeks=weeks, goal_dict=goal, output_format='dict')
    assert p['weeks'], p.get('validation_errors')
    tc.verify(p, goal['training_contract'], c)       # the contract's own checks agree with the scale
    return p


def _row(p, week: int, day: int, role: str) -> dict:
    return next(e for s in p['weeks'][week]['schedule'][day] for e in s['exercises'] if e['slot_role'] == role)


def test_a_novice_does_half_of_each_section():
    p = _filly('novice')
    row = _row(p, 0, 1, 'persist_session_tripod_row')
    assert (row['load']['sets'], row['load']['reps'], row['load']['target_rpe']) == (3, '10', 7), row['load']
    assert row['load']['rx'] == {'sets': 6} and row['load']['level_scaled']['sources']['volume'] == 'commons'
    conditioning = _row(p, 0, 1, 'persist_session_conditioning')
    assert conditioning['load']['duration_minutes'] == 8 and conditioning['load']['rx'] == {'duration_minutes': 15}
    # The warm-up and cooldown as written; the Bridge week still keeps the work.
    warm = _row(p, 0, 1, 'persist_session_warm_up')
    assert warm['load']['duration_minutes'] == 10 and 'rx' not in warm['load']
    assert p['weeks'][12]['is_deload']


def test_both_tracks_scale_and_the_elite_runs_them_as_printed():
    for track in ('functional_bodybuilding', 'pump_lift'):
        assert _filly('intermediate', track, weeks=2)['weeks']
        elite = _filly('elite', track, weeks=2)
        assert not any('rx' in e['load'] for w in elite['weeks'] for ss in w['schedule'].values()
                       for s in ss for e in s['exercises']), track


if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
