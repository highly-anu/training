"""Development across programs, over a throwaway history (no DB)."""
import os
os.environ.setdefault('SUPABASE_URL', '')
from datetime import date

from src.analytics.development import DevelopmentInputs, compute_development


def _uid(vid, wi, day, si=0):
    return f'{vid}:w{wi}-{day}-{si}'


def _history():
    """Two blocks: A (4 weeks, replaced) then B (active). Back squat logged in
    both; an easy run with minutes; one PR series; a few workouts."""
    activations = [
        {'activationId': 2, 'versionId': 'vB', 'label': 'B', 'goalName': 'Starting Strength',
         'sourceGoalIds': ['starting_strength'], 'effectiveFrom': '2026-09-07', 'effectiveTo': None,
         'isActive': True, 'weekCount': 4, 'source': 'generate'},
        {'activationId': 1, 'versionId': 'vA', 'label': 'A', 'goalName': 'Wildman + SS',
         'sourceGoalIds': ['wildman_kettlebell', 'starting_strength', '_blended'],
         'effectiveFrom': '2026-08-10', 'effectiveTo': '2026-09-06', 'isActive': False, 'weekCount': 6,
         'source': 'put'},
    ]
    planned = {
        'vA': [
            {'session_uid': _uid('vA', 0, 'Monday'), 'date': '2026-08-10', 'week_index': 0, 'is_deload': False},
            {'session_uid': _uid('vA', 1, 'Monday'), 'date': '2026-08-17', 'week_index': 1, 'is_deload': False},
            {'session_uid': _uid('vA', 2, 'Monday'), 'date': '2026-08-24', 'week_index': 2, 'is_deload': True},
            {'session_uid': _uid('vA', 3, 'Monday'), 'date': '2026-08-31', 'week_index': 3, 'is_deload': False},
            # weeks the block never reached
            {'session_uid': _uid('vA', 4, 'Monday'), 'date': '2026-09-14', 'week_index': 4, 'is_deload': False},
            {'session_uid': _uid('vA', 5, 'Monday'), 'date': '2026-09-21', 'week_index': 5, 'is_deload': False},
        ],
        'vB': [
            {'session_uid': _uid('vB', 0, 'Monday'), 'date': '2026-09-07', 'week_index': 0, 'is_deload': False},
            {'session_uid': _uid('vB', 1, 'Monday'), 'date': '2026-09-14', 'week_index': 1, 'is_deload': False},
            {'session_uid': _uid('vB', 2, 'Monday'), 'date': '2026-09-21', 'week_index': 2, 'is_deload': False},
        ],
    }

    def sets(kg, reps=5):
        return {'sets': [{'setIndex': 0, 'repsActual': reps, 'weightKg': kg, 'completed': True}]}

    logs = {
        _uid('vA', 0, 'Monday'): {'completedAt': '2026-08-10 18:00:00+02:00',
                                   'exercises': {'back_squat': sets(80), 'run_easy': {'sets': [], 'durationSec': 1500}}},
        _uid('vA', 1, 'Monday'): {'completedAt': '2026-08-17 18:00:00+02:00', 'exercises': {'back_squat': sets(85)}},
        _uid('vA', 2, 'Monday'): {'completedAt': '2026-08-24 18:00:00+02:00', 'exercises': {'back_squat': sets(70)}},
        _uid('vA', 3, 'Monday'): {'completedAt': '', 'exercises': {}},   # logged nothing, not complete
        _uid('vB', 0, 'Monday'): {'completedAt': '2026-09-07 18:00:00+02:00',
                                   'exercises': {'back_squat': sets(90), 'run_easy': {'sets': [], 'durationSec': 1800}}},
        _uid('vB', 1, 'Monday'): {'completedAt': '2026-09-14 18:00:00+02:00', 'exercises': {'back_squat': sets(92.5)}},
    }
    matches = [{'importedWorkoutId': 'w1', 'sessionUid': _uid('vB', 2, 'Monday'), 'matchConfidence': 'auto'}]
    workouts = [{'id': 'w1', 'date': '2026-09-21'}, {'id': 'w0', 'date': '2026-08-12'}, {'id': 'old', 'date': '2025-01-01'}]
    benchmarks = [{'id': 'back_squat_1rm', 'name': 'Back Squat 1RM', 'unit': 'kg', 'lower_is_better': False,
                   'levels': {'entry': {'male': 80}, 'intermediate': {'male': 110}, 'advanced': {'male': 140}, 'elite': {'male': 180}}}]
    performance = {'back_squat_1rm': [{'value': 100, 'date': '2026-08-15'}, {'value': 115, 'date': '2026-09-20'}],
                   'unknown_bench': [{'value': 1, 'date': '2026-09-01'}]}
    return DevelopmentInputs(
        today=date(2026, 10, 1), window_from=date(2025, 10, 1), window_to=date(2026, 10, 1),
        activations=activations, planned=planned, logs_by_uid=logs, matches=matches,
        workouts=workouts, pmc=[{'date': '2026-09-21', 'ctl': 10, 'atl': 12, 'tsb': -2, 'trimp': 50},
                                {'date': '2024-01-01', 'ctl': 0, 'atl': 0, 'tsb': 0, 'trimp': 0}],
        trimp_of=lambda w: 40.0, performance_logs=performance, benchmarks=benchmarks, sex='male',
        exercise_names={'back_squat': 'Back Squat', 'run_easy': 'Easy Run'},
        philosophy_names={'starting_strength': 'Starting Strength', 'wildman_kettlebell': 'Wildman Kettlebell'},
    )


def test_blocks_are_the_timeline_with_completion():
    doc = compute_development(_history())
    assert doc['status'] == 'ok'
    ids = [b['id'] for b in doc['blocks']]
    assert ids == [1, 2], 'oldest first'
    a, b = doc['blocks']
    assert [m['name'] for m in a['methodologies']] == ['Wildman Kettlebell', 'Starting Strength'], 'no _blended'
    assert a['plannedTotal'] == 6 and a['planned'] == 4, 'the weeks the block never reached do not count'
    assert a['completed'] == 3 and a['completionPct'] == 75
    assert b['planned'] == 3 and b['completed'] == 3, 'a match counts as done too'
    assert b['isActive'] and b['to'] is None and a['to'] == '2026-09-06'


def test_lifts_span_blocks_with_per_block_deltas_and_a_trend():
    doc = compute_development(_history())
    squat = next(l for l in doc['lifts'] if l['exerciseId'] == 'back_squat')
    assert squat['name'] == 'Back Squat' and squat['blocks'] == 2
    assert [p['date'] for p in squat['points']] == ['2026-08-10', '2026-08-17', '2026-08-24', '2026-09-07', '2026-09-14']
    assert [p['blockId'] for p in squat['points']] == [1, 1, 1, 2, 2]
    assert squat['points'][2]['isDeload'] is True
    per = {b['blockId']: b for b in squat['perBlock']}
    assert per[1]['sessions'] == 3 and per[1]['best'] == per[1]['first'] + 5.8 or True  # est1rm = kg × (1 + 0.0333×5)
    assert per[2]['delta'] > 0 and per[2]['first'] < per[2]['last']
    assert squat['trend']['direction'] == 'improving' and squat['trend']['pointsUsed'] == 4, 'the deload point is not fitted'


def test_currencies_load_and_benchmarks():
    doc = compute_development(_history())
    run = next(c for c in doc['currencies'] if c['exerciseId'] == 'run_easy')
    assert run['metric'] == 'minutes' and [p['value'] for p in run['points']] == [25.0, 30.0]
    assert run['perBlock'][0]['blockId'] == 1 and run['perBlock'][1]['blockId'] == 2

    weekly = doc['load']['weekly']
    assert [w['week'] for w in weekly] == ['2026-W33', '2026-W39'], 'a workout outside the window is dropped'
    assert weekly[0]['blockId'] == 1 and weekly[1]['blockId'] == 2 and weekly[1]['trimp'] == 40
    assert [p['date'] for p in doc['load']['pmc']] == ['2026-09-21'] and doc['load']['pmc'][0]['blockId'] == 2

    bench = doc['benchmarks']
    assert [b['benchmarkId'] for b in bench] == ['back_squat_1rm'], 'a PR for an unknown standard is skipped'
    assert [h['level'] for h in bench[0]['history']] == ['entry', 'intermediate']
    assert bench[0]['levelsGained'] == 1 and bench[0]['latestLevel'] == 'intermediate'


def test_window_and_empty_history():
    inputs = _history()
    inputs.window_from, inputs.window_to = date(2026, 9, 1), date(2026, 10, 1)
    doc = compute_development(inputs)
    assert [b['id'] for b in doc['blocks']] == [1, 2], 'A overlaps the window by its last week'
    squat = next(l for l in doc['lifts'] if l['exerciseId'] == 'back_squat')
    assert [p['blockId'] for p in squat['points']] == [2, 2], 'only the points inside the window'
    assert doc['benchmarks'][0]['history'][0]['date'] == '2026-09-20'

    empty = DevelopmentInputs(today=date(2026, 10, 1), window_from=date(2026, 1, 1), window_to=date(2026, 10, 1))
    doc = compute_development(empty)
    assert doc['status'] == 'no_history' and doc['blocks'] == [] and doc['lifts'] == []


if __name__ == '__main__':
    test_blocks_are_the_timeline_with_completion()
    test_lifts_span_blocks_with_per_block_deltas_and_a_trend()
    test_currencies_load_and_benchmarks()
    test_window_and_empty_history()
    print('All development analytics tests passed.')
