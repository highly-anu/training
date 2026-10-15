"""Log ▸ Linking: recorded workouts and planned sessions, one card per day.

The server's copy of `frontend/src/lib/linking.ts`, for clients with no
matcher of their own (the phone; `GET /api/health/linking`). Same rules:

- One card per calendar day from the first planned day to `today`, newest
  first: the current program's days and, before them, every earlier
  program's (`planned_sessions`). A date an earlier program has rows on is
  that program's day, as in the matcher's index (`history_aware_index`).
- A workout is only ever *suggested* for a session on its own date, scored
  with the shared `score_match`, one-to-one, best first. A server suggestion
  is kept when it names a session on the workout's date. Linking across
  dates is the athlete's call.
- Every session carries the `session_uid` a match stores; without it the
  server resolves the legacy key on the workout's date, which finds nothing
  across days.

Pure: no Flask, no DB. Change a rule here and in linking.ts together.
"""
from __future__ import annotations

import re
from datetime import date, timedelta

from src.workout_matcher import (
    DAY_NAMES, RULES, score_match, session_calendar_date, session_equipment,
)

_KEY = re.compile(r'^(\d+)-([A-Za-z]+)(?:-(\d+))?$')


def dismiss_key(workout_id: str, session_key: str) -> str:
    return f'{workout_id}|{session_key}'


def session_uid(version_id: str, week_index: int, day_name: str, index: int) -> str:
    """Mirrors `program_history.session_uid`."""
    return f'{version_id}:w{week_index}-{day_name}-{index}'


def _is_day_level(key: str) -> bool:
    m = _KEY.match(key or '')
    return bool(m) and m.group(3) is None


def _name(modality: str, archetype_name) -> str:
    return archetype_name or (modality or '').replace('_', ' ')


def program_sessions(program: dict, start_date: str, version_id: str | None) -> dict[str, dict]:
    """Every planned session of the current program, by its per-session key."""
    out: dict[str, dict] = {}
    for week_index, week in enumerate((program or {}).get('weeks') or []):
        schedule = week.get('schedule') or {}
        for day_name in DAY_NAMES:
            day_sessions = schedule.get(day_name)
            if not day_sessions:
                continue
            day = session_calendar_date(start_date, week_index, day_name)
            for index, s in enumerate(day_sessions):
                key = f"{week.get('week_number')}-{day_name}-{index}"
                if key in out:
                    continue   # a repeated week number: the first one owns the key
                archetype = s.get('archetype') or {}
                out[key] = {
                    'key': key, 'legacyKey': key,
                    'uid': session_uid(version_id, week_index, day_name, index) if version_id else None,
                    'date': day, 'weekNumber': week.get('week_number'), 'dayName': day_name, 'index': index,
                    'modality': s.get('modality'),
                    'name': _name(s.get('modality'), archetype.get('name')),
                    'durationMinutes': archetype.get('duration_estimate_minutes') or RULES['defaultSessionMinutes'],
                    'equipment': session_equipment(s),
                    'historical': False,
                    'programVersionId': version_id,
                    'completedAt': None,
                }
    return out


def history_session(row: dict) -> dict:
    """An archived session (a `GET /programs/planned-sessions` row) as a card row.
    The archive keeps no equipment, so the activity gate caps it."""
    uid = row['sessionUid']
    return {
        'key': uid, 'legacyKey': row.get('sessionKey'), 'uid': uid,
        'date': row['date'],
        'weekNumber': row.get('weekNumber') if row.get('weekNumber') is not None else row.get('weekIndex', 0) + 1,
        'dayName': row.get('dayName'), 'index': row.get('sessionIndex') or 0,
        'modality': row.get('modality'),
        'name': _name(row.get('modality'), row.get('archetypeName')),
        'durationMinutes': row.get('durationMinutes') or RULES['defaultSessionMinutes'],
        'equipment': [],
        'historical': True,
        'programVersionId': row.get('programVersionId') or uid.split(':')[0],
        'completedAt': row.get('completedAt'),
    }


def _by_legacy_key(sessions: list[dict], key: str) -> dict | None:
    """The session a stored key names among one day's sessions. A day-level
    key names that day's session only when it has just one."""
    exact = [s for s in sessions if s['legacyKey'] == key]
    if exact:
        return exact[0] if len(exact) == 1 else None
    if not _is_day_level(key):
        return None
    day = [s for s in sessions if (s['legacyKey'] or '').startswith(f'{key}-')]
    return day[0] if len(day) == 1 else None


def _score(workout: dict, s: dict) -> int:
    return score_match(workout, s['modality'], s['durationMinutes'], s['equipment'])


def suggest_for_day(workouts: list[dict], sessions: list[dict], dismissed=frozenset()) -> list[dict]:
    """Every pair at or above the suggest threshold, best first, each side used
    once. Ties keep the earlier workout and the earlier session."""
    pairs = []
    for w in workouts:
        for s in sessions:
            if dismiss_key(w['id'], s['key']) in dismissed:
                continue
            score = _score(w, s)
            if score >= RULES['suggestThreshold']:
                pairs.append({'workout': w, 'session': s, 'score': score, 'fromPending': False})
    pairs.sort(key=lambda p: -p['score'])   # stable, as Array.sort is
    used_w, used_s, out = set(), set(), []
    for p in pairs:
        if p['workout']['id'] in used_w or p['session']['key'] in used_s:
            continue
        used_w.add(p['workout']['id'])
        used_s.add(p['session']['key'])
        out.append(p)
    return out


def _belongs_to_version(match: dict, version_id: str | None) -> bool:
    """`lib/sessionMatching.belongsToVersion`."""
    if match.get('inCurrentProgram') is False:
        return False
    if not match.get('sessionUid') or not version_id:
        return True
    return match['sessionUid'].startswith(f'{version_id}:')


def _add_days(day: str, n: int) -> str:
    return (date.fromisoformat(day) + timedelta(days=n)).isoformat()


def build_linking_days(*, workouts: list[dict], matches: list[dict], pending: list[dict],
                       program: dict | None, program_start_date: str | None,
                       program_version_id: str | None, history: list[dict], today: str,
                       dismissed=frozenset()) -> list[dict]:
    """One card per day, newest first. `pending` is the server's outstanding
    suggestions (`importedWorkoutId`, `sessionKey`), newest first; `history` the
    planned-sessions rows across programs (the current version's are skipped)."""
    current = (program_sessions(program, program_start_date, program_version_id)
               if program and program_start_date else {})
    current_first = min([s['date'] for s in current.values()] + [program_start_date],
                        default=None) if current else None

    past = [history_session(r) for r in history or []
            if not (program_version_id and r.get('programVersionId') == program_version_id)]
    past_by_uid = {s['uid']: s for s in past}

    every = list(current.values()) + past
    if not every:
        return []
    first_date = min(s['date'] for s in every)

    def in_range(d) -> bool:
        return bool(d) and first_date <= d <= today

    by_date: dict[str, list[dict]] = {}
    for s in past:
        by_date.setdefault(s['date'], []).append(s)
    past_dates = set(by_date)
    for s in current.values():
        if s['date'] not in past_dates:
            by_date.setdefault(s['date'], []).append(s)
    for lst in by_date.values():
        lst.sort(key=lambda s: s['index'])

    def past_on(d: str) -> list[dict]:
        return [s for s in by_date.get(d, []) if s['historical']]

    def session_of(m: dict, workout_date: str) -> dict | None:
        uid = m.get('sessionUid')
        if uid and uid in past_by_uid:
            return past_by_uid[uid]
        if _belongs_to_version(m, program_version_id):
            key = m.get('sessionKey') or ''
            s = current.get(key) or (current.get(f'{key}-0') if _is_day_level(key) else None)
            if s:
                return s
        if uid:
            return None                 # a version this page has no rows for
        key = m.get('sessionKey') or ''
        return (_by_legacy_key(past_on(workout_date), key)
                or _by_legacy_key(past_on(_add_days(workout_date, -1)) + past_on(_add_days(workout_date, 1)), key))

    match_of = {m['importedWorkoutId']: m for m in matches}
    linked_keys: set[str] = set()
    links, unlinked, elsewhere, declined = [], [], [], []

    for w in workouts:
        m = match_of.get(w['id'])
        if not m:
            if in_range(w.get('date')):
                unlinked.append(w)
            continue
        if m.get('matchConfidence') == 'rejected':
            if in_range(w.get('date')):
                declined.append(w)
            continue
        s = session_of(m, w.get('date') or '')
        if s:
            linked_keys.add(s['key'])
            if in_range(w.get('date')) or in_range(s['date']):
                links.append({'workout': w, 'session': s})
        elif in_range(w.get('date')):
            elsewhere.append({'workout': w, 'sessionKey': m.get('sessionKey')})

    days: dict[str, dict] = {}

    def day(d: str) -> dict:
        if d not in days:
            first = (by_date.get(d) or [None])[0]
            historical = first['historical'] if first else not (current_first and d >= current_first)
            days[d] = {
                'date': d, 'historical': historical,
                'programVersionId': first['programVersionId'] if first else (None if historical else program_version_id),
                'links': [], 'suggestions': [], 'workouts': [], 'sessions': [],
                'elsewhere': [], 'declined': [], 'needsAttention': False,
            }
        return days[d]

    for d in by_date:
        if in_range(d):
            day(d)
    for w in unlinked:
        day(w['date'])
    for link in links:
        wd, sd = link['workout']['date'], link['session']['date']
        if in_range(wd):
            day(wd)['links'].append(link)
        if sd != wd and in_range(sd):
            day(sd)['links'].append(link)
    for e in elsewhere:
        day(e['workout']['date'])['elsewhere'].append(e)
    for w in declined:
        day(w['date'])['declined'].append(w)

    pending_for: dict[str, str] = {}
    for p in pending:
        pending_for.setdefault(p['importedWorkoutId'], p['sessionKey'])

    for d in days.values():
        free_w = [w for w in unlinked if w['date'] == d['date']]
        free_s = [s for s in by_date.get(d['date'], []) if s['key'] not in linked_keys]

        for w in free_w:
            key = pending_for.get(w['id'])
            s = _by_legacy_key(free_s, key) if key else None
            if not s or dismiss_key(w['id'], s['key']) in dismissed:
                continue
            d['suggestions'].append({'workout': w, 'session': s, 'score': _score(w, s), 'fromPending': True})
            free_s = [x for x in free_s if x is not s]
        taken = {p['workout']['id'] for p in d['suggestions']}
        free_w = [w for w in free_w if w['id'] not in taken]

        scored = suggest_for_day(free_w, free_s, dismissed)
        d['suggestions'].extend(scored)
        sw = {p['workout']['id'] for p in scored}
        ss = {p['session']['key'] for p in scored}
        d['workouts'] = [w for w in free_w if w['id'] not in sw]
        d['sessions'] = [s for s in free_s if s['key'] not in ss]
        d['needsAttention'] = bool(d['suggestions'] or d['workouts'])

    return sorted(days.values(), key=lambda d: d['date'], reverse=True)


# ── Wire shape ────────────────────────────────────────────────────────────────

_WORKOUT_KEYS = ('id', 'date', 'startTime', 'source', 'activityType', 'name',
                 'durationMinutes', 'inferredModalityId', 'distance')
_SESSION_KEYS = ('key', 'legacyKey', 'uid', 'date', 'weekNumber', 'dayName', 'index',
                 'modality', 'name', 'durationMinutes', 'historical', 'programVersionId',
                 'completedAt')


def _w(w: dict) -> dict:
    return {k: w.get(k) for k in _WORKOUT_KEYS if k in w}


def _s(s: dict) -> dict:
    return {k: s.get(k) for k in _SESSION_KEYS}


def to_wire(days: list[dict], labels: dict[str, str] | None = None) -> list[dict]:
    """Slim, JSON-ready days: a workout carries its summary, never its series."""
    labels = labels or {}
    out = []
    for d in days:
        out.append({
            'date': d['date'],
            'historical': d['historical'],
            'programVersionId': d['programVersionId'],
            'programLabel': labels.get(d['programVersionId']) if d['programVersionId'] else None,
            'links': [{'workout': _w(p['workout']), 'session': _s(p['session'])} for p in d['links']],
            'suggestions': [{'workout': _w(p['workout']), 'session': _s(p['session']),
                             'score': p['score'], 'fromPending': p['fromPending']}
                            for p in d['suggestions']],
            'workouts': [_w(w) for w in d['workouts']],
            'sessions': [_s(s) for s in d['sessions']],
            'elsewhere': [{'workout': _w(e['workout']), 'sessionKey': e['sessionKey']} for e in d['elsewhere']],
            'declined': [_w(w) for w in d['declined']],
            'needsAttention': d['needsAttention'],
        })
    return out
