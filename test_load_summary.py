"""Analytics ▸ Load's summary, computed on the server for both clients.

src/analytics/load_summary.py (pure) and GET /api/health/load/summary with
the load reader stubbed. No database.
"""
import os
os.environ.setdefault('SUPABASE_URL', '')
from datetime import date

from src.analytics import load_summary as ls
from src.analytics import zones

TODAY = date(2026, 10, 13)  # a Tuesday


def _w(id, day, minutes=60, modality='aerobic_base', km=None, unit='km', avg=140, gain=None, cal=None, act='Running'):
    return {'id': id, 'date': day, 'durationMinutes': minutes, 'inferredModalityId': modality,
            'activityType': act,
            'distance': None if km is None else {'value': km, 'unit': unit},
            'elevation': None if gain is None else {'gain': gain, 'loss': gain},
            'calories': cal, 'heartRate': {'avg': avg, 'max': (avg or 0) + 20, 'samples': []}}


WORKOUTS = [
    _w('a', '2026-10-12', 60, km=10, gain=100, cal=600),
    _w('b', '2026-10-01', 30, 'max_strength', avg=None, act='Strength'),
    _w('c', '2026-09-20', 90, km=15000, unit='m', avg=150),       # metres
    _w('d', '2026-08-30', 45, km=8),                               # prior 30 d window
    _w('e', '2026-10-14', 45),                                     # after today: ignored
]


def test_totals_and_prior():
    s = ls.summarize(WORKOUTS, 190, '30d', TODAY)
    assert s['from'] == '2026-09-14', 'thirty days including today' and s['to'] == '2026-10-13'
    t = s['totals']
    assert t['sessions'] == 3 and t['minutes'] == 180
    assert t['distanceKm'] == 25.0, 'metres are converted; the phone summed them as km'
    assert t['elevationGainM'] == 100 and t['calories'] == 600
    assert s['prior'] == {'sessions': 1, 'minutes': 45.0, 'distanceKm': 8.0,
                          'elevationGainM': None, 'elevationLossM': None, 'calories': None}
    edge = ls.summarize([_w('x', '2026-10-07'), _w('y', '2026-10-06')], 190, '7d', TODAY)['totals']
    assert edge['sessions'] == 1, '7d is seven days including today: the 7th, not the 6th'
    assert ls.summarize(WORKOUTS, 190, 'all', TODAY)['prior'] is None
    assert ls.summarize(WORKOUTS, 190, 'all', TODAY)['totals']['sessions'] == 4


def test_mixes():
    s = ls.summarize(WORKOUTS, 190, '30d', TODAY)
    assert [m['id'] for m in s['modalities']] == ['aerobic_base', 'max_strength']
    assert sum(m['pct'] for m in s['modalities']) == 100
    assert s['activities'][0] == {'activityType': 'Running', 'minutes': 150.0, 'sessions': 2,
                                  'modalityId': 'aerobic_base'}


def test_consistency_is_twelve_monday_weeks():
    c = ls.summarize(WORKOUTS, 190, '7d', TODAY)['consistency']
    assert len(c) == 12 and c[-1]['weekStart'] == '2026-10-12'
    assert c[-1]['sessions'] == 1, 'this week: Monday the 12th; the 14th has not happened'
    assert {x['weekStart']: x['sessions'] for x in c}['2026-09-28'] == 1


def test_zone_minutes_match_the_load_maths():
    s = ls.summarize(WORKOUTS, 190, '30d', TODAY)
    z = s['zones']
    assert z['workoutsEstimated'] == 2 and z['workoutsMeasured'] == 0, 'the strength session has no HR'
    expected = [sum(zones.zone_minutes(w, 190)['minutes'][i] for w in WORKOUTS[:3] if w['heartRate']['avg'])
                for i in range(5)]
    assert z['minutes'] == [round(m, 1) for m in expected]
    f = s['focus28d']
    assert abs(f['base'] + f['threshold'] + f['anaerobic'] - 150) < 0.2, 'a and c: the last 28 days with HR'
    assert ls.summarize([], 190, '30d', TODAY)['zones'] is None


def test_route():
    import api
    seen = {}

    def fake_reader(uid, max_hr, since=None, backfill=40):
        seen['since'] = since
        return [dict(w) for w in WORKOUTS]
    orig = (api._workouts_for_load, api._get_user_max_hr)
    api._workouts_for_load, api._get_user_max_hr = fake_reader, (lambda uid: 190)
    try:
        c = api.app.test_client()
        body = c.get('/api/health/load/summary?period=30d&today=2026-10-13').get_json()
        assert body['totals']['sessions'] == 3 and body['to'] == '2026-10-13'
        assert seen['since'] == date(2026, 7, 14), 'twelve weeks + one back, for consistency'
        c.get('/api/health/load/summary?period=all')
        assert seen['since'] is None
        assert c.get('/api/health/load/summary?period=2w').status_code == 422
        assert c.get('/api/health/load/summary?today=13.10.2026').status_code == 422
    finally:
        api._workouts_for_load, api._get_user_max_hr = orig


if __name__ == '__main__':
    test_totals_and_prior(); print('ok totals_and_prior')
    test_mixes(); print('ok mixes')
    test_consistency_is_twelve_monday_weeks(); print('ok consistency')
    test_zone_minutes_match_the_load_maths(); print('ok zones')
    test_route(); print('ok route')
    print('all passed')
