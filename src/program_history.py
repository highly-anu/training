"""Program history: which plan was in force when, and what it planned each day.

Why this exists
---------------
`user_programs` holds one row per athlete and `src/db.py save_user_program`
upserts it, so generating a program destroyed the previous one. Nothing recorded
what had been planned, and a planned session's only identity was the
program-relative string `"{week_number}-{DayName}-{idx}"` — which references
nothing, so after a regenerate every stored match silently re-pointed at
whatever now occupied that slot. A workout that arrived for a date outside the
*current* program was dropped by the matcher and could never be matched again.

Three tables, separating three different things:

  program_versions     immutable snapshot of a plan, deduplicated by skeleton
  program_activations  the timeline — append-only, DATE-valued intervals
  planned_sessions     the geometry — one row per planned session per version,
                       carrying the calendar date it fell on

This module's top half is pure and has no database in it, so the flattening and
the hashing can be tested without PostgreSQL and reused by the backfill script.

Identity rules that must not be got wrong
-----------------------------------------
`session_uid` is keyed on the week's **array index**, never on `week_number`.
`week_number` is not unique: src/generator.py sets it from `week_in_program`,
and with an event date src/phase_calendar.build_remaining_schedule starts that
at the athlete's *absolute* program week, so a 16-week generate legitimately
produces weeks[0..15] numbered 16..31. Splice that onto kept weeks (the web's
useRegenerateFromWeek) and one `week_number` appears at two array indices —
keyed on it, the primary key insert collides and the whole version is lost.
`week_number` and `legacy_key` are descriptive columns with no unique
constraint; resolution by legacy key is always (user_id, legacy_key, date).

Dates come from `workout_matcher.session_calendar_date`, called rather than
reimplemented: PUT /api/user/program does not Monday-align (only generate does)
and the web settings sheet lets the athlete pick any date, so non-Monday starts
are real and both paths must agree.
"""
from __future__ import annotations

import hashlib
import json
from datetime import date

from src.program_keys import DAY_NAMES, normalize_program_keys, pick
from src.workout_matcher import RULES, session_calendar_date

# Keys injected into the envelope at read time by GET /api/user/program. They
# are not part of the plan and must not perturb either hash.
_VOLATILE_KEYS = ('revision', 'programVersionId', 'historyRecorded')


# ── Reading the envelope ─────────────────────────────────────────────────────

def unwrap(envelope: dict) -> dict:
    """The GeneratedProgram inside a stored envelope.

    Tolerates the envelope-less shape too: the generate auto-save used to write
    the bare GeneratedProgram, leaving the generator's own keys at the top level
    (see test_program_envelope.py). Such a row is still a real program.
    """
    if not isinstance(envelope, dict):
        return {}
    envelope = normalize_program_keys(envelope)
    current = envelope.get('currentProgram')
    if isinstance(current, dict):
        return current
    return envelope if envelope.get('weeks') is not None else {}


def start_date_of(envelope: dict) -> str | None:
    """The program's start date as YYYY-MM-DD, or None.

    None is a real, unrecoverable state — test_program_envelope.py documents a
    production row with no start date at all. Callers must skip rather than try
    to insert into a DATE NOT NULL column.
    """
    if not isinstance(envelope, dict):
        return None
    envelope = normalize_program_keys(envelope)
    raw = envelope.get('programStartDate')
    if raw is None:
        # A bare GeneratedProgram carries the generator's own spelling.
        raw = envelope.get('program_start_date')
    if raw is None:
        return None
    text = str(raw)[:10]
    try:
        date.fromisoformat(text)
    except ValueError:
        return None
    return text


# ── Hashing ──────────────────────────────────────────────────────────────────

def skeleton_of(envelope: dict) -> str:
    """A canonical string of everything that makes this plan *this* plan.

    Covers the start date and, ordered by week index, each week's number, phase
    and deload flag, then each day's sessions as (modality, archetype id,
    ordered exercise ids).

    Excluded on purpose: goal, constraints, validation, volume_summary,
    compromises, coverage_report, sourceGoalIds/Weights, eventDate, framework,
    week_in_phase, archetype name/category/duration, and every load, slot, rest
    and note. Two reasons. The three self-healing re-saves in
    GET /api/user/program rebuild exactly those keys, and hashing them would
    mint a spurious version on every app open. And iOS re-encodes
    `ProgramLoad.reps` through AnyCodable, so an `8` comes back as `8.0`.

    Days are iterated in DAY_NAMES order, never dict order. Swift re-encodes
    `[String: [ProgramSession]]` with arbitrary key order, so hashing the
    schedule as it arrives would mint a version on every iOS save. This is
    load-bearing, not tidiness.
    """
    program = unwrap(envelope)
    parts: list[str] = ['start|%s' % (start_date_of(envelope) or '')]

    for week_index, week in enumerate(program.get('weeks') or []):
        week_number = pick(week, 'week_number', 'weekNumber')
        if week_number is None:
            week_number = week_index + 1
        parts.append('w%d|%s|%s|%s' % (
            week_index,
            week_number,
            week.get('phase') or '',
            bool(pick(week, 'is_deload', 'isDeload')),
        ))
        schedule = week.get('schedule') or {}
        for day_name in DAY_NAMES:
            for session_index, session in enumerate(schedule.get(day_name) or []):
                archetype = session.get('archetype') or {}
                exercise_ids = ','.join(
                    (ea.get('exercise') or {}).get('id') or ''
                    for ea in (session.get('exercises') or [])
                )
                parts.append('d|%s|%d|%s|%s|%s' % (
                    day_name,
                    session_index,
                    session.get('modality') or '',
                    archetype.get('id') or '',
                    exercise_ids,
                ))

    return '\n'.join(parts)


def skeleton_hash(envelope: dict) -> str:
    return hashlib.sha256(skeleton_of(envelope).encode()).hexdigest()


def version_id(user_id: str, envelope: dict) -> str:
    """The version's primary key, scoped to the athlete.

    The user id is in the hash as well as in the table's composite key, so two
    athletes running the same philosophy from the same Monday cannot collide.
    """
    raw = '%s|%s' % (user_id, skeleton_of(envelope))
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def content_hash(envelope: dict) -> str:
    """Hash of the whole stored envelope, minus the read-time injections.

    Distinct from the skeleton hash: a regenerate at a different training level
    can produce an identical skeleton with different prescriptions. Same
    skeleton and different content means the snapshot is stale, not that the
    plan is new.
    """
    if not isinstance(envelope, dict):
        return hashlib.sha256(b'').hexdigest()
    trimmed = {k: v for k, v in normalize_program_keys(envelope).items()
               if k not in _VOLATILE_KEYS}
    cp = trimmed.get('currentProgram')
    if isinstance(cp, dict) and 'phase_summary' in cp:
        # Derived on read (src/phase_summary.py); a client that echoes it back
        # must not make the snapshot look stale.
        trimmed['currentProgram'] = {k: v for k, v in cp.items() if k != 'phase_summary'}
    canonical = json.dumps(trimmed, sort_keys=True, separators=(',', ':'),
                           default=str)
    return hashlib.sha256(canonical.encode()).hexdigest()


def richness(envelope: dict) -> int:
    """How much of the plan's detail this copy still carries.

    An iOS save strips information the server put there: `ServerProgram` has no
    `goal`, and `ProgramExerciseAssignment` declares `slot_role`/`slot_type` but
    no `slot` object — which src/progression_tracker.py and
    GET /api/progression/exercises both read. So "same skeleton, refresh the
    snapshot" must never let a stripped copy overwrite a complete one. A
    snapshot is only replaced by one at least as rich.
    """
    program = unwrap(envelope)
    score = sum(1 for key in ('goal', 'constraints', 'validation',
                              'volume_summary', 'coverage_report')
                if program.get(key))
    has_slot = has_test = False
    for week in (program.get('weeks') or []):
        for sessions in (week.get('schedule') or {}).values():
            for session in (sessions or []):
                # A test's link to its standards: a copy that dropped it (an
                # older client that strips unknown keys) is the poorer one.
                has_test = has_test or bool(session.get('test'))
                has_slot = has_slot or any(ea.get('slot') for ea in (session.get('exercises') or []))
                if has_slot and has_test:
                    return score + 2
    return score + int(has_slot) + int(has_test)


# ── Flattening ───────────────────────────────────────────────────────────────

def flatten_program(vid: str, envelope: dict) -> list[dict]:
    """One row per planned session, with the calendar date it falls on.

    Rows use the `planned_sessions` column names. Returns [] when the program
    has no resolvable start date — without one there are no dates, and a row
    without a date answers none of the questions this table exists for.

    `modality` and `duration_min` are derived with exactly the expressions
    `workout_matcher.index_sessions_by_date` uses, because the same workout must
    score identically whether it is matched through history or through the
    current program.
    """
    start = start_date_of(envelope)
    if not start:
        return []

    program = unwrap(envelope)
    rows: list[dict] = []

    for week_index, week in enumerate(program.get('weeks') or []):
        week_number = pick(week, 'week_number', 'weekNumber')
        if week_number is None:
            week_number = week_index + 1
        phase = week.get('phase')
        schedule = week.get('schedule') or {}
        for day_name in DAY_NAMES:
            sessions = schedule.get(day_name) or []
            if not sessions:
                continue
            cal_date = session_calendar_date(start, week_index, day_name)
            if not cal_date:
                continue
            for session_index, session in enumerate(sessions):
                archetype = session.get('archetype') or {}
                rows.append({
                    'session_uid':   session_uid(vid, week_index, day_name, session_index),
                    'program_version_id': vid,
                    'date':          cal_date,
                    'week_index':    week_index,
                    'week_number':   int(week_number),
                    'day_name':      day_name,
                    'session_index': session_index,
                    'legacy_key':    legacy_key(week_number, day_name, session_index),
                    'modality':      session.get('modality') or '',
                    'archetype_id':   archetype.get('id'),
                    'archetype_name': archetype.get('name') or session.get('modality') or '',
                    'duration_min':  int(pick(archetype, 'duration_estimate_minutes',
                                              'durationEstimateMinutes')
                                         or RULES['defaultSessionMinutes']),
                    'phase':         phase,
                    'is_deload':     bool(pick(session, 'is_deload', 'isDeload')),
                })
    return rows


def session_uid(vid: str, week_index: int, day_name: str, session_index: int) -> str:
    """The globally stable identity of a planned session.

    `week_index`, not `week_number` — see the module docstring.
    """
    return '%s:w%d-%s-%d' % (vid, week_index, day_name, session_index)


def legacy_key(week_number, day_name: str, session_index: int) -> str:
    """The program-relative key every existing client already speaks."""
    return '%s-%s-%d' % (week_number, day_name, session_index)


def index_entry(row: dict) -> dict:
    """A planned_sessions row as a matcher candidate."""
    return {
        'sessionKey': row['legacy_key'],
        'sessionUid': row['session_uid'],
        'modality':   row['modality'],
        'duration':   row['duration_min'],
    }


def index_by_date(rows: list[dict]) -> dict[str, list[dict]]:
    """Matcher-shaped date index over planned_sessions rows.

    Sorted by session_index so the matcher's first-wins tie-break
    (workout_matcher.auto_match_indexed) is deterministic regardless of the
    order the rows arrived in.
    """
    index: dict[str, list[dict]] = {}
    for row in sorted(rows, key=lambda r: r['session_index']):
        index.setdefault(str(row['date']), []).append(index_entry(row))
    return index


# ── Interval arithmetic ──────────────────────────────────────────────────────
#
# Boundaries are DATEs computed here, never `activated_at::date` in SQL: that
# cast uses the server's TimeZone (UTC on fly.io), so a 21:00 regenerate at
# UTC-7 would land on tomorrow and the boundary would be a day out for a
# seven-hour window every evening.

def compute_effective_from(activation_day: date, start_day: date,
                           is_first: bool) -> date:
    """When a newly activated version starts owning dates.

    The *first* activation on an athlete's timeline runs from the program's own
    start date, not from the moment it was archived. That is what lets the
    program archived on first read own its already-elapsed weeks — anchoring it
    to `now` instead would leave every existing match unattributable and would
    be a regression against today's behaviour, where the matcher covers the
    program's whole span.

    Later activations start the day they are activated, so the new plan owns the
    rest of today; a start date in the future is honoured, leaving the
    intervening weeks to the predecessor rather than creating a dead zone where
    nothing matches.
    """
    if is_first:
        return start_day
    return max(activation_day, start_day)


def clamp_effective_to(own_from: date, successor_from: date) -> date:
    """Close an interval at its successor's start, never before its own start.

    Two activations in one day give a zero-length interval, which the
    resolution query naturally returns nothing for. The clamp is what keeps it
    empty rather than inverted.
    """
    return max(own_from, successor_from)


# ── Continuity ───────────────────────────────────────────────────────────────
#
# Rebuilding the weeks ahead — "from tomorrow", or after an injury, a new
# schedule or new equipment — is the same program carrying on, not a switch.
# Before this, every such save opened a new activation from today and every
# match and log stayed pinned to the old version's uids, which session_scope
# (and both clients' belongsToVersion) reject for the version in force: the
# athlete's elapsed sessions in the current block stopped counting.

def divergence_date(old_rows: list[dict], new_rows: list[dict],
                    from_day: date) -> date | None:
    """The first date on or after `from_day` whose planned sessions differ
    between two versions, or None when they never do.

    A day is the same when it holds the same sessions in the same slots — by
    modality and archetype, not by prescription, since a swapped exercise or
    an adjusted load does not make it a different session. Rows are
    `planned_sessions` rows (or flatten_program's), dates as DATE or ISO text.
    """
    old, new = _by_day(old_rows, from_day), _by_day(new_rows, from_day)
    differing = [d for d in old.keys() | new.keys() if old.get(d) != new.get(d)]
    return min(differing) if differing else None


def same_sessions(old_rows: list[dict], new_rows: list[dict]) -> list[dict]:
    """`old_rows` on the days both versions plan alike (see divergence_date) —
    the sessions a successor carries over, whatever interval they fell in."""
    old, new = _by_day(old_rows), _by_day(new_rows)
    alike = {d for d, v in old.items() if new.get(d) == v}
    return [r for r in old_rows if _as_day(r['date']) in alike]


def _as_day(value) -> date:
    return value if isinstance(value, date) else date.fromisoformat(str(value)[:10])


def _by_day(rows: list[dict], from_day: date = date.min) -> dict[date, list]:
    days: dict[date, list] = {}
    for r in rows:
        d = _as_day(r['date'])
        if d < from_day:
            continue
        days.setdefault(d, []).append((r['day_name'], r['session_index'],
                                       r.get('modality') or '', r.get('archetype_id') or ''))
    return {d: sorted(v) for d, v in days.items()}


def carry_over_until(today: date, divergence: date | None) -> date | None:
    """Whether a successor in the same block continues the plan in force, and
    up to which date (exclusive) the predecessor's sessions carry over to it.

    It continues when no elapsed day changed: everything before today is as it
    was. Today itself is the athlete's to change — an injury regenerate may
    rewrite today's session — and carries over only when it did not. A
    successor that rewrites an elapsed day is a different plan for those days,
    and the timeline switches on today as it always did (None).
    """
    if divergence is None:
        return date.max
    return divergence if divergence >= today else None


# ─────────────────────────────────────────────────────────────────────────────
# Storage
# ─────────────────────────────────────────────────────────────────────────────
#
# Deliberately NOT written in health_store's `with get_conn() ... except
# Exception: pass` style. Under autocommit that context manager rolls back a
# transaction that does not exist, so a failure between closing the old interval
# and opening the new one would leave a half-written timeline. Everything here
# that changes the timeline runs in one real transaction on its own connection,
# serialised per athlete by an advisory lock, and logged rather than raised — a
# history failure must never fail the program save that triggered it.

import logging as _logging

_log = _logging.getLogger(__name__)

_TABLES_CREATED = False

_DDL = (
    '''CREATE TABLE IF NOT EXISTS program_versions (
        user_id TEXT NOT NULL, id TEXT NOT NULL,
        skeleton_hash TEXT NOT NULL, content_hash TEXT NOT NULL,
        program_data JSONB NOT NULL, start_date DATE NOT NULL,
        week_count INTEGER NOT NULL DEFAULT 0,
        first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (user_id, id))''',
    '''CREATE TABLE IF NOT EXISTS program_activations (
        id BIGSERIAL PRIMARY KEY, user_id TEXT NOT NULL,
        program_version_id TEXT NOT NULL, lineage_id TEXT NOT NULL,
        effective_from DATE NOT NULL, effective_to DATE,
        activated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        source TEXT NOT NULL DEFAULT 'put', source_revision TEXT,
        source_goal_ids JSONB NOT NULL DEFAULT '[]'::jsonb, goal_name TEXT)''',
    '''CREATE TABLE IF NOT EXISTS planned_sessions (
        user_id TEXT NOT NULL, session_uid TEXT NOT NULL,
        program_version_id TEXT NOT NULL, date DATE NOT NULL,
        week_index INTEGER NOT NULL, week_number INTEGER,
        day_name TEXT NOT NULL, session_index INTEGER NOT NULL,
        legacy_key TEXT NOT NULL, modality TEXT NOT NULL DEFAULT '',
        archetype_id TEXT, archetype_name TEXT,
        duration_min INTEGER NOT NULL DEFAULT 60, phase TEXT,
        is_deload BOOLEAN NOT NULL DEFAULT FALSE,
        PRIMARY KEY (user_id, session_uid))''',
    'CREATE INDEX IF NOT EXISTS idx_prog_act_user_range ON program_activations (user_id, effective_from, effective_to)',
    'CREATE INDEX IF NOT EXISTS idx_prog_act_user_revision ON program_activations (user_id, source_revision)',
    'CREATE INDEX IF NOT EXISTS idx_planned_user_date ON planned_sessions (user_id, date)',
    'CREATE INDEX IF NOT EXISTS idx_planned_legacy_date ON planned_sessions (user_id, legacy_key, date)',
    'CREATE INDEX IF NOT EXISTS idx_planned_version ON planned_sessions (user_id, program_version_id)',
    # Deny-by-default. This path runs when the migration has NOT been applied —
    # on Supabase these tables land in `public`, where PostgREST exposes them, so
    # creating them with row security off would publish every athlete's plans to
    # anyone holding the anon key. Enabling it with no policy denies all
    # non-owner roles; the API connects as the owner and is unaffected, and
    # migrations/005_program_history.sql then adds the real per-user policies.
    # No CREATE POLICY here: a test database has no `auth` schema.
    'ALTER TABLE program_versions    ENABLE ROW LEVEL SECURITY',
    'ALTER TABLE program_activations ENABLE ROW LEVEL SECURITY',
    'ALTER TABLE planned_sessions    ENABLE ROW LEVEL SECURITY',
)


def _ensure_tables() -> bool:
    """Create the history tables if the migration has not been run.

    The same safety net health_store keeps for progression_snapshots, with one
    difference: the flag is set only *after* the commit returns. health_store
    sets its flag first, so if the DDL rolls back the flag stays true and every
    later call in that process fails against a table that was never created.

    Runs on its own autocommit connection rather than inside record_version's
    transaction, so two athletes' first writes cannot race on DDL inside a lock
    that only serialises per athlete. No RLS here — a test database has no
    `auth` schema; migrations/005_program_history.sql is the authority on that.
    """
    global _TABLES_CREATED
    if _TABLES_CREATED:
        return True
    from src.db import new_conn
    conn = new_conn(autocommit=True)
    if conn is None:
        return False
    try:
        with conn.cursor() as cur:
            for statement in _DDL:
                cur.execute(statement)
        _TABLES_CREATED = True
        return True
    except Exception as e:                                  # pragma: no cover
        _log.warning('program history DDL failed: %s', e)
        return False
    finally:
        conn.close()


def _dict_cursor(conn):
    import psycopg2.extras
    return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


def _is_referenced(cur, user_id: str, vid: str) -> bool:
    """Has anything been attached to this version's sessions yet?

    Used only by the same-day squash. A version nothing points at can be
    replaced in place; one with a match or a log against it is history.
    """
    prefix = vid + ':%'
    for table in ('workout_matches', 'session_logs'):
        try:
            cur.execute(
                f'SELECT 1 FROM {table} WHERE user_id = %s AND session_uid LIKE %s LIMIT 1',
                (user_id, prefix))
            if cur.fetchone():
                return True
        except Exception:
            # The column only exists after 005. Treat "cannot tell" as
            # "referenced" so a squash can never discard real history.
            return True
    return False


def _carry_over(cur, user_id: str, old_vid: str, new_vid: str,
                kept_rows: list[dict]) -> int:
    """Re-point matches, suggestions and logs from the predecessor's kept
    sessions to the same sessions of its successor; returns rows moved.

    A kept session sits at the same date, so at the same week index, day and
    slot — the uid differs only in its version prefix. A log whose new uid is
    already taken stays where it is rather than collide on the primary key.
    Each table runs under a savepoint: one missing a column (a database ahead
    of its migrations) must not cost the timeline the rest.
    """
    if not kept_rows:
        return 0
    pairs = [(r['session_uid'], new_vid + r['session_uid'][len(old_vid):]) for r in kept_rows
             if r['session_uid'].startswith(old_vid + ':')]
    if not pairs:
        return 0
    values = ','.join(cur.mogrify('(%s, %s)', p).decode() for p in pairs).replace('%', '%%')
    moved = 0
    guards = {
        'session_logs': ' AND NOT EXISTS (SELECT 1 FROM session_logs s2 WHERE '
                        's2.user_id = t.user_id AND s2.session_uid = m.new_uid)',
    }
    for table in ('workout_matches', 'workout_match_suggestions', 'session_logs'):
        cur.execute('SAVEPOINT carry_over')
        try:
            cur.execute(f'''
                UPDATE {table} AS t SET session_uid = m.new_uid
                  FROM (VALUES {values}) AS m(old_uid, new_uid)
                 WHERE t.user_id = %s AND t.session_uid = m.old_uid{guards.get(table, '')}
            ''', (user_id,))
            moved += cur.rowcount
            cur.execute('RELEASE SAVEPOINT carry_over')
        except Exception as e:
            cur.execute('ROLLBACK TO SAVEPOINT carry_over')
            _log.warning('carry_over skipped %s for %s: %s', table, user_id, e)
    return moved


def is_archived(user_id: str, source_revision: str | None) -> bool:
    """Is the stored program at this revision already in the history?

    The short-circuit that keeps GET /api/user/program cheap. That endpoint
    already fetches user_programs.updated_at as the revision, so one indexed
    lookup answers this before anyone hashes a ~1 MB envelope.
    """
    if not source_revision:
        return False
    return bool(_query('SELECT 1 FROM program_activations '
                       'WHERE user_id = %s AND source_revision = %s LIMIT 1',
                       (user_id, str(source_revision))))


def record_version(user_id: str, envelope: dict, source: str = 'put',
                   source_revision: str | None = None) -> dict:
    """Archive a program and put it at the head of the athlete's timeline.

    Idempotent on the skeleton: re-recording the same plan adds no version and
    no activation, which is what makes it safe to call from the self-healing
    GET path and from every iOS round-trip.

    Returns {'recorded': bool, 'versionId': str|None, 'reason': str} and never
    raises. `reason` is for the log and the test suite, not for users.
    """
    import json as _json
    import uuid as _uuid

    out = {'recorded': False, 'versionId': None, 'reason': ''}

    start = start_date_of(envelope)
    if not start:
        # A real, unrecoverable production state (test_program_envelope.py).
        # Without a start date there are no dates, and a planned session with no
        # date answers none of the questions this table exists for.
        out['reason'] = 'no_start_date'
        return out

    program = unwrap(envelope)
    weeks = program.get('weeks') or []
    if not weeks:
        out['reason'] = 'no_weeks'
        return out

    vid = version_id(user_id, envelope)
    out['versionId'] = vid
    rows = flatten_program(vid, envelope)

    if not _ensure_tables():
        out['reason'] = 'no_database'
        return out

    from src.db import new_conn
    conn = new_conn(autocommit=False)
    if conn is None:
        out['reason'] = 'no_database'
        return out

    try:
        with _dict_cursor(conn) as cur:
            # Serialise per athlete: PUT /api/user/program and the GET heal can
            # otherwise interleave and open two activations for one plan.
            cur.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',
                        ('program_history:' + user_id,))

            start_day = date.fromisoformat(start)
            new_richness = richness(envelope)

            # ── the snapshot ──────────────────────────────────────────────
            cur.execute('SELECT content_hash, program_data FROM program_versions '
                        'WHERE user_id = %s AND id = %s', (user_id, vid))
            stored = cur.fetchone()
            if stored is None:
                cur.execute('''
                    INSERT INTO program_versions
                        (user_id, id, skeleton_hash, content_hash, program_data,
                         start_date, week_count)
                    VALUES (%s, %s, %s, %s, %s::jsonb, %s, %s)
                    ON CONFLICT (user_id, id) DO NOTHING
                ''', (user_id, vid, skeleton_hash(envelope), content_hash(envelope),
                      _json.dumps(envelope, default=str), start_day, len(weeks)))
            elif stored['content_hash'] != content_hash(envelope):
                # Same plan, different prescriptions — the snapshot is stale.
                # Only ever replaced by a copy at least as rich: an iOS save
                # strips `goal` and every `slot`, and letting that overwrite the
                # server's copy would quietly degrade the archive.
                if new_richness >= richness(stored['program_data'] or {}):
                    cur.execute('''
                        UPDATE program_versions
                           SET program_data = %s::jsonb, content_hash = %s
                         WHERE user_id = %s AND id = %s
                    ''', (_json.dumps(envelope, default=str),
                          content_hash(envelope), user_id, vid))

            # ── the geometry ──────────────────────────────────────────────
            # Immutable: a version's rows are written once and never updated.
            if rows:
                from psycopg2.extras import execute_values
                execute_values(cur, '''
                    INSERT INTO planned_sessions
                        (user_id, session_uid, program_version_id, date, week_index,
                         week_number, day_name, session_index, legacy_key, modality,
                         archetype_id, archetype_name, duration_min, phase, is_deload)
                    VALUES %s
                    ON CONFLICT (user_id, session_uid) DO NOTHING
                ''', [(user_id, r['session_uid'], r['program_version_id'], r['date'],
                       r['week_index'], r['week_number'], r['day_name'],
                       r['session_index'], r['legacy_key'], r['modality'],
                       r['archetype_id'], r['archetype_name'], r['duration_min'],
                       r['phase'], r['is_deload']) for r in rows])

            # ── the timeline ──────────────────────────────────────────────
            cur.execute('''SELECT a.id, a.program_version_id, a.lineage_id,
                                  a.effective_from, v.start_date
                             FROM program_activations a
                        LEFT JOIN program_versions v
                               ON v.user_id = a.user_id AND v.id = a.program_version_id
                            WHERE a.user_id = %s AND a.effective_to IS NULL
                         ORDER BY a.id DESC LIMIT 1''', (user_id,))
            open_act = cur.fetchone()

            goal_name = (program.get('goal') or {}).get('name')
            goal_ids = normalize_program_keys(envelope).get('sourceGoalIds') or []

            if open_act and open_act['program_version_id'] == vid:
                # Already the plan in force. Refresh the audit fields so the
                # revision short-circuit recognises this save next time, but
                # leave the interval alone — nothing about the timeline changed.
                cur.execute('''UPDATE program_activations
                                  SET source_revision = COALESCE(%s, source_revision),
                                      source_goal_ids = %s::jsonb,
                                      goal_name       = COALESCE(%s, goal_name)
                                WHERE id = %s''',
                            (source_revision, _json.dumps(goal_ids), goal_name,
                             open_act['id']))
                conn.commit()
                out['reason'] = 'already_active'
                return out

            cur.execute('SELECT COUNT(*) AS n FROM program_activations WHERE user_id = %s',
                        (user_id,))
            is_first = (cur.fetchone()['n'] == 0)

            today = date.today()
            eff_from = compute_effective_from(today, start_day, is_first)

            # A lineage is one training block: same start date, same block, even
            # after an edit or a re-roll. A new start date starts a new one.
            if open_act and open_act['start_date'] == start_day:
                lineage = open_act['lineage_id']
            else:
                lineage = _uuid.uuid4().hex

            # The same block rebuilt ahead of the athlete carries on: the
            # successor takes over every interval of the block whose elapsed
            # days it plans exactly as they were (newest first, stopping at
            # the first that differs), and what was matched, suggested or
            # logged against those sessions moves with them. Those intervals
            # close empty — still on the timeline, as the record that the plan
            # changed. Walking back past the open interval is what lets a
            # program whose past an earlier regenerate rewrote be repaired by
            # restoring those days and saving.
            carries: list[tuple[dict, date]] = []
            if open_act and open_act['start_date'] == start_day:
                cur.execute('''SELECT id, program_version_id, effective_from, effective_to
                                 FROM program_activations
                                WHERE user_id = %s AND lineage_id = %s
                                  AND (effective_to IS NULL OR effective_to > effective_from)
                             ORDER BY effective_from DESC, id DESC''',
                            (user_id, open_act['lineage_id']))
                block = cur.fetchall()
                cur.execute('''SELECT program_version_id, session_uid, date, day_name,
                                      session_index, modality, archetype_id
                                 FROM planned_sessions
                                WHERE user_id = %s AND program_version_id = ANY(%s)''',
                            (user_id, sorted({a['program_version_id'] for a in block} | {vid})))
                rows_of: dict[str, list[dict]] = {}
                for r in cur.fetchall():
                    rows_of.setdefault(r['program_version_id'], []).append(r)
                for act in block:
                    lo, hi = act['effective_from'], act['effective_to'] or date.max
                    old_rows = [r for r in rows_of.get(act['program_version_id'], [])
                                if lo <= r['date'] < hi]
                    new_rows = [r for r in rows_of.get(vid, []) if lo <= r['date'] < hi]
                    until = carry_over_until(today, divergence_date(old_rows, new_rows, lo))
                    if until is None:
                        break
                    carries.append((act, until))
                if carries:
                    eff_from = carries[-1][0]['effective_from']

            squashed = False
            if open_act:
                if (open_act['effective_from'] == today
                        and not (carries and eff_from < open_act['effective_from'])
                        and not _is_referenced(cur, user_id, open_act['program_version_id'])):
                    # Same-day edit that nothing points at yet: retarget the open
                    # activation instead of chaining. Updating in place rather
                    # than delete-and-insert keeps its effective_from, so no gap
                    # can open between it and its predecessor.
                    cur.execute('''UPDATE program_activations
                                      SET program_version_id = %s, lineage_id = %s,
                                          activated_at = NOW(), source = %s,
                                          source_revision = %s,
                                          source_goal_ids = %s::jsonb, goal_name = %s
                                    WHERE id = %s''',
                                (vid, lineage, source, source_revision,
                                 _json.dumps(goal_ids), goal_name, open_act['id']))
                    squashed = True
                else:
                    cur.execute('UPDATE program_activations SET effective_to = %s WHERE id = %s',
                                (clamp_effective_to(open_act['effective_from'], eff_from),
                                 open_act['id']))

            if not squashed:
                cur.execute('''
                    INSERT INTO program_activations
                        (user_id, program_version_id, lineage_id, effective_from,
                         source, source_revision, source_goal_ids, goal_name)
                    VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb, %s)
                ''', (user_id, vid, lineage, eff_from, source, source_revision,
                      _json.dumps(goal_ids), goal_name))

            carried = 0
            if carries and not squashed:
                for act, _until in carries:
                    if act['id'] != open_act['id']:
                        cur.execute('UPDATE program_activations SET effective_to = effective_from '
                                    'WHERE id = %s', (act['id'],))
                # Every session a taken-over version planned as the successor
                # does, in or out of its own interval: a log written after a
                # later save still names that save's version. Oldest first, so
                # when two logs name one session the one written while it was
                # in force keeps it (_carry_over never overwrites).
                done: set[str] = set()
                for act, _until in reversed(carries):
                    old_vid = act['program_version_id']
                    if old_vid == vid or old_vid in done:
                        continue
                    done.add(old_vid)
                    carried += _carry_over(cur, user_id, old_vid, vid,
                                           same_sessions(rows_of.get(old_vid, []),
                                                         rows_of.get(vid, [])))

        conn.commit()
        out['recorded'] = True
        out['reason'] = ('squashed' if squashed
                         else 'continued' if carries else 'activated')
        out['carried'] = carried
    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        _log.warning('record_version failed for %s: %s', user_id, e)
        out['reason'] = 'error: %s' % e
    finally:
        conn.close()

    if out['recorded']:
        prune_versions(user_id)
    return out


# ── Reading ──────────────────────────────────────────────────────────────────
#
# Every read filters planned_sessions through the activation that was in force
# on the row's own date. That is what keeps a superseded plan's already-elapsed
# sessions attributable while excluding the weeks it never got to run.
#
# DISTINCT ON (session_uid) because a version can in principle be activated more
# than once; two candidate sets for one date would inflate the `unambiguous`
# count in workout_matcher.auto_match_indexed and silently demote auto-matches
# to suggestions.

_EFFECTIVE_JOIN = '''
      FROM planned_sessions ps
      JOIN program_activations a
        ON a.user_id = ps.user_id
       AND a.program_version_id = ps.program_version_id
       AND ps.date >= a.effective_from
       AND (a.effective_to IS NULL OR ps.date < a.effective_to)
'''

_ROW_COLUMNS = ('ps.session_uid, ps.program_version_id, ps.date, ps.week_index, '
                'ps.week_number, ps.day_name, ps.session_index, ps.legacy_key, '
                'ps.modality, ps.archetype_id, ps.archetype_name, ps.duration_min, '
                'ps.phase, ps.is_deload')


def _query(sql: str, params: tuple) -> list[dict]:
    """Run a read and return plain dicts, or [] if anything at all goes wrong.

    On the thread's reused read connection (`db.read_conn`), retried once on a
    fresh one if the link turns out to have dropped."""
    from src.db import read_conn
    for _attempt in range(2):
        conn = read_conn()
        if conn is None:
            return []
        try:
            with _dict_cursor(conn) as cur:
                cur.execute(sql, params)
                return [dict(r) for r in cur.fetchall()]
        except Exception as e:
            if conn.closed:
                continue
            _log.warning('program history read failed: %s', e)
            return []
    return []


def planned_sessions_on_dates(user_id: str, dates: list[str]) -> list[dict]:
    """The sessions that were planned on these dates, across every program."""
    wanted = sorted({str(d)[:10] for d in dates if d})
    if not wanted:
        return []
    return _query(
        f'SELECT DISTINCT ON (ps.session_uid) {_ROW_COLUMNS} {_EFFECTIVE_JOIN} '
        'WHERE ps.user_id = %s AND ps.date = ANY(%s::date[]) '
        'ORDER BY ps.session_uid',
        (user_id, wanted))


def sessions_on_dates(user_id: str, dates: list[str]) -> dict[str, list[dict]]:
    """Matcher-shaped date index over the athlete's whole program history.

    This is what lets a workout that landed inside a finished block be matched
    at all. Indexing the current program alone drops it, permanently.
    """
    return index_by_date(planned_sessions_on_dates(user_id, dates))


def planned_sessions_between(user_id: str, from_date: str, to_date: str) -> list[dict]:
    """Every planned session in a date range, ordered for display."""
    return _query(
        f'SELECT DISTINCT ON (ps.session_uid) {_ROW_COLUMNS} {_EFFECTIVE_JOIN} '
        'WHERE ps.user_id = %s AND ps.date >= %s::date AND ps.date <= %s::date '
        'ORDER BY ps.session_uid',
        (user_id, str(from_date)[:10], str(to_date)[:10]))


def sessions_for_version(user_id: str, vid: str) -> list[dict]:
    """A single version's own rows, effective or not.

    Unfiltered by the activation interval on purpose: browsing a finished block
    should show the whole plan, including the weeks it never got to run.
    """
    return _query(
        'SELECT session_uid, program_version_id, date, week_index, week_number, '
        'day_name, session_index, legacy_key, modality, archetype_id, '
        'archetype_name, duration_min, phase, is_deload '
        'FROM planned_sessions WHERE user_id = %s AND program_version_id = %s '
        'ORDER BY week_index, date, session_index',
        (user_id, vid))


def resolve_session(user_id: str, *, session_uid: str | None = None,
                    legacy_key: str | None = None, date_str: str | None = None,
                    widen: bool = False) -> dict | None:
    """The planned session a match or a log refers to.

    By uid it is exact. By legacy key it needs the date too, because a legacy
    key is not unique — a spliced program can carry the same `week_number` at
    two array indices — and if the pair still matches more than one row this
    refuses rather than guesses.

    `widen` allows a one-day slip, and is for attributing an *existing* match
    for display only, never for scoring: src/fit_import.py derives a workout's
    date from a UTC-forced start time, so an evening workout west of UTC is
    already dated a day late and no user timezone is stored anywhere.
    """
    if session_uid:
        rows = _query(
            'SELECT session_uid, program_version_id, date, week_index, week_number, '
            'day_name, session_index, legacy_key, modality, archetype_id, '
            'archetype_name, duration_min, phase, is_deload '
            'FROM planned_sessions WHERE user_id = %s AND session_uid = %s',
            (user_id, session_uid))
        return rows[0] if rows else None

    if not legacy_key or not date_str:
        return None

    day = str(date_str)[:10]
    candidates = _by_legacy_key(planned_sessions_on_dates(user_id, [day]), legacy_key)
    if len(candidates) == 1:
        return candidates[0]
    if candidates:
        return None                       # ambiguous — refuse rather than guess

    if not widen:
        return None
    try:
        anchor = date.fromisoformat(day)
    except ValueError:
        return None
    from datetime import timedelta as _td
    neighbours = [(anchor - _td(days=1)).isoformat(), (anchor + _td(days=1)).isoformat()]
    near = _by_legacy_key(planned_sessions_on_dates(user_id, neighbours), legacy_key)
    return near[0] if len(near) == 1 else None


def _by_legacy_key(rows: list[dict], legacy: str) -> list[dict]:
    """Rows a stored session key refers to, in either of the shapes in the wild.

    Keys come in two forms. The matcher and the watch write the full
    '{week}-{Day}-{index}'; the dashboard, the session screen and
    progression_tracker write a day-level '{week}-{Day}' with no index, which
    progression_tracker indexes alongside the full form. A day-level key means
    "that day's session", so it resolves only when the day has exactly one —
    which the single-element return in the caller enforces.
    """
    exact = [r for r in rows if r['legacy_key'] == legacy]
    if exact:
        return exact
    if legacy.count('-') >= 2:
        return []
    return [r for r in rows if r['legacy_key'].startswith(legacy + '-')]


def list_activations(user_id: str) -> list[dict]:
    """The athlete's program timeline, newest first.

    Joins to workout_matches and session_logs in Python rather than SQL:
    migrations/001 types user_id as TEXT while supabase/schema.sql types
    workout_matches.user_id as UUID, so a SQL join between them has no operator.
    """
    activations = _query('''
        SELECT a.id AS activation_id, a.program_version_id, a.lineage_id,
               a.effective_from, a.effective_to, a.activated_at, a.source,
               a.source_goal_ids, a.goal_name,
               v.start_date, v.week_count, v.first_seen_at
          FROM program_activations a
     LEFT JOIN program_versions v
            ON v.user_id = a.user_id AND v.id = a.program_version_id
         WHERE a.user_id = %s
      ORDER BY a.effective_from DESC, a.id DESC
    ''', (user_id,))
    if not activations:
        return []

    planned = _query(
        'SELECT program_version_id, COUNT(*) AS n, MIN(date) AS first_date, '
        'MAX(date) AS last_date FROM planned_sessions '
        'WHERE user_id = %s GROUP BY program_version_id', (user_id,))
    counts = {p['program_version_id']: p for p in planned}

    matched_uids = {r['session_uid'] for r in _query(
        "SELECT session_uid FROM workout_matches WHERE user_id = %s "
        "AND session_uid IS NOT NULL AND match_confidence <> 'rejected'",
        (user_id,))}
    logged_uids = {r['session_uid'] for r in _query(
        'SELECT session_uid FROM session_logs WHERE user_id = %s '
        'AND session_uid IS NOT NULL', (user_id,))}

    out = []
    for a in activations:
        vid = a['program_version_id']
        prefix = vid + ':'
        stats = counts.get(vid) or {}
        out.append({
            'activationId':   a['activation_id'],
            'versionId':      vid,
            'lineageId':      a['lineage_id'],
            'label':          _label(a),
            'goalName':       a['goal_name'],
            'sourceGoalIds':  a['source_goal_ids'] or [],
            'effectiveFrom':  str(a['effective_from']),
            'effectiveTo':    str(a['effective_to']) if a['effective_to'] else None,
            'isActive':       a['effective_to'] is None,
            'activatedAt':    str(a['activated_at']),
            'source':         a['source'],
            'startDate':      str(a['start_date']) if a['start_date'] else None,
            'weekCount':      a['week_count'],
            'sessionCount':   int(stats.get('n') or 0),
            'firstDate':      str(stats['first_date']) if stats.get('first_date') else None,
            'lastDate':       str(stats['last_date']) if stats.get('last_date') else None,
            'matchedCount':   sum(1 for u in matched_uids if u and u.startswith(prefix)),
            'loggedCount':    sum(1 for u in logged_uids if u and u.startswith(prefix)),
        })
    return out


def _label(activation: dict) -> str:
    """A display name derived at read time, never stored.

    A stored label goes stale the moment anything it was derived from changes.
    """
    name = activation.get('goal_name')
    if not name:
        ids = activation.get('source_goal_ids') or []
        name = ', '.join(str(i).replace('_', ' ').title() for i in ids) or 'Program'
    weeks = activation.get('week_count') or 0
    span = str(activation.get('effective_from'))
    return f'{name} · {weeks} wk · from {span}' if weeks else f'{name} · from {span}'


def get_version(user_id: str, vid: str) -> dict | None:
    """The frozen envelope of one archived program."""
    rows = _query(
        'SELECT id, program_data, start_date, week_count, skeleton_hash, first_seen_at '
        'FROM program_versions WHERE user_id = %s AND id = %s', (user_id, vid))
    if not rows:
        return None
    row = rows[0]
    return {
        'versionId':   row['id'],
        'program':     row['program_data'],
        'startDate':   str(row['start_date']),
        'weekCount':   row['week_count'],
        'firstSeenAt': str(row['first_seen_at']),
    }


def active_version_id(user_id: str) -> str | None:
    """The version currently at the head of the timeline."""
    rows = _query('SELECT program_version_id FROM program_activations '
                  'WHERE user_id = %s AND effective_to IS NULL '
                  'ORDER BY id DESC LIMIT 1', (user_id,))
    return rows[0]['program_version_id'] if rows else None


def active_plan_dates(user_id: str) -> tuple[str | None, dict]:
    """(active version id, {legacy_key or session_uid: planned date}) — what
    session_scope checks a row's dates against. A spliced program can carry
    one legacy key twice; such a key is left out rather than guessed, and a
    row scoped to it is dated by its uid instead (uids contain ':', keys never
    do, so one dict holds both)."""
    vid = active_version_id(user_id)
    if not vid:
        return None, {}
    rows = _query('SELECT legacy_key, session_uid, date FROM planned_sessions '
                  'WHERE user_id = %s AND program_version_id = %s', (user_id, vid))
    dates: dict = {}
    dup: set = set()
    for r in rows:
        k = r['legacy_key']
        if k in dates:
            dup.add(k)
        dates[k] = r['date']
    for k in dup:
        dates.pop(k, None)
    for r in rows:
        dates[r['session_uid']] = r['date']
    return vid, dates


def annotate_logs(logs: list[dict], planned: dict[str, dict]) -> list[dict]:
    """Name the planned session each recent log belongs to (in place).

    `planned` is planned_rows_for_uids' answer for the logs' uids. Pure.

    The web writes a day-level key ('1-Wednesday'); the phone looks sessions up
    by '1-Wednesday-0' and so found neither the completion nor the linked
    workout. The uid names the exact session, so a current-program log is
    handed over under its full key — and a write back under that key resolves
    to the same uid, the same row.
    """
    for log in logs:
        row = planned.get(log.get('session_uid') or '')
        if not row:
            continue
        log['planned_name'] = row.get('archetype_name')
        log['planned_modality'] = row.get('modality')
        log['planned_date'] = row.get('date')
        log['program_version_id'] = row.get('program_version_id')
        log['week_index'] = row.get('week_index')
        log['day_name'] = row.get('day_name')
        full = row.get('legacy_key')
        if (log.get('in_current_program') and full
                and full.startswith(log['session_key'] + '-')):
            log['session_key'] = full
    return logs


def planned_rows_for_uids(user_id: str, uids: list[str]) -> dict[str, dict]:
    """The flat `planned_sessions` rows for named sessions, keyed by uid —
    name, modality, date and position, without loading any version snapshot.
    What a list of logs needs to say which session each one was."""
    wanted = sorted({u for u in (uids or []) if u})
    if not wanted:
        return {}
    rows = _query(
        'SELECT session_uid, program_version_id, date, week_index, week_number, '
        'day_name, session_index, legacy_key, modality, archetype_id, archetype_name, '
        'phase, is_deload '
        'FROM planned_sessions WHERE user_id = %s AND session_uid = ANY(%s::text[])',
        (user_id, wanted))
    out = {}
    for row in rows:
        record = dict(row)
        record['date'] = str(row['date'])
        out[row['session_uid']] = record
    return out


def session_lookup(user_id: str, uids: list[str]) -> list[dict]:
    """Full records for named sessions, including the session JSON itself.

    `planned_sessions` deliberately stores no session payload — it would be a
    second copy of what `program_versions.program_data` already holds, and the
    web store writes on every drag-move. So the exercises, slots and loads come
    from the version snapshot, walked by the (week_index, day_name,
    session_index) the flat row records.

    Bounded by the uids the caller asks for, which in practice is "the sessions
    something is attached to" — every match and every log. That keeps the
    progression endpoints from loading every snapshot the athlete has ever had.
    """
    wanted = sorted({u for u in (uids or []) if u})
    if not wanted:
        return []

    rows = _query(
        'SELECT session_uid, program_version_id, date, week_index, week_number, '
        'day_name, session_index, legacy_key, modality, archetype_id, '
        'archetype_name, duration_min, phase, is_deload '
        'FROM planned_sessions WHERE user_id = %s AND session_uid = ANY(%s::text[]) '
        'ORDER BY date, session_index',
        (user_id, wanted))
    if not rows:
        return []

    version_ids = sorted({r['program_version_id'] for r in rows})
    snapshots = {
        v['id']: unwrap(v['program_data'])
        for v in _query('SELECT id, program_data FROM program_versions '
                        'WHERE user_id = %s AND id = ANY(%s::text[])',
                        (user_id, version_ids))
    }

    out: list[dict] = []
    for row in rows:
        program = snapshots.get(row['program_version_id']) or {}
        weeks = program.get('weeks') or []
        if row['week_index'] >= len(weeks):
            continue
        day = (weeks[row['week_index']].get('schedule') or {}).get(row['day_name']) or []
        if row['session_index'] >= len(day):
            continue
        record = dict(row)
        record['date'] = str(row['date'])
        record['session'] = day[row['session_index']]
        out.append(record)
    return out


def active_session_uid(user_id: str, legacy: str) -> str | None:
    """The uid of a session in the plan that is in force right now.

    What a session log needs. A log arrives carrying only a program-relative
    key — the dashboard and the watch do not know what a program version is —
    and the session it means is the one in today's plan. Resolving against the
    active version rather than against a date is also what makes a log write
    stable: the same key always lands on the same row for as long as that plan
    is the current one.

    None when it cannot be resolved without guessing, and the log then falls
    back to its bare session_key, exactly as before.
    """
    if not legacy:
        return None
    vid = active_version_id(user_id)
    if not vid:
        return None
    rows = _query('SELECT session_uid, legacy_key FROM planned_sessions '
                  'WHERE user_id = %s AND program_version_id = %s', (user_id, vid))
    found = _by_legacy_key(rows, legacy)
    return found[0]['session_uid'] if len(found) == 1 else None


def prune_versions(user_id: str, keep: int = 40) -> int:
    """Drop closed versions nothing refers to, beyond the most recent `keep`.

    The web store PUTs on every drag-move, so an afternoon of editing can mint
    a lot of versions. A version is only ever removed when its interval is
    closed, it is outside the retention window, and no match or log points at
    any of its sessions.
    """
    from src.db import new_conn
    conn = new_conn(autocommit=False)
    if conn is None:
        return 0
    removed = 0
    try:
        with _dict_cursor(conn) as cur:
            cur.execute('SELECT pg_advisory_xact_lock(hashtext(%s))',
                        ('program_history:' + user_id,))
            cur.execute('''SELECT program_version_id, MAX(id) AS newest
                             FROM program_activations
                            WHERE user_id = %s
                         GROUP BY program_version_id
                         ORDER BY newest DESC
                           OFFSET %s''', (user_id, keep))
            stale = [r['program_version_id'] for r in cur.fetchall()]
            for vid in stale:
                cur.execute('SELECT 1 FROM program_activations WHERE user_id = %s '
                            'AND program_version_id = %s AND effective_to IS NULL LIMIT 1',
                            (user_id, vid))
                if cur.fetchone() or _is_referenced(cur, user_id, vid):
                    continue
                cur.execute('DELETE FROM planned_sessions WHERE user_id = %s '
                            'AND program_version_id = %s', (user_id, vid))
                cur.execute('DELETE FROM program_activations WHERE user_id = %s '
                            'AND program_version_id = %s', (user_id, vid))
                cur.execute('DELETE FROM program_versions WHERE user_id = %s AND id = %s',
                            (user_id, vid))
                removed += 1
        conn.commit()
    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        _log.warning('prune_versions failed for %s: %s', user_id, e)
    finally:
        conn.close()
    return removed
