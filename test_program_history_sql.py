#!/usr/bin/env python
"""Program history against a real PostgreSQL: the timeline and the acceptance test.

The question this feature exists to answer is the one at the bottom of this
file: after a program has been replaced, can a workout that landed inside the
*old* block still be matched to the session that was actually planned for it?
Before program history the answer was no — the matcher indexed only the stored
program, so such a workout had no candidates and was dropped for good.

Needs a local PostgreSQL; skips cleanly (exit 0) without one.

    brew services start postgresql@14 && createdb training_test
    .venv/bin/python test_program_history_sql.py
"""
import os
import sys
from datetime import date, timedelta

TEST_DSN = os.environ.get('TEST_DATABASE_URL',
                          'postgresql://localhost:5432/training_test?sslmode=disable')
import psycopg2
try:
    psycopg2.connect(TEST_DSN).close()
except Exception as e:
    print('no local pg, skipping:', e)
    sys.exit(0)

os.environ['DATABASE_URL'] = TEST_DSN
os.environ['SUPABASE_URL'] = ''
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src import health_store
from src import program_history as ph
from src import workout_matcher as wm

_failures: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  ok   {label}')
    else:
        print(f'  FAIL {label}' + (f' — {detail}' if detail else ''))
        _failures.append(label)


conn = psycopg2.connect(TEST_DSN)
conn.autocommit = True


def reset() -> None:
    with conn.cursor() as c:
        c.execute('''
            DROP TABLE IF EXISTS program_versions, program_activations,
                                 planned_sessions, workout_matches,
                                 workout_match_suggestions, session_logs,
                                 workouts, user_programs CASCADE;
            CREATE TABLE workouts (
                id TEXT NOT NULL, user_id TEXT NOT NULL, source TEXT NOT NULL,
                date DATE NOT NULL, start_time TIMESTAMPTZ, end_time TIMESTAMPTZ,
                duration_minutes INTEGER, activity_type TEXT,
                inferred_modality_id TEXT, hr_avg REAL, hr_max REAL, hr_min REAL,
                calories INTEGER, distance_value REAL, distance_unit TEXT,
                raw_data JSONB DEFAULT '{}', gps_track JSONB,
                elevation_gain INTEGER, elevation_loss INTEGER, hr_samples JSONB,
                dedupe_key TEXT, canonical_id TEXT,
                PRIMARY KEY (id, user_id));
            CREATE TABLE workout_matches (
                imported_workout_id TEXT NOT NULL, user_id TEXT NOT NULL,
                session_key TEXT NOT NULL, match_confidence TEXT NOT NULL,
                matched_at TIMESTAMPTZ NOT NULL, session_uid TEXT,
                PRIMARY KEY (imported_workout_id, user_id));
            CREATE TABLE workout_match_suggestions (
                imported_workout_id TEXT NOT NULL, user_id TEXT NOT NULL,
                session_key TEXT NOT NULL, score INTEGER NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW(), session_uid TEXT,
                PRIMARY KEY (imported_workout_id, user_id));
            CREATE TABLE user_programs (
                user_id TEXT PRIMARY KEY, program_data JSONB,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW());
            CREATE TABLE session_logs (
                session_key TEXT NOT NULL, user_id TEXT NOT NULL,
                exercises JSONB NOT NULL DEFAULT '{}', notes TEXT DEFAULT '',
                fatigue_rating INTEGER, completed_at TIMESTAMPTZ,
                source TEXT DEFAULT 'web', avg_hr REAL, peak_hr REAL,
                -- no exercise_timeline: production never had it; the writer adds it
                session_uid TEXT,
                log_key TEXT GENERATED ALWAYS AS (COALESCE(session_uid, session_key)) STORED,
                PRIMARY KEY (user_id, log_key));
        ''')
    ph._TABLES_CREATED = False
    ph._ensure_tables()
    health_store._TIMELINE_COLUMN_READY = None


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


TODAY = date.today()
START_A = monday_of(TODAY - timedelta(days=28))     # four weeks of history


def session(modality: str, arch: str, minutes: int) -> dict:
    return {'modality': modality,
            'archetype': {'id': arch, 'name': arch.title(),
                          'duration_estimate_minutes': minutes},
            'exercises': [{'exercise': {'id': arch + '_ex'},
                           'slot': {'slot_type': 'time_domain'}}]}


def program(modality: str, arch: str, minutes: int, weeks: int = 8,
            start: date | None = START_A) -> dict:
    return {
        'currentProgram': {
            'goal': {'id': '_phil_' + arch, 'name': arch.title() + ' Plan'},
            'constraints': {'training_level': 'intermediate'},
            'weeks': [
                {'week_number': n, 'phase': 'base', 'schedule': {
                    'Monday': [session(modality, arch, minutes)],
                }}
                for n in range(1, weeks + 1)
            ],
        },
        'programStartDate': start.isoformat() if start else None,
        'sourceGoalIds': [arch],
    }


U = 'history-test-user'
PROG_A = program('aerobic_base', 'z2_run', 60)
PROG_B = program('max_strength', 'squat_day', 60)


# ── The timeline ─────────────────────────────────────────────────────────────

def test_bootstrap() -> None:
    print('\narchiving a program that is already under way')
    reset()
    out = ph.record_version(U, PROG_A, source='heal', source_revision='rev-1')
    check('recorded', out['recorded'], out['reason'])

    acts = ph.list_activations(U)
    check('one activation', len(acts) == 1, str(len(acts)))
    check('it runs from the program start date, not from today',
          acts and acts[0]['effectiveFrom'] == START_A.isoformat(),
          acts[0]['effectiveFrom'] if acts else '')
    check('it is open', acts and acts[0]['isActive'])
    check('8 weeks of sessions were flattened',
          acts and acts[0]['sessionCount'] == 8, str(acts[0]['sessionCount']))
    check('the revision short-circuit now recognises it',
          ph.is_archived(U, 'rev-1'))
    check('...and does not recognise a different revision',
          not ph.is_archived(U, 'rev-2'))


def test_idempotent_under_a_heal_storm() -> None:
    print('\nre-recording the same plan (the GET heal storm)')
    reset()
    ph.record_version(U, PROG_A, source='put', source_revision='rev-1')
    for _ in range(5):
        out = ph.record_version(U, PROG_A, source='heal')
        check('a repeat is not a new activation', out['reason'] == 'already_active',
              out['reason'])
    check('still one activation', len(ph.list_activations(U)) == 1)

    with conn.cursor() as c:
        c.execute('SELECT COUNT(*) FROM program_versions WHERE user_id = %s', (U,))
        check('still one version', c.fetchone()[0] == 1)
        c.execute('SELECT COUNT(*) FROM planned_sessions WHERE user_id = %s', (U,))
        check('still 8 planned sessions', c.fetchone()[0] == 8)

    # The three heals rebuild goal and volume_summary; none is a new plan.
    healed = {**PROG_A, 'currentProgram': {**PROG_A['currentProgram'],
                                           'volume_summary': [{'week': 1}],
                                           'goal': {'id': 'x', 'name': 'Rebuilt'}}}
    out = ph.record_version(U, healed, source='heal')
    check('a healed envelope is not a new plan', out['reason'] == 'already_active',
          out['reason'])
    check('and still one activation', len(ph.list_activations(U)) == 1)


def test_regenerate_splits_the_timeline() -> None:
    print('\nregenerating splits the timeline at today')
    reset()
    ph.record_version(U, PROG_A, source='heal', source_revision='rev-1')
    # Attach a log so the same-day squash cannot fire.
    vid_a = ph.version_id(U, PROG_A)
    with conn.cursor() as c:
        c.execute("INSERT INTO session_logs (session_key, user_id, session_uid, completed_at) "
                  "VALUES ('1-Monday-0', %s, %s, NOW())",
                  (U, ph.session_uid(vid_a, 0, 'Monday', 0)))
    out = ph.record_version(U, PROG_B, source='put', source_revision='rev-2')
    check('the regenerate was recorded', out['recorded'], out['reason'])

    acts = ph.list_activations(U)
    check('two activations', len(acts) == 2, str(len(acts)))
    new, old = acts[0], acts[-1]
    check('the new plan owns today',
          new['effectiveFrom'] == TODAY.isoformat(), new['effectiveFrom'])
    check('the new plan is open', new['effectiveTo'] is None)
    check('the old plan closes where the new one starts',
          old['effectiveTo'] == TODAY.isoformat(), str(old['effectiveTo']))
    check('the old plan keeps its own start',
          old['effectiveFrom'] == START_A.isoformat(), old['effectiveFrom'])
    check('the old plan is no longer active', not old['isActive'])
    check('a new start date was not involved, so the lineage is shared',
          new['lineageId'] == old['lineageId'])


def test_rebuilding_ahead_continues_the_block() -> None:
    print('\nrebuilding the weeks ahead keeps the block going')
    reset()
    ph.record_version(U, PROG_A, source='heal', source_revision='rev-1')
    vid_a = ph.version_id(U, PROG_A)
    # Weeks whose Monday is behind the athlete (or is today).
    elapsed = (TODAY - START_A).days // 7 + 1
    # A match, a suggestion and a log on elapsed sessions; one log ahead.
    with conn.cursor() as c:
        c.execute("INSERT INTO workout_matches (imported_workout_id, user_id, session_key, "
                  "match_confidence, matched_at, session_uid) "
                  "VALUES ('w-1', %s, '1-Monday-0', 'auto', NOW(), %s)",
                  (U, ph.session_uid(vid_a, 0, 'Monday', 0)))
        c.execute("INSERT INTO workout_match_suggestions (imported_workout_id, user_id, "
                  "session_key, score, session_uid) VALUES ('w-2', %s, '2-Monday-0', 60, %s)",
                  (U, ph.session_uid(vid_a, 1, 'Monday', 0)))
        c.execute("INSERT INTO session_logs (session_key, user_id, session_uid, completed_at) "
                  "VALUES ('2-Monday-0', %s, %s, NOW())",
                  (U, ph.session_uid(vid_a, 1, 'Monday', 0)))
        c.execute("INSERT INTO session_logs (session_key, user_id, session_uid) "
                  "VALUES ('8-Monday-0', %s, %s)",
                  (U, ph.session_uid(vid_a, 7, 'Monday', 0)))
    insert_workout('w-1', START_A, 'aerobic_base', 60)

    # Weeks behind the athlete kept, the rest rebuilt as strength.
    rebuilt = program('aerobic_base', 'z2_run', 60)
    for w in rebuilt['currentProgram']['weeks'][elapsed:]:
        w['schedule'] = {'Monday': [session('max_strength', 'squat_day', 60)]}
    out = ph.record_version(U, rebuilt, source='put', source_revision='rev-2')
    vid_b = ph.version_id(U, rebuilt)
    check('the rebuild continues the block', out['reason'] == 'continued', out['reason'])
    check('three rows carried over', out.get('carried') == 3, str(out.get('carried')))

    acts = ph.list_activations(U)
    check('two activations: the change is on the record', len(acts) == 2, str(len(acts)))
    new, old = acts[0], acts[-1]
    check('the rebuild owns the block from its start',
          new['effectiveFrom'] == START_A.isoformat(), new['effectiveFrom'])
    check('the old version closes empty',
          old['effectiveFrom'] == old['effectiveTo'] == START_A.isoformat(),
          f"{old['effectiveFrom']}..{old['effectiveTo']}")
    check('one lineage', new['lineageId'] == old['lineageId'])
    check('the rebuild carries the match and the log',
          new['matchedCount'] == 1 and new['loggedCount'] == 1,
          f"{new['matchedCount']} / {new['loggedCount']}")

    with conn.cursor() as c:
        c.execute('SELECT session_uid FROM workout_match_suggestions WHERE user_id = %s', (U,))
        check('the suggestion moved', c.fetchone()[0] == ph.session_uid(vid_b, 1, 'Monday', 0))
        c.execute("SELECT session_uid FROM session_logs WHERE user_id = %s "
                  "AND session_key = '8-Monday-0'", (U,))
        check('a log on a rebuilt session stays with the old version',
              c.fetchone()[0] == ph.session_uid(vid_a, 7, 'Monday', 0))

    matches = health_store.get_matches(U)
    check('the match is in the current program',
          matches and matches[0]['inCurrentProgram'] is True, str(matches))
    check("...under the rebuild's uid",
          matches and matches[0]['sessionUid'] == ph.session_uid(vid_b, 0, 'Monday', 0))
    check('elapsed dates resolve to the rebuild',
          {c['sessionUid'].split(':')[0]
           for cs in ph.sessions_on_dates(U, [START_A.isoformat()]).values() for c in cs}
          == {vid_b})


def test_restoring_a_rewritten_past_repairs_the_block() -> None:
    print('\nrestoring the days a regenerate rewrote puts the block back together')
    reset()
    ph.record_version(U, PROG_A, source='heal')
    vid_a = ph.version_id(U, PROG_A)
    with conn.cursor() as c:
        c.execute("INSERT INTO workout_matches (imported_workout_id, user_id, session_key, "
                  "match_confidence, matched_at, session_uid) "
                  "VALUES ('w-1', %s, '1-Monday-0', 'auto', NOW(), %s)",
                  (U, ph.session_uid(vid_a, 0, 'Monday', 0)))
    insert_workout('w-1', START_A, 'aerobic_base', 60)

    # The old client's "from tomorrow": every week rewritten, the past too.
    bad = program('max_strength', 'squat_day', 60)
    out = ph.record_version(U, bad, source='put')
    check('rewriting the past is a switch', out['reason'] == 'activated', out['reason'])
    check('...which takes the match off the current program',
          health_store.get_matches(U)[0]['inCurrentProgram'] is False)

    # The repair: the elapsed days as they were, the rebuilt days kept.
    elapsed = (TODAY - START_A).days // 7 + (0 if TODAY.weekday() == 0 else 1)
    repaired = program('max_strength', 'squat_day', 60)
    for w in repaired['currentProgram']['weeks'][:elapsed]:
        w['schedule'] = {'Monday': [session('aerobic_base', 'z2_run', 60)]}
    out = ph.record_version(U, repaired, source='put')
    vid_r = ph.version_id(U, repaired)
    check('the repair continues the block', out['reason'] == 'continued', out['reason'])
    acts = ph.list_activations(U)
    active = [a for a in acts if a['isActive']]
    rest = [a for a in acts if not a['isActive']]
    check('it runs from the block start',
          len(active) == 1 and active[0]['versionId'] == vid_r
          and active[0]['effectiveFrom'] == START_A.isoformat(), str(active))
    check('both earlier versions close empty',
          len(rest) == 2 and all(a['effectiveFrom'] == a['effectiveTo'] for a in rest),
          str([(a['effectiveFrom'], a['effectiveTo']) for a in rest]))
    m = health_store.get_matches(U)[0]
    check('the match is back on the current program',
          m['inCurrentProgram'] is True and m['sessionUid'].startswith(vid_r + ':'), str(m))



def test_a_regenerate_keeps_the_day_already_trained() -> None:
    print('\na whole-program regenerate keeps the past, and today once it is trained')
    reset()
    from src.program_keys import DAY_NAMES

    def every_day(name: str) -> dict:
        prog = program('power', 'kb_ballistic_session', 30)
        for w in prog['currentProgram']['weeks']:
            w['schedule'] = {d: [session('power', 'kb_ballistic_session', 30)] for d in DAY_NAMES}
            for ss in w['schedule'].values():
                # Its own name and movements; the archetype id is the same.
                ss[0]['archetype']['name'] = name
                ss[0]['exercises'][0]['exercise']['id'] = name.lower().replace(' ', '_')
        return prog

    old = every_day('KB Ballistic Power Session')
    ph.record_version(U, old, source='heal')
    vid_old = ph.version_id(U, old)
    wi, offset = divmod((TODAY - START_A).days, 7)
    today_uid = ph.session_uid(vid_old, wi, DAY_NAMES[offset], 0)
    check('nothing trained today yet', ph.trained_on(U, TODAY) is False)
    with conn.cursor() as c:
        c.execute("INSERT INTO workout_matches (imported_workout_id, user_id, session_key, "
                  "match_confidence, matched_at, session_uid) VALUES ('w-today', %s, 'k', 'manual', NOW(), %s)",
                  (U, today_uid))
    check('a matched workout makes today trained', ph.trained_on(U, TODAY) is True)

    # A contract module shares the archetype id; only the name says it is a
    # different session (Wildman's swing module, 2026-10-19).
    new = every_day('Nerd Math Two-Hand Swing')
    check('a different name is a different day',
          ph.divergence_date(ph.flatten_program('a', old), ph.flatten_program('b', new), START_A) == START_A)
    kept, changed = ph.restore_elapsed(U, new, TODAY + timedelta(days=1))
    days = {d for d, *_ in changed}
    check('every elapsed day and today are given back', days == {START_A + timedelta(days=n)
          for n in range((TODAY - START_A).days + 1)}, str(sorted(days))[:120])
    week = kept['currentProgram']['weeks'][wi]['schedule']
    tomorrow = TODAY + timedelta(days=1)
    tw, toff = divmod((tomorrow - START_A).days, 7)
    check("today keeps the session that was trained",
          week[DAY_NAMES[offset]][0]['archetype']['name'] == 'KB Ballistic Power Session')
    check('tomorrow is the new plan',
          kept['currentProgram']['weeks'][tw]['schedule'][DAY_NAMES[toff]][0]['archetype']['name']
          == 'Nerd Math Two-Hand Swing')
    out = ph.record_version(U, kept, source='generate')
    check('the block continues', out['reason'] == 'continued', out['reason'])
    m = health_store.get_matches(U)[0]
    check("today's match is on the current program",
          m['inCurrentProgram'] is True and m['sessionUid'].startswith(out['versionId'] + ':'), str(m))


def test_intervals_are_disjoint() -> None:
    print('\nno date resolves to two plans')
    days = [(START_A + timedelta(days=i)).isoformat() for i in range(0, 60)]
    index = ph.sessions_on_dates(U, days)
    over = {d: c for d, c in index.items() if len(c) > 1}
    check('every date has at most one candidate', not over, str(over))

    version_of = {}
    for d, candidates in index.items():
        version_of[d] = {c['sessionUid'].split(':')[0] for c in candidates}
    check('no date draws from two versions',
          all(len(v) == 1 for v in version_of.values()))


def test_a_new_start_date_starts_a_new_lineage() -> None:
    print('\na new start date starts a new lineage')
    reset()
    ph.record_version(U, PROG_A, source='heal')
    restarted = program('aerobic_base', 'z2_run', 60, start=monday_of(TODAY))
    ph.record_version(U, restarted, source='put')
    acts = ph.list_activations(U)
    check('two activations', len(acts) == 2, str(len(acts)))
    check('the lineages differ', acts[0]['lineageId'] != acts[-1]['lineageId'])


def test_same_day_squash() -> None:
    print('\nediting twice in one day squashes')
    reset()
    ph.record_version(U, PROG_A, source='heal')          # from START_A, not today
    a = ph.record_version(U, PROG_B, source='put')        # opens today
    check('the regenerate chained', a['reason'] == 'activated', a['reason'])

    edited = program('mixed_modal_conditioning', 'metcon', 45)
    b = ph.record_version(U, edited, source='put')
    check('an unreferenced same-day edit squashed', b['reason'] == 'squashed',
          b['reason'])
    acts = ph.list_activations(U)
    check('still two activations, not three', len(acts) == 2, str(len(acts)))
    check('the open one now points at the edit',
          acts[0]['versionId'] == ph.version_id(U, edited))
    check('and kept its effective_from', acts[0]['effectiveFrom'] == TODAY.isoformat())

    # Once something references it, the squash must stop.
    with conn.cursor() as c:
        c.execute("INSERT INTO workout_matches (imported_workout_id, user_id, "
                  "session_key, match_confidence, matched_at, session_uid) "
                  "VALUES ('w-ref', %s, '1-Monday-0', 'auto', NOW(), %s)",
                  (U, ph.session_uid(ph.version_id(U, edited), 0, 'Monday', 0)))
    again = program('durability', 'mobility_day', 30)
    c3 = ph.record_version(U, again, source='put')
    # Only days ahead changed, so it carries on the block — chained, not squashed.
    check('a referenced same-day version is not squashed away',
          c3['reason'] == 'continued', c3['reason'])
    check('now three activations', len(ph.list_activations(U)) == 3)


def test_no_start_date_is_a_clean_skip() -> None:
    print('\na program with no start date')
    reset()
    out = ph.record_version(U, program('aerobic_base', 'z2_run', 60, start=None))
    check('is skipped, not an error', out['recorded'] is False
          and out['reason'] == 'no_start_date', out['reason'])
    check('and writes no activation', ph.list_activations(U) == [])

    out = ph.record_version(U, {'currentProgram': {'weeks': []},
                                'programStartDate': START_A.isoformat()})
    check('an empty program is skipped too', out['reason'] == 'no_weeks', out['reason'])


def test_resolve_session() -> None:
    print('\nresolving a stored reference back to its planned session')
    reset()
    ph.record_version(U, PROG_A, source='heal')
    vid = ph.version_id(U, PROG_A)
    uid = ph.session_uid(vid, 2, 'Monday', 0)

    by_uid = ph.resolve_session(U, session_uid=uid)
    check('by uid', by_uid is not None and by_uid['week_index'] == 2)
    check('an unknown uid resolves to nothing',
          ph.resolve_session(U, session_uid='nope:w0-Monday-0') is None)

    week3_date = (START_A + timedelta(days=14)).isoformat()
    by_key = ph.resolve_session(U, legacy_key='3-Monday-0', date_str=week3_date)
    check('by legacy key and date', by_key is not None and by_key['session_uid'] == uid,
          str(by_key))
    check('a legacy key with the wrong date resolves to nothing',
          ph.resolve_session(U, legacy_key='3-Monday-0',
                             date_str=(START_A + timedelta(days=7)).isoformat()) is None)
    check('widening finds a one-day slip',
          ph.resolve_session(U, legacy_key='3-Monday-0',
                             date_str=(START_A + timedelta(days=15)).isoformat(),
                             widen=True) is not None)
    check('...and is off by default',
          ph.resolve_session(U, legacy_key='3-Monday-0',
                             date_str=(START_A + timedelta(days=15)).isoformat()) is None)


def test_prune_respects_references() -> None:
    print('\npruning')
    reset()
    ph.record_version(U, PROG_A, source='heal')
    vid_a = ph.version_id(U, PROG_A)
    with conn.cursor() as c:
        c.execute("INSERT INTO workout_matches (imported_workout_id, user_id, "
                  "session_key, match_confidence, matched_at, session_uid) "
                  "VALUES ('w1', %s, '1-Monday-0', 'auto', NOW(), %s)",
                  (U, ph.session_uid(vid_a, 0, 'Monday', 0)))
    ph.record_version(U, PROG_B, source='put')

    check('pruning to nothing keeps the referenced version',
          ph.prune_versions(U, keep=0) == 0)
    with conn.cursor() as c:
        c.execute('SELECT COUNT(*) FROM program_versions WHERE user_id = %s AND id = %s',
                  (U, vid_a))
        check('version A survives', c.fetchone()[0] == 1)

    # An unreferenced, closed version is fair game.
    reset()
    ph.record_version(U, PROG_A, source='heal')
    ph.record_version(U, program('durability', 'mobility_day', 30), source='put')
    ph.record_version(U, PROG_B, source='put')
    removed = ph.prune_versions(U, keep=1)
    check('an unreferenced closed version is pruned', removed >= 1, str(removed))
    check('the open one is never pruned',
          any(a['isActive'] for a in ph.list_activations(U)))


# ── The acceptance test ──────────────────────────────────────────────────────

def test_matching_inside_a_finished_block() -> None:
    print('\nACCEPTANCE — matching a workout that landed inside a finished block')
    reset()
    ph.record_version(U, PROG_A, source='heal', source_revision='rev-1')
    vid_a = ph.version_id(U, PROG_A)
    with conn.cursor() as c:   # a log, so the regenerate cannot squash A away
        c.execute("INSERT INTO session_logs (session_key, user_id, session_uid, completed_at) "
                  "VALUES ('1-Monday-0', %s, %s, NOW())",
                  (U, ph.session_uid(vid_a, 0, 'Monday', 0)))
    ph.record_version(U, PROG_B, source='put', source_revision='rev-2')
    vid_b = ph.version_id(U, PROG_B)

    # A Zone 2 run done in week 3 of the old block, imported only now.
    past_monday = START_A + timedelta(days=14)
    old_workout = {'id': 'fit_file-old', 'date': past_monday.isoformat(),
                   'inferredModalityId': 'aerobic_base', 'durationMinutes': 62}

    # What the old behaviour would do: index the CURRENT program only.
    current_index = wm.index_sessions_by_date(PROG_B['currentProgram'],
                                             PROG_B['programStartDate'])
    before = wm.auto_match_indexed([old_workout], current_index, [])
    check('against the current program alone it is a strength day, so no auto-match',
          not before['confirmed'], str(before))

    # What history does.
    history_index = ph.sessions_on_dates(U, [old_workout['date']])
    after = wm.auto_match_indexed([old_workout], history_index, [])
    check('against history it matches', len(after['confirmed']) == 1, str(after))
    if after['confirmed']:
        m = after['confirmed'][0]
        check('it matches the old block\'s week 3 Monday', m['sessionKey'] == '3-Monday-0',
              m['sessionKey'])
        check('and carries the OLD version\'s session uid',
              m.get('sessionUid', '').startswith(vid_a + ':'), str(m.get('sessionUid')))
        check('not the new version\'s',
              not m.get('sessionUid', '').startswith(vid_b + ':'))

    # A workout inside the new block resolves to the new block.
    next_monday = monday_of(TODAY + timedelta(days=7))
    new_workout = {'id': 'fit_file-new', 'date': next_monday.isoformat(),
                   'inferredModalityId': 'max_strength', 'durationMinutes': 58}
    out = wm.auto_match_indexed([new_workout],
                                ph.sessions_on_dates(U, [new_workout['date']]), [])
    check('a workout in the new block matches the new block',
          len(out['confirmed']) == 1
          and out['confirmed'][0]['sessionUid'].startswith(vid_b + ':'),
          str(out))

    # And the old block's *unrun* weeks are excluded — it was superseded.
    future_in_a = [(TODAY + timedelta(days=d)).isoformat() for d in range(1, 21)]
    from_a = [c for d in future_in_a
              for c in ph.sessions_on_dates(U, [d]).get(d, [])
              if c['sessionUid'].startswith(vid_a + ':')]
    check('the superseded plan\'s remaining weeks are not candidates', not from_a,
          str(from_a))


def insert_workout(wid: str, when: date, modality: str, minutes: int) -> dict:
    with conn.cursor() as c:
        c.execute("""INSERT INTO workouts (id, user_id, source, date, start_time,
                       end_time, duration_minutes, activity_type,
                       inferred_modality_id)
                     VALUES (%s, %s, 'fit_file', %s, %s, %s, %s, 'running', %s)
                     ON CONFLICT (id, user_id) DO NOTHING""",
                  (wid, U, when, when, when, minutes, modality))
    return {'id': wid, 'date': when.isoformat(), 'inferredModalityId': modality,
            'durationMinutes': minutes}


def test_match_and_store_without_history() -> None:
    """The union index must never do worse than indexing the current program."""
    print('\nmatch_and_store with an empty history (fresh deploy / local dev)')
    reset()
    import json as _json
    with conn.cursor() as c:
        c.execute('INSERT INTO user_programs (user_id, program_data) VALUES (%s, %s)',
                  (U, _json.dumps(PROG_A)))

    when = START_A + timedelta(days=7)
    workout = insert_workout('fit_file-nohist', when, 'aerobic_base', 60)
    check('history really is empty', ph.list_activations(U) == [])

    out = wm.match_and_store(U, [workout])
    check('it still auto-matched', out['confirmed'] == 1, str(out))
    with conn.cursor() as c:
        c.execute('SELECT session_key, session_uid FROM workout_matches '
                  'WHERE user_id = %s AND imported_workout_id = %s',
                  (U, workout['id']))
        row = c.fetchone()
    check('via the current program, so the legacy key is right',
          row and row[0] == '2-Monday-0', str(row))
    check('and no uid could be resolved, which is honest', row and row[1] is None,
          str(row))


def test_match_and_store_with_history() -> None:
    print('\nmatch_and_store across a replaced program')
    reset()
    import json as _json
    ph.record_version(U, PROG_A, source='heal', source_revision='rev-1')
    vid_a = ph.version_id(U, PROG_A)
    with conn.cursor() as c:     # pin A so the regenerate cannot squash it
        c.execute("INSERT INTO session_logs (session_key, user_id, session_uid, "
                  "completed_at) VALUES ('1-Monday-0', %s, %s, NOW())",
                  (U, ph.session_uid(vid_a, 0, 'Monday', 0)))
    ph.record_version(U, PROG_B, source='put', source_revision='rev-2')
    with conn.cursor() as c:     # PROG_B is what is stored now
        c.execute('INSERT INTO user_programs (user_id, program_data) VALUES (%s, %s) '
                  'ON CONFLICT (user_id) DO UPDATE SET program_data = EXCLUDED.program_data',
                  (U, _json.dumps(PROG_B)))

    when = START_A + timedelta(days=14)          # week 3 Monday of the old block
    workout = insert_workout('fit_file-hist', when, 'aerobic_base', 62)
    out = wm.match_and_store(U, [workout])
    check('the old-block workout auto-matched', out['confirmed'] == 1, str(out))

    with conn.cursor() as c:
        c.execute('SELECT session_key, session_uid FROM workout_matches '
                  'WHERE user_id = %s AND imported_workout_id = %s',
                  (U, workout['id']))
        row = c.fetchone()
    check('it points at the old block\'s week 3 Monday', row and row[0] == '3-Monday-0',
          str(row))
    check('and stored the old version\'s session uid',
          row and row[1] == ph.session_uid(vid_a, 2, 'Monday', 0), str(row))

    matches = [m for m in __import__('src.health_store', fromlist=['x']).get_matches(U)
               if m['importedWorkoutId'] == workout['id']]
    check('get_matches surfaces sessionUid',
          matches and matches[0].get('sessionUid'), str(matches))


def test_manual_confirm_resolves_a_uid() -> None:
    """A confirmation from the dialog gets a uid without the client sending one."""
    print('\nmanually confirming a match')
    reset()
    from src import health_store
    ph.record_version(U, PROG_A, source='heal')
    vid_a = ph.version_id(U, PROG_A)

    when = START_A + timedelta(days=21)          # week 4 Monday
    workout = insert_workout('fit_file-manual', when, 'mixed_modal_conditioning', 40)
    health_store.upsert_match(U, {'importedWorkoutId': workout['id'],
                                  'sessionKey': '4-Monday-0',
                                  'matchConfidence': 'manual'})
    with conn.cursor() as c:
        c.execute('SELECT session_uid FROM workout_matches WHERE user_id = %s '
                  'AND imported_workout_id = %s', (U, workout['id']))
        row = c.fetchone()
    check('the uid was resolved server-side from the workout date',
          row and row[0] == ph.session_uid(vid_a, 3, 'Monday', 0), str(row))

    # A day-level key, which the dashboard and session screen write.
    w2 = insert_workout('fit_file-daykey', START_A + timedelta(days=28), 'aerobic_base', 55)
    health_store.upsert_match(U, {'importedWorkoutId': w2['id'],
                                  'sessionKey': '5-Monday',
                                  'matchConfidence': 'manual'})
    with conn.cursor() as c:
        c.execute('SELECT session_uid FROM workout_matches WHERE user_id = %s '
                  'AND imported_workout_id = %s', (U, w2['id']))
        row = c.fetchone()
    check('a day-level key resolves when the day has one session',
          row and row[0] == ph.session_uid(vid_a, 4, 'Monday', 0), str(row))

    # A rejection names no session and must not invent one.
    health_store.upsert_match(U, {'importedWorkoutId': workout['id'],
                                  'sessionKey': '', 'matchConfidence': 'rejected'})
    with conn.cursor() as c:
        c.execute('SELECT session_uid FROM workout_matches WHERE user_id = %s '
                  'AND imported_workout_id = %s', (U, workout['id']))
        row = c.fetchone()
    check('a rejection clears the uid', row and row[0] is None, str(row))


def test_session_log_timeline_column_is_added_on_demand() -> None:
    """Production's session_logs never had exercise_timeline.

    The writer inserts it and its `except` swallows the failure, so every log
    the server received was dropped while the PUT routes answered {saved: ...}.
    This suite's own DDL used to declare the column, which is why nothing here
    noticed; reset() now builds the table the way production has it.
    """
    print('\nsession log timeline on a table that lacks the column')
    reset()
    timeline = [{'exerciseId': 'back_squat', 'startOffset': 0, 'endOffset': 600,
                 'avgHRDuring': 128}]

    def has_column() -> bool:
        with conn.cursor() as c:
            c.execute("SELECT 1 FROM information_schema.columns WHERE table_name = "
                      "'session_logs' AND column_name = 'exercise_timeline'")
            return c.fetchone() is not None

    check('the test schema is production-shaped: no exercise_timeline', not has_column())

    health_store.upsert_session_log(U, {
        'sessionKey': '1-Monday-0',
        'exercises': {'back_squat': {'sets': [{'completed': True, 'weightKg': 100,
                                               'repsActual': 5}]}},
        'notes': 'with a timeline', 'completedAt': '2026-06-01T10:00:00+00:00',
        'exerciseTimeline': timeline,
    })
    with conn.cursor() as c:
        c.execute('SELECT count(*) FROM session_logs WHERE user_id = %s', (U,))
        stored = c.fetchone()[0]
    check('the log was stored, not swallowed', stored == 1, str(stored))
    check('the column was added on first use', has_column())

    got = health_store.get_session_logs(U).get('1-Monday-0', {})
    check('its timeline round-trips through get_session_logs',
          got.get('exerciseTimeline') == timeline, str(got.get('exerciseTimeline')))

    # A later save that carries no timeline (a notes edit, the phone) keeps it.
    health_store.upsert_session_log(U, {
        'sessionKey': '1-Monday-0', 'exercises': {}, 'notes': 'edited',
        'completedAt': '2026-06-01T10:05:00+00:00',
    })
    again = health_store.get_session_logs(U).get('1-Monday-0', {})
    check('the later write landed', again.get('notes') == 'edited', str(again.get('notes')))
    check('and did not erase the timeline',
          again.get('exerciseTimeline') == timeline, str(again.get('exerciseTimeline')))


def test_logs_no_longer_merge_across_programs() -> None:
    """The corruption migrations/006 exists to stop.

    upsert_session_log merges: `exercises = session_logs.exercises ||
    EXCLUDED.exercises` and `completed_at = GREATEST(...)`. With the old
    program-relative primary key, logging week 3 Monday of a NEW program pulled
    the OLD block's set data into the row and carried its completion timestamp
    forward — so a session never performed rendered as complete, with somebody
    else's numbers in it.
    """
    print('\nsession logs across a replaced program')
    reset()
    from src import health_store
    import json as _json

    ph.record_version(U, PROG_A, source='heal')
    vid_a = ph.version_id(U, PROG_A)
    health_store.upsert_session_log(U, {
        'sessionKey': '3-Monday-0',
        'exercises': {'z2_run_ex': [{'weightKg': 0, 'reps': 1, 'note': 'block A'}]},
        'notes': 'the old block', 'completedAt': '2026-01-01T10:00:00+00:00',
    })
    with conn.cursor() as c:
        c.execute('SELECT session_uid FROM session_logs WHERE user_id = %s', (U,))
        row = c.fetchone()
    check('the log was scoped to the active version',
          row and row[0] == ph.session_uid(vid_a, 2, 'Monday', 0), str(row))

    # Replace the program, pinning A so the squash cannot fire.
    ph.record_version(U, PROG_B, source='put')
    vid_b = ph.version_id(U, PROG_B)
    check('B is the active version', ph.active_version_id(U) == vid_b)

    health_store.upsert_session_log(U, {
        'sessionKey': '3-Monday-0',
        'exercises': {'squat_day_ex': [{'weightKg': 100, 'reps': 5}]},
        # On the session's own day: a log completed before its week is not
        # the active program's (src/session_scope.py).
        'notes': 'the new block',
        'completedAt': (START_A + timedelta(days=14)).isoformat() + 'T10:00:00+00:00',
    })

    with conn.cursor() as c:
        c.execute('SELECT session_uid, notes, exercises FROM session_logs '
                  'WHERE user_id = %s ORDER BY session_uid', (U,))
        rows = c.fetchall()
    check('there are now two separate rows, not one merged one', len(rows) == 2,
          str(len(rows)))
    by_uid = {r[0]: r for r in rows}
    a_uid = ph.session_uid(vid_a, 2, 'Monday', 0)
    b_uid = ph.session_uid(vid_b, 2, 'Monday', 0)
    check("the old block's log is untouched",
          a_uid in by_uid and by_uid[a_uid][1] == 'the old block')
    check("the new block's log has only its own exercises",
          b_uid in by_uid and list(by_uid[b_uid][2]) == ['squat_day_ex'],
          str(by_uid.get(b_uid, ('', '', {}))[2]))
    check("...and did not inherit the old block's set data",
          b_uid in by_uid and 'z2_run_ex' not in by_uid[b_uid][2])

    logs = health_store.get_session_logs(U)
    check('get_session_logs returns the active program\'s log for that key',
          logs.get('3-Monday-0', {}).get('notes') == 'the new block',
          str(logs.get('3-Monday-0', {}).get('notes')))
    check('and only one entry for it', len(logs) == 1, str(list(logs)))

    everything = health_store.get_session_logs_by_uid(U)
    check('the uid-keyed reader still sees both blocks', len(everything) == 2,
          str(len(everything)))


def test_progression_sees_finished_blocks() -> None:
    """What compute_matched_sessions did to a match from a replaced block.

    Its index was built from the ONE stored program. Where the key did not
    resolve there, the match hit `if not session_entry: continue` and vanished.
    Where it did resolve — and it usually does, because a regenerate keeps the
    start date, so '3-Monday-0' exists in both plans — it resolved to the WRONG
    session and the athlete was shown their Zone 2 run as a squat day. The second
    failure mode is the worse one, and it is what this asserts.
    """
    print('\nprogression across a replaced program')
    reset()
    from src import health_store
    from src import progression_tracker as pt
    import json as _json

    ph.record_version(U, PROG_A, source='heal')
    vid_a = ph.version_id(U, PROG_A)
    when = START_A + timedelta(days=14)              # week 3 Monday of block A
    workout = insert_workout('fit_file-prog', when, 'aerobic_base', 61)
    health_store.upsert_match(U, {'importedWorkoutId': workout['id'],
                                  'sessionKey': '3-Monday-0',
                                  'matchConfidence': 'auto'})
    # Pin A, then replace it.
    health_store.upsert_session_log(U, {
        'sessionKey': '3-Monday-0',
        'exercises': {'z2_run_ex': {'sets': [
            {'completed': True, 'weightKg': 0, 'repsActual': 1, 'durationSec': 3660}]}},
        'completedAt': when.isoformat() + 'T09:00:00+00:00'})
    ph.record_version(U, PROG_B, source='put')
    with conn.cursor() as c:
        c.execute('INSERT INTO user_programs (user_id, program_data) VALUES (%s, %s) '
                  'ON CONFLICT (user_id) DO UPDATE SET program_data = EXCLUDED.program_data',
                  (U, _json.dumps(PROG_B)))

    matches = [m for m in health_store.get_matches(U) if m['matchConfidence'] != 'rejected']
    wo_map = {w['id']: w for w in health_store.get_workouts(U)}
    logs_by_uid = health_store.get_session_logs_by_uid(U)
    uids = {m['sessionUid'] for m in matches if m.get('sessionUid')} | set(logs_by_uid)
    hist = ph.session_lookup(U, sorted(uids))
    check('session_lookup found the old block\'s session', len(hist) >= 1, str(len(hist)))
    check('and carries its exercises',
          hist and (hist[0]['session'].get('exercises')), str(hist[:1]))

    # The old behaviour: index the stored program only.
    before = pt.compute_matched_sessions(matches, wo_map, PROG_B['currentProgram'])
    check('without history the run is relabelled as the new block\'s session',
          len(before) == 1 and before[0]['archetype']['name'] == 'Squat_Day',
          str(before and before[0]['archetype']))
    check('...and its modality no longer matches the workout',
          before and before[0]['modalityMatch'] == 'other',
          str(before and before[0].get('modalityMatch')))

    after = pt.compute_matched_sessions(
        matches, wo_map, PROG_B['currentProgram'],
        history_sessions=hist, active_version_id=ph.active_version_id(U))
    check('with history it is reported', len(after) == 1, str(len(after)))
    if after:
        check('as the old block\'s week 3', after[0]['weekNumber'] == 3,
              str(after[0].get('weekNumber')))
        check('with the old block\'s own archetype',
              after[0]['archetype']['name'] == 'Z2_Run', str(after[0]['archetype']))
        check('and the modality now agrees with the workout',
              after[0]['modalityMatch'] == 'exact', str(after[0]['modalityMatch']))

    hist_pts = pt.compute_exercise_history(
        health_store.get_session_logs(U), PROG_B['currentProgram'],
        history_sessions=hist, logs_by_uid=logs_by_uid,
        active_version_id=ph.active_version_id(U))
    check('the logged set from the old block is in exercise history',
          'z2_run_ex' in hist_pts, str(list(hist_pts)))
    if 'z2_run_ex' in hist_pts:
        pt0 = hist_pts['z2_run_ex'][0]
        check('and is attributed to the old version',
              pt0.get('program_version_id') == vid_a, str(pt0.get('program_version_id')))


def test_rows_from_before_the_program_stay_off_it() -> None:
    """The production case of 2026-10-14. A program in its first week showed
    week 6 completed and linked, from a March workout and an April log keyed
    '6-Monday-0' with no session_uid — rows from before program history, which
    every reader assumed were the current program's on their key alone."""
    print('\nrows from before the program stay off it')
    reset()
    ph.record_version(U, PROG_B, source='put')
    vid = ph.version_id(U, PROG_B)
    old_day = START_A - timedelta(days=200)
    insert_workout('fit_file-march', old_day, 'aerobic_base', 60)
    with conn.cursor() as c:
        # Exactly what production holds: no uid on either.
        c.execute("INSERT INTO workout_matches (imported_workout_id, user_id, session_key, "
                  "match_confidence, matched_at) VALUES (%s, %s, '6-Monday-0', 'auto', %s)",
                  ('fit_file-march', U, old_day))
        c.execute("INSERT INTO session_logs (session_key, user_id, completed_at, source) "
                  "VALUES ('6-Monday-0', %s, %s, 'manual')", (U, old_day))
        c.execute("INSERT INTO session_logs (session_key, user_id, source) "
                  "VALUES ('5-Monday-0', %s, 'fit_file')", (U,))

    # This program's own week 2 Monday, matched and logged the normal way.
    wk2 = START_A + timedelta(days=7)
    insert_workout('fit_file-wk2', wk2, 'max_strength', 60)
    health_store.upsert_match(U, {'importedWorkoutId': 'fit_file-wk2',
                                  'sessionKey': '2-Monday-0', 'matchConfidence': 'auto'})
    # A second recording of the same session (two watch saves, 2026-10-17).
    insert_workout('fit_file-wk2-again', wk2, 'max_strength', 5)
    health_store.upsert_match(U, {'importedWorkoutId': 'fit_file-wk2-again',
                                  'sessionKey': '2-Monday-0', 'matchConfidence': 'manual'})
    health_store.upsert_session_log(U, {'sessionKey': '2-Monday-0', 'exercises': {},
                                        'completedAt': wk2.isoformat() + 'T18:00:00+00:00'})
    # A stale client logging "week 7 Monday" today: stamped with this
    # version's uid by key alone, two weeks before week 7 begins.
    health_store.upsert_session_log(U, {'sessionKey': '7-Monday-0', 'exercises': {},
                                        'completedAt': TODAY.isoformat() + 'T07:00:00+00:00'})

    logs = health_store.get_session_logs(U)
    check("this program's week 2 log is offered", '2-Monday-0' in logs, str(sorted(logs)))
    check('the April log does not complete week 6', '6-Monday-0' not in logs, str(sorted(logs)))
    check('an undated unscoped log is not offered', '5-Monday-0' not in logs)
    check('a log completed before its week is not offered', '7-Monday-0' not in logs)

    by_wid = {m['importedWorkoutId']: m for m in health_store.get_matches(U)}
    check('the March match is still returned (history needs it)', 'fit_file-march' in by_wid)
    check('...flagged outside the current program',
          by_wid.get('fit_file-march', {}).get('inCurrentProgram') is False,
          str(by_wid.get('fit_file-march')))
    check("this program's match is flagged inside it",
          by_wid.get('fit_file-wk2', {}).get('inCurrentProgram') is True
          and (by_wid['fit_file-wk2'].get('sessionUid') or '').startswith(vid + ':'),
          str(by_wid.get('fit_file-wk2')))

    recent_rows = health_store.get_recent_session_logs(U)
    check('a log with two linked workouts is listed once',
          [r['session_key'] for r in recent_rows].count('2-Monday-0') == 1,
          str([r['session_key'] for r in recent_rows]))
    recent = {(r['session_key'], r['session_uid']): r for r in recent_rows}
    flags = {k[0]: r['in_current_program'] for k, r in recent.items()}
    check('the phone gets the same verdicts',
          flags.get('2-Monday-0') is True and flags.get('6-Monday-0') is False
          and flags.get('7-Monday-0') is False, str(flags))
    wk2_row = next((r for k, r in recent.items() if k[0] == '2-Monday-0'), {})
    check("and week 2's log links its own workout", wk2_row.get('matched_workout_id') == 'fit_file-wk2',
          str(wk2_row.get('matched_workout_id')))


def test_a_bike_ride_is_not_an_old_blocks_run() -> None:
    """The activity gate on the import path, for a workout inside a replaced
    block: planned_sessions carries no exercises, so the old session's
    equipment comes from its version snapshot. On 2026-10-14 a 20-minute ride
    auto-matched a kettlebell swing session because both were aerobic_base."""
    print('\nthe activity gate across a replaced program')
    reset()
    import json as _json
    ph.record_version(U, PROG_A, source='heal', source_revision='rev-1')
    vid_a = ph.version_id(U, PROG_A)
    with conn.cursor() as c:     # pin A so the regenerate cannot squash it
        c.execute("INSERT INTO session_logs (session_key, user_id, session_uid, "
                  "completed_at) VALUES ('1-Monday-0', %s, %s, NOW())",
                  (U, ph.session_uid(vid_a, 0, 'Monday', 0)))
    ph.record_version(U, PROG_B, source='put', source_revision='rev-2')
    with conn.cursor() as c:
        c.execute('INSERT INTO user_programs (user_id, program_data) VALUES (%s, %s) '
                  'ON CONFLICT (user_id) DO UPDATE SET program_data = EXCLUDED.program_data',
                  (U, _json.dumps(PROG_B)))
        when = START_A + timedelta(days=14)      # week 3 Monday of A: a 60-min z2 run
        c.execute("""INSERT INTO workouts (id, user_id, source, date, start_time, end_time,
                       duration_minutes, activity_type, inferred_modality_id)
                     VALUES ('garmin-ride', %s, 'garmin', %s, %s, %s, 60, 'Cycling', 'aerobic_base'),
                            ('garmin-run', %s, 'garmin', %s, %s, %s, 60, 'Running', 'aerobic_base')""",
                  (U, when, when, when, U, when, when, when))
    ride = {'id': 'garmin-ride', 'date': when.isoformat(), 'activityType': 'Cycling',
            'inferredModalityId': 'aerobic_base', 'durationMinutes': 60}
    run = {**ride, 'id': 'garmin-run', 'activityType': 'Running'}

    out = wm.match_and_store(U, [ride])
    check('the ride is not auto-matched to the run', out['confirmed'] == 0, str(out))
    check('...it is suggested instead', out['suggested'] == 1, str(out))
    out = wm.match_and_store(U, [run])
    check('a run on the same day still auto-matches', out['confirmed'] == 1, str(out))


if __name__ == '__main__':
    test_bootstrap()
    test_idempotent_under_a_heal_storm()
    test_regenerate_splits_the_timeline()
    test_intervals_are_disjoint()
    test_rebuilding_ahead_continues_the_block()
    test_restoring_a_rewritten_past_repairs_the_block()
    test_a_regenerate_keeps_the_day_already_trained()
    test_a_new_start_date_starts_a_new_lineage()
    test_same_day_squash()
    test_no_start_date_is_a_clean_skip()
    test_resolve_session()
    test_prune_respects_references()
    test_matching_inside_a_finished_block()
    test_match_and_store_without_history()
    test_match_and_store_with_history()
    test_manual_confirm_resolves_a_uid()
    test_session_log_timeline_column_is_added_on_demand()
    test_logs_no_longer_merge_across_programs()
    test_progression_sees_finished_blocks()
    test_rows_from_before_the_program_stay_off_it()
    test_a_bike_ride_is_not_an_old_blocks_run()

    if _failures:
        print(f'\n{len(_failures)} failure(s): ' + ', '.join(_failures))
        sys.exit(1)
    print('\nAll program history SQL tests passed.')
