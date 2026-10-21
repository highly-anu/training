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
    # A training contract since 2026-10-20 (test_training_contract.py pins the
    # source's rules); this is what the selector-era checks still hold.
    prog = program('starting_strength', 6, training_level='novice', starting_loads_kg={'back_squat': 60})
    archs = [(s.get('archetype') or {}).get('id') for _, s in sessions(prog)]
    check('only sessions A and B', set(archs) == {'3x5_linear', '3x5_linear_b'}, str(set(archs)))
    check('A and B alternate', all(a != b for a, b in zip(archs, archs[1:])), str(archs[:6]))
    lifts = {}
    for _, s in sessions(prog):
        for ea in s['exercises']:
            if ea.get('exercise'):
                lifts.setdefault((s['archetype']['id'], ea['slot_role']), set()).add(ea['exercise']['id'])
    check('the squat is the back squat, every session',
          lifts.get(('3x5_linear', 'novice_lp_squat')) == {'back_squat'}
          and lifts.get(('3x5_linear_b', 'novice_lp_squat')) == {'back_squat'}, str(lifts))
    check('A presses and deadlifts', lifts.get(('3x5_linear', 'novice_lp_press')) == {'strict_press'}
          and lifts.get(('3x5_linear', 'novice_lp_deadlift')) == {'deadlift'})
    check('B benches and cleans', lifts.get(('3x5_linear_b', 'novice_lp_bench')) == {'bench_press'}
          and lifts.get(('3x5_linear_b', 'novice_lp_power_clean')) == {'power_clean'})
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

    # No shipped phase rotates its main lifts since CrossFit runs as written;
    # a phase given the flag still does.
    goal = goals.philosophy_to_goal('gym_jones', FRAMEWORKS)
    goal['phase_sequence'] = [{**ph, 'rotate_main_lifts': True} for ph in goal['phase_sequence']]
    prog = generate(goal_id=goal['id'], goal_dict=goal, num_weeks=4, output_format='dict',
                    constraints={'days_per_week': 5, 'session_time_minutes': 90, 'training_level': 'intermediate',
                                 'equipment': list(ALL_EQUIPMENT), 'injury_flags': [], 'fatigue_state': 'normal',
                                 'periodization_week': 1})
    lifts = set()
    for _, s in sessions(prog):
        for ea in s['exercises']:
            if ea.get('exercise') and is_main_lift_slot(ea.get('slot') or {}):
                lifts.add(ea['exercise']['id'])
    check('a phase that rotates its main lifts still varies them (rotate_main_lifts)', len(lifts) > 1, str(lifts))


def test_deloads() -> None:
    print('deloads follow the framework')
    prog = program('crossfit', 8, days_per_week=4)
    check('no deload where the framework declares none',
          not any(w['is_deload'] for w in prog['weeks']))
    prog = program('uphill_athlete', 8, days_per_week=6, session_time_minutes=360)
    flagged = [w['week_number'] for w in prog['weeks'] if w['is_deload']]
    check('Uphill transition recovers on its 4th week', flagged == [4, 8], str(flagged))


def test_constraints() -> None:
    print('constraints')
    prog = program('horsemen_gpp', 4, days_per_week=5, session_time_minutes=45)
    mods = {s['modality'] for _, s in sessions(prog)}
    check('a 45-minute week keeps max strength', 'max_strength' in mods, str(mods))
    capped = [s['archetype']['duration_estimate_minutes'] for _, s in sessions(prog)
              if s['modality'] == 'max_strength']
    check('and caps it at 45 minutes', capped and max(capped) <= 45, str(capped))

    # Starting Strength without a barbell, or with the press ruled out, used to
    # deliver sessions whose slots were empty; its contract refuses and says why.
    prog = program('starting_strength', 2, training_level='novice', equipment=['kettlebell', 'open_space'])
    check('no barbell is refused, naming the equipment',
          not prog['weeks'] and 'equipment' in prog['validation_errors'][0]['message'])

    prog = program('starting_strength', 2, training_level='novice', injury_flags=['shoulder_impingement'])
    check('an injury that rules out an essential lift refuses with its reason',
          not prog['weeks'] and 'injury' in prog['validation_errors'][0]['message'])

    prog = program('gym_jones', 2, training_level='intermediate', days_per_week=5,
                   equipment=['kettlebell', 'open_space'])
    empties = [ea for _, s in sessions(prog) for ea in s['exercises'] if not ea.get('exercise') and not ea.get('meta')]
    check('a slot emptied by equipment says so',
          all(ea.get('equipment_gap') or ea.get('injury_skip') or ea.get('coverage_gap') or ea.get('gap_reason')
              for ea in empties), str(empties[:1]))


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
    check('Phase II stops before the unconfirmed snatch and the jerk', not used & banned, str(used & banned))


# ── Review fixes (2026-10-16), on synthetic libraries ─────────────────────────

def _ex(eid, patterns=('squat',), **kw):
    return {'id': eid, 'name': eid, 'category': 'barbell', 'equipment': [],
            'movement_patterns': list(patterns), **kw}


SLOT = {'role': 'main', 'slot_type': 'sets_reps', 'sets': 3, 'reps': 5, 'intensity': 'heavy',
        'exercise_filter': {'movement_pattern': 'squat'}}
FLAGS = {'knee': {'excluded_movement_patterns': ['squat'],
                  'modified_exercises': [{'instead_of': 'back_squat', 'use': 'box_squat'}]}}


def explain_all(exercises, unlocked=None, flags=('knee',), phase_excluded=frozenset(), equipment=()):
    constraints = {'equipment': list(equipment), 'injury_flags': list(flags), 'training_level': 'intermediate'}
    _, excl_ids = selector._injury_exclusions(constraints, FLAGS)
    pool = (set(exercises) if unlocked is None else set(unlocked)) - excl_ids - set(phase_excluded)
    return selector._explain_unfilled(SLOT, constraints, exercises, pool, excl_ids, FLAGS,
                                      'base', set(), None, 'max_strength',
                                      phase_excluded=phase_excluded)


def explain(*args, **kw):
    """(reason, substitute, instead_of)."""
    return explain_all(*args, **kw)[:3]


def blocked(*args, **kw):
    """The slot's `blocked_by`."""
    return explain_all(*args, **kw)[3]


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


def test_blocked_by_names_the_constraint() -> None:
    print('an empty slot names what blocks it')
    lib = {'back_squat': _ex('back_squat', equipment=['barbell', 'rack', 'open_space'])}
    b = blocked(lib, flags=())
    check('equipment: the items the lift needs, never open space',
          b == {'cause': 'equipment', 'exercise': 'back_squat', 'needs': ['barbell', 'rack']}, str(b))
    b = blocked(lib, flags=(), equipment=['barbell'])
    check('equipment: only what is missing', b and b.get('needs') == ['rack'], str(b))
    b = blocked({'back_squat': _ex('back_squat')})
    check('injury: the flag that rules the lift out',
          b and b['cause'] == 'injury' and b['flags'] == ['knee'] and b['exercise'] == 'back_squat', str(b))
    b = blocked({'back_squat': _ex('back_squat'), 'box_squat': _ex('box_squat')})
    check('injury substitute: the flag it came via', b and b.get('via') == 'knee', str(b))
    b = blocked({'snatch': _ex('snatch', requires=['zz_unknown_skill'])}, unlocked=set(), flags=())
    check('level: what it requires that the level has not reached',
          b and b['cause'] == 'level' and b['requires'] == ['zz_unknown_skill'], str(b))
    lib_known = {'snatch': _ex('snatch', requires=['bracing', 'zz_unknown_skill'])}
    constraints = {'equipment': [], 'injury_flags': [], 'training_level': 'novice'}
    b = selector._explain_unfilled(SLOT, constraints, lib_known, set(), set(), FLAGS, 'base', set(), None,
                                   'max_strength', known=frozenset({'bracing'}))[3]
    check('level: never a concept the level already knows',
          b and b['requires'] == ['zz_unknown_skill'], str(b))
    b = blocked({'snatch': _ex('snatch')}, flags=(), phase_excluded=frozenset({'snatch'}))
    check('phase: the lift the phase leaves out', b == {'cause': 'phase', 'exercise': 'snatch'}, str(b))


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
    for phil, weeks in (('marcus_filly', 13), ('horsemen_gpp', 8), ('ido_portal', 12)):
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
    # Phase II leaves out the sport lifts; the snatch joins it once confirmed
    # (training_contract `when_mastered`). A stored week may name the phase
    # by its former id ('foundations').
    banned = {'wk_kb_half_snatch', 'kb_jerk_single', 'kb_jerk_double', 'wk_kb_long_cycle_press'}
    def offered(extra):
        r = client.post('/api/exercises/substitute', json={**body, **extra})
        return {a['assignment']['exercise']['id'] for a in (r.get_json() or {}).get('alternatives') or []}
    without = offered({})
    with_phase = offered({'phase_id': 'foundations', 'framework_id': 'kb_general_practice'})
    check('without the phase the banned lifts are on offer', bool(without & banned), str(without))
    check('with it they are not', bool(with_phase) and not with_phase & banned, str(with_phase))
    # A program built by a training contract keeps its fixed modules: the swap
    # refuses. Asked of the stored program, so a legacy or blended program swaps.
    from unittest.mock import patch
    with patch('src.db.get_user_program',
               return_value={'currentProgram': {'training_contract': {'id': 'wildman_kettlebell/general_practice@1'}}}):
        response = client.post('/api/exercises/substitute', json=body)
    check('a generic swap cannot bypass a fixed module', response.status_code == 422, str(response.get_json())[:200])


def test_a_framework_prescribes_its_own_way() -> None:
    # No shipped framework declares `progression_overrides` since Marcus
    # Filly's package became a contract; the mechanism is generic, so a
    # framework given one here prescribes its strength as RPE targets.
    print('Progression overrides: a framework can prescribe RPE, Starting Strength kg')
    real, real_one = loader.load_all_frameworks, loader.load_framework
    override = {'progression_overrides': {'max_strength': 'rpe_autoregulation'}}

    def with_override():
        out = real()
        out['block_periodization'] = {**out['block_periodization'], **override}
        return out

    def one_with_override(fid):
        fw = real_one(fid)
        return {**fw, **override} if fid == 'block_periodization' else fw
    loader.load_all_frameworks, loader.load_framework = with_override, one_with_override
    try:
        prog = program('gym_jones', 10, days_per_week=5)
        strength = [(w, ea) for w, s in sessions(prog) if s['modality'] == 'max_strength'
                    for ea in s['exercises'] if ea.get('exercise') and ea.get('slot_type') == 'sets_reps']
        check('overridden strength sets carry a target RPE, not a fixed kg',
              strength and all(ea['load'].get('target_rpe') and 'weight_kg' not in ea['load'] for _, ea in strength),
              str([ea['load'] for _, ea in strength[:2]]))
        # Each slot's deload sets against its own working sets.
        by_slot: dict = {}
        for w, ea in strength:
            by_slot.setdefault(ea['slot_role'], {}).setdefault(bool(w.get('is_deload')), set()).add(ea['load'].get('sets'))
        both = {role: d for role, d in by_slot.items() if d.get(True) and d.get(False)}
        check('an RPE deload week has fewer sets than a working week',
              both and all(max(d[True]) < min(d[False]) for d in both.values()), str(both))
        # A swap in that week is prescribed the same way as the week around it.
        import os
        os.environ.setdefault('SUPABASE_URL', '')
        import api
        session = next(s for w, s in sessions(prog) if s['modality'] == 'max_strength')
        row = next(ea for ea in session['exercises'] if ea.get('exercise') and ea.get('slot_type') == 'sets_reps')
        r = api.app.test_client().post('/api/exercises/substitute', json={
            'archetype_id': session['archetype']['id'], 'slot_role': row['slot_role'],
            'philosophy_ids': ['gym_jones'], 'phase': session.get('phase') or 'base', 'week_in_phase': 1,
            'framework_id': 'block_periodization',
            'constraints': {'equipment': list(ALL_EQUIPMENT), 'training_level': 'intermediate'}, 'limit': 5})
        alts = (r.get_json() or {}).get('alternatives') or []
        check('a swapped lift carries an RPE target, not a kg',
              alts and all('target_rpe' in a['assignment']['load'] and 'weight_kg' not in a['assignment']['load']
                           for a in alts), str([a['assignment']['load'] for a in alts[:2]]))
    finally:
        loader.load_all_frameworks, loader.load_framework = real, real_one
    ss = program('starting_strength', 2, training_level='novice', starting_loads_kg={'back_squat': 60})
    loads = [ea['load'] for _, s in sessions(ss) for ea in s['exercises'] if ea.get('exercise')]
    check('a framework without overrides is unchanged (SS: kg, no RPE)',
          any(l.get('weight_kg') for l in loads) and not any('target_rpe' in l for l in loads))


def test_substitution_is_recorded() -> None:
    print('a session scheduled as another modality says so')
    # Contract modules retain their own stimulus at every supported level;
    # legacy fallback reporting is still exercised by the validator below.
    kb = {'equipment': ['kettlebell'], 'days_per_week': 4, 'session_time_minutes': 40}
    novice = program('wildman_kettlebell', 4, track_id='general_practice', training_level='novice', **kb)
    swapped = [s for _, s in sessions(novice) if s.get('substituted_for')]
    check('a novice retains the declared Wildman modules without substitution',
          not swapped and novice['weeks'],
          str([(s['modality'], s.get('substituted_for')) for s in swapped]))
    report = novice['coverage_report']['substituted_sessions']
    check('the coverage report lists them with a week number and a day name',
          len(report) == len(swapped) and all(isinstance(r['week'], int) and isinstance(r['day'], str)
                                              for r in report), str(report[:2]))
    check('contract generation introduces no fallback compromises', not novice['compromises'])
    intermediate = program('wildman_kettlebell', 4, track_id='general_practice',
                           training_level='intermediate', **kb)
    check('an intermediate gets the modalities as asked, nothing substituted',
          not intermediate['coverage_report']['substituted_sessions']
          and {'power', 'movement_skill'} <= {s['modality'] for _, s in sessions(intermediate)})

    from src import provenance
    from src.validator import ValidationResult, check_level_coverage
    goal = goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, track_id='general_practice')
    policy = provenance.resolve_source_policy(goal)
    archetypes = provenance.scope(loader.load_all_data(), policy)['archetypes']
    result = ValidationResult()
    check_level_coverage({'strength_endurance': {'aerobic_base'}}, {'training_level': 'novice'},
                         archetypes, policy, result)
    check('LEVEL_COVERAGE_GAP names the level, the levels written for and the substitute',
          [w['code'] for w in result.warnings] == ['LEVEL_COVERAGE_GAP']
          and 'novice' in result.warnings[0]['message']
          and 'only intermediate' in result.warnings[0]['message']
          and 'aerobic base' in result.warnings[0]['message'], str(result.warnings))
    result = ValidationResult()
    check_level_coverage({'strength_endurance': {'aerobic_base'}}, {'training_level': 'intermediate'},
                         archetypes, policy, result)
    check('no warning when the level is covered (the swap had another cause)', not result.warnings)

    # Gym Jones max strength: emom_strength names no levels (open to all) but
    # is not for the base phase; the others start at intermediate. A novice's
    # base-phase swap is the phase's doing, not the level's.
    gj = goals.philosophy_to_goal('gym_jones', FRAMEWORKS)
    gj_policy = provenance.resolve_source_policy(gj)
    gj_arch = provenance.scope(loader.load_all_data(), gj_policy)['archetypes']
    result = ValidationResult()
    check_level_coverage({'max_strength': {'aerobic_base'}}, {'training_level': 'novice'},
                         gj_arch, gj_policy, result)
    check('an archetype open to every level means the level is not the cause', not result.warnings,
          str(result.warnings))


def main() -> int:
    for t in (test_starting_strength, test_main_lift_pinning, test_deloads, test_constraints,
              test_cadence, test_phase_exclusions, test_injury_substitute_rules, test_gap_reasons,
              test_blocked_by_names_the_constraint, test_pins_never_repeat_a_lift, test_unfilled_cache,
              test_taper_keeps_the_framework_share_for_sets, test_declared_deloads,
              test_single_session_routes, test_a_framework_prescribes_its_own_way,
              test_substitution_is_recorded):
        t()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s)")
        return 1
    print('all selection tests passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
