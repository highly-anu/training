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
    flat = generator._build_phase_entries([], 'base', 2, 3, first_week_number=3)
    assert [e['week_in_program'] for e in flat] == [3, 4, 5]
    assert [e['week_in_phase'] for e in flat] == [2, 3, 4]

    seq = [{'phase': 'base', 'weeks': 4}, {'phase': 'build', 'weeks': 2}]
    tail = generator._build_phase_entries(seq, 'base', 3, 4, first_week_number=3)
    assert [(e['phase'], e['week_in_phase'], e['week_in_program']) for e in tail] == [
        ('base', 3, 3), ('base', 4, 4), ('build', 1, 5), ('build', 2, 6),
    ]
    whole = generator._build_phase_entries(seq, 'base', 1, 6)
    assert [e['week_in_program'] for e in whole] == [1, 2, 3, 4, 5, 6], 'a full generate still starts at 1'
    assert generator._build_phase_entries([], 'base', 1, 2, first_week_number=0)[0]['week_in_program'] == 1


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


if __name__ == '__main__':
    test_phase_entries_number_from_the_first_week()
    test_route_numbers_the_tail_and_defaults_to_one()
    print('All week numbering tests passed.')
