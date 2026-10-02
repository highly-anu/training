"""The per-workout metrics cache and the load routes' reader.

zones.compute_metrics / cached_metrics (pure), api._workouts_for_load with
the store stubbed (which rows get their series read, how many per call, what
is written back), and api._matched_ids_in_window (the program analytics read
series only for matches inside the program's span). No database.
"""
import os
os.environ.setdefault('SUPABASE_URL', '')
from datetime import date, datetime, timedelta

from src.analytics import zones


def _samples(start='2026-09-20T10:00:00+00:00', n=600, bpm=150):
    t0 = datetime.fromisoformat(start)
    return [{'timestamp': (t0 + timedelta(seconds=5 * i)).isoformat(), 'bpm': bpm} for i in range(n)]


def test_compute_and_cache():
    full = {'id': 'a', 'date': '2026-09-20', 'durationMinutes': 50,
            'heartRate': {'avg': 150, 'max': 170, 'samples': _samples()}}
    m = zones.compute_metrics(full, 185)
    assert m['method'] == 'samples' and m['version'] == zones.version() and m['maxHr'] == 185
    assert abs(sum(m['zoneMinutes']) - 50) < 1e-6
    assert m['trimp'] == round(zones.trimp(full, 185), 3), 'the cache holds what the series say'

    summary = {'id': 'a', 'date': '2026-09-20', 'durationMinutes': 50,
               'heartRate': {'avg': 150, 'max': 170, 'samples': []}, 'metrics': m}
    assert zones.cached_metrics(summary, 185) is m
    assert zones.trimp(summary, 185) == m['trimp'], 'a summary with the cache reads it, not the estimate'
    assert zones.zone_minutes(summary, 185)['method'] == 'samples'
    assert zones.cached_metrics(summary, 190) is None, 'another max HR is another cache'
    assert zones.cached_metrics(dict(summary, metrics=dict(m, version=m['version'] + 1)), 185) is None, 'new edges, stale cache'
    assert zones.cached_metrics(dict(summary, metrics={'trimp': 'x'}), 185) is None, 'malformed is absent'
    estimate = zones.trimp(dict(summary, metrics=None), 185)
    assert estimate > 0 and estimate != m['trimp'], 'without the cache a summary falls back to the HR estimate'

    none = zones.compute_metrics({'id': 'b', 'durationMinutes': 30, 'heartRate': {'avg': None, 'max': None, 'samples': []}}, 185)
    assert none['method'] == 'none' and none['trimp'] == 0


def test_load_reader_reads_series_only_for_stale_rows():
    import api
    good = zones.compute_metrics({'durationMinutes': 30, 'heartRate': {'avg': 140, 'max': 160, 'samples': _samples(n=360, bpm=140)}}, 185)
    lib = [   # newest first, as the store returns them
        {'id': 'new1',   'date': '2026-09-30', 'durationMinutes': 40, 'heartRate': {'avg': 150, 'max': 170, 'samples': []}, 'metrics': None},
        {'id': 'cached', 'date': '2026-09-29', 'durationMinutes': 30, 'heartRate': {'avg': 140, 'max': 160, 'samples': []}, 'metrics': good},
        {'id': 'nohr',   'date': '2026-09-28', 'durationMinutes': 45, 'heartRate': {'avg': None, 'max': None, 'samples': []}, 'metrics': None},
        {'id': 'new2',   'date': '2026-09-27', 'durationMinutes': 40, 'heartRate': {'avg': 155, 'max': 175, 'samples': []}, 'metrics': None},
        {'id': 'old',    'date': '2026-01-01', 'durationMinutes': 60, 'heartRate': {'avg': 150, 'max': 170, 'samples': []}, 'metrics': None},
    ]
    series = {w['id']: dict(w, heartRate=dict(w['heartRate'], samples=_samples(n=480, bpm=w['heartRate']['avg'] or 0)))
              for w in lib}
    calls = {'with_hr': [], 'saved': []}
    api._health.get_workouts = lambda user_id, summary_only=False: [dict(w) for w in lib]
    def with_hr(user_id, ids):
        calls['with_hr'].append(list(ids))
        return [series[i] for i in ids]
    api._health.get_workouts_with_hr = with_hr
    api._health.save_workout_metrics = lambda user_id, wid, metrics: calls['saved'].append(wid) or True

    out = api._workouts_for_load('u', 185, since=date(2026, 9, 1), backfill=1)
    assert [w['id'] for w in out] == ['new1', 'cached', 'nohr', 'new2'], 'windowed by since'
    assert calls['with_hr'] == [['new1']], 'one call, the newest stale row with HR, within the bound'
    assert set(calls['saved']) == {'new1', 'nohr'}, 'the HR-less row is cached from its summary without a read'
    by = {w['id']: w for w in out}
    assert by['new1']['metrics']['method'] == 'samples'
    assert by['nohr']['metrics']['method'] == 'none' and by['nohr']['metrics']['trimp'] == 0
    assert by['cached']['metrics'] is good
    assert by['new2'].get('metrics') is None, 'beyond the bound: next call; scored from its summary meanwhile'
    assert zones.trimp(by['new2'], 185) > 0

    # The next call picks up where this one left off.
    calls['with_hr'].clear()
    lib[0]['metrics'] = by['new1']['metrics']; lib[2]['metrics'] = by['nohr']['metrics']
    out = api._workouts_for_load('u', 185, since=date(2026, 9, 1), backfill=10)
    assert calls['with_hr'] == [['new2']]


def test_matched_ids_are_windowed_to_the_program():
    import api
    matches = [{'importedWorkoutId': 'spring', 'matchConfidence': 'auto'},
               {'importedWorkoutId': 'in', 'matchConfidence': '1'},
               {'importedWorkoutId': 'rej', 'matchConfidence': 'rejected'},
               {'importedWorkoutId': 'gone', 'matchConfidence': 'auto'}]
    summaries = [{'id': 'spring', 'date': '2026-05-20'}, {'id': 'in', 'date': '2026-09-25'},
                 {'id': 'rej', 'date': '2026-09-26'}, {'id': 'late', 'date': '2027-03-01'}]
    assert api._matched_ids_in_window(matches, summaries, date(2026, 9, 21), date(2027, 1, 25)) == ['in']


if __name__ == '__main__':
    test_compute_and_cache(); print('ok compute_and_cache')
    test_load_reader_reads_series_only_for_stale_rows(); print('ok load_reader')
    test_matched_ids_are_windowed_to_the_program(); print('ok matched_ids_window')
    print('all passed')
