"""Progress a slot earns from the log (src/earned_progress.py): a session made
steps the next one on, a miss repeats it, and the weeks ahead are forecast.

    SUPABASE_URL='' .venv/bin/python test_earned_progress.py
"""
from __future__ import annotations

import copy
import os
import sys
from datetime import date

os.environ['SUPABASE_URL'] = ''
os.environ['DATABASE_URL'] = ''
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import earned_progress as ep  # noqa: E402

SQUAT = {'id': 'back_squat', 'name': 'Back Squat'}
DAYS = ('Monday', 'Thursday')


def slot(**progress):
    return {'role': 'b1', 'slot_type': 'sets_reps', 'sets': 3, 'reps': 5, 'start_kg': 80,
            'progress': {'add_kg': 2.5, 'earned': True, **progress}}


def session(the_slot, light=False, arch='day_a', role=None):
    s = dict(the_slot, role=role or the_slot['role'])
    return {'archetype': {'id': arch, 'slots': [s]}, **({'light': True} if light else {}),
            'exercises': [{'exercise': SQUAT, 'slot_role': s['role'], 'slot_type': 'sets_reps', 'load': {}}]}


def program(weeks=3, the_slot=None, deload=()):
    """Two sessions a week (Monday, Thursday), numbered from 1."""
    the_slot = the_slot or slot()
    return [{'week_number': w, 'phase': 'build', 'is_deload': w in deload,
             'schedule': {d: [session(the_slot)] for d in DAYS}} for w in range(1, weeks + 1)]


def kgs(weeks):
    return [w['schedule'][d][0]['exercises'][0]['load'].get('weight_kg') for w in weeks for d in DAYS]


def done(kg=None, reps=5, sets=3, **more):
    return {'exercises': {'back_squat': {'sets': [{'setIndex': i, 'repsActual': reps, 'completed': True,
                                                   **({'weightKg': kg} if kg else {})} for i in range(sets)], **more}}}


START, TODAY = '2026-11-23', date(2026, 11, 23)     # a Monday; nothing is behind yet


def test_a_new_program_is_forecast_by_exposure():
    weeks = program()
    changed, state = ep.replan(weeks, {}, START, TODAY)
    assert kgs(weeks) == [80, 82.5, 85, 87.5, 90, 92.5], kgs(weeks)
    assert changed == 6 and state[('day_a', 'b1')]['steps'] == 6
    assert ep.replan(weeks, {}, START, TODAY)[0] == 0          # saying it twice changes nothing
    assert weeks[0]['schedule']['Monday'][0]['exercises'][0]['load'] == {'sets': 3, 'reps': 5, 'weight_kg': 80}


def test_a_made_session_steps_on_and_a_miss_repeats():
    weeks = program()
    ep.replan(weeks, {}, START, TODAY)
    logs = {'1-Monday-0': done(80), '1-Thursday-0': done(82.5, reps=4)}
    changed, _ = ep.replan(weeks, logs, START, date(2026, 11, 27))
    assert kgs(weeks) == [80, 82.5, 82.5, 85, 87.5, 90], kgs(weeks)
    assert changed == 4
    # One set short is a miss too; the one-tap answer wins over the sets.
    short = program(2)
    ep.replan(short, {'1-Monday-0': done(80, sets=2)}, START, TODAY)
    assert kgs(short)[:2] == [80, 80]
    tapped = program(2)
    ep.replan(tapped, {'1-Monday-0': done(80, reps=3, made=True)}, START, TODAY)
    assert kgs(tapped)[:2] == [80, 82.5]


def test_a_day_gone_by_unlogged_earns_nothing():
    weeks = program()
    ep.replan(weeks, {}, START, date(2026, 11, 25))            # Monday is behind, Thursday ahead
    assert kgs(weeks) == [80, 80, 82.5, 85, 87.5, 90], kgs(weeks)
    logged = program()
    ep.replan(logged, {'1-Monday': done(80)}, START, date(2026, 11, 25))   # the day-level key
    assert kgs(logged)[:3] == [80, 82.5, 85]
    without = program()
    ep.replan(without, {'1-Monday-0': {'exercises': {'other': {'sets': []}}}}, START, TODAY)
    assert kgs(without)[:2] == [80, 80]                           # logged, but not this lift


def test_a_weight_logged_becomes_where_it_carries_on_from():
    weeks = program()
    ep.replan(weeks, {'1-Monday-0': done(85)}, START, TODAY)
    assert kgs(weeks) == [80, 87.5, 90, 92.5, 95, 97.5], kgs(weeks)
    lighter = program(2)
    ep.replan(lighter, {'1-Monday-0': done(75)}, START, TODAY)
    assert kgs(lighter) == [80, 77.5, 80, 82.5], kgs(lighter)


def test_double_progression_is_earned_rep_by_rep():
    the_slot = slot(add_reps=1, top_reps=7)
    weeks = program(3, the_slot)
    ep.replan(weeks, {'1-Thursday-0': done(80, reps=5)}, START, TODAY)   # 6 were asked on Thursday
    got = [(w['schedule'][d][0]['exercises'][0]['load']['reps'], w['schedule'][d][0]['exercises'][0]['load']['weight_kg'])
           for w in weeks for d in DAYS]
    assert got == [(5, 80), (6, 80), (6, 80), (7, 80), (5, 82.5), (6, 82.5)], got


def test_a_light_day_neither_earns_nor_counts():
    weeks = program(3, deload=(2,))
    for d in DAYS:      # the deload week's days are composed light (week_template)
        s = weeks[1]['schedule'][d][0]
        s['light'] = True
        s['archetype']['slots'][0]['light_share'] = 0.8
    ep.replan(weeks, {}, START, TODAY)
    assert kgs(weeks) == [80, 82.5, 68, 68, 85, 87.5], kgs(weeks)


def test_a_second_piece_of_a_day_is_the_same_slot():
    weeks = program(1)
    weeks[0]['schedule']['Thursday'] = [session(slot(), arch='row_day', role='day_a__b1')]
    ep.replan(weeks, {}, START, TODAY)
    assert kgs(weeks) == [80, 82.5]


def test_a_tail_carries_on_from_the_weeks_before_it():
    whole = program(4)
    head, tail = copy.deepcopy(whole[:2]), copy.deepcopy(whole[2:])
    logs = {'1-Monday-0': done(80), '1-Thursday-0': done(82.5, reps=3)}
    _, state = ep.replan(head, logs, START, date(2026, 12, 7))
    ep.replan(tail, logs, START, date(2026, 12, 7), state, first_week_index=2)
    ep.replan(whole, logs, START, date(2026, 12, 7))
    assert kgs(tail) == kgs(whole)[4:] == [82.5, 85, 87.5, 90], (kgs(tail), kgs(whole))


def test_nothing_earned_nothing_touched():
    plain = {'role': 'b1', 'slot_type': 'sets_reps', 'sets': 3, 'reps': 5, 'start_kg': 80, 'progress': {'add_kg': 2.5}}
    weeks = program(2, plain)
    for w in weeks:
        for d in DAYS:
            w['schedule'][d][0]['exercises'][0]['load'] = {'sets': 3, 'reps': 5, 'weight_kg': 80 + 2.5 * (w['week_number'] - 1)}
    before = copy.deepcopy(weeks)
    assert not ep.has_earned(weeks) and ep.replan(weeks, {'1-Monday-0': done(100)}, START, TODAY)[0] == 0
    assert weeks == before
    assert ep.has_earned(program(1))


def test_the_routes():
    import api
    from src import db
    weeks = program()
    ep.replan(weeks, {}, START, TODAY)
    store = {'envelope': {'currentProgram': {'weeks': weeks}, 'programStartDate': START}, 'logs': {}, 'saved': 0}
    real = (db.get_user_program, db.save_user_program, db.get_program_revision, api._health.get_session_logs,
            api._health.upsert_session_log, api._record_program_history, api._user_today)
    db.get_user_program = lambda uid: copy.deepcopy(store['envelope'])
    def save(uid, envelope):
        store['envelope'], store['saved'] = copy.deepcopy(envelope), store['saved'] + 1
    db.save_user_program = save
    db.get_program_revision = lambda uid: 'r1'
    api._health.get_session_logs = lambda uid: store['logs']
    def upsert(uid, log):
        store['logs'][log['sessionKey']] = log
        return {'session_uid': None}
    api._health.upsert_session_log = upsert
    api._record_program_history = lambda *a, **k: {}
    api._user_today = lambda uid: TODAY
    try:
        client = api.app.test_client()
        missed = client.put('/api/health/sessions/1-Monday-0', json={**done(80, reps=3), 'completedAt': '2026-11-23T10:00:00Z'})
        assert missed.status_code == 200 and missed.get_json().get('programChanged') is True, missed.get_json()
        assert kgs(store['envelope']['currentProgram']['weeks'])[:3] == [80, 80, 82.5] and store['saved'] == 1
        again = client.put('/api/health/sessions/1-Monday-0', json={**done(80, reps=3), 'completedAt': '2026-11-23T10:00:00Z'})
        assert 'programChanged' not in again.get_json() and store['saved'] == 1      # the same log changes nothing
        made = client.put('/api/health/sessions/1-Monday-0', json={**done(80), 'completedAt': '2026-11-23T10:00:00Z'})
        assert made.get_json().get('programChanged') is True
        assert kgs(store['envelope']['currentProgram']['weeks'])[:3] == [80, 82.5, 85]
        store['envelope'] = {'currentProgram': {'weeks': [{'week_number': 1, 'schedule': {}}]}, 'programStartDate': START}
        other = client.put('/api/health/sessions/1-Monday-0', json={**done(80), 'completedAt': '2026-11-23T10:00:00Z'})
        assert 'programChanged' not in other.get_json() and store['saved'] == 2      # nothing earned, nothing saved
    finally:
        (db.get_user_program, db.save_user_program, db.get_program_revision, api._health.get_session_logs,
         api._health.upsert_session_log, api._record_program_history, api._user_today) = real


def test_the_session_builder_writes_it():
    from src import manual_builder as mb
    cat = mb.catalog()
    arch, problems = mb.to_archetype({'name': 'A', 'modality': 'max_strength', 'blocks': [{'kind': 'sets', 'movements': [
        {'exercise_id': 'back_squat', 'sets': 3, 'reps': 5, 'start_kg': 80,
         'progress': {'add_kg': 2.5, 'earned': True, 'every_weeks': 2}}]}]}, 'u1_ms_a', cat)
    assert arch and arch['slots'][0]['progress'] == {'add_kg': 2.5, 'earned': True}, (arch, problems)
    assert mb.from_archetype(arch)['blocks'][0]['movements'][0]['progress'] == {'add_kg': 2.5, 'earned': True}


if __name__ == '__main__':
    failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith('test_') and callable(fn):
            try:
                fn()
                print(f'ok    {name}')
            except Exception as exc:  # noqa: BLE001
                failed += 1
                import traceback
                print(f'FAIL  {name}: {exc!r}')
                traceback.print_exc(limit=2)
    sys.exit(1 if failed else 0)
