"""Results a logged session suggests, and the athlete confirms.

A test session (src/standard_tests.py) is planned with a standard on each
scored slot. When its log arrives — from the web, the phone or a watch — the
logged outcome of that slot is read as a result on the standard and kept as a
*suggestion* (`standard_result_suggestions`, migrations/012). A pending
suggestion is never a result: workout_match_suggestions exists because a dozen
readers took "a match row that isn't rejected" as matched, and a result row
that is only a guess would be the same mistake in the standards' history. It
becomes a result in performance_logs only when the athlete confirms it — on
the web, the phone or, with `standardResults` in the session log, the watch.

A completed single on a lift a ×BW standard is `derived_from` suggests a
result too, when it beats the current one: training is Starting Strength's
test. The estimate from heavier sets stays a read-time estimate
(analytics.benchmarks.standing).

`candidates` and `describe` are pure; `after_session_log` does the I/O, and
never fails the log write it follows — what went wrong is in its answer.
"""
from __future__ import annotations

import logging
from datetime import datetime, timezone

from src import standards as _standards
from src.analytics import benchmarks_data as bd

_log = logging.getLogger(__name__)

ORIGINS = ('test_slot', 'derived_single', 'best_effort')
STATUSES = ('pending', 'confirmed', 'dismissed')

# A session log's `source` → the result's. The watch measured it, so a result
# confirmed from a watch-logged session says so; every other log is a session.
_RESULT_SOURCE = {'garmin': 'garmin', 'apple_watch': 'apple_watch', 'watch': 'apple_watch'}


def result_source(log_source: str | None) -> str:
    return _RESULT_SOURCE.get((log_source or '').lower(), 'session')


# ── finding a slot's entry in a log ──────────────────────────────────────────

def _humanise(role: str | None) -> str:
    return (role or '').replace('_', ' ').strip().casefold()


def _keys_for(assignment: dict) -> list[str]:
    """What a log may call this exercise, most exact first: the id the web and
    the phone key by, then the name Garmin keys by (case-folded too), then the
    slot role as a person would say it."""
    ex = assignment.get('exercise') or {}
    keys = [ex.get('id'), ex.get('name')]
    keys += [k.casefold() for k in keys if k]
    keys.append(_humanise(assignment.get('slot_role')))
    return [k for k in keys if k]


def entries_for(assignments: list[dict], exercises: dict) -> list[dict | None]:
    """Each assignment's entry in the log's `exercises`, in order; None where
    there is none, or where a name would fit two of the session's slots
    (refuse rather than guess — the same lift twice in one test is real)."""
    exercises = exercises or {}
    folded = {str(k).casefold(): v for k, v in exercises.items()}
    claims: dict[str, int] = {}
    for a in assignments:
        for k in set(_keys_for(a)):
            claims[k] = claims.get(k, 0) + 1
    out = []
    for a in assignments:
        ex_id = (a.get('exercise') or {}).get('id')
        hit = None
        for k in _keys_for(a):
            if claims.get(k, 0) > 1 and k != ex_id:
                continue
            if k in exercises:
                hit = exercises[k]
            elif k in folded:
                hit = folded[k]
            if hit is not None:
                break
        out.append(hit if isinstance(hit, dict) else None)
    return out


# ── reading a result ─────────────────────────────────────────────────────────

def _sets(entry: dict) -> list[dict]:
    """An entry's sets that were not marked undone. Garmin writes `reps`, the
    web and the phone `repsActual`; both are read."""
    raw = entry.get('sets') if isinstance(entry, dict) else None
    return [s for s in (raw or []) if isinstance(s, dict) and s.get('completed') is not False]


def _reps(s: dict):
    v = s.get('repsActual') if s.get('repsActual') is not None else s.get('reps')
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def _pos(v) -> float | None:
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return float(v) if v > 0 else None


def _time_value(b: dict, seconds: float) -> float:
    """Seconds in the standard's unit (minutes for a time_minutes standard)."""
    if b.get('metric_type') == 'time_minutes':
        return round(seconds / 60, 4)
    return round(seconds, 1)


def read_result(b: dict, kind: str | None, entry: dict | None, *, slot_type: str | None = None,
                log_source: str | None = None) -> tuple[float, dict] | None:
    """(value in the standard's unit, input to keep) from one exercise's log
    entry, or None when the entry holds no reading of this kind.

    duration  `durationSec` (a for-time slot's clock)
    rounds    `rounds`, a partial round's reps in the first set kept beside it
              ("20 + 7"); a Garmin AMRAP before 2.0 wrote its rounds as `reps`
    reps      `repsActual` — summed over the sets of a timed slot (reps in six
              minutes), the best set otherwise (max reps)
    hold      the longest `durationSeconds`
    distance  `distanceKm`, in metres
    load      the heaviest single ÷ bodyweight is `derived_single`'s job; a
              test slot logging a load is read by `single_from_sets`
    """
    if not isinstance(entry, dict):
        return None
    sets = _sets(entry)
    if kind == 'duration':
        sec = _pos(entry.get('durationSec'))
        return (_time_value(b, sec), {'seconds': sec}) if sec else None
    if kind == 'rounds':
        rounds = entry.get('rounds')
        partial = _reps(sets[0]) if sets else None
        if rounds is None and (log_source or '').lower() == 'garmin' and sets and sets[0].get('reps') is not None:
            rounds, partial = sets[0].get('reps'), None
        if isinstance(rounds, bool) or not isinstance(rounds, (int, float)) or rounds < 0:
            return None
        if rounds == 0 and not partial:
            return None
        inp = {'rounds': int(rounds)}
        if partial:
            inp['reps'] = int(partial)
        return float(int(rounds)), inp
    if kind == 'reps':
        counts = [r for r in (_reps(s) for s in sets) if r is not None and r > 0]
        if not counts:
            return None
        total = sum(counts) if slot_type == 'time_domain' else max(counts)
        return float(total), ({'sets': counts} if len(counts) > 1 else {})
    if kind == 'hold':
        holds = [h for h in (_pos(s.get('durationSeconds')) for s in sets) if h]
        if not holds:
            return None
        return _time_value(b, max(holds)), {'seconds': max(holds)}
    if kind == 'distance':
        km = _pos(entry.get('distanceKm'))
        return (round(km * 1000, 1), {'km': km}) if km else None
    return None


def single_from_sets(entry: dict | None) -> float | None:
    """The heaviest completed single in an entry, in kg; None without one."""
    best = None
    for s in _sets(entry or {}):
        kg = _pos(s.get('weightKg'))
        if kg and _reps(s) == 1:
            best = kg if best is None else max(best, kg)
    return best


def derived_map(benchmarks: list[dict]) -> dict[str, list[str]]:
    """{exercise id: [×BW standard ids whose single it suggests]} from each
    standard's `derived_from` (data/benchmarks; `suggest: single` is the
    default and the only kind there is)."""
    out: dict[str, list[str]] = {}
    for b in benchmarks:
        d = b.get('derived_from') or {}
        if b.get('metric_type') != 'bw_ratio' or d.get('suggest', 'single') != 'single':
            continue
        for ex in d.get('exercises') or []:
            out.setdefault(ex, []).append(b['id'])
    return out


# ── what a log suggests ──────────────────────────────────────────────────────

def candidates(sessions: list[dict], exercises: dict, *, benchmarks: dict[str, dict],
               logs: dict, day: str, tz: str | None = None, log_source: str | None = None,
               derived: dict[str, list[str]] | None = None, names: dict[str, str] | None = None,
               ) -> tuple[list[dict], list[dict]]:
    """(suggestions, skipped) for one session log.

    `sessions` are the planned sessions the log belongs to (one, or a day's
    when a day-level key cannot say which); `exercises` the merged log's;
    `benchmarks` by id; `logs` the athlete's results (standards_store
    shape), read for bodyweight and for whether a single beats the current
    result. `derived` is derived_map's answer, `names` {exercise name: id}
    for a log keyed by name. Each suggestion is {benchmarkId, value, input,
    exerciseId, slotRole, origin, sessionIndex}; each skip {benchmarkId,
    reason} — `not_logged` is not reported (a test half done is not a skip).
    """
    out: list[dict] = []
    skipped: list[dict] = []
    seen: set[str] = set()
    used_entries: set[int] = set()

    def add(c: dict) -> None:
        if c['benchmarkId'] in seen:
            return
        seen.add(c['benchmarkId'])
        out.append(c)

    for si, session in enumerate(sessions or []):
        assignments = [a for a in (session.get('exercises') or []) if isinstance(a, dict)]
        found = entries_for(assignments, exercises)
        for a, entry in zip(assignments, found):
            ref = a.get('standard')
            if not ref or not entry:
                continue
            sid = ref.get('id') if isinstance(ref, dict) else ref
            b = benchmarks.get(sid)
            if not b:
                continue
            used_entries.add(id(entry))
            kind = (ref.get('result') if isinstance(ref, dict) else None)
            if kind == 'load':
                kg = single_from_sets(entry)
                got = _bw_ratio(b, kg, logs, day, tz, skipped) if kg else None
            else:
                got = read_result(b, kind, entry, slot_type=a.get('slot_type'), log_source=log_source)
            if got:
                add({'benchmarkId': sid, 'value': got[0], 'input': got[1] or None,
                     'exerciseId': (a.get('exercise') or {}).get('id'), 'slotRole': a.get('slot_role'),
                     'origin': 'test_slot', 'sessionIndex': si})

    # Singles on the lifts a ×BW standard is read from — any session.
    for key, entry in (exercises or {}).items():
        if not isinstance(entry, dict) or id(entry) in used_entries:
            continue
        ex_id = key if key in (derived or {}) else (names or {}).get(str(key).casefold())
        for sid in (derived or {}).get(ex_id or '', []):
            b = benchmarks.get(sid)
            kg = single_from_sets(entry)
            if not b or not kg or sid in seen:
                continue
            got = _bw_ratio(b, kg, logs, day, tz, skipped)
            if not got:
                continue
            current = _standards.entries(logs.get(sid), tz)
            if current and current[-1]['value'] >= got[0]:
                continue                     # does not beat the current result
            add({'benchmarkId': sid, 'value': got[0], 'input': got[1], 'exerciseId': ex_id,
                 'slotRole': None, 'origin': 'derived_single', 'sessionIndex': None})
    return out, skipped


def _bw_ratio(b: dict, kg: float, logs: dict, day: str, tz: str | None,
              skipped: list[dict]) -> tuple[float, dict] | None:
    try:
        return _standards.resolve_input(b, {'kg': kg, 'reps': 1}, logs, day, tz)
    except _standards.InputError:
        skipped.append({'benchmarkId': b['id'], 'reason': 'no_bodyweight'})
        return None


# ── decisions sent with a log ────────────────────────────────────────────────

def normalise_decisions(raw) -> tuple[dict[str, dict], list[str]]:
    """`standardResults` from a session log — {benchmarkId: {decision:
    save|dismiss, value?|text?}} — as ({id: {decision, body}}, problems).
    What is not a decision is reported, never guessed at."""
    out: dict[str, dict] = {}
    problems: list[str] = []
    if raw in (None, {}):
        return out, problems
    if not isinstance(raw, dict):
        return out, ['standardResults must be an object keyed by standard id']
    for sid, d in raw.items():
        if not isinstance(d, dict) or d.get('decision') not in ('save', 'dismiss'):
            problems.append(f'{sid}: decision must be save or dismiss')
            continue
        body = {k: d[k] for k in ('value', 'text', 'kg', 'reps') if d.get(k) is not None}
        out[str(sid)] = {'decision': d['decision'], 'body': body}
    return out, problems


# ── how a suggestion reads ───────────────────────────────────────────────────

def describe(rows: list[dict], benchmarks: dict[str, dict], logs: dict, sex: str = 'male',
             tz: str | None = None, session_names: dict[str, str] | None = None) -> list[dict]:
    """Suggestion rows as the clients show them: the value and its level in
    the server's words, what it would replace (the current result) and
    whether it would be the best — so the confirm reads "Fran 4:58 ·
    advanced · new best" on every screen without a client computing it."""
    out = []
    for r in rows:
        b = benchmarks.get(r['benchmarkId'])
        if not b:
            continue
        p = _standards.point(b, r['value'], r.get('loggedOn'), sex)
        every = _standards.entries(logs.get(b['id']), tz)
        # A re-logged value reopens a saved suggestion: confirming it corrects
        # that result, so it is read against the others and says what it corrects.
        own = next((e for e in every if r.get('performanceLogId') and e['id'] == r['performanceLogId']), None)
        es = [e for e in every if e is not own]
        better = min if b['lower_is_better'] else max
        best = better(es, key=lambda e: e['value']) if es else None
        current = es[-1] if es else None
        is_best = best is None or (r['value'] < best['value'] if b['lower_is_better'] else r['value'] > best['value'])
        out.append({
            'id': r['id'], 'benchmarkId': b['id'], 'name': b.get('name'), 'domain': b.get('domain'),
            'value': r['value'], 'valueText': p['valueText'], 'level': p['level'],
            'levelIndex': p['levelIndex'], 'next': p['next'], 'nextText': p['nextText'],
            'inputText': input_text(r.get('input')),
            'current': (_standards.point(b, current['value'], current['date'], sex) if current else None),
            'bestText': bd.format_value(b, best['value']) if best else None,
            'replacesText': bd.format_value(b, own['value']) if own else None,
            'isBest': is_best,
            'origin': r.get('origin'), 'status': r.get('status'), 'source': r.get('source'),
            'loggedOn': r.get('loggedOn'), 'sessionUid': r.get('sessionUid'),
            'sessionKey': r.get('sessionKey'), 'exerciseId': r.get('exerciseId'),
            'slotRole': r.get('slotRole'), 'resultId': r.get('performanceLogId'),
            'sessionName': (session_names or {}).get(r.get('sessionUid') or r.get('sessionKey') or ''),
        })
    return out


def input_text(inp: dict | None) -> str | None:
    """What was logged, when it says more than the value: "20 + 7" for a
    partial round, the load for a single."""
    if not isinstance(inp, dict):
        return None
    if inp.get('rounds') is not None:
        return f"{inp['rounds']} + {inp['reps']}" if inp.get('reps') else None
    return _standards.input_text(inp)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── after a session log is saved ─────────────────────────────────────────────

_TEST_ARCHETYPES: frozenset | None = None
_DERIVED_NAMES: dict | None = None


def _test_archetype_ids() -> frozenset:
    """Every archetype that is a test — the cheap gate: a log of any other
    session reads no snapshot. Built once per process (an archetype authored
    as a test at runtime is seen after a restart)."""
    global _TEST_ARCHETYPES
    if _TEST_ARCHETYPES is None:
        from src import loader
        from src.standard_tests import is_test
        _TEST_ARCHETYPES = frozenset(a['id'] for a in loader.load_all_archetypes() if is_test(a))
    return _TEST_ARCHETYPES


def _derived_names(derived: dict) -> dict:
    """{case-folded exercise name: id} for the lifts a ×BW standard reads —
    Garmin keys its logs by name."""
    global _DERIVED_NAMES
    if _DERIVED_NAMES is None:
        from src import loader
        catalog, _ = loader.load_all_exercises()
        _DERIVED_NAMES = {str(catalog[i].get('name') or i).casefold(): i for i in derived if i in catalog}
    return _DERIVED_NAMES


def _log_day(row: dict | None, tz: str | None) -> str:
    """The athlete's day the session was done: its completion's, else today's."""
    raw = (row or {}).get('completed_at')
    if raw:
        day = _standards.day_of({'date': str(raw).replace(' ', 'T')}, tz)
        if day:
            return day
    from zoneinfo import ZoneInfo
    try:
        now = datetime.now(ZoneInfo(tz)) if tz else datetime.now(timezone.utc)
    except Exception:  # noqa: BLE001 — an unknown zone reads as UTC
        now = datetime.now(timezone.utc)
    return now.date().isoformat()


def after_session_log(user_id: str, log: dict, row: dict | None, *, session_uid: str | None) -> dict | None:
    """What a just-saved session log suggests, and any decisions it carried.

    `log` is the body as sent, `row` the merged row the upsert returned
    (`exercises` is every exercise logged so far, not only this write's).
    None when the log cannot bear on a standard — no exercises in this
    write and no decisions, or neither a test session nor a single on a
    derived lift. Otherwise {pending, confirmed, skipped, problems, error}:
    a failure here never fails the log, and is said rather than swallowed.
    """
    decisions, problems = normalise_decisions(log.get('standardResults'))
    if not (log.get('exercises') or decisions):
        return None
    try:
        return _after(user_id, log, row or {}, session_uid, decisions, problems)
    except Exception as exc:  # noqa: BLE001 — the log is saved; say what is not
        _log.warning('standards: suggestions for %s failed: %s', log.get('sessionKey'), exc)
        return {'pending': [], 'confirmed': [], 'skipped': [], 'problems': problems,
                'error': 'could not read this session for standards'}


def _after(user_id: str, log: dict, row: dict, session_uid: str | None,
           decisions: dict, problems: list) -> dict | None:
    import json as _json
    from src import program_history, standards_store
    from src.db import get_user_profile

    exercises = row.get('exercises') if row.get('exercises') is not None else log.get('exercises')
    if isinstance(exercises, str):
        exercises = _json.loads(exercises)
    exercises = exercises if isinstance(exercises, dict) else {}
    key = log.get('sessionKey') or row.get('session_key') or ''

    planned = (list(program_history.planned_rows_for_uids(user_id, [session_uid]).values())
               if session_uid else program_history.planned_rows_for_key(user_id, key))
    tests = [r for r in planned if r.get('archetype_id') in _test_archetype_ids()]
    benchmarks = bd.by_id()
    derived = derived_map(list(benchmarks.values()))
    names = _derived_names(derived)
    lifts = [k for k in exercises if k in derived or str(k).casefold() in names]
    if not tests and not lifts and not decisions:
        return None

    sessions = []
    if tests:
        by_uid = {r['session_uid']: r for r in program_history.session_lookup(
            user_id, [r['session_uid'] for r in tests])}
        sessions = [by_uid[r['session_uid']]['session'] for r in tests if r['session_uid'] in by_uid]
        tests = [r for r in tests if r['session_uid'] in by_uid]

    profile = get_user_profile(user_id) or {}
    sex = (profile.get('sex') or 'male').lower()
    tz = profile.get('timezone') or None
    logs = standards_store.list_results(user_id)
    day = _log_day(row, tz)
    log_source = log.get('source') or row.get('source')
    found, skipped = candidates(sessions, exercises, benchmarks=benchmarks, logs=logs, day=day, tz=tz,
                                log_source=log_source, derived=derived, names=names)

    # Each suggestion keys on its own session: a test's on the test's uid
    # (the log may name only the day), a single on the log's.
    own_uid = session_uid or (planned[0]['session_uid'] if len(planned) == 1 else None)
    rows, keep = [], {}
    for c in found:
        uid = tests[c['sessionIndex']]['session_uid'] if c['sessionIndex'] is not None else own_uid
        rows.append({**c, 'sessionUid': uid, 'sessionKey': key, 'source': result_source(log_source),
                     'loggedOn': day})
        keep.setdefault(standards_store.log_key(uid, key), set()).add(c['benchmarkId'])
    for r in tests:
        keep.setdefault(r['session_uid'], set())
    if lifts:
        keep.setdefault(standards_store.log_key(own_uid, key), set())
    standards_store.upsert_suggestions(user_id, rows, prune_keys=keep)

    # Decisions the log carried (a watch's Save / Not a test): only for a
    # standard this session tests or suggested, so a device token reaches no
    # further than the session it logged.
    allowed = {(a.get('standard') or {}).get('id') if isinstance(a.get('standard'), dict) else a.get('standard')
               for s in sessions for a in (s.get('exercises') or []) if isinstance(a, dict)} - {None}
    allowed |= {c['benchmarkId'] for c in found}
    keys = list(keep)
    if decisions:
        current = {s['benchmarkId']: s for s in standards_store.list_suggestions(
            user_id, statuses=STATUSES, log_keys=keys)}
        via = log_source or 'session'
        for sid, d in decisions.items():
            s = current.get(sid)
            if sid not in allowed or s is None:
                problems.append(f'{sid}: not a standard this session suggests')
                continue
            if d['decision'] == 'dismiss':
                standards_store.set_suggestion_status(user_id, s['id'], 'dismissed', via=via,
                                                      from_statuses=('pending',))
                continue
            value = inp = None
            if d['body']:
                try:
                    value, inp = _standards.resolve_input(benchmarks[sid], d['body'], logs, day, tz)
                except _standards.InputError as exc:
                    problems.append(f'{sid}: {exc}')
                    continue
            standards_store.confirm_suggestion(user_id, s['id'], via=via, value=value, input_=inp)

    every = standards_store.list_suggestions(user_id, statuses=('pending', 'confirmed'), log_keys=keys)
    logs = standards_store.list_results(user_id) if decisions else logs
    names_by_key = {r['session_uid']: r.get('archetype_name') for r in planned}
    described = describe(every, benchmarks, logs, sex, tz, names_by_key)
    return {'pending': [s for s in described if s['status'] == 'pending'],
            'confirmed': [s for s in described if s['status'] == 'confirmed'],
            'skipped': skipped, 'problems': problems, 'error': None}
