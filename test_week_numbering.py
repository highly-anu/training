"""A partial regenerate's tail continues the week numbering.

No DB: the generator directly, then the route through the Flask test client.
"""
import os
os.environ.setdefault('SUPABASE_URL', '')

from src import generator

CONSTRAINTS = {
    'training_level': 'intermediate', 'days_per_week': 3, 'session_time_minutes': 60,
    'equipment': ['barbell', 'rack', 'plates', 'pull_up_bar', 'open_space'],
    'injury_flags': [],
}


def test_phase_entries_number_from_the_first_week():
    seq = [{'phase_id': 'acc', 'phase': 'base', 'weeks': 4, 'framework_id': 'fw_a'},
           {'phase_id': 'int', 'phase': 'build', 'weeks': 2, 'framework_id': 'fw_b'}]
    tail = generator._build_phase_entries(seq, 'acc', 3, 4, first_week_number=3)
    assert [(e['phase'], e['week_in_phase'], e['week_in_program']) for e in tail] == [
        ('base', 3, 3), ('base', 4, 4), ('build', 1, 5), ('build', 2, 6),
    ]
    assert [e['framework_id'] for e in tail] == ['fw_a', 'fw_a', 'fw_b', 'fw_b']
    whole = generator._build_phase_entries(seq, None, 1, 6)
    assert [e['week_in_program'] for e in whole] == [1, 2, 3, 4, 5, 6], 'a full generate still starts at 1'
    assert generator._build_phase_entries(seq, 'acc', 1, 2, first_week_number=0)[0]['week_in_program'] == 1

    # Past the end of the sequence the last phase continues — on its framework,
    # with its week count running on rather than restarting at 1.
    padded = generator._build_phase_entries(seq, 'int', 1, 4)
    assert [(e['phase_id'], e['week_in_phase'], e['framework_id']) for e in padded] == [
        ('int', 1, 'fw_b'), ('int', 2, 'fw_b'), ('int', 3, 'fw_b'), ('int', 4, 'fw_b'),
    ]


def test_tail_crossing_a_phase_resumes_in_the_right_phase():
    # A regenerate from week 10 of a 4-month macro (4 weeks per month) sends the
    # target week's own phase and week_in_phase; the tail continues there
    # instead of restarting the first phase.
    import api
    client = api.app.test_client()
    c = dict(CONSTRAINTS, days_per_week=5, periodization_week=2, start_phase='job_specific')
    r = client.post('/api/programs/generate', json={
        'philosophy_id': 'horsemen_gpp', 'constraints': c, 'num_weeks': 5, 'week_in_program': 10})
    assert r.status_code == 200, r.get_json()
    weeks = r.get_json()['weeks']
    assert [(w['phase_id'], w['week_in_phase'], w['week_number']) for w in weeks] == [
        ('job_specific', 2, 10), ('job_specific', 3, 11), ('job_specific', 4, 12),
        ('maintenance', 1, 13), ('maintenance', 2, 14),
    ]


def test_route_numbers_the_tail_and_defaults_to_one():
    import api
    client = api.app.test_client()
    body = {'philosophy_id': 'starting_strength', 'constraints': dict(CONSTRAINTS, periodization_week=2),
            'num_weeks': 2, 'week_in_program': 3}
    r = client.post('/api/programs/generate', json=body)
    assert r.status_code == 200, r.get_json()
    weeks = r.get_json()['weeks']
    assert [w['week_number'] for w in weeks] == [3, 4]
    assert [w['week_in_phase'] for w in weeks] == [2, 3], 'the phase continues from periodization_week'

    r = client.post('/api/programs/generate', json={'philosophy_id': 'starting_strength',
                                                    'constraints': CONSTRAINTS, 'num_weeks': 2})
    assert [w['week_number'] for w in r.get_json()['weeks']] == [1, 2]

    r = client.post('/api/programs/generate', json={'philosophy_id': 'starting_strength',
                                                    'constraints': CONSTRAINTS, 'num_weeks': 1,
                                                    'week_in_program': 'nonsense'})
    assert r.get_json()['weeks'][0]['week_number'] == 1, 'garbage is treated as unset'


def test_envelope_recovers_its_sources_from_the_goal():
    # A regenerate that names no philosophy still records which ones built the
    # program: one from '_phil_<id>', a blend from the goal's primary_sources.
    import api
    one = {'goal': {'id': '_phil_uphill_athlete', 'primary_sources': ['uphill_athlete']}}
    assert api._goal_ids_from_body({}, one)[0] == ['uphill_athlete']
    blend = {'goal': {'id': '_phil_blend', 'primary_sources': ['uphill_athlete', 'horsemen_gpp']}}
    assert api._goal_ids_from_body({}, blend)[0] == ['uphill_athlete', 'horsemen_gpp']
    assert api._goal_ids_from_body({}, {'goal': {'id': '_phil_blend'}})[0] == [], 'never "blend"'
    assert api._goal_ids_from_body({'philosophy_id': 'x'}, blend)[0] == ['x'], 'the request wins'


if __name__ == '__main__':
    test_phase_entries_number_from_the_first_week()
    test_route_numbers_the_tail_and_defaults_to_one()
    test_tail_crossing_a_phase_resumes_in_the_right_phase()
    test_envelope_recovers_its_sources_from_the_goal()
    print('All week numbering tests passed.')
