"""Collapsing the same activity arriving from several sources.

A workout's primary key embeds its source (see src/workout_ids.py), so one
morning run can land four times: pushed by the Garmin webhook, relayed out of
Apple Health by the phone, pulled from Strava, and uploaded by hand as a .fit.
Four ids, four rows, one run.

Matching on the id cannot fix this — and changing the id formula is not an
option, because workout_matches.imported_workout_id references it. So dedup is
a separate layer: decide whether an incoming workout *is* an existing one, and
if so merge into the row that is already there rather than inserting.

Two mechanisms, deliberately:

  `dedupe_key` is a coarse bucket stored on the row — cheap to index, but
  fragile on its own, since a start time that differs by a few seconds across a
  minute boundary hashes differently.

  `is_same_activity` is the actual decision, made over a ±5 minute window. The
  key narrows; the comparison decides.

Rules that matter:
  - The canonical row's id NEVER changes. workout_matches and session_logs
    point at it.
  - Losing rows are never deleted, only marked with `canonical_id`.
  - A richer source arriving later promotes its data into the canonical row
    without taking over its identity.
"""
from __future__ import annotations

import hashlib
from datetime import datetime, timezone

# How much detail a source carries, best first. A FIT file (from a manual
# export or from Garmin) has per-second GPS, HR, cadence and power; an Apple
# Health summary relayed by the phone has far less; a Strava summary less again.
SOURCE_RANK = ['fit_file', 'garmin', 'apple_watch_live', 'watch', 'apple_health',
               'strava', 'manual']

# Data columns worth promoting from a richer duplicate into the canonical row.
MERGEABLE_FIELDS = ('gpsTrack', 'hrSamples', 'elevation', 'calories', 'distance',
                    'inferredModalityId')

# How far apart two recordings of the same activity may start.
START_WINDOW_SECONDS = 5 * 60
# Durations must agree within this many minutes, or 10%, whichever is larger —
# devices stop at different moments and auto-pause differs between them.
MIN_DURATION_TOLERANCE_MIN = 3
DURATION_TOLERANCE_FRACTION = 0.10


def source_rank(source: str | None) -> int:
    """Lower is richer. Unknown sources sort last."""
    try:
        return SOURCE_RANK.index(source or '')
    except ValueError:
        return len(SOURCE_RANK)


def parse_time(value) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except (ValueError, TypeError):
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def dedupe_key(workout: dict) -> str | None:
    """Coarse bucket for an activity, independent of which source reported it.

    Start time is rounded to the minute and duration to the nearest 5, so small
    disagreements between devices still land together. This is an index
    fast-path, not the decision — see `is_same_activity`.
    """
    start = parse_time(workout.get('startTime'))
    if start is None:
        return None
    try:
        duration = float(workout.get('durationMinutes') or 0)
    except (TypeError, ValueError):
        return None

    minute_bucket = int(start.timestamp() // 60)
    duration_bucket = int(round(duration / 5.0) * 5)
    raw = f'{minute_bucket}|{duration_bucket}'
    return hashlib.sha256(raw.encode()).hexdigest()[:24]


def _family(modality: str | None) -> str:
    from src.workout_matcher import modality_family
    return modality_family(modality)


def is_same_activity(a: dict, b: dict) -> bool:
    """Are these two records of one activity?

    Requires overlapping start times and agreeing durations. Modality is a veto
    only when both sides claim one and they disagree by family — a bike ride and
    a strength session that happen to start together are not the same thing,
    but an unlabelled import should not be blocked from merging.
    """
    start_a, start_b = parse_time(a.get('startTime')), parse_time(b.get('startTime'))
    if start_a is None or start_b is None:
        return False
    if abs(start_a.timestamp() - start_b.timestamp()) > START_WINDOW_SECONDS:
        return False

    try:
        dur_a = float(a.get('durationMinutes') or 0)
        dur_b = float(b.get('durationMinutes') or 0)
    except (TypeError, ValueError):
        return False
    tolerance = max(MIN_DURATION_TOLERANCE_MIN,
                    DURATION_TOLERANCE_FRACTION * max(dur_a, dur_b))
    if abs(dur_a - dur_b) > tolerance:
        return False

    mod_a, mod_b = a.get('inferredModalityId'), b.get('inferredModalityId')
    if mod_a and mod_b and _family(mod_a) != _family(mod_b):
        return False

    return True


def _is_empty(value) -> bool:
    if value is None:
        return True
    if isinstance(value, (list, dict, str)):
        return len(value) == 0
    return False


def merge_fields(canonical: dict, incoming: dict) -> dict:
    """Fields the canonical row should gain from `incoming`.

    Always fills gaps. When `incoming` comes from a richer source it also
    replaces fields the canonical row already has — a Strava summary should not
    keep its coarse elevation once the real FIT file turns up. The canonical
    row's identity (id, source) is never part of this.
    """
    incoming_is_richer = source_rank(incoming.get('source')) < source_rank(canonical.get('source'))

    updates: dict = {}
    for field in MERGEABLE_FIELDS:
        new_value = incoming.get(field)
        if _is_empty(new_value):
            continue
        if _is_empty(canonical.get(field)) or incoming_is_richer:
            updates[field] = new_value

    # Heart-rate summary is nested; treat its parts individually.
    incoming_hr = incoming.get('heartRate') or {}
    canonical_hr = canonical.get('heartRate') or {}
    hr_updates = {}
    for key in ('avg', 'max', 'min', 'samples'):
        new_value = incoming_hr.get(key)
        if _is_empty(new_value):
            continue
        if _is_empty(canonical_hr.get(key)) or incoming_is_richer:
            hr_updates[key] = new_value
    if hr_updates:
        updates['heartRate'] = {**canonical_hr, **hr_updates}

    return updates


def plan_upserts(incoming: list[dict], existing: list[dict]) -> list[dict]:
    """Decide what to do with each incoming workout.

    `existing` is the user's current canonical rows (id, source, startTime,
    durationMinutes, inferredModalityId and whichever data fields were
    fetched). Returns one action per incoming workout:

        {'action': 'insert', 'workout': {...}}
        {'action': 'merge',  'canonicalId': str, 'updates': {...},
         'duplicateId': str, 'workout': {...}}

    Incoming workouts are also compared against each other, so a single batch
    carrying the same activity twice collapses rather than racing itself.
    """
    pool = list(existing)
    actions: list[dict] = []

    for workout in incoming:
        canonical = next((e for e in pool if is_same_activity(e, workout)), None)

        if canonical is None or canonical.get('id') == workout.get('id'):
            # Nothing to merge with, or it *is* this row — a plain idempotent
            # re-import, which the primary key already handles.
            actions.append({'action': 'insert', 'workout': workout})
            if canonical is None:
                pool.append(workout)
            continue

        updates = merge_fields(canonical, workout)
        canonical.update(updates)  # later items in the batch see the enrichment
        actions.append({
            'action': 'merge',
            'canonicalId': canonical['id'],
            'duplicateId': workout.get('id'),
            'updates': updates,
            'workout': workout,
        })

    return actions
