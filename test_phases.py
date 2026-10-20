"""Tracks and phases: every philosophy owns its phases, and the engine keeps them.

No DB: the loader, the goal builder, the generator, the event-date calendar and
the generate route through the Flask test client.

    SUPABASE_URL='' .venv/bin/python test_phases.py
"""
import os
import re
from datetime import date, timedelta

os.environ.setdefault('SUPABASE_URL', '')

from src import generator, goals, loader, phases  # noqa: E402
from src.phase_calendar import build_remaining_schedule, compute_phase_from_date  # noqa: E402

FRAMEWORKS = list(loader.load_all_frameworks().values())
PHILS = loader.load_philosophies()

CONSTRAINTS = {
    'training_level': 'intermediate', 'days_per_week': 5, 'session_time_minutes': 75,
    'equipment': ['barbell', 'rack', 'plates', 'kettlebell', 'pull_up_bar', 'ruck_pack',
                  'open_space', 'box', 'sandbag', 'dumbbell', 'sled'],
    'injury_flags': [], 'periodization_week': 1, 'fatigue_state': 'normal',
}


def ok(cond, msg):
    assert cond, msg
    print(f'  ok   {msg}')


def _gen(goal, constraints, num_weeks):
    return generator.generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                              num_weeks=num_weeks, output_format='dict')


def test_every_package_owns_its_tracks():
    for phil in PHILS:
        own = {os.path.splitext(f)[0] for f in os.listdir(
            os.path.join('data', 'packages', phil['id'], 'frameworks'))}
        errs = phases.validate_philosophy_tracks(phil, own)
        ok(not errs, f"{phil['id']} declares valid tracks on its own frameworks {errs or ''}")
        ok(not any(k in phil for k in ('framework_groups', 'canonical_phase_sequence',
                                       'primary_framework_id')),
           f"{phil['id']} carries none of the retired phase keys")


def test_no_phase_text_names_another_philosophy():
    # The bug this replaces: Wildman's base phase described in Uphill's words,
    # its build phase in Gym Jones's. A package's phase text may name only itself.
    names = {}
    for phil in PHILS:
        short = phil['name'].split(' —')[0].split(' /')[0].strip()
        names[phil['id']] = {short, phil['id'].replace('_', ' ')}
    names['uphill_athlete'] |= {'Uphill'}
    names['gym_jones'] |= {'Twight'}
    names['crossfit'] |= {'CrossFit'}
    names['marcus_filly'] |= {'Filly'}
    names['starting_strength'] |= {'Rippetoe'}
    names['horsemen_gpp'] |= {'Horsemen'}
    for phil in PHILS:
        text = ' '.join(
            str(v) for t in phil['tracks'] for v in
            [t.get('name'), t.get('description')] + [
                x for ph in t['phases'] for x in
                [ph.get('name'), ph.get('focus'), ph.get('description'), ph.get('intensity'),
                 *(ph.get('adaptations') or [])]]
            if v)
        for other, words in names.items():
            if other == phil['id']:
                continue
            hits = [w for w in words if re.search(rf'\b{re.escape(w)}\b', text, re.I)]
            ok(not hits, f"{phil['id']} phase text never names {other}"
               + (f' (found {hits})' if hits else ''))


def test_goal_carries_the_track():
    g = goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS)
    ok(g['track']['id'] == 'general_practice', 'Wildman defaults to its primary track')
    ok([e['phase_id'] for e in g['phase_sequence']] == ['build'],
       "the goal's phases are Wildman's own: one repeatable Phase II")
    ok([phases.resolve_start_phase(g['phase_sequence'], old) for old in ('foundations', 'ladder', 'practice')]
       == ['build'] * 3, "a stored week's former phase id starts the phase that replaced it")
    ok(all(e.get('description') for e in g['phase_sequence']), 'each phase carries its own text')
    p = goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, track_id='pentathlon')
    ok({e['framework_id'] for e in p['phase_sequence']} == {'kb_pentathlon'},
       'the pentathlon track runs on the pentathlon framework')
    try:
        goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, track_id='nope')
        raise AssertionError('an unknown track must raise')
    except phases.PhaseResolutionError:
        ok(True, 'an unknown track is an error')


def test_uphill_starts_at_transition():
    g = goals.philosophy_to_goal('uphill_athlete', FRAMEWORKS)
    weeks = _gen(g, dict(CONSTRAINTS), 6)['weeks']
    ok([w['phase_id'] for w in weeks[:5]] == ['transition'] * 4 + ['base'],
       'with no start given Uphill runs Transition first')
    ok(weeks[0]['framework'] == 'uphill_transition_phase', 'on the transition framework')


def test_event_date_keeps_phase_frameworks():
    g = goals.philosophy_to_goal('uphill_athlete', FRAMEWORKS)
    today = date(2026, 1, 5)
    cal = compute_phase_from_date(g, today + timedelta(weeks=12), today=today)
    sched = build_remaining_schedule(cal)
    by_phase = {e['phase_id']: e['framework_id'] for e in sched}
    ok(by_phase == {'base': 'uphill_base_phase', 'specific': 'uphill_specific_phase',
                    'taper': 'uphill_taper_phase'},
       'every week to the event carries its own phase framework')
    c = dict(CONSTRAINTS, start_phase=cal['phase_id'], periodization_week=cal['week_in_phase'])
    weeks = generator.generate(goal_id=g['id'], goal_dict=g, constraints=c, num_weeks=0,
                               phase_schedule=sched, output_format='dict')['weeks']
    ok({w['phase_id']: w['framework'] for w in weeks} == by_phase,
       'and the generated weeks run those frameworks')


def test_legacy_inputs_map_onto_tracks():
    hit = goals.owner_track_for_framework(['uphill_athlete'], {}, 'uphill_specific_phase')
    ok(hit and hit[1]['id'] == 'full_program' and hit[2]['id'] == 'specific',
       'a legacy framework pick maps to its track and phase')
    hit = goals.owner_track_for_framework(['wildman_kettlebell'], {}, 'kb_pentathlon')
    ok(hit and hit[1]['id'] == 'pentathlon', "Wildman's pentathlon framework picks its track")
    seq = goals.philosophy_to_goal('uphill_athlete', FRAMEWORKS)['phase_sequence']
    ok(phases.resolve_start_phase(seq, None, 'taper') == 'taper', 'a legacy kind maps to its phase')
    ok(phases.resolve_start_phase(seq, None, 'peak') == 'transition',
       'a kind the track lacks starts at the first phase')
    ok(phases.legacy_kind_missing(seq, None, 'peak'), '…and is reported')
    try:
        phases.resolve_start_phase(seq, 'nope', None)
        raise AssertionError('an unknown start_phase must raise')
    except phases.PhaseResolutionError:
        ok(True, 'an unknown start_phase id is an error')


def test_route():
    import api
    client = api.app.test_client()
    r = client.post('/api/programs/generate', json={
        'philosophy_id': 'uphill_athlete', 'framework_id': 'uphill_specific_phase',
        'constraints': dict(CONSTRAINTS), 'num_weeks': 2})
    weeks = r.get_json()['weeks']
    ok([w['framework'] for w in weeks] == ['uphill_specific_phase'] * 2,
       'an explicit framework pick is honoured, not overridden')
    ok(weeks[0]['phase_id'] == 'specific' and weeks[0]['phase_name'] == 'Specific'
       and weeks[0]['track_id'] == 'full_program', 'weeks carry phase id, name and track')

    r = client.post('/api/programs/generate', json={
        'philosophy_id': 'wildman_kettlebell', 'track_id': 'pentathlon',
        'constraints': dict(CONSTRAINTS, mastered_exercises=goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, 'pentathlon')['training_contract']['modules'][0]['requires_mastery']), 'num_weeks': 1})
    body = r.get_json()
    ok(body['weeks'][0]['phase_id'] == 'event_technique', 'a track pick starts at its first phase')
    ok(body['goal']['track']['id'] == 'pentathlon', 'and the goal names the track')

    r = client.post('/api/programs/generate', json={
        'philosophy_id': 'starting_strength', 'constraints': dict(CONSTRAINTS, days_per_week=3,
                                                                  training_phase='base'),
        'num_weeks': 1})
    body = r.get_json()
    ok(body['validation']['feasible'] and body['weeks'][0]['phase_id'] == 'novice_lp',
       "the iOS builder's 'base' still generates for a track without a base phase")

    # The iOS payload: track and start phase inside constraints, the week's
    # kind beside them as the legacy training_phase (a tail regenerate).
    r = client.post('/api/programs/generate', json={
        'philosophy_id': 'wildman_kettlebell',
        'constraints': dict(CONSTRAINTS, days_per_week=4, track_id='pentathlon', start_phase='timed_sets',
                            training_phase='build', phase='build', periodization_week=3,
                            mastered_exercises=goals.philosophy_to_goal('wildman_kettlebell', FRAMEWORKS, 'pentathlon')['training_contract']['modules'][0]['requires_mastery']),
        'num_weeks': 2, 'week_in_program': 7})
    weeks = r.get_json()['weeks']
    ok([(w['track_id'], w['phase_id'], w['week_in_phase']) for w in weeks]
       == [('pentathlon', 'timed_sets', 3), ('pentathlon', 'timed_sets', 4)],
       "the phone's tail regenerate resumes in its own track and phase")

    r = client.post('/api/programs/generate', json={
        'philosophy_id': 'uphill_athlete', 'constraints': dict(CONSTRAINTS, start_phase='nope'),
        'num_weeks': 1})
    ok(not r.get_json()['validation']['feasible'], 'an unknown start phase is infeasible')


if __name__ == '__main__':
    test_every_package_owns_its_tracks()
    test_no_phase_text_names_another_philosophy()
    test_goal_carries_the_track()
    test_uphill_starts_at_transition()
    test_event_date_keeps_phase_frameworks()
    test_legacy_inputs_map_onto_tracks()
    test_route()
    print('\nAll phase tests passed.')
