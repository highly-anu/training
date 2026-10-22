"""Weeks the source writes day by day (src/week_template.py), on hand-built
categories and workouts; then Horsemen's 4-Month Macro generated as written.

    .venv/bin/python test_week_template.py
"""
import os
import sys

os.environ.setdefault('SUPABASE_URL', '')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import week_template as wt  # noqa: E402

CATS = {
    'warm': {'name': 'Warm-up', 'modality': 'mixed_modal_conditioning', 'archetypes': ['w1', 'w2'], 'warm_up': False},
    'str': {'name': 'Strength', 'modality': 'max_strength', 'archetypes': ['s1', 's2', 's3']},
    'pe': {'name': 'Power endurance', 'modality': 'mixed_modal_conditioning', 'archetypes': ['p1'], 'fallback': ['rec']},
    'rec': {'name': 'Recovery', 'modality': 'aerobic_base', 'archetypes': ['r1'], 'warm_up': False},
}
FW = {'categories': CATS, 'warm_up_category': 'warm'}


def _arch(aid, minutes, equipment=()):
    return {'id': aid, 'name': aid.upper(), 'duration_estimate_minutes': minutes,
            'required_equipment': list(equipment),
            'slots': [{'role': 'main', 'slot_type': 'rounds_for_time', 'load': '24 kg (53 lb)'},
                      {'role': 'b', 'slot_type': 'amrap_movement', 'parent_slot_role': 'main'}]}


ARCH = {a['id']: a for a in [_arch('w1', 10), _arch('w2', 15), _arch('s1', 50), _arch('s2', 40, ['sled']),
                              _arch('s3', 70), _arch('p1', 30, ['tire']), _arch('r1', 40)]}
TEMPLATE = ['str', 'pe', ['str', 'pe'], {'categories': ['rec'], 'warm_up': True}, 'str', 'rec', 'rest']


def _fits(equipment):
    return lambda a, minutes: a['duration_estimate_minutes'] <= minutes and set(a['required_equipment']) <= set(equipment)


def test_days_drop_in_order_and_keep_their_positions():
    kept, dropped = wt.training_days(TEMPLATE, 4, ['rec', 'pe'], CATS)
    assert [d for d, _ in kept] == [1, 2, 3, 5], kept
    assert dropped == ['Recovery', 'Recovery'], dropped
    kept, _ = wt.training_days(TEMPLATE, 3, ['rec', 'pe'], CATS)
    assert [d for d, _ in kept] == [1, 3, 5], 'the last power-endurance day goes after recovery'
    # Preferred days take the kept days in order; a forced rest day moves to the nearest free day.
    assert [d for d, _ in wt.place_days(kept, [2, 4, 6], [])] == [2, 4, 6]
    assert [d for d, _ in wt.place_days(kept, [], [3])] == [1, 2, 5]


def test_rotation_equipment_time_and_fallback():
    rotation = {}
    entry = {'week_template': TEMPLATE, 'drop_order': ['rec']}
    week, notes = wt.plan_week(entry, FW, {'days_per_week': 6, 'session_time_minutes': 60}, ARCH,
                               rotation, _fits([]))
    # s2 needs a sled and s3 is too long: strength rotates s1, s1, s1.
    assert [week[d][0]['pieces'][0]['archetype_id'] for d in (1, 5)] == ['s1', 's1']
    # p1 needs a tire: power endurance falls back to recovery, and the week says so.
    assert week[2][0]['category'] == 'rec' and any('Power endurance' in n for n in notes), notes
    # Day 3 does two pieces when both fit: s1 (50) leaves 10 minutes, nothing fits.
    assert [p['archetype_id'] for p in week[3][0]['pieces']] == ['s1'], week[3]
    # The warm-up opens a strength day; a recovery day opens with one only when the template says so.
    assert week[1][0]['warm_up']['archetype_id'] == 'w1' and 'warm_up' not in week[6][0]
    assert 'warm_up' in week[4][0]
    with_sled, _ = wt.plan_week(entry, FW, {'days_per_week': 6, 'session_time_minutes': 60}, ARCH,
                                {}, _fits(['sled', 'tire']))
    assert [with_sled[d][0]['pieces'][0]['archetype_id'] for d in (1, 3, 5)] == ['s1', 's2', 's1']
    assert with_sled[2][0]['category'] == 'pe'


def test_compose_prefixes_roles_and_marks_light_days():
    arch = wt.compose([('str', ARCH['s1']), ('pe', ARCH['p1'])], ARCH['w1'], True, CATS)
    roles = [s['role'] for s in arch['slots']]
    assert roles == ['warm_up__w1__main', 'warm_up__w1__b', 'main', 'b', 'p1__main', 'p1__b'], roles
    assert arch['slots'][5]['parent_slot_role'] == 'p1__main'
    # A swap finds a borrowed slot in its own archetype.
    assert wt.source_slot('s1', 'warm_up__w1__main') == ('w1', 'main')
    assert wt.source_slot('s1', 'p1__b') == ('p1', 'b') and wt.source_slot('s1', 'main') == ('s1', 'main')
    assert arch['id'] == 's1' and arch['name'] == 'S1 + P1' and arch['duration_estimate_minutes'] == 90
    assert arch['slots'][2]['load'].startswith('Light, work on form (written: 24 kg')
    assert arch['slots'][0]['load'] == '24 kg (53 lb)', 'the warm-up is never lightened'
    assert set(arch['required_equipment']) == {'tire'}


_EQUIPMENT = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'rings', 'box',
              'sandbag', 'medicine_ball', 'rower', 'ghd', 'rope', 'sled', 'tire', 'jump_rope', 'open_space']


def _horsemen(**overrides):
    from src import goals, loader
    from src.generator import generate
    goal = goals.philosophy_to_goal('horsemen_gpp', list(loader.load_all_frameworks().values()), 'four_month_macro')
    c = dict(equipment=list(_EQUIPMENT),
             days_per_week=6, session_time_minutes=120, training_level='intermediate')
    c.update(overrides)
    return generate(None, c, num_weeks=16, goal_dict=goal, output_format='dict'), goal


def test_horsemen_runs_the_source_weeks_as_written():
    p, goal = _horsemen()
    assert len(p['weeks']) == 16, p.get('validation_errors')
    first = p['weeks'][0]
    cats = [first['schedule'][d][0].get('category') for d in sorted(first['schedule'])]
    assert cats == ['strength', 'job_specific_long', 'power_endurance', 'smmf', 'strength', 'recovery'], cats
    named = {s['archetype']['id'] for w in p['weeks'] for ss in w['schedule'].values() for s in ss}
    assert len(named) >= 40, f'the rotation reaches {len(named)} workouts in 16 weeks'
    for w in p['weeks']:
        for ss in w['schedule'].values():
            for s in ss:
                for ea in s['exercises']:
                    load = ea.get('load') or {}
                    assert 'weight_kg' not in load, 'no load is computed: the source writes it'
    tests = [(w['week_number'], s['test']['archetype']) for w in p['weeks'] for ss in w['schedule'].values()
             for s in ss if s.get('test')]
    assert tests == [(2, 'horsemen_pt_test'), (16, 'horsemen_pt_test')], tests


def test_horsemen_without_the_equipment_passes_workouts_over():
    p, _ = _horsemen(equipment=['kettlebell', 'pull_up_bar', 'open_space'], days_per_week=4,
                     session_time_minutes=60)
    assert len(p['weeks']) == 16, p.get('validation_errors')
    from src import loader
    arch = {a['id']: a for a in loader.load_all_archetypes()}
    for w in p['weeks']:
        assert len(w['schedule']) <= 4
        for ss in w['schedule'].values():
            for s in ss:
                for piece in s.get('pieces') or []:
                    need = set(arch[piece['archetype_id']].get('required_equipment') or []) - {'open_space'}
                    assert need <= {'kettlebell', 'pull_up_bar'}, (piece, need)
    assert any('leaves out' in c for c in p['compromises']), p['compromises'][:5]



def test_a_regenerate_from_mid_track_carries_on_the_rotation():
    # "From tomorrow": the tail starts at a later week and must plan exactly
    # what the whole track planned there, warm-ups included.
    def picks(week):
        return [(d, [p['archetype_id'] for p in s.get('pieces') or []], (s.get('warm_up') or {}).get('archetype_id'))
                for d, ss in sorted(week['schedule'].items()) for s in ss]
    whole, _ = _horsemen()
    for phase, week, index in (('strength', 3, 2), ('power_endurance', 2, 5), ('job_specific', 1, 8), ('maintenance', 4, 15)):
        tail, _ = _horsemen(start_phase=phase, periodization_week=week)
        assert picks(tail['weeks'][0]) == picks(whole['weeks'][index]), (phase, week)


def test_long_days_take_the_long_template_days():
    cats = {**CATS, 'long': {'name': 'Long', 'modality': 'durability', 'archetypes': ['s3'], 'long_day': True}}
    entry = {'week_template': ['str', 'long', 'str', 'rest', 'rest', 'rest', 'rest'], 'drop_order': []}
    c = {'days_per_week': 3, 'session_time_minutes': 90, 'preferred_days': [1, 2, 6],
         'day_configs': {1: {'minutes': 60}, 2: {'minutes': 60}, 6: {'minutes': 90}}}
    week, _ = wt.plan_week(entry, {'categories': cats, 'warm_up_category': 'warm'}, c, ARCH, {}, _fits([]))
    assert week[6][0]['category'] == 'long' and week[1][0]['category'] == week[2][0]['category'] == 'str', week



def test_routes_regenerate_and_swap_a_templated_day():
    import api
    client = api.app.test_client()
    p, _ = _horsemen()
    c = dict(equipment=list(_EQUIPMENT), days_per_week=6, session_time_minutes=120,
             training_level='intermediate')
    # One day regenerated: another named workout of its category, as written.
    r = client.post('/api/sessions/generate', json={
        'modality': 'max_strength', 'phase': 'base', 'phase_id': 'strength', 'framework_id': 'concurrent_training',
        'category': 'strength', 'current_archetype_id': 'hm_tongue_lashing', 'constraints': c,
        'philosophy_ids': ['horsemen_gpp'], 'primary_sources': ['horsemen_gpp']})
    assert r.status_code == 200, r.get_json()
    body = r.get_json()
    assert body['category'] == 'strength' and body['archetype']['pool_only'] and body['warm_up'], body.get('category')
    assert body['archetype']['id'] != 'hm_tongue_lashing'
    # A warm-up slot swaps in its own archetype, and keeps the session's role.
    s = next(s for w in p['weeks'] for ss in w['schedule'].values() for s in ss if s.get('warm_up'))
    ea = next(e for e in s['exercises'] if e['slot_role'].startswith('warm_up__') and e.get('exercise'))
    r = client.post('/api/exercises/substitute', json={
        'archetype_id': s['archetype']['id'], 'slot_role': ea['slot_role'], 'exercise_id': ea['exercise']['id'],
        'constraints': c, 'philosophy_ids': ['horsemen_gpp'], 'framework_id': 'concurrent_training'})
    # Found (it used to 404); an as-written slot offers only the source's own
    # substitutes, so a movement with none answers 422 "no alternative".
    assert r.status_code == 200 or (r.status_code == 422 and 'No alternative' in r.get_json()['detail']), r.get_json()
    for a in r.get_json().get('alternatives') or []:
        assert a['assignment']['slot_role'] == ea['slot_role']



def test_crossfit_runs_glassmans_cycle_and_the_girls_as_written():
    # R1, R3, R5-R8: three on, one off, the days cycling through one, two and
    # three elements, Table 4's workouts first; R10, R11: the Girls in the
    # pools as written, each a selectable test of its standard.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    goal = goals.philosophy_to_goal('crossfit', list(loader.load_all_frameworks().values()), 'constantly_varied')
    c = dict(equipment=list(ALL_EQUIPMENT) + ['rings'], days_per_week=6, session_time_minutes=60,
             training_level='intermediate')
    p = generate(None, c, num_weeks=12, goal_dict=goal, output_format='dict')
    days = [(w['week_number'], d, s) for w in p['weeks'] for d, ss in sorted(w['schedule'].items()) for s in ss]
    cycle = ['m', 'gw', 'triplet', None, 'g', 'wm', 'triplet', None, 'w', 'mg', 'triplet', None]
    for wk, d, s in days:
        assert s.get('category') == cycle[(7 * (wk - 1) + d - 1) % 12], (wk, d, s.get('category'))
    rest = {(w['week_number'], d) for w in p['weeks'] for d in range(1, 8) if d not in w['schedule']}
    assert all(cycle[(7 * (wk - 1) + d - 1) % 12] is None for wk, d in rest), 'rest falls on every fourth day'
    names = [s['archetype']['id'] for _, _, s in days]
    assert names[:6] == ['cf_run_10k', 'cf_hspu_deadlift_couplet', 'cf_run_pull_thruster_triplet',
                         'cf_handstand_practice', 'cf_bench_row_couplet', 'cf_lunge_press_row_triplet'], names[:6]
    assert {'cf_fran', 'cf_cindy', 'cf_helen'} <= set(names) and len(set(names)) >= 35, len(set(names))
    fran = next(s for _, _, s in days if s['archetype']['id'] == 'cf_fran')
    head = next(e for e in fran['exercises'] if e.get('standard'))
    assert head['exercise']['id'] == 'thruster' and head['standard']['id'] == 'wod_fran_minutes'
    assert '95 lb' in head['load']['load_note'] and head['load']['target_rounds'] == 3
    deadlift = next(s for _, _, s in days if s['archetype']['id'] == 'cf_deadlift_5_3_3_2')
    assert deadlift['exercises'][0]['load']['reps'] == '5-3-3-2-2-2-1-1-1'
    assert not any(w['is_deload'] for w in p['weeks']), 'no deload: the rest day is the rest (R14)'


def test_gym_jones_runs_its_two_months_as_written():
    # R4, R9: each plan's 28 days in order, six a week and the seventh rest;
    # R10: a novice with no track named gets Soldier of Steel and cannot take
    # Operator Fitness; R12: no deload week.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    frameworks = list(loader.load_all_frameworks().values())

    def month(level, track=None):
        goal = goals.philosophy_to_goal('gym_jones', frameworks, track, level)
        c = dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=120, training_level=level)
        return generate(None, c, num_weeks=4, goal_dict=goal, output_format='dict'), goal

    for level, track, prefix in (('intermediate', 'operator_fitness', 'gj_of_d'), ('novice', None, 'gj_sos_d')):
        p, goal = month(level, track)
        assert goal['track']['id'] == (track or 'soldier_of_steel'), goal['track']['id']
        ids = [[s['archetype']['id'] for d in range(1, 8) for s in w['schedule'].get(d, [])] for w in p['weeks']]
        assert ids == [[f'{prefix}{7 * k + d:02d}' for d in range(1, 7)] for k in range(4)], ids
        assert all(7 not in w['schedule'] for w in p['weeks']), 'the seventh day rests'
        assert not any(w['is_deload'] for w in p['weeks'])
    p, _ = month('intermediate', 'operator_fitness')
    hike = p['weeks'][0]['schedule'][6][0]['exercises'][0]
    assert hike['exercise']['id'] == 'ruck' and '20-30 lb' in hike['load']['load_note'], hike['load']
    p, _ = month('novice', 'operator_fitness')
    assert not p['weeks'], 'Operator Fitness is not written for the newly training'


def test_atg_runs_its_programs_as_written():
    # R1-R3: each program's workouts on their days, every week the same; R1:
    # Zero needs no equipment; R4, R5: the sled leads, the upper body comes
    # last, and walking backward stands in for the sled; R7: no deload.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    frameworks = list(loader.load_all_frameworks().values())

    def block(level, track, days, equipment=ALL_EQUIPMENT, minutes=60):
        goal = goals.philosophy_to_goal('atg', frameworks, track, level)
        c = dict(equipment=list(equipment), days_per_week=days, session_time_minutes=minutes, training_level=level)
        return generate(None, c, num_weeks=4, goal_dict=goal, output_format='dict'), goal

    def week_ids(w):
        return {d: [s['archetype']['id'] for s in w['schedule'].get(d, [])] for d in range(1, 8) if w['schedule'].get(d)}

    for level, track, days, equipment, want in (
            ('novice', None, 3, (), {1: ['atg_zero'], 3: ['atg_zero'], 5: ['atg_zero']}),
            ('intermediate', None, 2, ALL_EQUIPMENT, {1: ['atg_p2_w1'], 4: ['atg_p2_w2']}),
            ('advanced', None, 4, ALL_EQUIPMENT,
             {1: ['atg_pro_mon'], 2: ['atg_pro_tue'], 4: ['atg_pro_thu'], 5: ['atg_pro_fri']})):
        p, goal = block(level, track, days, equipment)
        assert len(p['weeks']) == 4, (goal['track']['id'], p.get('validation'))
        assert all(week_ids(w) == want for w in p['weeks']), [week_ids(w) for w in p['weeks']]
        assert not any(w['is_deload'] for w in p['weeks'])
    p, _ = block('intermediate', 'program', 2)
    roles = [ea['slot']['role'] for ea in p['weeks'][0]['schedule'][1][0]['exercises']]
    assert roles[0] == 'sled' and roles[-1] == 'shoulder_press', roles
    sled = p['weeks'][0]['schedule'][1][0]['exercises'][0]
    assert sled['exercise']['id'] == 'sled_forward_backward', sled['exercise']['id']
    p, _ = block('intermediate', 'program', 2, [e for e in ALL_EQUIPMENT if e != 'sled'])
    assert p['weeks'][0]['schedule'][1][0]['exercises'][0]['exercise']['id'] == 'backward_walk'
    p, _ = block('novice', 'knee_ability_pro', 4)
    assert not p['weeks'], 'Knee Ability Pro is written for trained athletes'


def test_kelly_starrett_runs_the_21_day_challenge_as_written():
    # R1: Days 1-21 in order, every day, needing no equipment; R3: floor
    # sitting every day; R7: then day 21 every day, no deload.
    from src import goals, loader
    from src.generator import generate
    frameworks = list(loader.load_all_frameworks().values())
    goal = goals.philosophy_to_goal('kelly_starrett', frameworks, None, 'novice')
    c = dict(equipment=[], days_per_week=7, session_time_minutes=30, training_level='novice')
    p = generate(None, c, num_weeks=5, goal_dict=goal, output_format='dict')
    ids = [s['archetype']['id'] for w in p['weeks'] for d in range(1, 8) for s in w['schedule'].get(d, [])]
    assert ids == [f'btm_d{n:02d}' for n in range(1, 22)] + ['btm_d21'] * 14, ids
    sessions = [s for w in p['weeks'] for d in range(1, 8) for s in w['schedule'].get(d, [])]
    assert all(any(ea['exercise']['id'] == 'floor_sitting' for ea in s['exercises']) for s in sessions)
    assert not any(w['is_deload'] for w in p['weeks'])
    c['days_per_week'] = 5
    assert not generate(None, c, num_weeks=3, goal_dict=goal, output_format='dict')['weeks'], 'the challenge is daily'


def test_ido_portal_runs_the_floreio_routines_at_each_level():
    # R1: the routines in the PDF's order, each at the athlete's level (R2);
    # R3: the preparation opens every routine; R6: no deload.
    from src import goals, loader
    from src.generator import generate
    from src.package_eval import ALL_EQUIPMENT
    frameworks = list(loader.load_all_frameworks().values())
    goal = goals.philosophy_to_goal('ido_portal', frameworks, None, 'novice')
    suffix = {'novice': ('_b', '_bi', 'w3'), 'intermediate': ('_i', '_bi', 'w3'), 'advanced': ('_a', 'w3')}
    for level, ends in suffix.items():
        c = dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=90, training_level=level)
        p = generate(None, c, num_weeks=3, goal_dict=goal, output_format='dict')
        ids = [s['archetype']['id'] for w in p['weeks'] for d in range(1, 8) for s in w['schedule'].get(d, [])]
        assert len(ids) == 18 and all(i.endswith(ends) for i in ids), (level, ids)
        assert len(set(ids[:13])) == 13, ('thirteen routines before one repeats', level, ids)
        assert all(7 not in w['schedule'] for w in p['weeks'])
        assert not any(w['is_deload'] for w in p['weeks'])
        first = p['weeks'][0]['schedule'][1][0]['exercises'][0]['exercise']['id']
        assert first in ('jump_rope', 'joint_mobility'), first
    order = [s['archetype']['id'] for d in range(1, 7)
             for s in generate(None, dict(equipment=list(ALL_EQUIPMENT), days_per_week=6, session_time_minutes=90,
                                          training_level='novice'), num_weeks=1, goal_dict=goal,
                               output_format='dict')['weeks'][0]['schedule'][d]]
    assert order == ['ido_basic_b', 'ido_w1_b', 'ido_w2_bi', 'ido_w3', 'ido_w4_b', 'ido_w5_b'], order


if __name__ == '__main__':
    failed = 0
    for name, fn in list(globals().items()):
        if name.startswith('test_') and callable(fn):
            try:
                fn()
                print('ok', name)
            except Exception as exc:  # noqa: BLE001
                failed += 1
                print('FAIL', name, repr(exc))
    print('all passed' if not failed else f'{failed} failed')
    sys.exit(1 if failed else 0)
