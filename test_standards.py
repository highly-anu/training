"""The standards: levels, the text a value prints as, the athlete's results and
the routes that read and write them. No database (the store is stubbed).

    SUPABASE_URL='' .venv/bin/python test_standards.py
"""
import os
from unittest import mock

os.environ.setdefault('SUPABASE_URL', '')

from src import standards
from src.analytics import benchmarks_data as bd

DEFS = bd.by_id()


def test_values_print_the_same_everywhere():
    fran, ruck = DEFS['wod_fran_minutes'], DEFS['ruck_12mi_40lb_minutes']
    assert bd.format_value(fran, 4.97) == '4:58', 'a time is a clock'
    assert bd.format_value(ruck, 200) == '3:20:00', 'past an hour the clock has hours'
    assert bd.format_value(DEFS['back_squat_bw_ratio'], 1.5) == '1.5×BW'
    assert bd.format_value(DEFS['pull_up_reps'], 12.0) == '12 reps', 'reps are whole'
    assert bd.format_value(DEFS['pull_up_reps'], 10.0) == '10 reps', 'and keep their noughts'
    assert bd.format_value(DEFS['ruck_12mi_40lb_minutes'], 100) == '1:40:00'
    assert bd.format_value(DEFS['pack_vertical_ft_per_hour'], 1500) == '1500 ft/h'
    assert bd.format_value(DEFS['wod_cindy_rounds'], 20.5) == '20.5 rounds'
    assert bd.format_value(DEFS['handstand_hold_wall_seconds'], 45) == '45 s', 'a hold stays in seconds'
    assert bd.format_value(None, 82.4) == '82.4 kg', 'bodyweight'
    assert bd.format_value(DEFS['pull_up_reps'], 1) == '1 rep', 'one rep'
    assert bd.format_value(fran, None) is None


def test_typed_values_read_back():
    fran, hold, squat = DEFS['wod_fran_minutes'], DEFS['handstand_hold_wall_seconds'], DEFS['back_squat_bw_ratio']
    assert bd.parse_input(fran, '4:58') == round(298 / 60, 4), 'm:ss is minutes for a time standard'
    assert bd.parse_input(DEFS['ruck_12mi_40lb_minutes'], '3:20:00') == 200.0
    assert bd.parse_input(fran, '5.5') == 5.5 and bd.parse_input(fran, 5) == 5.0
    assert bd.parse_input(hold, '1:30') == 90.0, 'm:ss is seconds for a hold'
    assert bd.parse_input(squat, '1,5') == 1.5, 'a decimal comma'
    assert bd.parse_input(DEFS['pull_up_reps'], '0') == 0.0, 'nought reps is a result'
    for bad in ('', 'abc', '4:75', '-1', '0', True, None, '1:2:3:4'):
        assert bd.parse_input(fran, bad) is None, bad
    assert bd.parse_input(squat, '1:30') is None, 'no clock for a ratio'
    assert bd.format_value(fran, bd.parse_input(fran, '4:58')) == '4:58', 'and prints back the same'


def test_female_tables_never_read_none():
    for b in bd.load_benchmarks():
        for sex in ('male', 'female'):
            ladder = bd.thresholds(b, sex)
            assert list(ladder) == list(bd.LEVELS), b['id']
            assert all(isinstance(v, float) for v in ladder.values()), (b['id'], sex, ladder)


def test_cell_levels_follow_cells_own_words():
    squat = DEFS['cell_hips_back_squat']
    # Cell: I basic 0.85, II beginner 1.25, III intermediate 1.50, IV advanced 1.75, V elite 2.00
    assert bd.thresholds(squat) == {'entry': 1.25, 'intermediate': 1.5, 'advanced': 1.75, 'elite': 2.0}
    assert bd.level_of(squat, 1.0)['level'] is None, 'Cell I is below entry'
    assert 'cell_work_capacity_thruster' in DEFS, 'the thruster loads from work_capacity'
    assert DEFS['cell_work_capacity_thruster']['notes'], 'and says it is a load for reps'


def test_categories_have_one_name_and_order():
    rows = [bd.to_client(b) for b in bd.load_benchmarks()]
    assert {r['categoryName'] for r in rows} <= set(bd.CATEGORY_NAME.values())
    assert all(isinstance(r['categoryOrder'], int) for r in rows)
    assert rows[0]['standardsText']['entry'], 'thresholds come with their text'


def test_every_standard_measures_a_modality():
    """The ladder is drawn in the modality's colour, so every domain must be one."""
    modalities = {f[:-5] for f in os.listdir('data/commons/modalities') if f.endswith('.yaml')}
    for b in bd.load_benchmarks():
        assert b['domain'] in modalities, (b['id'], b['domain'])


def test_summary_current_is_latest_best_is_best():
    logs = {
        'wod_fran_minutes': [{'id': 1, 'value': 6.0, 'date': '2026-05-01 10:00:00+00:00'},
                             {'id': 2, 'value': 4.97, 'date': '2026-09-01 10:00:00+00:00'},
                             {'id': 3, 'value': 5.5, 'date': '2026-10-01 10:00:00+00:00'}],
        'bodyweight_kg': [{'id': 4, 'value': 81.5, 'date': '2026-10-01 07:00:00+00:00'}],
        'a_retired_standard': [{'id': 5, 'value': 1, 'date': '2026-01-01'}],
        'back_squat_bw_ratio': [{'id': 6, 'value': 'abc', 'date': '2026-01-01'}],
    }
    out = standards.summarise(bd.load_benchmarks(), logs, 'male')
    fran = out['standards']['wod_fran_minutes']
    assert fran['current']['valueText'] == '5:30' and fran['current']['level'] == 'intermediate'
    assert fran['current']['nextText'] == '5:00' and fran['current']['gapText'] == '0:30'
    assert fran['best']['valueText'] == '4:58' and fran['best']['level'] == 'advanced', 'lower is better'
    assert [e['id'] for e in fran['entries']] == [1, 2, 3] and fran['count'] == 3
    assert out['bodyweight'] == {'value': 81.5, 'valueText': '81.5 kg', 'date': '2026-10-01'}
    assert 'a_retired_standard' not in out['standards'] and 'back_squat_bw_ratio' not in out['standards']


def test_below_entry_has_no_level():
    p = standards.point(DEFS['pull_up_reps'], 0.0, '2026-10-01', 'male')
    assert p['level'] is None and p['levelIndex'] == 0 and p['next'] == 'entry' and p['nextText'] == '1 rep'


def test_digest_moves_on_an_edit_that_keeps_the_count():
    before = {'x': [{'id': 1, 'value': 5.0, 'date': '2026-10-01'}]}
    after = {'x': [{'id': 1, 'value': 4.0, 'date': '2026-10-01'}]}
    assert standards.digest_key(before) != standards.digest_key(after)


def test_routes():
    import api
    c = api.app.test_client()
    assert len(c.get('/api/standards').json) == len(c.get('/api/benchmarks').json) == len(DEFS)
    logs = {'wod_fran_minutes': [{'id': 2, 'value': 4.97, 'date': '2026-09-01 10:00:00+00:00'}]}
    with mock.patch.object(api._health, 'get_performance_logs', return_value=logs), \
            mock.patch('src.db.get_user_profile', return_value={'sex': 'female'}):
        r = c.get('/api/standards/results')
    assert r.status_code == 200 and r.json['sex'] == 'female'
    assert r.json['standards']['wod_fran_minutes']['current']['valueText'] == '4:58'

    with mock.patch.object(api._health, 'add_performance_entry', return_value=9) as add:
        bad = [{'benchmarkId': 'nope', 'value': 1}, {'benchmarkId': 'wod_fran_minutes', 'value': 'abc'},
               {'benchmarkId': 'wod_fran_minutes', 'value': True},
               {'benchmarkId': 'wod_fran_minutes', 'value': 5, 'loggedAt': 'garbage'}]
        for body in bad:
            assert c.post('/api/health/performance', json=body).status_code == 422, body
        assert c.post('/api/health/performance', json={'benchmarkId': 'wod_fran_minutes'}).status_code == 400
        assert not add.called, 'nothing invalid reaches the store'
        r = c.post('/api/health/performance', json={'benchmarkId': 'wod_fran_minutes', 'value': 5})
        assert r.status_code == 200 and r.json == {'saved': 'wod_fran_minutes', 'id': 9}
        assert add.call_args.args[3], 'a missing loggedAt is now, not an empty string the insert rejects'
        assert c.post('/api/health/performance', json={'benchmarkId': 'bodyweight_kg', 'value': 80}).status_code == 200
        r = c.post('/api/health/performance', json={'benchmarkId': 'wod_fran_minutes', 'text': '4:58'})
        assert r.status_code == 200 and add.call_args.args[2] == round(298 / 60, 4), 'typed text is parsed on the server'
        assert c.post('/api/health/performance', json={'benchmarkId': 'wod_fran_minutes', 'text': '4:99'}).status_code == 422
    with mock.patch.object(api._health, 'add_performance_entry', side_effect=RuntimeError('db down')):
        r = c.post('/api/health/performance', json={'benchmarkId': 'wod_fran_minutes', 'value': 5})
    assert r.status_code == 503, 'a failed write is not reported as saved'


if __name__ == '__main__':
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn(); print('ok', name)
    print('all passed')
