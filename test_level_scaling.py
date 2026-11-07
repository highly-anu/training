#!/usr/bin/env python
"""A prescription written for one level, done at another (src/level_scaling.py,
docs/logic/levels.md): the shares, the authored level's cap, the rounding, a
fixed load by sex, a relative load untouched; a movement out of reach replaced
by its scale; `min_level`; the suitability table. No generation, no package —
a package's own programs are tested in its folder (CrossFit's
tests/test_level_scaling.py).

    .venv/bin/python test_level_scaling.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('SUPABASE_URL', '')

from src import level_scaling as ls, levels, phases, selector  # noqa: E402

ELITE = {'authored_level': 'elite', 'level_scaling': {}}


def test_shares_come_from_the_commons_relative_to_the_authored_level():
    shares, sources = ls.factors('intermediate', ELITE)
    assert shares == levels.scaling('intermediate') and set(sources.values()) == {'commons'}
    # Written for the advanced: an intermediate does 0.7 / 0.85 of it.
    shares, _ = ls.factors('intermediate', {'authored_level': 'advanced'})
    assert abs(shares['volume'] - 0.7 / 0.85) < 1e-9


def test_at_or_above_the_authored_level_nothing_scales():
    assert ls.factors('elite', ELITE) is None
    assert ls.factors('elite', {'authored_level': 'intermediate'}) is None   # never more than written
    assert ls.factors('novice', None) is None
    assert ls.factors('unknown', ELITE) is None


def test_a_track_share_wins_per_dimension():
    policy = {'authored_level': 'elite', 'level_scaling': {'novice': {'load': 0.4}}}
    shares, sources = ls.factors('novice', policy)
    assert shares['load'] == 0.4 and sources['load'] == 'track'
    assert shares['volume'] == levels.scaling('novice')['volume'] and sources['volume'] == 'commons'


def test_no_policy_leaves_the_load_alone():
    load = {'sets': 5, 'reps': 5, 'load_note': '75% of 1RM'}
    assert ls.scale_prescription(load, {}, 'novice', None) is load


def test_counts_round_half_up_and_never_under_one():
    out = ls.scale_prescription({'sets': 3, 'reps': 1, 'rep_scheme': [21, 15, 9], 'reps_per_round': 5},
                                {}, 'novice', ELITE)
    assert out['sets'] == 2 and out['reps'] == 1 and out['rep_scheme'] == [11, 8, 5] and out['reps_per_round'] == 3
    assert out['rx'] == {'sets': 3, 'rep_scheme': [21, 15, 9], 'reps_per_round': 5}
    assert ls.scale_prescription({'sets': 1}, {}, 'novice', ELITE) == {'sets': 1}    # one set stays one


def test_time_and_distance_scale_to_whole_units():
    out = ls.scale_prescription({'time_minutes': 20, 'hold_seconds': 45, 'work_sec': 30, 'distance_m': 400,
                                 'distance_km': 5.0}, {}, 'intermediate', ELITE)
    assert out['time_minutes'] == 14 and out['hold_seconds'] == 30 and out['work_sec'] == 20
    assert out['distance_m'] == 280 and out['distance_km'] == 3.5


def test_a_relative_load_is_the_athletes_own():
    # A % of 1RM or of bodyweight carries no load_kg: the text passes through.
    out = ls.scale_prescription({'sets': 5, 'reps': 3, 'load_note': '85% of 1RM'},
                                {'load': '85% of 1RM'}, 'novice', ELITE)
    assert out['load_note'] == '85% of 1RM' and 'weight_kg' not in out


def test_a_fixed_load_by_sex_and_bell():
    slot = {'load': '95 lb (43 kg); women 65 lb (30 kg)', 'load_kg': {'male': 43, 'female': 30}}
    assert ls.scale_prescription({}, slot, 'novice', ELITE)['weight_kg'] == 22.5          # men's when unknown
    out = ls.scale_prescription({}, slot, 'novice', ELITE, 'female')
    assert out['weight_kg'] == 15.0 and out['load_note'].startswith('15 kg · Rx 95 lb')
    assert ls.scale_prescription({}, {'load_kg': 24}, 'intermediate', ELITE, kg_step=4)['weight_kg'] == 16.0
    # At the authored level the written weight is the weight, nothing marked scaled.
    out = ls.scale_prescription({}, slot, 'elite', ELITE, 'female')
    assert out == {'weight_kg': 30.0}


def test_the_policy_is_opt_in_per_track():
    assert ls.policy_for({'id': 't'}) is None
    assert ls.policy_for({'authored_level': 'elite', 'level_scaling': {'novice': {'load': 0.5}}}) == \
        {'authored_level': 'elite', 'level_scaling': {'novice': {'load': 0.5}}}


def test_level_scaling_is_validated_against_the_authored_level():
    phil = {'id': 'p', 'tracks': [{'id': 't', 'authored_level': 'intermediate',
                                   'level_scaling': {'novice': {'load': 0.5}, 'advanced': {'load': 0.9}},
                                   'phases': [{'id': 'a', 'kind': 'base', 'framework_id': 'f'}]},
                                  {'id': 'u', 'level_scaling': {'novice': {'load': 0.5}},
                                   'phases': [{'id': 'a', 'kind': 'base', 'framework_id': 'f'}]}]}
    errors = phases.validate_philosophy_tracks(phil)
    assert any('advanced, at or above the authored intermediate' in e for e in errors), errors
    assert any('p/u: level_scaling without authored_level' in e for e in errors), errors
    assert not any('novice' in e for e in errors), errors


def test_a_scaled_slot_takes_the_nearest_scale_first():
    exercises = {'muscle_up': {'scaling_down': ['pull_up', 'dip']}, 'pull_up': {'scaling_down': ['ring_row']},
                 'dip': {'scaling_down': ['push_up']}, 'ring_row': {}, 'push_up': {}}
    slot = {'exercise_filter': {'exercise_ids': ['muscle_up'], 'category': 'bodyweight'}}
    scaled, written_of = selector._scaled_slot(slot, exercises)
    assert scaled['exercise_filter'] == {'exercise_ids': ['pull_up', 'dip', 'ring_row', 'push_up'], 'ordered': True}
    assert set(written_of.values()) == {'muscle_up'}
    assert selector._scaled_slot({'exercise_filter': {'movement_pattern': 'squat'}}, exercises) == (None, {})


def test_min_level_locks_an_exercise_below_it():
    exercises = {'snatch': {'id': 'snatch', 'min_level': 'advanced'}, 'clean': {'id': 'clean'}}
    assert selector._get_unlocked('intermediate', exercises) == {'clean'}
    assert selector._get_unlocked('advanced', exercises) == {'clean', 'snatch'}


def test_the_suitability_table_reads_requires_and_min_level():
    from src import level_suitability
    by_package = {'pkg': {'a': {'id': 'a'}, 'b': {'id': 'b', 'requires': ['muscle_up']},
                          'c': {'id': 'c', 'min_level': 'intermediate', 'scaling_down': ['a']}}}
    got = level_suitability.min_levels('pkg', by_package, {})
    assert got['a'] == 'novice' and got['c'] == 'intermediate'
    assert got['b'] == 'advanced'      # the muscle-up is an advanced athlete's (level_concepts.yaml)


if __name__ == '__main__':
    import unittest
    suite = unittest.TestSuite(unittest.FunctionTestCase(f) for name, f in list(globals().items())
                               if name.startswith('test_') and callable(f))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
