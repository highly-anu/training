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

from src import goals, loader, progression, scheduler, selector
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


# ── Review fixes (2026-10-16), on synthetic libraries ─────────────────────────

def _ex(eid, patterns=('squat',), **kw):
    return {'id': eid, 'name': eid, 'category': 'barbell', 'equipment': [],
            'movement_patterns': list(patterns), **kw}


SLOT = {'role': 'main', 'slot_type': 'sets_reps', 'sets': 3, 'reps': 5, 'intensity': 'heavy',
        'exercise_filter': {'movement_pattern': 'squat'}}
FLAGS = {'knee': {'excluded_movement_patterns': ['squat'],
                  'modified_exercises': [{'instead_of': 'back_squat', 'use': 'box_squat'}]}}


def explain(exercises, unlocked=None, flags=('knee',), phase_excluded=frozenset()):
    constraints = {'equipment': [], 'injury_flags': list(flags), 'training_level': 'intermediate'}
    _, excl_ids = selector._injury_exclusions(constraints, FLAGS)
    pool = (set(exercises) if unlocked is None else set(unlocked)) - excl_ids - set(phase_excluded)
    return selector._explain_unfilled(SLOT, constraints, exercises, pool, excl_ids, FLAGS,
                                      'base', set(), None, 'max_strength',
                                      phase_excluded=phase_excluded)


def test_injury_substitute_rules() -> None:
    print('injury substitutes')
    lib = {'back_squat': _ex('back_squat'), 'box_squat': _ex('box_squat')}
    reason, sub, was = explain(lib)
    check('a flag substitute fills the slot', reason == 'injury' and sub and sub['id'] == 'box_squat'
          and was == 'back_squat')
    reason, sub, _ = explain(lib, phase_excluded=frozenset({'box_squat'}))
    check('never one the phase leaves out', reason == 'injury' and sub is None)
    reason, sub, _ = explain(lib, unlocked={'back_squat'})
    check('never one locked at the athlete\'s level', reason == 'injury' and sub is None)
    lib2 = {**lib, 'box_squat': _ex('box_squat', contraindicated_with=['knee'])}
    check('never one a flag contraindicates', explain(lib2)[1] is None)


def test_gap_reasons() -> None:
    print('why a slot is empty')
    lib = {'snatch': _ex('snatch')}
    reason, _, _ = explain(lib, flags=(), phase_excluded=frozenset({'snatch'}))
    check('a phase exclusion is the phase, not the level', reason == 'phase', str(reason))
    reason, _, _ = explain({'snatch': _ex('snatch', requires=['zz_unknown_skill'])},
                           unlocked=set(), flags=())
    check('a locked lift is the level', reason == 'level', str(reason))


def _populate(exercises, slots, pins, cache=None, flags=()):
    arch = {'id': 'a', 'name': 'A', 'modality': 'max_strength', 'slots': slots,
            'duration_estimate_minutes': 60}
    constraints = {'equipment': [], 'injury_flags': list(flags), 'training_level': 'intermediate',
                   'session_time_minutes': 75}
    return selector.populate_session({'modality': 'max_strength', 'is_deload': False}, {'primary_sources': []},
                                     constraints, exercises, [arch], FLAGS, 'base', 1,
                                     forced_archetype=arch, pinned_lifts=pins, unfilled_cache=cache)


def test_pins_never_repeat_a_lift() -> None:
    print('pinned lifts within a session')
    lib = {'back_squat': _ex('back_squat'), 'front_squat': _ex('front_squat')}
    two = [dict(SLOT, role='first'), dict(SLOT, role='second')]
    out = _populate(lib, two, {('a', 0): 'zz_gone', ('a', 1): 'back_squat'})
    ids = [ea['exercise']['id'] for ea in out['exercises'] if ea.get('exercise')]
    check('a fresh pick leaves the other slot its pin', ids == ['front_squat', 'back_squat'], str(ids))
    out = _populate(lib, two, {('a', 0): 'back_squat', ('a', 1): 'back_squat'})
    ids = [ea['exercise']['id'] for ea in out['exercises'] if ea.get('exercise')]
    check('a pin already used this session is not reused', len(ids) == len(set(ids)), str(ids))


def test_unfilled_cache() -> None:
    print('an empty slot is explained once per phase')
    calls = []
    real = selector._explain_unfilled
    selector._explain_unfilled = lambda *a, **k: calls.append(1) or real(*a, **k)
    try:
        cache: dict = {}
        lib = {'back_squat': _ex('back_squat')}
        for _ in range(3):
            _populate(lib, [SLOT], {}, cache, flags=('knee',))
    finally:
        selector._explain_unfilled = real
    check('three weeks, one explanation', len(calls) == 1, str(len(calls)))


def test_taper_keeps_the_framework_share_for_sets() -> None:
    print('a taper cuts sets by the framework share')
    check('time and distance are corrected for the kind',
          abs(progression._kind_adjusted_keep('taper', 0.5, 0.6) - 0.5 / 0.6) < 1e-9)
    check('outside a taper the share is as given', progression._kind_adjusted_keep('base', 0.5, 0.6) == 0.5)
    ex = {'id': 'back_squat', 'starting_load_kg': {'intermediate': 100}}
    load = progression.calculate_load(ex, {'slot_type': 'sets_reps', 'sets': 4, 'reps': 5}, 'linear_load',
                                      2, 'taper', 'intermediate', True, deload_keep=0.5)
    check('4 sets keep 2 in a taper deload', load['sets'] == 2, str(load))


def test_declared_deloads() -> None:
    print('deload protocols')
    for phil, weeks in (('marcus_filly', 10), ('horsemen_gpp', 8), ('ido_portal', 12)):
        kw = {'track_id': 'gpp_circuits'} if phil == 'horsemen_gpp' else {}
        prog = program(phil, weeks, days_per_week=5, **kw)
        check(f'{phil} deloads on schedule', any(w['is_deload'] for w in prog['weeks']))


def test_single_session_routes() -> None:
    print('swap and session regenerate apply the phase')
    import os
    os.environ.setdefault('SUPABASE_URL', '')
    import api
    client = api.app.test_client()
    body = {'archetype_id': 'kb_double_strength', 'slot_role': 'main', 'exercise_id': 'kb_press_double',
            'philosophy_ids': ['wildman_kettlebell'], 'phase': 'base', 'week_in_phase': 1,
            'constraints': {'equipment': ['kettlebell', 'open_space'], 'training_level': 'intermediate'},
            'limit': 10}
    banned = {'wk_kb_snatch', 'wk_kb_half_snatch', 'kb_jerk_single', 'kb_jerk_double', 'wk_kb_long_cycle_press'}
    def offered(extra):
        r = client.post('/api/exercises/substitute', json={**body, **extra})
        return {a['assignment']['exercise']['id'] for a in (r.get_json() or {}).get('alternatives') or []}
    without = offered({})
    with_phase = offered({'phase_id': 'foundations', 'framework_id': 'kb_general_practice'})
    check('without the phase the banned lifts are on offer', bool(without & banned), str(without))
    check('with it they are not', bool(with_phase) and not with_phase & banned, str(with_phase))


def main() -> int:
    for t in (test_starting_strength, test_main_lift_pinning, test_deloads, test_constraints,
              test_cadence, test_phase_exclusions, test_injury_substitute_rules, test_gap_reasons,
              test_pins_never_repeat_a_lift, test_unfilled_cache,
              test_taper_keeps_the_framework_share_for_sets, test_declared_deloads,
              test_single_session_routes):
        t()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('all selection tests passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
