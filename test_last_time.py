"""src/last_time.py: what the athlete did last time, per exercise, for the
watches' session screens. No database."""
from src.last_time import describe, last_by_exercise


def test_describe_each_currency():
    assert describe({'sets': [{'completed': True, 'repsActual': 10, 'weightKg': 24},
                              {'completed': True, 'repsActual': 8, 'weightKg': 28},
                              {'completed': False, 'repsActual': 5, 'weightKg': 32}]}) == '28kg × 8', 'heaviest completed set'
    assert describe({'sets': [{'completed': True, 'repsActual': 12}, {'completed': True, 'repsActual': 9}]}) == '12 reps'
    assert describe({'sets': [{'completed': True, 'durationSeconds': 40}, {'completed': True, 'durationSeconds': 45}]}) == '45 s'
    assert describe({'sets': [], 'rounds': 7}) == '7 rounds'
    assert describe({'durationSec': 360, 'sets': [{'completed': True, 'repsActual': 108}]}) == '108 reps in 6 min'
    assert describe({'sets': [], 'distanceKm': 8.4, 'durationSec': 2880}) == '8.4 km'
    assert describe({'sets': [], 'durationSec': 2700}) == '45 min'
    assert describe({'sets': [{'completed': False, 'repsActual': 5}]}) is None


def test_most_recent_earlier_log_wins():
    logs = {
        '1-Monday-0': {'completedAt': '2026-10-05T10:00:00Z', 'exercises': {
            'squat': {'sets': [{'completed': True, 'repsActual': 5, 'weightKg': 100}]},
            'run': {'sets': [], 'durationSec': 1800}}},
        '1-Wednesday-0': {'completedAt': '2026-10-07T10:00:00Z', 'exercises': {
            'squat': {'sets': [{'completed': True, 'repsActual': 5, 'weightKg': 102.5}]},
            'press': {'sets': []}}},
        '1-Friday-0': {'completedAt': '2026-10-09T10:00:00Z', 'exercises': {
            'squat': {'sets': [{'completed': True, 'repsActual': 5, 'weightKg': 105}]}}},
        '1-Saturday-0': {'completedAt': '', 'exercises': {'squat': {'sets': [{'completed': True, 'weightKg': 200}]}}},
    }
    last = last_by_exercise(logs, '2026-10-09')
    assert last == {'squat': '102.5kg × 5', 'run': '30 min'}, last
    assert 'press' not in last, 'a log that says nothing about the exercise is skipped'



def test_a_bad_row_is_skipped_not_raised():
    logs = [
        {'completedAt': '2026-10-08T10:00:00Z', 'exercises': {'run': {'durationSec': '300'}, 'x': {'sets': ['x']},
                                                               'y': {'rounds': 'abc'}}},
        {'completedAt': '2026-10-07T10:00:00Z', 'exercises': 'garbage'},
        'not a log',
        {'completedAt': '2026-10-06T10:00:00Z', 'exercises': {'run': {'sets': [], 'durationSec': 1500}}},
    ]
    assert last_by_exercise(logs, '2026-10-09') == {'run': '25 min'}


if __name__ == '__main__':
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn(); print('ok', name)
    print('all passed')
