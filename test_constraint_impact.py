#!/usr/bin/env python
"""src/constraint_impact.py and POST /api/dev/constraint-impact: what the
athlete's equipment, injuries and level change in a program, and which one.

The rules on hand-built programs first, then the route on real generations.

Run: SUPABASE_URL='' .venv/bin/python test_constraint_impact.py
"""
from __future__ import annotations

import os
import sys

os.environ.setdefault('SUPABASE_URL', '')

from src import constraint_impact as ci

FAILURES: list[str] = []


def check(label: str, condition: bool, detail='') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


EXERCISES = {
    'back_squat': {'id': 'back_squat', 'name': 'Back Squat', 'equipment': ['barbell', 'rack'],
                   'movement_patterns': ['squat']},
    'goblet_squat': {'id': 'goblet_squat', 'name': 'Goblet Squat', 'equipment': ['kettlebell'],
                     'movement_patterns': ['squat']},
    'kb_swing': {'id': 'kb_swing', 'name': 'KB Swing', 'equipment': ['kettlebell'],
                 'movement_patterns': ['hinge']},
    'deadlift': {'id': 'deadlift', 'name': 'Deadlift', 'equipment': ['barbell'],
                 'movement_patterns': ['hinge']},
}
ARCHETYPES = {
    'novice_a': {'id': 'novice_a', 'name': 'Novice A', 'training_levels': ['novice'],
                 'required_equipment': ['barbell']},
    'hlm': {'id': 'hlm', 'name': 'HLM', 'training_levels': ['intermediate'],
            'required_equipment': ['barbell']},
    'kb_day': {'id': 'kb_day', 'name': 'KB Day', 'required_equipment': ['kettlebell']},
}
FLAGS = {'lumbar_disc': {'name': 'Lumbar Disc', 'excluded_movement_patterns': ['hinge']}}


def ea(ex_id=None, role='main', gap=None, injury=False):
    out = {'slot_role': role, 'exercise': EXERCISES[ex_id] if ex_id else None}
    if gap:
        out['gap_reason'] = gap
    if injury:
        out['injury_skip'] = True
    return out


def sess(arch_id, *slots, modality='max_strength', **extra):
    return {'modality': modality, 'archetype': ARCHETYPES[arch_id], 'exercises': list(slots), **extra}


def program(*weeks):
    return {'weeks': [{'week_number': i + 1, 'schedule': w} for i, w in enumerate(weeks)]}


def analyse(actual, reference, relaxed, constraints, ref_level='intermediate', unlocked=None):
    ref_c = {**constraints, 'equipment': ['barbell', 'kettlebell', 'rack'], 'injury_flags': [],
             'training_level': ref_level}
    return ci.analyse(actual, reference, relaxed, constraints=constraints, reference_constraints=ref_c,
                      exercises=EXERCISES, archetypes=ARCHETYPES, injury_flags=FLAGS, unlocked=unlocked)


def test_runs():
    print('the runs')
    check('a framework written for the level keeps it', ci.reference_level('novice', ['novice']) == 'novice')
    check('no levels listed keeps it', ci.reference_level('advanced', None) == 'advanced')
    check('the nearest listed level', ci.reference_level('elite', ['novice', 'intermediate']) == 'intermediate')
    check('a tie goes to the lower', ci.reference_level('intermediate', ['novice', 'advanced']) == 'novice')

    athlete = {'equipment': ['kettlebell'], 'injury_flags': ['lumbar_disc'], 'training_level': 'intermediate',
               'days_per_week': 3, 'track_id': 'lp'}
    lib = {'exercises': EXERCISES, 'archetypes': list(ARCHETYPES.values())}
    ref = ci.reference_constraints(athlete, lib, {'applicable_when': {'training_level': ['novice']}})
    check('reference equipment is what the packages use',
          ref['equipment'] == ['barbell', 'kettlebell', 'rack'], ref['equipment'])
    check('reference has no injuries and the framework\'s level',
          ref['injury_flags'] == [] and ref['training_level'] == 'novice')
    check('the schedule stays the athlete\'s', ref['days_per_week'] == 3 and ref['track_id'] == 'lp')
    pinned = ci.reference_constraints(athlete, lib, None, {'training_level': 'advanced', 'equipment': ['rings']})
    check('a request may pin the reference', pinned['training_level'] == 'advanced'
          and pinned['equipment'] == ['rings'])

    runs = ci.relaxations(athlete, ref)
    check('one run per constraint the athlete has', sorted(runs) == ['equipment', 'injury', 'level'], sorted(runs))
    check('each lifts only its own', runs['injury']['equipment'] == ['kettlebell']
          and runs['injury']['injury_flags'] == [] and runs['level']['training_level'] == 'novice')
    free = {**athlete, 'equipment': ref['equipment'], 'injury_flags': [], 'training_level': 'novice'}
    check('nothing to lift, nothing run', ci.relaxations(free, ref) == {})


def test_slot_emptied_by_equipment():
    print('a slot emptied by the equipment')
    athlete = {'equipment': ['kettlebell'], 'injury_flags': [], 'training_level': 'intermediate'}
    ref = program({'Monday': [sess('hlm', ea('back_squat'), ea('kb_swing', role='accessory'))]})
    act = program({'Monday': [sess('hlm', ea(role='main', gap='EQUIPMENT_UNAVAILABLE'), ea('kb_swing', role='accessory'))]})
    out = analyse(act, ref, {'equipment': ref}, athlete)
    ch = out['changes']
    check('one session changed', len(ch) == 1 and ch[0]['change'] == 'slots', ch)
    slot = ch[0]['slots'][0]
    check('only the emptied slot is listed', len(ch[0]['slots']) == 1 and slot['index'] == 0)
    check('it says what was planned and what is', slot['kind'] == 'emptied'
          and slot['from']['id'] == 'back_squat' and slot['to'] is None
          and slot['gap_reason'] == 'EQUIPMENT_UNAVAILABLE')
    check('equipment alone restores it', slot['causes'] == ['equipment'])
    check('in words', slot['why'] == [{'cause': 'equipment', 'text': 'Back Squat needs barbell, rack'}], slot['why'])
    check('what would restore it', out['restore']['equipment'] == [
        {'id': 'barbell', 'changes': 1}, {'id': 'rack', 'changes': 1}], out['restore'])
    check('totals per cause', out['totals'] == {'equipment': {'slots': 1}}, out['totals'])


def test_archetype_by_level_and_equipment():
    print('another session for the level, and its exercises need equipment')
    athlete = {'equipment': [], 'injury_flags': [], 'training_level': 'intermediate'}
    ref = program({'Monday': [sess('novice_a', ea('back_squat'), ea('deadlift'))]})
    act = program({'Monday': [sess('hlm', ea(gap='EQUIPMENT_UNAVAILABLE'), ea(gap='EQUIPMENT_UNAVAILABLE'))]})
    level_lifted = program({'Monday': [sess('novice_a', ea(gap='EQUIPMENT_UNAVAILABLE'), ea(gap='EQUIPMENT_UNAVAILABLE'))]})
    out = analyse(act, ref, {'equipment': act, 'level': level_lifted}, athlete, ref_level='novice')
    ch = out['changes'][0]
    check('an archetype change', ch['change'] == 'archetype'
          and ch['reference']['archetype']['id'] == 'novice_a' and ch['actual']['archetype']['id'] == 'hlm')
    check('the level brings it back; the equipment empties it anyway', ch['causes'] == ['level', 'equipment'], ch['causes'])
    check('why, both', [w['text'] for w in ch['why']] == [
        'Novice A is written for novice', '2 of 2 of its exercises need barbell, rack'], ch['why'])
    check('each reference exercise says what blocks it',
          ch['reference_slots'][0]['blocked_by'] == [{'cause': 'equipment', 'text': 'Back Squat needs barbell, rack'}])
    check('both slot lists', len(ch['reference_slots']) == 2 and len(ch['actual_slots']) == 2
          and ch['actual_slots'][0]['gap_reason'] == 'EQUIPMENT_UNAVAILABLE')
    check('counted under both', out['totals'] == {'level': {'sessions': 1}, 'equipment': {'sessions': 1}}, out['totals'])


def test_combined_and_alternatives():
    print('a slot two constraints rule out, and what one alone would give')
    athlete = {'equipment': ['kettlebell'], 'injury_flags': ['lumbar_disc'], 'training_level': 'intermediate'}
    ref = program({'Monday': [sess('kb_day', ea('deadlift'), ea('back_squat', role='squat'))]})
    act = program({'Monday': [sess('kb_day', ea(injury=True), ea('goblet_squat', role='squat'))]})
    eq_lifted = program({'Monday': [sess('kb_day', ea(injury=True), ea('back_squat', role='squat'))]})
    inj_lifted = program({'Monday': [sess('kb_day', ea('kb_swing'), ea('goblet_squat', role='squat'))]})
    out = analyse(act, ref, {'equipment': eq_lifted, 'injury': inj_lifted}, athlete)
    hinge, squat = out['changes'][0]['slots']
    check('no one constraint restores the deadlift', hinge['causes'] == ['combined'])
    check('and both are named', [w['cause'] for w in hinge['why']] == ['equipment', 'injury'], hinge['why'])
    check('an injury gap reads as one', hinge['gap_reason'] == 'INJURY_EXCLUDED')
    check('lifting the injury alone would swing', hinge['alternatives'] == [
        {'cause': 'injury', 'exercise': {'id': 'kb_swing', 'name': 'KB Swing'}}], hinge['alternatives'])
    check('a swap names both exercises', squat['kind'] == 'swapped'
          and squat['from']['id'] == 'back_squat' and squat['to']['id'] == 'goblet_squat')
    check('equipment alone restores the squat', squat['causes'] == ['equipment'] and squat['alternatives'] == [])


def test_order_and_added_sessions():
    print('calendar order, unchanged sessions, a session only one run has')
    athlete = {'equipment': ['kettlebell', 'barbell', 'rack'], 'injury_flags': [], 'training_level': 'intermediate'}
    same = sess('kb_day', ea('kb_swing'))
    ref = program({'Wednesday': [same], 'Monday': [same]},
                  {'Monday': [sess('hlm', ea('back_squat'))]})
    act = program({'Wednesday': [same], 'Monday': [same, sess('kb_day', ea('goblet_squat'))]},
                  {'Monday': [sess('kb_day', ea('kb_swing'))]})
    out = analyse(act, ref, {}, athlete)
    keys = [(c['week_index'], c['day'], c['session_index'], c['change']) for c in out['changes']]
    check('only changed sessions, in calendar order',
          keys == [(0, 'Monday', 1, 'added'), (1, 'Monday', 0, 'archetype')], keys)
    check('the week number comes from the week', out['changes'][1]['week_number'] == 2)
    check('nothing lifted reads as combined', out['changes'][1]['causes'] == ['combined'])
    check('HLM was open to the athlete: a knock-on', out['changes'][1]['knock_on'] is True
          and out['changes'][1]['why'][0]['cause'] == 'knock_on', out['changes'][1]['why'])
    check('an added session is not', out['changes'][0]['knock_on'] is False)
    check('the counts', out['sessions'] == {'total': 4, 'changed': 2, 'direct': 1}, out['sessions'])


def test_knock_on_and_level_locked():
    print('a rotation moved by an earlier change, and a level-locked exercise')
    athlete = {'equipment': ['kettlebell'], 'injury_flags': [], 'training_level': 'novice'}
    ref = program({'Monday': [sess('kb_day', ea('kb_swing'), ea('goblet_squat', role='squat'))]})
    act = program({'Monday': [sess('kb_day', ea('goblet_squat'), ea(role='squat', gap='LEVEL_LOCKED'))]})
    level_lifted = program({'Monday': [sess('kb_day', ea('kb_swing'), ea('goblet_squat', role='squat'))]})
    out = analyse(act, ref, {'level': level_lifted}, athlete, unlocked={'kb_swing'})
    swing, squat = out['changes'][0]['slots']
    check('the swing is open to a novice: knock-on', swing['knock_on'] is True
          and swing['why'] == [{'cause': 'knock_on',
                                'text': 'KB Swing is open to the athlete: an earlier change moved the rotation'}],
          swing['why'])
    check('the goblet squat is not unlocked: direct', squat['knock_on'] is False and squat['causes'] == ['level'])
    check('knock-ons are counted apart', out['totals'] == {'level': {'knock_on': 1, 'slots': 1}}, out['totals'])
    check('a session is direct if any slot is', out['changes'][0]['knock_on'] is False
          and out['sessions']['direct'] == 1)
    locked = ci._Explainer(athlete, {}, EXERCISES, ARCHETYPES, FLAGS, {'kb_swing'}).blockers(ea('goblet_squat'))
    check('the level says so', locked == [{'cause': 'level', 'needs': [],
                                          'text': 'Goblet Squat is not unlocked at novice'}], locked)


def test_route():
    print('the route, on real generations')
    import api
    client = api.app.test_client()
    athlete = {'equipment': [], 'days_per_week': 3, 'session_time_minutes': 60, 'training_level': 'intermediate',
               'injury_flags': [], 'avoid_movements': [], 'periodization_week': 1, 'fatigue_state': 'normal'}
    res = client.post('/api/dev/constraint-impact',
                      json={'philosophy_id': 'starting_strength', 'num_weeks': 1, 'constraints': athlete})
    body = res.get_json()
    check('200', res.status_code == 200, (res.status_code, body))
    check('the reference is the novice program with its equipment',
          body['reference']['training_level'] == 'novice'
          and {'barbell', 'plates', 'rack'} <= set(body['reference']['equipment']), body['reference'])
    check('equipment and level are lifted, injuries are not', body['lifted'] == ['equipment', 'level'], body['lifted'])
    changes = body['changes']
    check('every session changed', changes and body['sessions']['changed'] == body['sessions']['total'], body['sessions'])
    check('each is the level and the equipment',
          all(c['causes'] == ['level', 'equipment'] for c in changes), [c.get('causes') for c in changes])
    check('the 3x5 sessions are what was planned',
          all(c['reference']['archetype']['id'].startswith('3x5') for c in changes))
    check('a barbell would restore them',
          body['restore']['equipment'] and body['restore']['equipment'][0]['id'] in ('barbell', 'plates'),
          body['restore'])

    infeasible = client.post('/api/dev/constraint-impact', json={
        'philosophy_id': 'gym_jones', 'num_weeks': 1, 'constraints': {**athlete, 'days_per_week': 1}}).get_json()
    check('an infeasible schedule is refused, and the framework\'s days would generate',
          infeasible.get('feasible') is False and 'days/week' in infeasible['refused']['detail']
          and [u['cause'] for u in infeasible['unblocked_by']] == ['schedule']
          and not infeasible['reference_generates'], infeasible)
    missing = client.post('/api/dev/constraint-impact', json={'constraints': athlete})
    check('generate\'s own errors pass through', missing.status_code == 400)


def test_contract_rules():
    print('a training contract: proficiency, and what unblocks a refusal')
    goal = {'training_contract': {
        'modules': [{'requires_mastery': ['kb_clean', 'kb_jerk']}, {'requires_mastery': ['kb_press']}],
        'requires_kettlebell_pair': True,
        'level_seeds': {'intermediate': ['kb_press']}}}
    check('every movement a module needs confirmed',
          ci.contract_requirements(goal) == {'mastered_exercises': ['kb_clean', 'kb_jerk', 'kb_press'],
                                             'kettlebell_count': 2})
    check('less what the level already seeds',
          ci.contract_requirements(goal, 'intermediate')['mastered_exercises'] == ['kb_clean', 'kb_jerk'])
    check('no contract, nothing to confirm', ci.contract_requirements({}) == {})

    athlete = {'equipment': ['kettlebell'], 'injury_flags': [], 'training_level': 'intermediate',
               'mastered_exercises': ['kb_clean'], 'kettlebell_weights_kg': [16]}
    lib = {'exercises': EXERCISES, 'archetypes': []}
    ref = ci.reference_constraints(athlete, lib, None, None, ci.contract_requirements(goal, 'intermediate'))
    check('the reference confirms what the contract asks', ref['mastered_exercises'] == ['kb_clean', 'kb_jerk']
          and ref['kettlebell_count'] == 2 and 'kettlebell_weights_kg' not in ref, ref)
    runs = ci.relaxations(athlete, ref)
    check('proficiency is a constraint of its own', runs['proficiency']['mastered_exercises'] == ['kb_clean', 'kb_jerk']
          and runs['proficiency']['kettlebell_count'] == 2 and runs['proficiency']['equipment'] == ['kettlebell'])
    check('a bell inventory is equipment', 'kettlebell_weights_kg' not in runs['equipment'])
    names = {**EXERCISES, 'kb_jerk': {'name': 'Jerk'}}
    lifts = ci.describe_lifts(athlete, {**runs, 'schedule': {**athlete, 'days_per_week': 3, 'session_time_minutes': 60}},
                              names, FLAGS)
    check('each lift in words', lifts == {
        'equipment': 'add barbell, rack; any bell weight', 'proficiency': 'confirm mastery of Jerk; 2 matching bells',
        'schedule': '3 days, 60 min'}, lifts)
    check('the schedule is tried only at the framework\'s ideal',
          ci.schedule_probe({'days_per_week': 2, 'session_time_minutes': 90},
                            {'expectations': {'ideal_days_per_week': 3, 'ideal_session_minutes': 60}})
          == {'days_per_week': 3, 'session_time_minutes': 90}
          and ci.schedule_probe({'days_per_week': 3, 'session_time_minutes': 60},
                                {'expectations': {'ideal_days_per_week': 3}}) is None)

    refused = {'detail': 'confirm mastery', 'validation': {'errors': []}}
    one = ci.explain_refusal(refused, {'reference': True, 'proficiency': True, 'level': False}, lifts, ref)
    check('the one constraint that unblocks it', one['unblocked_by'] == [
        {'cause': 'proficiency', 'text': 'confirm mastery of Jerk; 2 matching bells'}] and one['feasible'] is False)
    both = ci.explain_refusal(refused, {'reference': True, 'proficiency': False, 'equipment': False}, lifts, ref)
    check('none alone, all together: combined', both['unblocked_by'] == [
        {'cause': 'combined', 'text': 'add barbell, rack; any bell weight; confirm mastery of Jerk; 2 matching bells'}],
        both['unblocked_by'])
    check('a reference that cannot run either says so',
          ci.explain_refusal(refused, {'reference': False}, {}, ref)['unblocked_by'] == [])

    athlete_ex = ci._Explainer(athlete, ref, {'kb_jerk': {'id': 'kb_jerk', 'name': 'Jerk', 'equipment': ['kettlebell']}},
                               {}, FLAGS, None)
    check('an exercise not yet confirmed says so',
          athlete_ex.blockers({'exercise': {'id': 'kb_jerk', 'name': 'Jerk'}}) == [
              {'cause': 'proficiency', 'needs': [], 'text': 'Jerk needs confirmed mastery'}])


def test_contract_route():
    print('the route on Wildman\'s training contract')
    import api
    client = api.app.test_client()
    athlete = {'equipment': ['kettlebell', 'open_space'], 'days_per_week': 4, 'session_time_minutes': 60,
               'training_level': 'intermediate', 'injury_flags': [], 'avoid_movements': [],
               'periodization_week': 1, 'fatigue_state': 'normal'}

    def impact(track, **extra):
        return client.post('/api/dev/constraint-impact', json={
            'philosophy_id': 'wildman_kettlebell', 'track_id': track, 'num_weeks': 2,
            'constraints': {**athlete, **extra}}).get_json()

    pent = impact('pentathlon')
    check('Pentathlon without the events confirmed is refused',
          pent['feasible'] is False and 'confirm mastery' in pent['refused']['detail'])
    check('confirming them alone unblocks it', [u['cause'] for u in pent['unblocked_by']] == ['proficiency']
          and 'Kettlebell Jerk (Single-Arm)' in pent['unblocked_by'][0]['text'], pent['unblocked_by'])
    double = impact('double_bell_practice', training_level='novice')
    check('a novice with one bell needs the level and the pair together',
          [u['cause'] for u in double['unblocked_by']] == ['combined']
          and 'at intermediate' in double['unblocked_by'][0]['text']
          and '2 matching bells' in double['unblocked_by'][0]['text'], double['unblocked_by'])
    knee = impact('general_practice', injury_flags=['knee_meniscus_post_op'])
    check('an essential movement an injury rules out refuses, and names the flag',
          [u['cause'] for u in knee['unblocked_by']] == ['injury'], knee.get('unblocked_by'))
    gp = impact('general_practice')
    check('what the level seeds is not asked for', gp['feasible'] and 'proficiency' not in gp['lifted']
          and gp['sessions']['changed'] == 0, (gp.get('lifted'), gp.get('sessions')))


def main() -> int:
    for fn in (test_runs, test_slot_emptied_by_equipment, test_archetype_by_level_and_equipment,
               test_combined_and_alternatives, test_order_and_added_sessions,
               test_knock_on_and_level_locked, test_route, test_contract_rules, test_contract_route):
        fn()
    if FAILURES:
        print(f'{len(FAILURES)} failed')
        return 1
    print('all passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
