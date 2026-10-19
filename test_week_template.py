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
