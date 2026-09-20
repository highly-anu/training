"""The deterministic workout id, in one place.

Every import path derives a workout's primary key from the same four fields, so
re-importing the same file is an idempotent upsert rather than a duplicate row.

DO NOT CHANGE THE FORMULA. `workout_matches.imported_workout_id` and
`session_logs.matched_workout_id` reference these ids; altering the hash orphans
every match already stored. Mirrored in:
  - frontend/src/lib/importParsers.ts   (deterministicId)
  - ios/TrainingCompanion/FITFileParser.swift
  - oauth.py                            (Strava)

Note the id is *source-tagged*: the same ride imported as `fit_file` and as
`garmin` yields two different ids by design. Collapsing those is the job of the
cross-source dedup layer, not of this function.
"""
from __future__ import annotations

import hashlib


def deterministic_id(source: str, start_time: str, activity_type: str,
                     duration_minutes) -> str:
    raw = f"{source}|{start_time}|{activity_type}|{duration_minutes}"
    h = hashlib.sha256(raw.encode()).hexdigest()[:24]
    return f"{source}-{h}"
