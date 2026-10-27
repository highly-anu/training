"""One program from several tracks (src/composition.py): the request, the
day shares, the ladder's cuts, and composed programs of real packages — a
contract beside a contract, a template beside a contract, two tracks of one
philosophy — then the API's answer.

    SUPABASE_URL='' .venv/bin/python test_composition.py
"""
import json
import os
import sys
from unittest.mock import patch

os.environ['SUPABASE_URL'] = ''
os.environ.setdefault('DATABASE_URL', '')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import composition, loader  # noqa: E402

GYM = ['barbell', 'rack', 'plates', 'kettlebell', 'dumbbell', 'pull_up_bar', 'rings', 'rower',
       'box', 'ghd', 'medicine_ball', 'rope', 'jump_rope', 'open_space', 'sandbag', 'sled', 'tire']
WILDMAN = ['wk_kb_clean_single', 'wk_kb_press_single', 'wk_kb_snatch', 'wk_kb_swing_single_arm']


def _constraints(**over):
    return {'equipment': GYM, 'training_level': 'intermediate', 'injury_flags': [], 'kettlebell_count': 2,
            'fatigue_state': 'normal', **over}


def _compose(lanes, weeks=8, **over):
    c = _constraints(**over)
    built = composition.build_lanes(composition.normalise_request({'lanes': lanes}, c), c,
                                    list(loader.load_all_frameworks().values()))
    return composition.generate(built, c, num_weeks=weeks), c


def _sessions(week):
    return [s for ss in week['schedule'].values() for s in ss]


# ── The request ──────────────────────────────────────────────────────────────

def test_lanes_are_resolved_weighted_and_heaviest_first():
    c = _constraints()
    out = composition.normalise_request({'lanes': [
        {'philosophy_id': 'starting_strength', 'weight': 1},
        {'philosophy_id': 'uphill_athlete', 'weight': 3, 'start_phase': 'base'}]}, c)
    assert [l['philosophy_id'] for l in out] == ['uphill_athlete', 'starting_strength'], out
    assert [l['weight'] for l in out] == [0.75, 0.25]
    # A track not named is the one written for the level (SS intermediate: Texas Method).
    assert out[1]['track_id'] == 'texas_method' and out[0]['start_phase'] == 'base', out


def test_the_blend_shape_is_read_as_a_composition():
    c = _constraints()
    out = composition.normalise_request({
        'philosophy_ids': ['wildman_kettlebell', 'uphill_athlete'],
        'philosophy_weights': {'wildman_kettlebell': 0.3, 'uphill_athlete': 0.7},
        'track_id': 'pentathlon', 'start_phase': 'timed_sets'}, c)
    by = {l['philosophy_id']: l for l in out}
    # The member that owns the track runs it, from the phase asked for; the
    # other runs its own track.
    assert by['wildman_kettlebell']['track_id'] == 'pentathlon'
    assert by['wildman_kettlebell'].get('start_phase') == 'timed_sets'
    assert by['uphill_athlete']['track_id'] == 'full_program' and 'start_phase' not in by['uphill_athlete']


def test_a_track_named_twice_or_weighed_at_zero_is_refused():
    c = _constraints()
    for lanes in ([{'philosophy_id': 'atg', 'track_id': 'zero'}, {'philosophy_id': 'atg', 'track_id': 'zero'}],
                  [{'philosophy_id': 'atg', 'weight': 0}, {'philosophy_id': 'bjj'}]):
        try:
            composition.normalise_request({'lanes': lanes}, c)
        except composition.CompositionError:
            continue
        raise AssertionError(f'{lanes} was accepted')
    # Two tracks of one philosophy are two lanes.
    out = composition.normalise_request({'lanes': [
        {'philosophy_id': 'wildman_kettlebell', 'track_id': 'general_practice'},
        {'philosophy_id': 'wildman_kettlebell', 'track_id': 'snatch_practice'}]}, c)
    assert len({composition.lane_key(l['philosophy_id'], l['track_id']) for l in out}) == 2


def test_days_split_by_weight_and_never_under_a_floor():
    assert composition.split_days([0.6, 0.4], 6) == [4, 2]
    assert composition.split_days([0.5, 0.5], 5) == [3, 2]
    assert composition.split_days([0.9, 0.1], 5) == [4, 1]
    # BJJ's classes need three days: a floor wins over the weight.
    assert composition.split_days([0.8, 0.2], 5, [1, 3]) == [4, 3]


def test_the_ladders_cuts_are_applied_to_the_contract_data():
    from src.training_contract import load_contract
    uphill = load_contract('uphill_athlete', 'full_program')
    cut = composition.derived_contract(uphill, {'optional': True, 'volume': 0.8,
                                                'exposures': {'general_strength': 1}})
    by = {m['id']: m for m in cut['modules']}
    assert not any(m.get('optional') for m in cut['modules'])
    long_day = next(m for m in uphill['modules'] if m['id'] == 'long_day')
    assert by['long_day']['progression']['start_minutes']['intermediate'] == \
        long_day['progression']['start_minutes']['intermediate'] * 0.8
    original = next(m for m in uphill['modules'] if m['id'] == 'general_strength')
    assert composition._exposures(by['general_strength']) == composition._exposures(original) - 1
    # BJJ's classes resolve to the lane's days before anything is cut.
    bjj = composition.derived_contract(load_contract('bjj', 'mat_support'), {'exposures': {}}, days=4)
    mat = next(m for m in bjj['modules'] if m['id'] == 'mat_class')
    assert 'exposures_by_days' not in mat and mat['exposures_per_week'] == 3, mat


# ── Composed programs ────────────────────────────────────────────────────────

def test_endurance_and_strength_share_seven_days():
    program, c = _compose([{'philosophy_id': 'uphill_athlete', 'weight': 0.6},
                           {'philosophy_id': 'starting_strength', 'weight': 0.4}],
                          weeks=12, days_per_week=7, session_time_minutes=90)
    assert not program.get('validation_errors'), program.get('validation_errors')
    keys = ['uphill_athlete/full_program', 'starting_strength/texas_method']
    assert [l['key'] for l in program['composition']['lanes']] == keys
    for week in program['weeks']:
        assert [l['lane_key'] for l in week['lanes']] == keys
        for day, sessions in week['schedule'].items():
            # One day's tracks fit in the athlete's day.
            assert sum(s['archetype']['duration_estimate_minutes'] for s in sessions) <= 90, (day, sessions)
            for s in sessions:
                # Each session is its track's, from its track's package, in its phase.
                assert s['lane_key'] in keys and s['archetype']['_package'] == s['lane_key'].split('/')[0]
                lane = next(l for l in week['lanes'] if l['lane_key'] == s['lane_key'])
                assert s['phase_id'] == lane['phase_id'] and s['framework'] == lane['framework']
        # The Texas Method's three days stay two days apart.
        ss_days = sorted(d for d, ss in week['schedule'].items() for s in ss if s['lane_key'] == keys[1])
        assert len(ss_days) == 3 and min(b - a for a, b in zip(ss_days, ss_days[1:])) >= 2, ss_days
    # The week is labelled by the lead track's phase.
    assert program['weeks'][0]['phase_id'] == 'transition'
    # Every cut names its track.
    assert all(line.split(':')[0] in ('Uphill Athlete', 'Starting Strength — Texas Method')
               for line in program['compromises']), program['compromises']


def test_a_templated_track_takes_the_room_a_contract_leaves():
    program, c = _compose([{'philosophy_id': 'horsemen_gpp', 'weight': 0.5},
                           {'philosophy_id': 'wildman_kettlebell', 'track_id': 'general_practice', 'weight': 0.5}],
                          weeks=6, days_per_week=6, session_time_minutes=75,
                          mastered_exercises=['wk_kb_clean_single', 'wk_kb_press_single'])
    assert not program.get('validation_errors'), program.get('validation_errors')
    for week in program['weeks']:
        lanes = {s['lane_key'] for s in _sessions(week)}
        assert lanes == {'horsemen_gpp/four_month_macro', 'wildman_kettlebell/general_practice'}, lanes
        for sessions in week['schedule'].values():
            assert sum(s['archetype']['duration_estimate_minutes'] for s in sessions) <= 75
    # Horsemen's own thinning ran at its share of the days, and says so.
    assert any(line.startswith('Horsemen GPP: With 3 training days') for line in program['compromises'])
    # Each contract module record keeps its bare id (confirmations read it).
    records = [m['id'] for w in program['weeks'] for s in _sessions(w) for m in s.get('modules') or []]
    assert 'swing' in records


def test_two_tracks_of_one_philosophy():
    program, _ = _compose([{'philosophy_id': 'wildman_kettlebell', 'track_id': 'general_practice', 'weight': 0.6},
                           {'philosophy_id': 'wildman_kettlebell', 'track_id': 'snatch_practice', 'weight': 0.4}],
                          weeks=4, days_per_week=5, session_time_minutes=60, mastered_exercises=WILDMAN)
    assert not program.get('validation_errors'), program.get('validation_errors')
    lanes = {s['lane_key'] for w in program['weeks'] for s in _sessions(w)}
    assert lanes == {'wildman_kettlebell/general_practice', 'wildman_kettlebell/snatch_practice'}
    states = {l['key']: l['module_state'] for l in program['composition']['lanes']}
    # Both tracks have a `snatch` module; each lane keeps its own state.
    assert all('snatch' in (s or {}) for s in states.values()), states


def test_a_track_that_cannot_run_alone_says_so_plainly():
    program, _ = _compose([{'philosophy_id': 'crossfit', 'weight': 0.5},
                           {'philosophy_id': 'starting_strength', 'weight': 0.5}],
                          weeks=4, days_per_week=5, session_time_minutes=75, training_level='novice')
    error = program['validation_errors'][0]
    assert error['code'] == 'COMPOSITION_UNFULFILLED'
    assert error['message'].startswith('CrossFit') and 'cannot fit beside' not in error['message'], error


def test_too_little_room_is_refused_naming_the_track():
    program, _ = _compose([{'philosophy_id': 'uphill_athlete', 'weight': 0.6},
                           {'philosophy_id': 'starting_strength', 'weight': 0.4}],
                          weeks=24, days_per_week=6, session_time_minutes=90)
    error = program['validation_errors'][0]
    assert 'cannot fit beside' in error['message'], error


def test_the_same_request_composes_the_same_program():
    lanes = [{'philosophy_id': 'bjj', 'weight': 0.6}, {'philosophy_id': 'kelly_starrett', 'weight': 0.4}]
    first, _ = _compose(lanes, weeks=4, days_per_week=5, session_time_minutes=75)
    second, _ = _compose(lanes, weeks=4, days_per_week=5, session_time_minutes=75)
    assert not first.get('validation_errors'), first.get('validation_errors')
    assert json.dumps(first, sort_keys=True, default=str) == json.dumps(second, sort_keys=True, default=str)


def test_a_lane_view_keeps_positions_and_drops_other_tracks_modules():
    program = {'composition': {'lanes': [{'key': 'a/x', 'training_contract': {'id': 'a/x@1'}, 'module_state': {'m': {}}}]},
               'weeks': [{'week_number': 1, 'schedule': {'Monday': [
                   {'lane_key': 'b/y', 'modules': [{'id': 'm'}]}, {'lane_key': 'a/x', 'modules': [{'id': 'm'}]}]}}]}
    view = composition.lane_view(program, 'a/x')
    monday = view['weeks'][0]['schedule']['Monday']
    assert 'modules' not in monday[0] and monday[1]['modules'] == [{'id': 'm'}]
    assert view['training_contract'] == {'id': 'a/x@1'} and view['module_state'] == {'m': {}}


# ── The API ──────────────────────────────────────────────────────────────────

def _post(body):
    with patch('src.db._get_pg_conn', return_value=None):
        import api
    with patch('src.db.get_user_program', return_value=None), patch('src.db.save_user_program'):
        r = api.app.test_client().post('/api/programs/generate', json={
            **body, 'persist': False, 'start_date': '2026-11-02'})
    return r.status_code, r.get_json()


def test_the_api_answers_a_composition_in_the_program_shape():
    status, body = _post({'lanes': [{'philosophy_id': 'bjj', 'weight': 0.6},
                                    {'philosophy_id': 'kelly_starrett', 'weight': 0.4}],
                          'num_weeks': 3, 'constraints': _constraints(days_per_week=5, session_time_minutes=75)})
    assert status == 200 and body['validation']['feasible'], body.get('detail')
    assert body['goal']['id'] == '_phil_composition'
    assert [t['lane_key'] for t in body['goal']['tracks']] == ['bjj/mat_support', 'kelly_starrett/built_to_move']
    assert body['goal']['primary_sources'] == ['bjj', 'kelly_starrett']
    week = body['weeks'][0]
    assert isinstance(week['lanes'], list) and all(isinstance(d, str) for d in week['schedule'])
    session = next(s for ss in week['schedule'].values() for s in ss)
    assert session['lane_key'] and session['phase_id'] and session['framework']
    assert body['composition']['lanes'][0]['training_contract']['id'].startswith('bjj/mat_support@')


def test_the_old_blend_shape_composes_too():
    status, body = _post({'philosophy_ids': ['bjj', 'kelly_starrett'],
                          'philosophy_weights': {'bjj': 0.6, 'kelly_starrett': 0.4},
                          'num_weeks': 2, 'constraints': _constraints(days_per_week=5, session_time_minutes=75)})
    assert status == 200 and body['validation']['feasible'], body.get('detail')
    assert {s['lane_key'] for w in body['weeks'] for ss in w['schedule'].values() for s in ss} == \
        {'bjj/mat_support', 'kelly_starrett/built_to_move'}


def test_a_refused_composition_is_answered_as_every_infeasible_request():
    status, body = _post({'lanes': [{'philosophy_id': 'crossfit', 'weight': 0.5},
                                    {'philosophy_id': 'starting_strength', 'weight': 0.5}],
                          'num_weeks': 2, 'constraints': _constraints(days_per_week=5, training_level='novice')})
    assert status == 200 and body['validation']['feasible'] is False and body['weeks'] == []
    assert body['detail'].startswith('CrossFit')


if __name__ == '__main__':
    failed = 0
    for name, fn in list(globals().items()):
        if name.startswith('test_') and callable(fn):
            try:
                fn()
                print('ok', name)
            except Exception as exc:  # noqa: BLE001
                failed += 1
                print('FAIL', name, '-', type(exc).__name__, exc)
    print('all passed' if not failed else f'{failed} failed')
    sys.exit(1 if failed else 0)
