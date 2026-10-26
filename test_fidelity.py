#!/usr/bin/env python
"""Unit tests for src/fidelity.py: each rule on hand-built weeks, no generation.

Run: .venv/bin/python test_fidelity.py
"""
from __future__ import annotations

import sys

from src import fidelity

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


MODALITIES = {
    'max_strength': {'recovery_cost': 'high', 'recovery_hours_min': 48, 'progression_model': 'linear_load'},
    'aerobic_base': {'recovery_cost': 'low', 'recovery_hours_min': 12, 'progression_model': 'time_to_task'},
    'anaerobic_intervals': {'recovery_cost': 'high', 'recovery_hours_min': 48},
    'mobility': {'recovery_cost': 'low', 'recovery_hours_min': 0},
}
EXERCISES = {
    'back_squat': {'id': 'back_squat', 'equipment': ['barbell', 'rack'], 'movement_patterns': ['squat']},
    'front_squat': {'id': 'front_squat', 'equipment': ['barbell', 'rack'], 'movement_patterns': ['squat']},
    'goblet_squat': {'id': 'goblet_squat', 'equipment': ['kettlebell'], 'movement_patterns': ['squat']},
    'easy_run': {'id': 'easy_run', 'equipment': [], 'movement_patterns': ['locomotion']},
    'box_squat': {'id': 'box_squat', 'equipment': ['barbell'], 'movement_patterns': ['squat'],
                  'category': 'barbell'},
}
LIB = {'modalities': MODALITIES, 'exercises': EXERCISES, 'injury_flags': {
    'knee': {'excluded_movement_patterns': ['squat'], 'excluded_exercises': [],
             'modified_exercises': [{'instead_of': 'back_squat', 'use': 'box_squat'}]},
}}


def arch(aid, modality, **kw):
    return {'id': aid, 'name': aid, 'modality': modality, 'duration_estimate_minutes': 60, **kw}


def lift(ex_id, idx=0, role='main', **slot):
    return {'exercise': EXERCISES[ex_id], 'slot_index': idx, 'slot_role': role,
            'slot_type': 'sets_reps',
            'slot': {'slot_type': 'sets_reps', 'intensity': 'heavy', **slot},
            'load': {'sets': 3, 'reps': 5, 'weight_kg': 100}}


def run(minutes, lo=1, hi=2):
    return {'exercise': EXERCISES['easy_run'], 'slot_index': 0, 'slot_role': 'main',
            'slot_type': 'time_domain', 'slot': {'slot_type': 'time_domain', 'intensity': 'zone2'},
            'load': {'duration_minutes': minutes, 'zone_lower': lo, 'zone_upper': hi}}


def session(modality, archetype, exercises):
    return {'modality': modality, 'archetype': archetype, 'exercises': exercises}


def week(n, schedule, phase_id='p1', kind='base', fw='fw', deload=False):
    return {'week_number': n, 'week_in_phase': n, 'phase': kind, 'phase_id': phase_id,
            'framework': fw, 'is_deload': deload, 'schedule': schedule}


FW = {'fw': {'id': 'fw', 'sessions_per_week': {'max_strength': 2, 'aerobic_base': 2},
             'intensity_distribution': {'zone1_2_pct': 0.9, 'zone3_pct': 0.1,
                                        'zone4_5_pct': 0.0, 'max_effort_pct': 0.0},
             'deload_protocol': {'frequency_weeks': 4, 'volume_reduction_pct': 0.6}}}
STRENGTH = arch('lp', 'max_strength', training_levels=['novice'], applicable_phases=['base'])
AEROBIC = arch('z2', 'aerobic_base', applicable_phases=['base'])
FULL = {'equipment': ['barbell', 'rack'], 'training_level': 'novice', 'injury_flags': [],
        'session_time_minutes': 75}


def rules(findings, rule=None):
    return [f for f in findings if rule is None or f.rule == rule]


def good_week(n, squat='back_squat', run_minutes=40, **kw):
    return week(n, {
        1: [session('max_strength', STRENGTH, [lift(squat)])],
        2: [session('aerobic_base', AEROBIC, [run(run_minutes)])],
        4: [session('max_strength', STRENGTH, [lift(squat)])],
        5: [session('aerobic_base', AEROBIC, [run(run_minutes)])],
    }, **kw)


def go(weeks, phase=None, constraints=FULL, phil=None):
    track = {'phases': [phase or {'id': 'p1', 'framework_id': 'fw'}]}
    return fidelity.check_program({'weeks': weeks}, phil or {}, track, constraints, FW, LIB)


def test_clean_program() -> None:
    print('a program that does what the framework says')
    found = [f for f in go([good_week(1), good_week(2)]) if f.severity != 'info']
    check('no errors or warnings', not found, str([f.key for f in found]))


def test_minutes_and_buckets() -> None:
    print('minutes and intensity buckets')
    s = session('aerobic_base', AEROBIC, [run(30, 2, 4)])
    b = fidelity.session_buckets(s)
    check('zone 2-4 spreads in thirds', abs(b['zone3_pct'] - 10) < 1e-6 and abs(b['zone4_5_pct'] - 10) < 1e-6)
    warm = dict(run(10), slot_role='warmup')
    s = session('max_strength', STRENGTH, [warm, lift('back_squat')])
    check('a lifting session is at least its estimate', fidelity.session_minutes(s) == 60)
    amrap = {'exercise': EXERCISES['easy_run'], 'slot': {'slot_type': 'amrap', 'intensity': 'heavy'},
             'load': {'time_minutes': 20}}
    s = session('aerobic_base', AEROBIC, [amrap])
    check('an AMRAP counts its time', fidelity.session_minutes(s) == 20)
    check('heavy conditioning is zone 4-5, not max effort',
          fidelity.session_buckets(s)['zone4_5_pct'] == 20)


def test_shape() -> None:
    print('weekly shape')
    only_lifting = week(1, {d: [session('max_strength', STRENGTH, [lift('back_squat')])] for d in (1, 3, 5, 7)})
    check('a declared modality never scheduled', bool(rules(go([only_lifting]), 'modality_missing')))
    extra = good_week(1)
    extra['schedule'][7] = [session('mobility', arch('flow', 'mobility'), [])]
    check('an undeclared modality', bool(rules(go([extra]), 'modality_foreign')))
    found = rules(go([extra], phil={'avoid_with': ['mobility']}), 'avoid_with')
    check('an avoided modality is an error', bool(found) and found[0].severity == 'error')


def test_intensity_and_zone_cap() -> None:
    print('intensity')
    hard = good_week(1, run_minutes=40)
    for d in (2, 5):
        hard['schedule'][d][0]['exercises'] = [run(40, 4, 5)]
    check('hard running against a 90/10 split', bool(rules(go([hard]), 'intensity_split')))
    phase = {'id': 'p1', 'framework_id': 'fw', 'checks': {'max_zone': 2}}
    check('a zone above the phase cap', bool(rules(go([hard], phase), 'zone_above_cap')))
    check('strength sits outside a split with no max-effort share',
          not rules(go([good_week(1)]), 'intensity_split'))


def test_levels_and_kinds() -> None:
    print('archetype fit')
    adv = good_week(1)
    adv['schedule'][1][0]['archetype'] = arch('hlm', 'max_strength', training_levels=['intermediate'])
    check('level mismatch', bool(rules(go([adv]), 'level_mismatch')))
    wrong = good_week(1, kind='taper')
    check('phase kind mismatch', bool(rules(go([wrong]), 'phase_kind_mismatch')))
    phase = {'id': 'p1', 'framework_id': 'fw', 'exclude_exercises': ['back_squat'],
             'checks': {'archetypes_forbidden': ['lp'], 'archetypes_required': ['z9'],
                        'modalities_required': ['anaerobic_intervals']}}
    found = {f.rule for f in go([good_week(1)], phase)}
    for rule in ('archetype_forbidden', 'archetype_required', 'exercise_forbidden', 'modality_required'):
        check(rule, rule in found)


def test_fixed_lifts() -> None:
    print('fixed main lifts')
    weeks = [good_week(1, squat='back_squat'), good_week(2, squat='front_squat')]
    check('a rotating main lift', bool(rules(go(weeks), 'main_lift_rotates')))
    check('rotation is fine when the phase says so',
          not rules(go(weeks, {'id': 'p1', 'framework_id': 'fw', 'rotate_main_lifts': True}),
                    'main_lift_rotates'))


def test_deload() -> None:
    print('deload')
    weeks = [good_week(1), good_week(2), good_week(3), good_week(4, run_minutes=40, deload=True)]
    check('a deload that keeps 100% instead of 60%', bool(rules(go(weeks), 'deload_size')))
    no_proto = {'fw': {**FW['fw'], 'deload_protocol': None}}
    found = fidelity.check_program({'weeks': weeks}, {}, {'phases': [{'id': 'p1', 'framework_id': 'fw'}]},
                                   FULL, no_proto, LIB)
    check('a deload with no protocol', bool(rules(found, 'deload_without_protocol')))
    check('no deload in four weeks', bool(rules(go([good_week(n) for n in range(1, 5)]), 'deload_missing')))


def test_volume() -> None:
    print('volume')
    phase = {'id': 'p1', 'framework_id': 'fw', 'checks': {'volume_change_per_week': [0.0, 0.15]}}
    weeks = [good_week(1, run_minutes=40), good_week(2, run_minutes=80)]
    check('a ramp above the band', bool(rules(go(weeks, phase), 'volume_ramp')))
    weeks = [good_week(1, run_minutes=40), good_week(3, run_minutes=80)]
    check('a gap restarts the ramp', not rules(go(weeks, phase), 'volume_ramp'))
    track = {'phases': [{'id': 'p1', 'framework_id': 'fw'},
                        {'id': 'p2', 'framework_id': 'fw', 'checks': {'volume_vs_previous_phase': [-0.6, -0.4]}}]}
    weeks = [good_week(1), good_week(2, phase_id='p2')]
    found = fidelity.check_program({'weeks': weeks}, {}, track, FULL, FW, LIB)
    check('a taper that drops nothing', bool(rules(found, 'volume_vs_previous_phase')))


def test_constraints() -> None:
    print('equipment, injuries, recovery, gaps')
    kb_only = {**FULL, 'equipment': ['kettlebell']}
    check('equipment the athlete lacks', bool(rules(go([good_week(1)], constraints=kb_only), 'equipment_violation')))
    knee = {**FULL, 'injury_flags': ['knee']}
    check('an excluded pattern', bool(rules(go([good_week(1)], constraints=knee), 'injury_violation')))
    skipped = good_week(1)
    skipped['schedule'][1][0]['exercises'] = [{'exercise': None, 'injury_skip': True, 'slot_role': 'main',
                                               'slot': {'exercise_filter': {'movement_pattern': 'squat'}}}]
    check('an injury skip with a named substitute',
          bool(rules(go([skipped], constraints=knee), 'injury_substitute_unused')))
    silent = good_week(1)
    silent['schedule'][1][0]['exercises'] = [{'exercise': None, 'slot_role': 'main', 'slot': {}}]
    check('an empty slot with no reason', bool(rules(go([silent]), 'silent_empty_slot')))
    tight = good_week(1)
    tight['schedule'][2] = [session('max_strength', STRENGTH, [lift('back_squat')])]
    check('two lifting days in a row', bool(rules(go([tight]), 'recovery_window')))


def test_claims() -> None:
    print("a phase's defining claims")
    clean = [good_week(1), good_week(2)]

    def claimed(weeks, **checks):
        return [f for f in go(weeks, {'id': 'p1', 'framework_id': 'fw', 'checks': checks})
                if f.rule in ('substituted_share', 'modality_outnumbers', 'archetype_share', 'distinct_archetypes')]

    swapped = good_week(1)
    swapped['schedule'][1][0]['substituted_for'] = 'max_strength'
    check('substitutes over the declared share', bool(claimed([swapped], max_substituted_share=0.2)))
    check('substitutes within the declared share', not claimed([swapped], max_substituted_share=0.25))
    found = claimed(clean, modality_outnumbers=[['max_strength', 'aerobic_base']])
    check('a modality that does not outnumber another', bool(found) and found[0].severity == 'error')
    check('one that does', not claimed([good_week(1)], modality_outnumbers=[['aerobic_base', 'mobility']]))
    check('one archetype over its share of the modality',
          bool(claimed(clean, max_archetype_share=0.5)))
    other = arch('lp_b', 'max_strength')
    varied = [good_week(n) for n in (1, 2)]
    for w in varied:
        w['schedule'][4][0]['archetype'] = other
    check('two archetypes each within their share',
          not [f for f in claimed(varied, max_archetype_share=0.5) if f.subject.startswith('max_strength')])
    check('too few archetypes in a window',
          bool(claimed(clean, min_distinct_archetypes={'weeks': 2, 'count': 2, 'modality': 'max_strength'})))
    check('enough archetypes in a window',
          not claimed(varied, min_distinct_archetypes={'weeks': 2, 'count': 2, 'modality': 'max_strength'}))
    contract = {'weeks': clean, 'training_contract': {'id': 'x'}}
    phase = {'phase_id': 'p1', 'checks': {'modality_outnumbers': [['max_strength', 'aerobic_base']]}}
    from src import training_contract
    try:
        training_contract.verify_phase_rules(contract, {'phase_sequence': [phase]})
        refused = False
    except training_contract.ContractError:
        refused = True
    check('a contract program breaking a claim is refused', refused)


def test_recovery_reads_the_modalities_windows() -> None:
    print('recovery: the scheduler\'s window, read back')
    mods = {**MODALITIES, 'long_recovery': {'recovery_cost': 'high', 'recovery_hours_min': 72}}

    def found(placed):
        out = fidelity._Collector()
        fidelity._check_recovery(out, 'p1', 1, placed, mods, frozenset())
        return [f.detail for f in out.findings()]

    check('two 48 h high-cost modalities two days apart are fine',
          not found({1: ['max_strength'], 3: ['anaerobic_intervals']}))
    check('a 72 h one two days from another high-cost one is not',
          found({1: ['long_recovery'], 3: ['max_strength']}) ==
          ['long_recovery and max_strength are both high-cost, 48 h apart; they need 72 h'],
          found({1: ['long_recovery'], 3: ['max_strength']}))
    check('three days apart it is', not found({1: ['long_recovery'], 4: ['max_strength']}))
    check('and it repeats only after its own 72 h',
          found({1: ['long_recovery'], 3: ['long_recovery']}) == ['long_recovery repeats after 48 h; it needs 72 h'])


def main() -> int:
    for t in (test_clean_program, test_minutes_and_buckets, test_shape, test_intensity_and_zone_cap,
              test_levels_and_kinds, test_fixed_lifts, test_deload, test_volume, test_constraints,
              test_claims, test_recovery_reads_the_modalities_windows):
        t()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('all fidelity rules pinned')
    return 0


if __name__ == '__main__':
    sys.exit(main())
