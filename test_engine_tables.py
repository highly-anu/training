"""The engine's tables as data: training levels, intensities, progression constants.

Each table moved out of code on 2026-10-31 (data/commons/training_levels.yaml,
intensities.yaml, progression.yaml) and must read back exactly what the code
held — the literals below are the code's, copied before it was removed — so
no program moved (test_single_lane_golden.py holds the programs). Then what is
new: a framework's `progression_defaults` overrides the ramps, and a
`rounds_for_time` slot is prescribed as a for-time piece, not the 3 x 5 default.

    SUPABASE_URL='' .venv/bin/python test_engine_tables.py
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('SUPABASE_URL', '')

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    print(f"  {'ok  ' if condition else 'FAIL'} {label}{'' if condition else ' ' + str(detail)}")
    if not condition:
        FAILURES.append(label)


def test_levels():
    print('training levels')
    from src import levels, selector
    check('the order', levels.order() == ('novice', 'intermediate', 'advanced', 'elite'), levels.order())
    check('the default', levels.default() == 'intermediate')
    check("a distance slot's share",
          {lv: levels.distance_multiplier(lv) for lv in levels.order()}
          == {'novice': 0.5, 'intermediate': 0.75, 'advanced': 1.0, 'elite': 1.25})
    check('an unknown level takes the default share', levels.distance_multiplier('nope') == 0.75)
    check('elite alone unlocks everything', [lv for lv in levels.order() if levels.unlocks_all(lv)] == ['elite'])
    check('seeds cascade upward; an unknown level is the lowest',
          levels.up_to('advanced') == ('novice', 'intermediate', 'advanced') and levels.up_to('x') == ('novice',))
    check('an unknown level sorts last', sorted(['elite', '?', 'novice'], key=levels.rank) == ['novice', 'elite', '?'])
    check('elite opens every exercise', selector._get_unlocked('elite', {'a': {'requires': ['z']}}) == {'a'})


def test_intensities():
    print('intensities')
    from src import fidelity, intensities, progression, recovery_regions, selector
    from src.analytics import hr_plan
    zones = {
        'zone1': (1, 1, 'Zone 1 (recovery)'), 'zone2': (1, 2, 'Zone 1-2 (conversational pace)'),
        'zone3': (3, 3, 'Zone 3 (tempo)'), 'zone4': (4, 4, 'Zone 4 (threshold)'),
        'zone4_5': (4, 5, 'Zone 4-5 (VO2max)'), 'zone5': (5, 5, 'Zone 5 (maximal)'),
        'light': (1, 2, 'Zone 1-2 (light)'), 'low': (1, 2, 'Zone 1-2 (easy)'),
        'moderate': (2, 3, 'Zone 2-3 (moderate)'), 'work_pace': (2, 3, 'Zone 2-3 (work pace)'),
        'high': (3, 4, 'Zone 3-4 (hard)'), 'hard': (3, 4, 'Zone 3-4 (hard)'),
        'max': (4, 5, 'Zone 4-5 (max effort)'), 'progressing': (2, 4, 'Zone 2-4 (progressive)')}
    check("progression's zone bands", progression._INTENSITY_ZONES == zones,
          set(progression._INTENSITY_ZONES.items()) ^ set(zones.items()))
    check("the selector's main-lift words", selector.MAIN_LIFT_INTENSITIES == {'heavy', 'max', 'max_effort'})
    check("fidelity's buckets", fidelity._INTENSITY_BUCKET == {
        'zone1': 'zone1_2_pct', 'zone2': 'zone1_2_pct', 'low': 'zone1_2_pct', 'light': 'zone1_2_pct',
        'bodyweight': 'zone1_2_pct', 'zone3': 'zone3_pct', 'moderate': 'zone3_pct', 'medium': 'zone3_pct',
        'submaximal': 'zone3_pct', 'progressing': 'zone3_pct', 'zone4': 'zone4_5_pct', 'zone4_5': 'zone4_5_pct',
        'zone5': 'zone4_5_pct', 'high': 'zone4_5_pct', 'heavy': 'max_effort_pct', 'max': 'max_effort_pct',
        'max_effort': 'max_effort_pct'})
    check("the heart-rate plan's load words", hr_plan._LOAD_WORDS == {'progressing'})
    check("the recovery weights", intensities.recovery_weights() == {
        'max_effort': 1.25, 'max': 1.25, 'heavy': 1.25, 'high': 1.25, 'zone4_5': 1.25, 'zone4': 1.25,
        'light': 0.5, 'low': 0.5, 'zone1': 0.5, 'zone2': 0.5})
    check('an unlisted intensity weighs 1', recovery_regions._intensity({'intensity': 'moderate'}) == 1)
    check('the authored tokens are the schema\'s seventeen, hard and work_pace not among them',
          len(intensities.authoring()) == 17 and not {'hard', 'work_pace'} & set(intensities.authoring()))


def test_progression_constants():
    print('progression constants')
    from src import progression
    check('the RPE load factors', progression._constants()['rpe'] == {10: 1.09, 9: 1.05, 8: 1.00, 7: 0.95, 6: 0.90})
    check('the ramps', progression.ramps_for(None) == {'time': 0.10, 'distance': 0.08})
    fw = {'progression_defaults': {'ramps': {'time': 0.2}}}
    check("a framework's progression_defaults overrides one ramp",
          progression.ramps_for(fw) == {'time': 0.2, 'distance': 0.08})
    slot = {'slot_type': 'time_domain', 'duration_minutes': 30}
    base = progression.calculate_load({}, slot, 'time_to_task', 2, 'build', 'intermediate', False)
    faster = progression.calculate_load({}, slot, 'time_to_task', 2, 'build', 'intermediate', False,
                                        ramps=progression.ramps_for(fw))
    check('and the week builds by it, under the phase kind\'s ceiling',
          (base['duration_minutes'], faster['duration_minutes']) == (33, 36),
          (base, faster))
    rft = progression.calculate_load({}, {'slot_type': 'rounds_for_time', 'time_cap_sec': 900}, 'density', 1,
                                     'base', 'intermediate', False)
    check('rounds for time is a for-time piece, not 3 x 5', rft.get('sets') != 3 and rft.get('reps') != 5, rft)


def main() -> int:
    for t in (test_levels, test_intensities, test_progression_constants):
        t()
    print()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
