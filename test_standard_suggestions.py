"""Results a logged session suggests (src/standard_results.py).

    SUPABASE_URL='' .venv/bin/python test_standard_suggestions.py

The pure half reads each kind of logged outcome as a result — a for-time
clock, Cindy's rounds with a partial round, reps in six minutes, a hold, a
single on a lift a ×BW standard is read from — and finds a slot's entry in
the shapes the clients write (the web and the phone key by exercise id,
Garmin by name). The SQL half makes and drops its own database (never
training_test, the dev database; it skips without a local server) with
performance_logs shaped as production has it — UUID user id, none of 011's
columns — and drives the session-log routes: a logged test is a suggestion
and not a result until it is confirmed; a re-logged value corrects it; a
dismissal sticks; a watch's decision rides in the log.
"""
import os
import sys
import uuid
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

os.environ.setdefault('SUPABASE_URL', '')

FAILED = []


def check(name: str, ok: bool, detail: str = '') -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else f' — {detail}'}")
    if not ok:
        FAILED.append(name)


# ── pure ─────────────────────────────────────────────────────────────────────

def test_reading() -> None:
    print('reading a logged outcome as a result')
    from src import standard_results as sr
    from src.analytics import benchmarks_data as bd
    by = bd.by_id()
    row, cindy, clean = by['row_2km_minutes'], by['wod_cindy_rounds'], by['kb_pentathlon_clean_reps']

    v, inp = sr.read_result(row, 'duration', {'durationSec': 452})
    check('a for-time clock is read in the standard\'s minutes', abs(v - 452 / 60) < 1e-3 and inp == {'seconds': 452},
          f'{v} {inp}')
    check('…and prints as the clock', bd.format_value(row, v) == '7:32', bd.format_value(row, v))
    check('no clock, no result', sr.read_result(row, 'duration', {'durationSec': 0}) is None
          and sr.read_result(row, 'duration', {'sets': []}) is None)

    v, inp = sr.read_result(cindy, 'rounds', {'rounds': 20, 'sets': [{'setIndex': 0, 'repsActual': 7}]})
    check('Cindy: whole rounds, the partial round kept beside them', v == 20 and inp == {'rounds': 20, 'reps': 7},
          f'{v} {inp}')
    check('…and said as CrossFit says it', sr.input_text(inp) == '20 + 7', str(sr.input_text(inp)))
    v, _ = sr.read_result(cindy, 'rounds', {'sets': [{'reps': 18, 'weightKg': None}]}, log_source='garmin')
    check('a Garmin AMRAP before 2.0 wrote its rounds as reps', v == 18, str(v))
    check('…which from any other client is not a round count',
          sr.read_result(cindy, 'rounds', {'sets': [{'reps': 18}]}, log_source='web') is None)

    v, _ = sr.read_result(clean, 'reps', {'sets': [{'repsActual': 70}, {'repsActual': 32}]}, slot_type='time_domain')
    check('reps in a timed slot add up across its sets', v == 102, str(v))
    v, _ = sr.read_result(by['pull_up_reps'], 'reps', {'sets': [{'repsActual': 12}, {'repsActual': 9}]},
                          slot_type='sets_reps')
    check('max reps is the best set', v == 12, str(v))
    check('a set marked not done is not read',
          sr.read_result(clean, 'reps', {'sets': [{'repsActual': 70, 'completed': False}]}, slot_type='time_domain')
          is None)

    hs = next(b for b in by.values() if b['metric_type'] in ('time_seconds', 'time_sec'))
    v, _ = sr.read_result(hs, 'hold', {'sets': [{'durationSeconds': 35}, {'durationSeconds': 42}]})
    check('a hold is the longest one', v == 42, str(v))

    check('the heaviest completed single', sr.single_from_sets(
        {'sets': [{'weightKg': 130, 'repsActual': 3}, {'weightKg': 145, 'repsActual': 1},
                  {'weightKg': 150, 'repsActual': 1, 'completed': False}]}) == 145)


def test_finding() -> None:
    print('\nfinding a slot\'s entry in a log')
    from src import standard_results as sr
    a = {'exercise': {'id': 'row_2km_test', 'name': '2000m Row Time Trial'}, 'slot_role': 'row_2k'}
    entry = {'durationSec': 452}
    check('by id (web, phone)', sr.entries_for([a], {'row_2km_test': entry}) == [entry])
    check('by name (Garmin)', sr.entries_for([a], {'2000m Row Time Trial': entry}) == [entry])
    check('by name in another case', sr.entries_for([a], {'2000M ROW TIME TRIAL': entry}) == [entry])
    check('by the slot role as said', sr.entries_for([a], {'Row 2k': entry}) == [entry])
    twins = [{'exercise': {'id': 'x1', 'name': 'Push-up'}, 'slot_role': 'a'},
             {'exercise': {'id': 'x2', 'name': 'Push-up'}, 'slot_role': 'b'}]
    check('a name two slots share is not guessed at', sr.entries_for(twins, {'Push-up': entry}) == [None, None])
    check('…but their ids still find them', sr.entries_for(twins, {'x2': entry}) == [None, entry])


SESSION = {
    'modality': 'conditioning', 'archetype': {'id': 'gym_jones_row_2k_test', 'name': '2 km Row Test'},
    'test': {'archetype': 'gym_jones_row_2k_test', 'standards': ['row_2km_minutes']},
    'exercises': [
        {'exercise': {'id': 'row_easy', 'name': 'Easy Row'}, 'slot_role': 'warm_up', 'slot_type': 'time_domain'},
        {'exercise': {'id': 'row_2km_test', 'name': '2000m Row Time Trial'}, 'slot_role': 'row_2k',
         'slot_type': 'for_time', 'standard': {'id': 'row_2km_minutes', 'result': 'duration'}},
    ],
}


def test_candidates() -> None:
    print('\nwhat a log suggests')
    from src import standard_results as sr
    from src.analytics import benchmarks_data as bd
    by = bd.by_id()
    derived = sr.derived_map(list(by.values()))
    check('the derived lifts come from the standards\' YAML', 'back_squat_bw_ratio' in derived.get('back_squat', [])
          and 'back_squat_bw_ratio' in derived.get('mf_back_squat', []), str(derived.get('back_squat')))

    logs = {'bodyweight_kg': [{'id': 1, 'value': 80.0, 'loggedOn': '2026-10-01'}]}
    got, skipped = sr.candidates([SESSION], {'row_easy': {'durationSec': 600}, 'row_2km_test': {'durationSec': 452}},
                                 benchmarks=by, logs=logs, day='2026-10-05', derived=derived)
    check('the test slot suggests its standard, and nothing else does',
          [(c['benchmarkId'], c['origin'], c['sessionIndex']) for c in got] == [('row_2km_minutes', 'test_slot', 0)]
          and not skipped, f'{got} {skipped}')

    got, _ = sr.candidates([], {'back_squat': {'sets': [{'weightKg': 140, 'repsActual': 1}]}},
                           benchmarks=by, logs=logs, day='2026-10-05', derived=derived)
    check('a single on a derived lift suggests the ×BW result',
          [(c['benchmarkId'], c['value'], c['origin']) for c in got] == [('back_squat_bw_ratio', 1.75, 'derived_single')],
          str(got))
    check('…with the load kept', got[0]['input'] == {'kg': 140.0, 'reps': 1, 'bodyweightKg': 80.0, 'est': False},
          str(got[0]['input']))

    better = {**logs, 'back_squat_bw_ratio': [{'id': 9, 'value': 1.8, 'loggedOn': '2026-09-01'}]}
    got, _ = sr.candidates([], {'back_squat': {'sets': [{'weightKg': 140, 'repsActual': 1}]}},
                           benchmarks=by, logs=better, day='2026-10-05', derived=derived)
    check('a single that does not beat the current result suggests nothing', got == [], str(got))

    got, _ = sr.candidates([], {'Back Squat': {'sets': [{'weightKg': 140, 'reps': 1}]}}, benchmarks=by, logs=logs,
                           day='2026-10-05', derived=derived, names={'back squat': 'back_squat'})
    check('a Garmin log keyed by name is read too', [c['benchmarkId'] for c in got] == ['back_squat_bw_ratio'],
          str(got))

    got, skipped = sr.candidates([], {'back_squat': {'sets': [{'weightKg': 140, 'repsActual': 1}]}},
                                 benchmarks=by, logs={}, day='2026-10-05', derived=derived)
    check('without a bodyweight the single is skipped, and says why',
          got == [] and skipped == [{'benchmarkId': 'back_squat_bw_ratio', 'reason': 'no_bodyweight'}], str(skipped))

    got, _ = sr.candidates([], {'back_squat': {'sets': [{'weightKg': 120, 'repsActual': 5}]}},
                           benchmarks=by, logs=logs, day='2026-10-05', derived=derived)
    check('sets of five stay a read-time estimate', got == [], str(got))

    # The Garmin app since standards phase 6 (garmin/core/source/engine/Wire.mc):
    # keyed by exercise id, repsActual on a completed set — the reps the
    # athlete entered on the Results menu for a timed pentathlon set.
    pentathlon = {'exercises': [
        {'exercise': {'id': 'wk_kb_clean_single', 'name': 'KB Clean'}, 'slot_role': 'clean',
         'slot_type': 'time_domain', 'standard': {'id': 'kb_pentathlon_clean_reps', 'result': 'reps'}}]}
    got, _ = sr.candidates([pentathlon], {'wk_kb_clean_single': {'sets': [
        {'setIndex': 0, 'repsActual': 102, 'weightKg': 24, 'rpe': None, 'completed': True}]}},
        benchmarks=by, logs={}, day='2026-10-05', log_source='garmin')
    check("a Garmin set as the watch now sends it is read", [(c['benchmarkId'], c['value']) for c in got]
          == [('kb_pentathlon_clean_reps', 102.0)], str(got))


def test_decisions_and_words() -> None:
    print('\ndecisions and words')
    from src import standard_results as sr
    from src.analytics import benchmarks_data as bd
    d, problems = sr.normalise_decisions({'row_2km_minutes': {'decision': 'save', 'text': '7:30'},
                                          'wod_fran_minutes': {'decision': 'maybe'}})
    check('a save carries its value; anything else is reported',
          d == {'row_2km_minutes': {'decision': 'save', 'body': {'text': '7:30'}}} and len(problems) == 1,
          f'{d} {problems}')
    check('not an object is reported', sr.normalise_decisions(['x'])[1] != [])

    by = bd.by_id()
    rows = [{'id': 1, 'benchmarkId': 'row_2km_minutes', 'value': 452 / 60, 'loggedOn': '2026-10-05',
             'status': 'pending', 'origin': 'test_slot', 'sessionUid': 'v:w0-Monday-0', 'input': {'seconds': 452}}]
    logs = {'row_2km_minutes': [{'id': 3, 'value': 7.75, 'loggedOn': '2026-09-01'}]}
    out = sr.describe(rows, by, logs, 'male', None, {'v:w0-Monday-0': '2 km Row Test'})[0]
    check('it reads in the server\'s words', out['valueText'] == '7:32' and out['level'] is not None
          and out['sessionName'] == '2 km Row Test', str(out))
    check('…against the current result, and knows a new best', out['current']['valueText'] == '7:45'
          and out['isBest'] and out['bestText'] == '7:45', str(out))
    worse = sr.describe([{**rows[0], 'value': 8.0}], by, logs)[0]
    check('a slower row is not a best', not worse['isBest'])
    check("a result from the Apple Watch's log is the watch's",
          sr.result_source('apple_watch_live') == 'apple_watch' and sr.result_source('garmin') == 'garmin'
          and sr.result_source('manual') == 'session', sr.result_source('apple_watch_live'))


def run(wid: str = 'fit_file-run1', mps: float = 4.0, km: float = 5.2, sport: str = 'running',
        speed: bool = True, day: str = '2026-10-15') -> dict:
    """A FIT-shaped run: a point every 5 s at a steady speed."""
    from datetime import datetime as _dt, timedelta as _td
    t0 = _dt.fromisoformat(f'{day}T07:00:00+00:00')
    n = int(km * 1000 / (mps * 5)) + 1
    track = [{'timestamp': (t0 + _td(seconds=5 * i)).isoformat(), 'lat': 47.0, 'lng': 8.0,
              **({'speed': mps} if speed else {})} for i in range(n)]
    return {'id': wid, 'date': day, 'source': 'fit_file', 'activityType': sport.title(),
            'rawData': {'sport': sport}, 'distance': {'value': km, 'unit': 'km'}, 'gpsTrack': track}


def test_best_efforts() -> None:
    print('\nbest efforts from an imported run')
    from src import standard_results as sr
    from src.analytics import benchmarks_data as bd
    by = bd.by_id()
    check('the run standards declare their distance', by['run_1mile_minutes']['best_effort']['km'] == 1.609344
          and by['run_3mile_minutes']['best_effort']['label'] == '3 miles')
    # 4 m/s: a mile in 402 s (6:42), three in 1207 s.
    got = sr.effort_candidates([run()], by, {}, tracked={'run_1mile_minutes', 'run_3mile_minutes'})
    by_id = {c['benchmarkId']: c for c in got}
    check('a tracked standard gets its first result from a run that covers it',
          set(by_id) == {'run_1mile_minutes', 'run_3mile_minutes'}, str(sorted(by_id)))
    one = by_id.get('run_1mile_minutes') or {}
    check('…the fastest mile, the whole of it, in minutes', abs(one.get('value', 0) - 402.3 / 60) < 0.01,
          str(one.get('value')))
    check('…from the workout, on its day', one.get('workoutId') == 'fit_file-run1' and one.get('origin') == 'best_effort'
          and one.get('source') == 'workout' and one.get('loggedOn') == '2026-10-15', str(one))
    check('…said as what it is', sr.input_text(one.get('input')) == 'fastest 1 mile of 5.2 km',
          str(sr.input_text(one.get('input'))))
    check('a run too short for 5 miles suggests none', 'run_5mile_minutes' not in by_id)
    check('an untracked standard with no result suggests nothing',
          sr.effort_candidates([run()], by, {}, tracked=set()) == [])
    logs = {'run_1mile_minutes': [{'id': 1, 'value': 6.5, 'loggedOn': '2026-09-01'}]}
    got = sr.effort_candidates([run()], by, logs)
    check('a mile slower than the best suggests nothing', [c['benchmarkId'] for c in got] == [], str(got))
    got = sr.effort_candidates([run(mps=4.3)], by, logs)
    check('a mile faster than the best does', [c['benchmarkId'] for c in got] == ['run_1mile_minutes'], str(got))
    check('a ride is not a run', sr.effort_candidates([run(sport='cycling', mps=9)], by, logs) == [])
    check('positions without recorded speed are not read',
          sr.effort_candidates([run(mps=4.3, speed=False)], by, logs) == [])
    linked = {'fit_file-run1': {'sessionUid': 'v:w0-Monday-0', 'standards': {'run_3mile_minutes'}}}
    got = sr.effort_candidates([run(mps=3.0)], by, {'run_3mile_minutes': [{'id': 2, 'value': 20.0, 'loggedOn': '2026-09-01'}]},
                               linked=linked)
    three = [c for c in got if c['benchmarkId'] == 'run_3mile_minutes']
    check('a run matched to a test of the standard is that test, slower or not',
          len(three) == 1 and three[0]['sessionUid'] == 'v:w0-Monday-0' and three[0]['onlyNew'], str(got))


# ── SQL ──────────────────────────────────────────────────────────────────────

PRODUCTION_SHAPE = '''
CREATE TABLE performance_logs (
  id           BIGSERIAL PRIMARY KEY,
  user_id      UUID NOT NULL,
  benchmark_id TEXT NOT NULL,
  value        REAL NOT NULL,
  logged_at    TIMESTAMPTZ NOT NULL
);
CREATE TABLE session_logs (
  session_key TEXT NOT NULL, user_id TEXT NOT NULL,
  exercises JSONB NOT NULL DEFAULT '{}', notes TEXT DEFAULT '',
  fatigue_rating INTEGER, completed_at TIMESTAMPTZ,
  source TEXT DEFAULT 'web', avg_hr REAL, peak_hr REAL,
  session_uid TEXT,
  log_key TEXT GENERATED ALWAYS AS (COALESCE(session_uid, session_key)) STORED,
  PRIMARY KEY (user_id, log_key)
);
CREATE TABLE profiles (user_id TEXT PRIMARY KEY, profile_data JSONB);
CREATE TABLE user_programs (user_id TEXT PRIMARY KEY, program_data JSONB);
'''

USER = str(uuid.uuid4())
MONDAY = date.today() - timedelta(days=date.today().weekday())


def _squat_session() -> dict:
    return {'modality': 'max_strength', 'archetype': {'id': 'ss_novice_a', 'name': 'Workout A'},
            'exercises': [{'exercise': {'id': 'back_squat', 'name': 'Back Squat'}, 'slot_role': 'primary_squat',
                           'slot_type': 'sets_reps'}]}


def _mobility() -> dict:
    return {'modality': 'mobility', 'archetype': {'id': 'mob_flow', 'name': 'Mobility'},
            'exercises': [{'exercise': {'id': 'hip_flow', 'name': 'Hip Flow'}, 'slot_role': 'flow',
                           'slot_type': 'time_domain'}]}


def _envelope() -> dict:
    weeks = [{'week_number': n, 'phase': 'base', 'schedule': {
        'Monday': [SESSION], 'Wednesday': [_squat_session(), _mobility()]}} for n in (1, 2)]
    # Week 3: the test and a second session on one day.
    weeks.append({'week_number': 3, 'phase': 'base', 'schedule': {'Monday': [SESSION, _mobility()]}})
    return {'currentProgram': {'goal': {'id': 'gym_jones'}, 'weeks': weeks},
            'programStartDate': MONDAY.isoformat(), 'sourceGoalIds': ['gym_jones']}


def put(key: str, body: dict, by_uid: bool = False):
    import api
    from flask import g
    view = api.health_upsert_session_by_uid if by_uid else api.health_upsert_session
    with api.app.test_request_context(json=body, method='PUT'):
        g.user_id = USER
        resp = api.app.make_response(view.__wrapped__(key))
    return resp.status_code, resp.get_json()


def post(view_name: str, sid: int, body: dict | None = None):
    import api
    from flask import g
    with api.app.test_request_context(json=body or {}, method='POST'):
        g.user_id = USER
        resp = api.app.make_response(getattr(api, view_name).__wrapped__(sid))
    return resp.status_code, resp.get_json()


def sql_checks(dsn: str) -> None:
    import psycopg2
    import api  # noqa: F401 — its load_dotenv('.env.local', override=True) re-points DATABASE_URL
    import src.db
    from src import health_store, program_history as ph, standards_store as store
    if src.db.DATABASE_URL.split('?')[0] != dsn.split('?')[0]:
        print(f'Refusing to run: the store would write to {src.db.DATABASE_URL}, not the scratch database.')
        sys.exit(1)

    c = psycopg2.connect(dsn)
    c.autocommit = True
    with c.cursor() as cur:
        cur.execute(PRODUCTION_SHAPE)
        cur.execute('INSERT INTO profiles VALUES (%s, %s)', (USER, '{"timezone": "America/Los_Angeles"}'))
    ph._TABLES_CREATED = False
    ph._ensure_tables()
    health_store._TIMELINE_COLUMN_READY = None
    ph.record_version(USER, _envelope(), source='put')
    vid = ph.active_version_id(USER)
    test_uid = ph.session_uid(vid, 0, 'Monday', 0)

    print('\nsession logs → suggestions (PostgreSQL, production-shaped tables)')
    code, out = put('1-Monday-0', {'exercises': {'row_easy': {'durationSec': 600},
                                                 'row_2km_test': {'durationSec': 452}}, 'source': 'web'})
    pend = (out.get('standards') or {}).get('pending') or []
    check('a logged test slot comes back as a suggestion', code == 200 and [s['benchmarkId'] for s in pend]
          == ['row_2km_minutes'] and pend[0]['valueText'] == '7:32', f'{code} {out}')
    check('…on the test session, by its uid', pend and pend[0]['sessionUid'] == test_uid
          and pend[0]['sessionName'] == '2 km Row Test', str(pend))
    check('a suggestion is not a result', 'row_2km_minutes' not in store.list_results(USER))

    code, out = put('1-Monday-0', {'exercises': {'row_2km_test': {'durationSec': 450}}})
    pend = out['standards']['pending']
    check('a re-logged clock changes the suggestion, still one', len(pend) == 1 and pend[0]['valueText'] == '7:30',
          str(pend))
    code, out = put('1-Monday-0', {'exercises': {}, 'completedAt': f'{MONDAY}T18:00:00Z'})
    check('marking the session complete reads nothing', code == 200 and 'standards' not in out, str(out))

    sid = pend[0]['id']
    code, out = post('standards_confirm_suggestion', sid)
    rid = out.get('resultId')
    res = store.list_results(USER).get('row_2km_minutes') or []
    check('confirm makes it a result, from the session', code == 200 and len(res) == 1 and res[0]['id'] == rid
          and res[0]['source'] == 'session' and res[0]['sessionUid'] == test_uid, f'{out} {res}')
    check('…on the athlete\'s day it was first logged, where they are',
          res and res[0]['loggedOn'] == datetime.now(ZoneInfo('America/Los_Angeles')).date().isoformat(), str(res))
    code, again = post('standards_confirm_suggestion', sid)
    check('confirming twice keeps one result', again.get('resultId') == rid
          and len(store.list_results(USER)['row_2km_minutes']) == 1, str(again))

    code, out = put('1-Monday-0', {'exercises': {'row_2km_test': {'durationSec': 448}}})
    pend = out['standards']['pending']
    check('a corrected clock after confirming asks again', [s['valueText'] for s in pend] == ['7:28']
          and pend[0]['resultId'] == rid, str(out['standards']))
    check('…and says which result it corrects', pend and pend[0]['replacesText'] == '7:30', str(pend))
    post('standards_confirm_suggestion', sid)
    res = store.list_results(USER)['row_2km_minutes']
    check('…and the confirm corrects the same result', len(res) == 1 and res[0]['id'] == rid
          and abs(res[0]['value'] - 448 / 60) < 1e-3, str(res))

    code, out = post('standards_confirm_suggestion', sid, {'text': '7:20'})
    res = store.list_results(USER)['row_2km_minutes']
    check('a confirm may correct what was logged', code == 200 and abs(res[0]['value'] - 440 / 60) < 1e-3, str(res))

    print('\na single on a derived lift')
    code, out = put('1-Wednesday', {'exercises': {'back_squat': {'sets': [{'setIndex': 0, 'weightKg': 140,
                                                                            'repsActual': 1}]}}})
    st = out.get('standards') or {}
    check('without a bodyweight it is skipped, and the answer says why',
          st.get('pending') == [] and st.get('skipped') == [{'benchmarkId': 'back_squat_bw_ratio',
                                                             'reason': 'no_bodyweight'}], str(st))
    store.add_result(USER, 'bodyweight_kg', 80.0, logged_at=f'{MONDAY}T07:00:00Z', logged_on=MONDAY.isoformat())
    code, out = put('1-Wednesday', {'exercises': {'back_squat': {'sets': [{'setIndex': 0, 'weightKg': 140,
                                                                            'repsActual': 1}]}}})
    pend = out['standards']['pending']
    check('with one, a day-level key still finds it', [(s['benchmarkId'], s['valueText']) for s in pend]
          == [('back_squat_bw_ratio', '1.75×BW')], str(out['standards']))
    squat = pend[0]['id']
    with c.cursor() as cur:
        cur.execute("SELECT session_key FROM standard_result_suggestions WHERE origin = 'derived_single'")
        skeys = [r[0] for r in cur.fetchall()]
    check('a single without a session uid keys on its day too (a legacy key repeats in every program)',
          skeys and all(k.startswith('1-Wednesday@') for k in skeys), str(skeys))
    code, out = post('standards_dismiss_suggestion', squat)
    check('"Not a test" dismisses it', code == 200 and out['suggestion']['status'] == 'dismissed', str(out))
    code, out = put('1-Wednesday', {'exercises': {'back_squat': {'sets': [{'setIndex': 0, 'weightKg': 140,
                                                                            'repsActual': 1}]}}})
    check('…and a re-saved log does not bring it back', out['standards']['pending'] == [], str(out['standards']))
    check('dismissing twice is a 404', post('standards_dismiss_suggestion', squat)[0] == 404)
    code, out = post('standards_reopen_suggestion', squat)
    check('reopen undoes it', code == 200 and out['suggestion']['status'] == 'pending', str(out))
    code, out = put('1-Wednesday', {'exercises': {'back_squat': {'sets': [{'setIndex': 0, 'weightKg': 140,
                                                                            'repsActual': 3}]}}})
    check('a set changed to a triple takes the pending suggestion away', out['standards']['pending'] == [],
          str(out['standards']))

    code, out = put('1-Wednesday-1', {'exercises': {'hip_flow': {'durationSec': 900}}})
    check('a session with no standard in it reads nothing', code == 200 and 'standards' not in out, str(out))
    code, out = put('1-Wednesday', {'exercises': {'back_squat': {'sets': [{'setIndex': 0, 'weightKg': 100,
                                                                            'repsActual': 5}]}}})
    check('sets of five with nothing waiting read nothing', code == 200 and 'standards' not in out, str(out))
    code, out = put('1-Wednesday', {'exercises': {'back_squat': {'sets': [{'setIndex': 0, 'weightKg': 150,
                                                                            'repsActual': 1}]}},
                                    'standardResults': {'back_squat_bw_ratio': {'decision': 'save'}}})
    st = out.get('standards') or {}
    check('a decision in a log reaches only the standards that session tests',
          any('back_squat_bw_ratio' in p for p in st.get('problems', []))
          and not store.list_results(USER).get('back_squat_bw_ratio'), str(st))

    print('\na day with a test and another session')
    t3_uid = ph.session_uid(vid, 2, 'Monday', 0)
    code, out = put('3-Monday-0', {'source': 'garmin', 'exercises': {'2000m Row Time Trial': {'durationSec': 470}}})
    check('the watch\'s log of the test leaves a suggestion on its uid',
          [s['sessionUid'] for s in out['standards']['pending']] == [t3_uid], str(out.get('standards')))
    code, out = put('3-Monday', {'exercises': {'hip_flow': {'durationSec': 900}}})
    with c.cursor() as cur:
        cur.execute("SELECT count(*) FROM standard_result_suggestions WHERE session_uid = %s AND status = 'pending'",
                    (t3_uid,))
        left = cur.fetchone()[0]
    check('a web log of the other session leaves it alone', left == 1, str(left))

    print('\nthe watch decides in the log')
    code, out = put('2-Monday-0', {'source': 'garmin', 'exercises': {'2000m Row Time Trial': {'durationSec': 455}},
                                   'standardResults': {'row_2km_minutes': {'decision': 'save'},
                                                       'wod_fran_minutes': {'decision': 'save'}}})
    st = out['standards']
    conf = st['confirmed']
    res = store.list_results(USER)['row_2km_minutes']
    check('Save on the watch makes the result, from the watch',
          [s['valueText'] for s in conf] == ['7:35'] and len(res) == 2 and res[-1]['source'] == 'garmin', f'{st} {res}')
    check('a decision for a standard the session does not test is refused, and said',
          any('wod_fran_minutes' in p for p in st['problems']) and 'wod_fran_minutes' not in store.list_results(USER),
          str(st['problems']))

    print('\nrebuilding ahead carries a test\'s result and suggestion')
    from src.db import new_conn
    res_before = [e for e in store.list_results(USER).get('row_2km_minutes', []) if e['sessionUid'] == test_uid]
    conn = new_conn()
    try:
        with conn, conn.cursor() as cur:
            ph._carry_over(cur, USER, vid, 'vnext', [{'session_uid': test_uid}])
    finally:
        conn.close()
    new_uid = 'vnext' + test_uid[len(vid):]
    with c.cursor() as cur:
        cur.execute('SELECT count(*) FROM standard_result_suggestions WHERE session_uid = %s', (new_uid,))
        sugg = cur.fetchone()[0]
    res_after = [e for e in store.list_results(USER).get('row_2km_minutes', []) if e['sessionUid'] == new_uid]
    check('the suggestion and the result move to the successor\'s uid', sugg == 1
          and len(res_after) == len(res_before) == 1, f'{sugg} {res_before} {res_after}')
    conn = new_conn()
    try:
        with conn, conn.cursor() as cur:
            ph._carry_over(cur, USER, 'vnext', vid, [{'session_uid': new_uid}])   # put them back
    finally:
        conn.close()

    print('\nan imported run')
    from src import standard_results as sr2
    real_cps = sr2.current_program_standards
    sr2.current_program_standards = lambda uid: {'run_1mile_minutes': ['declared']}
    try:
        out = sr2.after_workouts_import(USER, [run('fit_file-run9', mps=4.0, km=2.0, day=MONDAY.isoformat())])
        pend = (out or {}).get('pending') or []
        check('a FIT run suggests the program\'s run standard',
              [(p['benchmarkId'], p['valueText'], p['origin']) for p in pend] == [('run_1mile_minutes', '6:42', 'best_effort')],
              str(out))
        check('…named by the activity, and said as the fastest mile',
              pend and pend[0]['sessionName'] == 'Running' and pend[0]['inputText'] == 'fastest 1 mile of 2 km', str(pend))
        again = sr2.after_workouts_import(USER, [run('fit_file-run9', mps=4.0, km=2.0, day=MONDAY.isoformat())])
        with c.cursor() as cur:
            cur.execute("SELECT count(*) FROM standard_result_suggestions WHERE origin = 'best_effort'")
            n = cur.fetchone()[0]
        check('the same run again is the same suggestion', n == 1, str(n))
        check('a workout with no speed costs nothing', sr2.after_workouts_import(USER, [run(speed=False)]) is None)
        run_sid = pend[0]['id'] if pend else 0
        code, res = post('standards_confirm_suggestion', run_sid)
        stored = store.list_results(USER).get('run_1mile_minutes') or []
        check('confirmed, it is a result from the workout', code == 200 and len(stored) == 1
              and stored[0]['source'] == 'workout' and stored[0]['workoutId'] == 'fit_file-run9', str(stored))
        out = sr2.after_workouts_import(USER, [run('fit_file-run10', mps=3.9, km=2.0, day=MONDAY.isoformat())])
        check('a slower mile the next day suggests nothing', out is None, str(out))
    finally:
        sr2.current_program_standards = real_cps

    print('\nthe old series delete')
    import api
    from flask import g
    real_del = store.delete_series
    store.delete_series = lambda *a, **k: (_ for _ in ()).throw(RuntimeError('down'))
    try:
        with api.app.test_request_context(method='DELETE'):
            g.user_id = USER
            resp = api.app.make_response(api.health_delete_performance.__wrapped__('run_1mile_minutes'))
    finally:
        store.delete_series = real_del
    check('a failed delete is a 503, not an HTML 500', resp.status_code == 503, str(resp.status_code))
    n = store.delete_series(USER, 'run_1mile_minutes')
    with c.cursor() as cur:
        cur.execute("SELECT status FROM standard_result_suggestions WHERE benchmark_id = 'run_1mile_minutes'")
        statuses = [r[0] for r in cur.fetchall()]
    check('deleting a series dismisses the suggestions its results came from',
          n == 1 and statuses and all(x == 'dismissed' for x in statuses), f'{n} {statuses}')

    print('\nfailures are said')
    store.delete_result(USER, rid)
    with c.cursor() as cur:
        cur.execute('SELECT status, performance_log_id FROM standard_result_suggestions WHERE id = %s', (sid,))
        status, plid = cur.fetchone()
    check('deleting a confirmed result dismisses its suggestion', status == 'dismissed' and plid is None,
          f'{status} {plid}')
    real = health_store.upsert_session_log
    health_store.upsert_session_log = lambda *a, **k: None
    try:
        code, out = put('1-Monday-0', {'exercises': {'row_2km_test': {'durationSec': 451}}})
    finally:
        health_store.upsert_session_log = real
    check('a session log that was not saved is a 503, not "saved"', code == 503, f'{code} {out}')
    code, out = put('1-Monday-0', {'exercises': {'row_2km_test': {}}})
    check('clearing a dismissed test\'s clock leaves it dismissed', out['standards']['pending'] == [], str(out))
    c.close()


def main() -> None:
    test_reading()
    test_finding()
    test_candidates()
    test_decisions_and_words()
    test_best_efforts()

    admin = os.environ.get('TEST_ADMIN_DSN', 'postgresql://localhost:5432/postgres?sslmode=disable')
    if 'supabase' in admin or 'pooler' in admin:
        print('Refusing to run against what looks like a production database.')
        sys.exit(1)
    try:
        import psycopg2
        conn = psycopg2.connect(admin)
        conn.autocommit = True
    except Exception as exc:
        print(f'\nNo local PostgreSQL available ({exc.__class__.__name__}) — skipping the SQL half.')
        conn = None
    if conn is not None:
        name = f'suggestions_test_{os.getpid()}'
        with conn.cursor() as cur:
            cur.execute(f'CREATE DATABASE {name}')
        try:
            dsn = admin.rsplit('/', 1)[0] + f'/{name}?sslmode=disable'
            os.environ['DATABASE_URL'] = dsn
            import importlib
            import src.db
            importlib.reload(src.db)            # it reads DATABASE_URL at import time
            sql_checks(dsn)
        finally:
            import src.db
            src.db.close_conn()
            with conn.cursor() as cur:
                cur.execute(f'DROP DATABASE IF EXISTS {name} WITH (FORCE)')
            conn.close()
    if FAILED:
        print(f'\n{len(FAILED)} failed')
        sys.exit(1)
    print('\nall standard suggestion checks passed')


if __name__ == '__main__':
    main()
