"""One workout's analysis, computed on the server for both clients.

src/analytics/workout_analysis.py against golden values the browser's
lib/hrZones.ts produced for data/workout_analysis_fixture.json before the
port (shared edges and custom edges, a sampled run and a summary-only
session), the phone's training-effect and recovery thresholds, best efforts,
and the route that attaches `analysis` to GET /api/health/workouts/<id>.
No database.
"""
import json
import os
os.environ.setdefault('SUPABASE_URL', '')
from datetime import date
from pathlib import Path

from src.analytics import workout_analysis as wa

FIXTURE = json.loads((Path(__file__).parent / 'data' / 'workout_analysis_fixture.json').read_text())
PROFILE_180 = {'hrConfig': {'maxHROverride': 180}}

# lib/hrZones.ts on the fixture, max HR 180 (computeHRZones, computeTRIMP,
# computeAerobicDecoupling), recorded 2026-10-13 — for the sampled run.
# The summary-only rows are the server's, NOT the browser's: both clients'
# normalCDF applied the erf polynomial to z instead of z/√2 and returned it
# as the CDF, which put the CDF at the mean near 0 instead of 0.5. The
# browser said [0, 5, 92, 3, 0] (TRIMP 90) and [0, 6, 40, 54, 0] (113) here;
# an average of 140 bpm against a Z2/Z3 edge of 140.4 splits about evenly.
GOLDEN = {
    'shared': {'run': ([0, 44, 31, 21, 4], 125), 'summary': ([0, 52, 46, 2, 0], 79)},
    'custom': {'run': ([0, 15, 36, 38, 11], 155), 'summary': ([0, 4, 65, 31, 0], 103)},
    'decoupling': 10.787,
}


def _profile(edges=None):
    p = {'hrConfig': {'maxHROverride': 180}}
    if edges:
        p['hrConfig']['zoneBoundaries'] = edges
    return p


def test_matches_the_browser():
    for name, edges in (('shared', None), ('custom', [0.6, 0.7, 0.8, 0.9])):
        for kind in ('run', 'summary'):
            a = wa.analyse(FIXTURE[kind], _profile(edges), date(2026, 10, 13))
            pct, trimp = GOLDEN[name][kind]
            assert a['zones']['pct'] == pct, (name, kind, a['zones']['pct'], pct)
            # The server multiplies exact fractions, the browser rounded ones.
            assert abs(a['trimp'] - trimp) <= 1, (name, kind, a['trimp'], trimp)
            assert a['zoneBoundariesSource'] == ('custom' if edges else 'shared')
    a = wa.analyse(FIXTURE['run'], _profile(), date(2026, 10, 13))
    assert abs(a['decoupling']['pct'] - GOLDEN['decoupling']) < 0.01 and a['decoupling']['label'] == 'high'
    assert a['zones']['method'] == 'samples'
    assert abs(sum(a['zones']['minutes']) - 60) < 0.05


def test_max_hr_and_edges_resolution():
    today = date(2026, 10, 13)
    a = wa.analyse(FIXTURE['summary'], {'dateOfBirth': '1990-10-14'}, today)
    assert a['maxHr'] == 220 - 35 and a['maxHrSource'] == 'age', 'an exact age, not a year difference'
    a = wa.analyse(FIXTURE['summary'], {}, today)
    assert a['maxHrSource'] == 'default'
    run = dict(FIXTURE['run'], heartRate=dict(FIXTURE['run']['heartRate'], max=230))
    assert wa.analyse(run, PROFILE_180, today)['maxHr'] == 180, "a workout's own peak never raises max HR"
    for bad in ([0.9, 0.8, 0.7, 0.6], [0.6, 0.7], ['x', 1, 2, 3], [0.6, 0.7, 0.8, 1.4]):
        assert wa.zone_boundaries({'hrConfig': {'zoneBoundaries': bad}})[1] == 'shared', bad


def test_phone_thresholds():
    assert wa.training_effect(10, [50, 50, 0, 0, 0]) == 'Recovery'
    assert wa.training_effect(20, [30, 40, 30, 0, 0]) == 'Base Development'
    assert wa.training_effect(20, [10, 40, 50, 0, 0]) == 'Maintenance'
    assert wa.training_effect(50, [0, 10, 40, 30, 20]) == 'Threshold'
    assert wa.training_effect(50, [0, 30, 40, 20, 10]) == 'Aerobic Capacity'
    assert wa.training_effect(80, [0, 10, 40, 30, 20]) == 'Highly Impacting'
    assert wa.training_effect(80, [0, 60, 30, 10, 0]) == 'Aerobic Capacity'
    assert [wa.recovery_hours(t) for t in (0, 20, 40, 70, 100)] == [8, 12, 18, 24, 36]
    a = wa.analyse(FIXTURE['run'], _profile(), date(2026, 10, 13))
    assert a['trainingEffect'] == 'Aerobic Capacity', 'TRIMP 125, 25 % in Z4-5'
    assert a['recoveryHours'] == 36


def test_best_efforts():
    efforts = {e['label']: e for e in wa.best_efforts(FIXTURE['run']['gpsTrack'])}
    assert set(efforts) == {'1 km', '5 km', '10 km'}
    # Speeds in the fixture run 2.65–3.15 m/s.
    # A window counts from 95 % of the distance, as on the phone.
    assert 0.95 * 1000 / 3.2 < efforts["1 km"]["seconds"] < 1000 / 2.6
    assert efforts['1 km']['secPerKm'] <= efforts['5 km']['secPerKm'] <= efforts['10 km']['secPerKm']
    assert wa.best_efforts(FIXTURE['run']['gpsTrack'][:5]) == []
    assert wa.analyse(FIXTURE['summary'], _profile())['bestEfforts'] == []


def test_no_heart_rate():
    a = wa.analyse({'durationMinutes': 30, 'heartRate': {'avg': None, 'samples': []}}, {})
    assert a['zones'] is None and a['trimp'] is None and a['trainingEffect'] is None
    assert a['decoupling'] is None


def test_route_attaches_analysis():
    import api
    import src.db as db
    stored = dict(FIXTURE['run'], id='w1', date='2026-10-01')
    orig = (api._health.get_workout, db.get_user_profile)
    api._health.get_workout = lambda uid, wid: dict(stored) if wid == 'w1' else None
    db.get_user_profile = lambda uid: _profile()
    try:
        client = api.app.test_client()
        body = client.get('/api/health/workouts/w1').get_json()
        assert body['id'] == 'w1' and body['analysis']['zones']['pct'] == GOLDEN['shared']['run'][0]
        assert client.get('/api/health/workouts/nope').status_code == 404
        db.get_user_profile = lambda uid: (_ for _ in ()).throw(RuntimeError('db down'))
        body = client.get('/api/health/workouts/w1').get_json()
        assert body['id'] == 'w1' and 'analysis' not in body, 'a failed analysis leaves the workout readable'
    finally:
        api._health.get_workout, db.get_user_profile = orig


if __name__ == '__main__':
    test_matches_the_browser(); print('ok matches_the_browser')
    test_max_hr_and_edges_resolution(); print('ok max_hr_and_edges')
    test_phone_thresholds(); print('ok phone_thresholds')
    test_best_efforts(); print('ok best_efforts')
    test_no_heart_rate(); print('ok no_heart_rate')
    test_route_attaches_analysis(); print('ok route')
    print('all passed')
