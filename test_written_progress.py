"""A slot's own numbers and how they move (progression.written_progress): the
weight and steps a hand-composed session writes, read under as_written.

    .venv/bin/python test_written_progress.py
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src.progression import _as_written, calculate_load, written_progress, written_steps  # noqa: E402


def load(slot, week=1, deload=False):
    return calculate_load({}, slot, 'as_written', week, 'build', 'intermediate', deload)


SQUAT = {'role': 'squat', 'slot_type': 'sets_reps', 'sets': 3, 'reps': 5}


def test_a_slot_without_the_keys_is_what_it_was():
    for slot in (SQUAT, {**SQUAT, 'load': '75% of 1RM'},
                 {'slot_type': 'time_domain', 'duration_minutes': 30, 'intensity': 'zone2'},
                 {'slot_type': 'static_hold', 'sets': 3, 'hold_seconds': 20}):
        first = _as_written(slot)
        assert 'weight_kg' not in first
        for week, deload in ((1, False), (5, False), (4, True)):
            assert _as_written(slot, week, deload) == first, (slot, week)
        assert written_progress(slot, 6) == (slot, None)


def test_a_start_weight_alone_is_fixed():
    slot = {**SQUAT, 'start_kg': 80}
    assert load(slot, 1) == {'sets': 3, 'reps': 5, 'weight_kg': 80}
    assert load(slot, 9) == load(slot, 1)
    assert load({**SQUAT, 'start_kg': 22.5, 'load': 'a pair'}) == \
        {'sets': 3, 'reps': 5, 'weight_kg': 22.5, 'load_note': 'a pair'}


def test_weight_steps_each_week():
    slot = {**SQUAT, 'start_kg': 80, 'progress': {'add_kg': 2.5}}
    assert [load(slot, w)['weight_kg'] for w in (1, 2, 3, 4)] == [80, 82.5, 85, 87.5]
    assert all(load(slot, w)['reps'] == 5 for w in (1, 4))
    every_two = {**SQUAT, 'start_kg': 80, 'progress': {'add_kg': 5, 'every_weeks': 2}}
    assert [load(every_two, w)['weight_kg'] for w in (1, 2, 3, 4, 5)] == [80, 80, 85, 85, 90]


def test_a_deload_week_repeats_the_week_before():
    slot = {**SQUAT, 'start_kg': 80, 'progress': {'add_kg': 2.5}}
    assert load(slot, 4, deload=True)['weight_kg'] == load(slot, 3)['weight_kg'] == 85
    assert load(slot, 5)['weight_kg'] == 90
    assert written_steps(slot, 1, True) == 0


def test_reps_climb_and_double_progression():
    plain = {**SQUAT, 'reps': 8, 'progress': {'add_reps': 1}}
    assert [load(plain, w)['reps'] for w in (1, 2, 3)] == [8, 9, 10]
    assert 'weight_kg' not in load(plain, 3)
    double = {**SQUAT, 'reps': 8, 'start_kg': 20, 'progress': {'add_reps': 2, 'top_reps': 12, 'add_kg': 2.5}}
    got = [(load(double, w)['reps'], load(double, w)['weight_kg']) for w in range(1, 8)]
    assert got == [(8, 20), (10, 20), (12, 20), (8, 22.5), (10, 22.5), (12, 22.5), (8, 25)], got
    # An odd step never passes the top.
    odd = {**SQUAT, 'reps': 8, 'start_kg': 20, 'progress': {'add_reps': 3, 'top_reps': 12, 'add_kg': 5}}
    assert [load(odd, w)['reps'] for w in (1, 2, 3, 4)] == [8, 11, 12, 8]
    # Reps written in words are the author's; only the weight can step.
    words = {**SQUAT, 'reps': 'max', 'start_kg': 10, 'progress': {'add_reps': 1, 'add_kg': 5}}
    assert load(words, 3) == {'sets': 3, 'reps': 'max', 'weight_kg': 20}


def test_time_distance_and_rounds():
    hold = {'slot_type': 'static_hold', 'sets': 3, 'hold_seconds': 20, 'progress': {'add_sec': 5}}
    assert [load(hold, w)['hold_seconds'] for w in (1, 2, 3)] == [20, 25, 30]
    row = {'slot_type': 'time_domain', 'duration_minutes': 30, 'intensity': 'zone2', 'progress': {'add_sec': 300}}
    third = load(row, 3)
    assert third['duration_minutes'] == 40 and third['zone_target']
    run = {'slot_type': 'distance', 'distance_m': 400, 'sets': 4, 'progress': {'add_m': 100}}
    assert load(run, 3)['distance_m'] == 600 and load(run, 3)['sets'] == 4
    piece = {'slot_type': 'for_time', 'rounds': 3, 'reps_per_round': 10, 'progress': {'add_rounds': 1}}
    assert [load(piece, w)['target_rounds'] for w in (1, 2, 3)] == [3, 4, 5]
    emom = {'slot_type': 'emom', 'sets': 10, 'work_sec': 20, 'rest_sec': 40, 'progress': {'add_rounds': 2}}
    assert load(emom, 2)['target_rounds'] == 12 and load(emom, 2)['time_minutes'] == 12
    sets = {**SQUAT, 'progress': {'add_rounds': 1}}
    assert load(sets, 3)['sets'] == 5


def test_the_schema_takes_the_keys():
    import jsonschema
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, 'docs', 'schemas', 'archetype.schema.json'), encoding='utf-8') as fh:
        schema = json.load(fh)
    arch = {'id': 'x_day', 'name': 'X', 'modality': 'max_strength', 'category': 'strength',
            'duration_estimate_minutes': 30,
            'slots': [{**SQUAT, 'start_kg': 80, 'progress': {'add_kg': 2.5, 'every_weeks': 1}}]}
    jsonschema.validate(arch, schema)
    for bad in ({'progress': {}}, {'progress': {'add_lbs': 5}}, {'start_kg': -1}, {'progress': {'add_kg': 0}}):
        broken = {**arch, 'slots': [{**SQUAT, **bad}]}
        try:
            jsonschema.validate(broken, schema)
        except jsonschema.ValidationError:
            continue
        raise AssertionError(f'accepted {bad}')


def test_blocks_word_the_start_weight():
    from src import session_blocks
    arch = {'id': 'x_day', 'name': 'X', 'modality': 'max_strength', 'slots': [
        {**SQUAT, 'start_kg': 80, 'exercise_filter': {'exercise_ids': ['back_squat']}}]}
    blocks = session_blocks.for_archetype(arch)
    assert blocks and blocks[0]['load'] == '80 kg', blocks


if __name__ == '__main__':
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            try:
                fn()
                print(f'ok    {name}')
            except Exception as exc:  # noqa: BLE001
                failed += 1
                print(f'FAIL  {name}: {exc!r}')
    sys.exit(1 if failed else 0)
