#!/usr/bin/env python
"""What the generator picks, pinned against what the methods call for.

Every case here was a divergence tools/check_fidelity.py found on 2026-10-16:
a Starting Strength novice on HLM, squats rotating through front and box
squats, a deload every 4th week in frameworks that declare none, a
45-minute athlete losing a method's core modality, empty slots with no
reason given, the first week on the second cadence pattern.

Run: SUPABASE_URL='' .venv/bin/python test_selection.py
"""
from __future__ import annotations

import sys

from src import goals, loader, scheduler
from src.selector import is_main_lift_slot
from src.generator import generate
from tools.check_styles import ALL_EQUIPMENT

FAILURES: list[str] = []
FRAMEWORKS = list(loader.load_all_frameworks().values())


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def program(phil: str, weeks: int, **kw) -> dict:
    goal = goals.philosophy_to_goal(phil, FRAMEWORKS, track_id=kw.pop('track_id', None))
    constraints = {'days_per_week': 3, 'session_time_minutes': 75, 'training_level': 'intermediate',
                   'equipment': list(ALL_EQUIPMENT), 'injury_flags': [], 'fatigue_state': 'normal',
                   'periodization_week': 1, **kw}
    return generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                    num_weeks=weeks, output_format='dict')


def sessions(prog: dict):
    for w in prog['weeks']:
        for day in sorted(w['schedule']):
            for s in w['schedule'][day]:
                yield w, s


def test_starting_strength() -> None:
    print('Starting Strength novice')
    prog = program('starting_strength', 6, training_level='novice')
    archs = [(s.get('archetype') or {}).get('id') for _, s in sessions(prog)]
    check('only sessions A and B', set(archs) == {'3x5_linear', '3x5_linear_b'}, str(set(archs)))
    check('A and B alternate', all(a != b for a, b in zip(archs, archs[1:])), str(archs[:6]))
    lifts = {}
    for _, s in sessions(prog):
        for ea in s['exercises']:
            if ea.get('exercise'):
                lifts.setdefault((s['archetype']['id'], ea['slot_role']), set()).add(ea['exercise']['id'])
    check('the squat is the back squat, every session',
          lifts.get(('3x5_linear', 'primary_squat')) == {'back_squat'}
          and lifts.get(('3x5_linear_b', 'primary_squat')) == {'back_squat'}, str(lifts))
    check('A presses and deadlifts', lifts.get(('3x5_linear', 'upper_press')) == {'strict_press'}
          and lifts.get(('3x5_linear', 'primary_pull')) == {'deadlift'})
    check('B benches and cleans', lifts.get(('3x5_linear_b', 'upper_press')) == {'bench_press'}
          and lifts.get(('3x5_linear_b', 'primary_pull')) == {'power_clean'})
    squats = [ea['load'].get('weight_kg') for _, s in sessions(prog) for ea in s['exercises']
              if (ea.get('exercise') or {}).get('id') == 'back_squat']
    check('the squat climbs week to week', squats[-1] > squats[0], str(squats))


def test_main_lift_pinning() -> None:
    print('main lifts hold within a phase')
    prog = program('horsemen_gpp', 4, days_per_week=5)
    by_slot = {}
    for _, s in sessions(prog):
        for ea in s['exercises']:
            if ea.get('exercise') and is_main_lift_slot(ea.get('slot') or {}):
                by_slot.setdefault((s['archetype']['id'], ea['slot_index']), set()).add(ea['exercise']['id'])
    rotating = {k: v for k, v in by_slot.items() if len(v) > 1}
    check('no main-lift slot rotates its lift', bool(by_slot) and not rotating, str(rotating))

    prog = program('crossfit', 4, days_per_week=4)
    lifts = set()
    for _, s in sessions(prog):
        for ea in s['exercises']:
            if ea.get('exercise') and (ea.get('slot') or {}).get('intensity') == 'heavy':
                lifts.add(ea['exercise']['id'])
    check('CrossFit still varies (rotate_main_lifts)', len(lifts) > 1, str(lifts))


def test_deloads() -> None:
    print('deloads follow the framework')
    prog = program('crossfit', 8, days_per_week=4)
    check('no deload where the framework declares none',
          not any(w['is_deload'] for w in prog['weeks']))
    prog = program('uphill_athlete', 8, days_per_week=5)
    flagged = [w['week_number'] for w in prog['weeks'] if w['is_deload']]
    check('Uphill transition deloads on its 4th week', 4 in flagged, str(flagged))


def test_constraints() -> None:
    print('constraints')
    prog = program('horsemen_gpp', 4, days_per_week=5, session_time_minutes=45)
    mods = {s['modality'] for _, s in sessions(prog)}
    check('a 45-minute week keeps max strength', 'max_strength' in mods, str(mods))
    capped = [s['archetype']['duration_estimate_minutes'] for _, s in sessions(prog)
              if s['modality'] == 'max_strength']
    check('and caps it at 45 minutes', capped and max(capped) <= 45, str(capped))

    prog = program('starting_strength', 2, training_level='novice', equipment=['kettlebell', 'open_space'])
    empties = [ea for _, s in sessions(prog) for ea in s['exercises'] if not ea.get('exercise')]
    check('a slot emptied by equipment says so',
          empties and all(ea.get('equipment_gap') and ea.get('gap_reason') == 'EQUIPMENT_UNAVAILABLE'
                          for ea in empties))

    prog = program('starting_strength', 2, training_level='novice', injury_flags=['shoulder_impingement'])
    presses = [ea for _, s in sessions(prog) for ea in s['exercises'] if ea['slot_role'] == 'upper_press']
    check('an injury-excluded press is an injury skip, not a silent gap',
          presses and all(ea.get('exercise') or ea.get('injury_skip') for ea in presses))


def test_cadence() -> None:
    print('cadence')
    fw = {'cadence_options': {3: [[1, 3, 5], [2, 4, 6]]}}
    check('week 1 takes the first pattern', scheduler._select_cadence('x', 3, 'base', 1, fw) == [1, 3, 5])
    check('week 2 the second', scheduler._select_cadence('x', 3, 'base', 2, fw) == [2, 4, 6])


def test_phase_exclusions() -> None:
    print('phase exercise exclusions')
    prog = program('wildman_kettlebell', 6, days_per_week=4, track_id='general_practice')
    banned = {'wk_kb_snatch', 'wk_kb_half_snatch', 'kb_jerk_single', 'kb_jerk_double', 'wk_kb_long_cycle_press'}
    used = {ea['exercise']['id'] for _, s in sessions(prog) for ea in s['exercises'] if ea.get('exercise')}
    check('foundations stops before the snatch and the jerk', not used & banned, str(used & banned))


def main() -> int:
    for t in (test_starting_strength, test_main_lift_pinning, test_deloads, test_constraints,
              test_cadence, test_phase_exclusions):
        t()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('all selection tests passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
