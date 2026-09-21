"""Match imported workouts to planned sessions, server-side.

A port of frontend/src/lib/workoutMatcher.ts. The browser copy still runs for
file uploads made in the web app; this one exists because the automatic import
paths have no browser — a Garmin webhook fires while nobody is logged in, and
the iOS app has no matcher of its own. Without it "automatic import" would stop
at the import and leave every workout unmatched until someone opened the web
app.

Both implementations read their thresholds from data/matching_rules.json and
are asserted against the same fixtures (data/matcher_fixtures.json) by
test_workout_matcher.py and frontend/src/lib/workoutMatcher.test.ts. Change the
scoring in the JSON, not here.

One deliberate difference from the TS: this reads both snake_case and camelCase
spellings of `week_number` / `duration_estimate_minutes`, because iOS has
written both into user_programs over time (see src/program_keys.py). The TS
reads snake_case only.
"""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from src.program_keys import DAY_NAMES, normalize_program_keys, pick

_RULES_PATH = Path(__file__).parent.parent / 'data' / 'matching_rules.json'

with open(_RULES_PATH, 'r', encoding='utf-8') as _f:
    RULES = json.load(_f)

# modality id -> family name
_FAMILY_OF = {
    modality: family
    for family, modalities in RULES['families'].items()
    for modality in modalities
}


def modality_family(modality: str | None) -> str:
    return _FAMILY_OF.get(modality or '', 'other')


def session_calendar_date(program_start_date: str, week_index: int, day_name: str) -> str:
    """Calendar date of a session.

    Note `week_index` is the *array position* in program.weeks, not the week's
    own `week_number` — the session key uses week_number, the date uses the
    index. They are not always the same number. The TS has the same split; do
    not "tidy" either one.
    """
    try:
        day_index = DAY_NAMES.index(day_name)
    except ValueError:
        return ''
    try:
        start = date.fromisoformat(str(program_start_date)[:10])
    except (ValueError, TypeError):
        return ''
    return (start + timedelta(days=week_index * 7 + day_index)).isoformat()


def score_match(workout: dict, session_modality: str, session_duration) -> int:
    """0-5. Modality agreement is worth more than duration agreement."""
    score = 0

    inferred = workout.get('inferredModalityId')
    if inferred:
        if inferred == session_modality:
            score += RULES['modalityExactPoints']
        elif modality_family(inferred) == modality_family(session_modality):
            score += RULES['familyPoints']

    try:
        dur_diff = abs(float(workout.get('durationMinutes') or 0) - float(session_duration or 0))
    except (TypeError, ValueError):
        return score

    for max_delta, points in RULES['durationTiers']:
        if dur_diff <= max_delta:
            score += points
            break

    return score


def index_sessions_by_date(program: dict, program_start_date: str) -> dict[str, list[dict]]:
    """calendar date -> the sessions planned for it."""
    index: dict[str, list[dict]] = {}
    for week_index, week in enumerate(program.get('weeks') or []):
        week_number = pick(week, 'week_number', 'weekNumber')
        if week_number is None:
            week_number = week_index + 1
        for day_name, sessions in (week.get('schedule') or {}).items():
            cal_date = session_calendar_date(program_start_date, week_index, day_name)
            if not cal_date:
                continue
            for session_index, session in enumerate(sessions or []):
                archetype = session.get('archetype') or {}
                index.setdefault(cal_date, []).append({
                    'sessionKey': f'{week_number}-{day_name}-{session_index}',
                    'modality': session.get('modality') or '',
                    'duration': pick(archetype, 'duration_estimate_minutes',
                                     'durationEstimateMinutes')
                                or RULES['defaultSessionMinutes'],
                })
    return index


def auto_match(workouts: list[dict], program: dict, program_start_date: str,
               existing_matches: list[dict] | None = None) -> dict:
    """Split workouts into confident matches and things worth asking about.

    Returns {'confirmed': [WorkoutMatch], 'suggested': [{importedWorkoutId,
    sessionKey, score}]}. A workout that already has a match is left alone, and
    one with no planned session that day is dropped entirely.
    """
    confirmed: list[dict] = []
    suggested: list[dict] = []

    existing_ids = {m.get('importedWorkoutId') for m in (existing_matches or [])}
    date_index = index_sessions_by_date(program, program_start_date)
    now_iso = datetime.now(timezone.utc).isoformat()

    auto_threshold = RULES['autoThreshold']
    suggest_threshold = RULES['suggestThreshold']

    for workout in workouts:
        workout_id = workout.get('id')
        if not workout_id or workout_id in existing_ids:
            continue

        candidates = date_index.get(workout.get('date') or '')
        if not candidates:
            continue

        scored = [
            {**c, 'score': score_match(workout, c['modality'], c['duration'])}
            for c in candidates
        ]
        # First-wins on ties, matching the TS reduce (a.score >= b.score).
        best = scored[0]
        for s in scored[1:]:
            if s['score'] > best['score']:
                best = s

        # A single candidate needs only to clear the bar; several need the best
        # one to be unambiguous, or we ask rather than guess.
        unambiguous = len(scored) == 1 or sum(1 for s in scored if s['score'] >= auto_threshold) == 1

        if best['score'] >= auto_threshold and unambiguous:
            confirmed.append({
                'importedWorkoutId': workout_id,
                'sessionKey': best['sessionKey'],
                'matchConfidence': 'auto',
                'matchedAt': now_iso,
            })
        elif best['score'] >= suggest_threshold:
            suggested.append({
                'importedWorkoutId': workout_id,
                'sessionKey': best['sessionKey'],
                'score': best['score'],
            })

    return {'confirmed': confirmed, 'suggested': suggested}


def match_and_store(user_id: str, workouts: list[dict]) -> dict:
    """Match freshly imported workouts and persist the result.

    Confident matches go to `workout_matches`; weaker ones go to
    `workout_match_suggestions`, deliberately NOT to `workout_matches` with a
    'pending' confidence — a dozen call sites across api.py and the frontend
    treat "has a row that isn't 'rejected'" as "is matched", so a pending row
    there would show up as a confirmed match everywhere.

    Returns counts; never raises — a matching failure must not fail the import
    that produced the workouts.
    """
    from src import health_store
    from src.db import get_user_program

    result = {'confirmed': 0, 'suggested': 0}
    if not workouts:
        return result

    try:
        stored = get_user_program(user_id)
        if not isinstance(stored, dict):
            return result
        stored = normalize_program_keys(stored)
        program = stored.get('currentProgram') or {}
        start_date = stored.get('programStartDate')
        if not program.get('weeks') or not start_date:
            return result

        existing = health_store.get_matches(user_id)
        outcome = auto_match(workouts, program, str(start_date), existing)

        for match in outcome['confirmed']:
            health_store.upsert_match(user_id, match)
        if outcome['suggested']:
            health_store.upsert_match_suggestions(user_id, outcome['suggested'])

        result['confirmed'] = len(outcome['confirmed'])
        result['suggested'] = len(outcome['suggested'])
    except Exception:
        # Deliberately swallowed: the workouts are already saved, and an
        # unmatched workout is a far better outcome than a failed import.
        pass

    return result
