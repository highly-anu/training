"""SQLite-backed storage for all user health and performance data."""
from __future__ import annotations

import json
import os
import sqlite3

DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'health.db')


def _get_db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create tables if they don't exist. Safe to call on every request."""
    with _get_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS workouts (
                id                  TEXT PRIMARY KEY,
                source              TEXT NOT NULL,
                date                TEXT NOT NULL,
                start_time          TEXT NOT NULL,
                end_time            TEXT NOT NULL,
                duration_minutes    INTEGER NOT NULL,
                activity_type       TEXT NOT NULL,
                inferred_modality_id TEXT,
                hr_avg              REAL,
                hr_max              REAL,
                hr_min              REAL,
                calories            INTEGER,
                distance_value      REAL,
                distance_unit       TEXT,
                raw_data            TEXT DEFAULT '{}',
                gps_track           TEXT,
                elevation_gain      INTEGER,
                elevation_loss      INTEGER,
                hr_samples          TEXT
            )
        ''')
        # Migrate existing tables that lack new columns
        try:
            conn.execute('ALTER TABLE workouts ADD COLUMN gps_track TEXT')
        except sqlite3.OperationalError:
            pass
        try:
            conn.execute('ALTER TABLE workouts ADD COLUMN elevation_gain INTEGER')
        except sqlite3.OperationalError:
            pass
        try:
            conn.execute('ALTER TABLE workouts ADD COLUMN elevation_loss INTEGER')
        except sqlite3.OperationalError:
            pass
        try:
            conn.execute('ALTER TABLE workouts ADD COLUMN hr_samples TEXT')
        except sqlite3.OperationalError:
            pass
        conn.execute('''
            CREATE TABLE IF NOT EXISTS session_logs (
                session_key     TEXT PRIMARY KEY,
                exercises       TEXT NOT NULL DEFAULT '{}',
                notes           TEXT DEFAULT '',
                fatigue_rating  INTEGER,
                completed_at    TEXT
            )
        ''')
        conn.execute('''
            CREATE TABLE IF NOT EXISTS daily_bio (
                date        TEXT PRIMARY KEY,
                resting_hr  INTEGER,
                hrv         REAL,
                notes       TEXT
            )
        ''')
        conn.execute('''
            CREATE TABLE IF NOT EXISTS workout_matches (
                imported_workout_id TEXT PRIMARY KEY,
                session_key         TEXT NOT NULL,
                match_confidence    TEXT NOT NULL,
                matched_at          TEXT NOT NULL
            )
        ''')
        conn.execute('''
            CREATE TABLE IF NOT EXISTS performance_logs (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                benchmark_id TEXT NOT NULL,
                value        REAL NOT NULL,
                logged_at    TEXT NOT NULL
            )
        ''')


# ── Workouts ──────────────────────────────────────────────────────────────────

def upsert_workouts(workouts: list[dict]) -> None:
    with _get_db() as conn:
        for w in workouts:
            hr   = w.get('heartRate') or {}
            dist = w.get('distance') or {}
            elev = w.get('elevation') or {}
            gps = w.get('gpsTrack')
            hr_samples = (hr.get('samples') or [])
            conn.execute('''
                INSERT OR REPLACE INTO workouts
                (id, source, date, start_time, end_time, duration_minutes,
                 activity_type, inferred_modality_id,
                 hr_avg, hr_max, hr_min, calories,
                 distance_value, distance_unit, raw_data,
                 gps_track, elevation_gain, elevation_loss, hr_samples)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                w['id'], w['source'], w['date'], w['startTime'], w['endTime'],
                w['durationMinutes'], w['activityType'],
                w.get('inferredModalityId'),
                hr.get('avg'), hr.get('max'), hr.get('min'),
                w.get('calories'),
                dist.get('value'), dist.get('unit'),
                json.dumps(w.get('rawData', {})),
                json.dumps(gps) if gps else None,
                elev.get('gain'), elev.get('loss'),
                json.dumps(hr_samples) if hr_samples else None,
            ))


def delete_workout(workout_id: str) -> None:
    with _get_db() as conn:
        conn.execute('DELETE FROM workouts WHERE id = ?', (workout_id,))
        conn.execute('DELETE FROM workout_matches WHERE imported_workout_id = ?', (workout_id,))


def get_workouts() -> list[dict]:
    with _get_db() as conn:
        rows = conn.execute('SELECT * FROM workouts ORDER BY date DESC').fetchall()
    return [_row_to_workout(row) for row in rows]


def _row_to_workout(row) -> dict:
    dist = None
    if row['distance_value'] is not None:
        dist = {'value': row['distance_value'], 'unit': row['distance_unit']}
    elev = None
    if row['elevation_gain'] is not None or row['elevation_loss'] is not None:
        elev = {'gain': row['elevation_gain'] or 0, 'loss': row['elevation_loss'] or 0}
    gps = json.loads(row['gps_track']) if row['gps_track'] else None
    hr_samples = json.loads(row['hr_samples']) if row['hr_samples'] else []
    return {
        'id':                 row['id'],
        'source':             row['source'],
        'date':               row['date'],
        'startTime':          row['start_time'],
        'endTime':            row['end_time'],
        'durationMinutes':    row['duration_minutes'],
        'activityType':       row['activity_type'],
        'inferredModalityId': row['inferred_modality_id'],
        'heartRate': {
            'avg':     row['hr_avg'],
            'max':     row['hr_max'],
            'min':     row['hr_min'],
            'samples': hr_samples,
        },
        'calories': row['calories'],
        'distance': dist,
        'gpsTrack': gps,
        'elevation': elev,
        'rawData':  json.loads(row['raw_data'] or '{}'),
    }


# ── Session logs ──────────────────────────────────────────────────────────────

def upsert_session_log(log: dict) -> None:
    with _get_db() as conn:
        conn.execute('''
            INSERT OR REPLACE INTO session_logs
            (session_key, exercises, notes, fatigue_rating, completed_at)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            log['sessionKey'],
            json.dumps(log.get('exercises', {})),
            log.get('notes', ''),
            log.get('fatigueRating'),
            log.get('completedAt', ''),
        ))


def get_session_logs() -> dict:
    with _get_db() as conn:
        rows = conn.execute('SELECT * FROM session_logs').fetchall()
    result = {}
    for row in rows:
        result[row['session_key']] = {
            'sessionKey':    row['session_key'],
            'exercises':     json.loads(row['exercises'] or '{}'),
            'notes':         row['notes'] or '',
            'fatigueRating': row['fatigue_rating'],
            'completedAt':   row['completed_at'] or '',
        }
    return result


# ── Daily bio ─────────────────────────────────────────────────────────────────

def upsert_daily_bio(entry: dict) -> None:
    with _get_db() as conn:
        conn.execute('''
            INSERT OR REPLACE INTO daily_bio (date, resting_hr, hrv, notes)
            VALUES (?, ?, ?, ?)
        ''', (
            entry['date'],
            entry.get('restingHR'),
            entry.get('hrv'),
            entry.get('notes'),
        ))


def get_daily_bio() -> dict:
    with _get_db() as conn:
        rows = conn.execute('SELECT * FROM daily_bio').fetchall()
    result = {}
    for row in rows:
        entry: dict = {'date': row['date']}
        if row['resting_hr'] is not None:
            entry['restingHR'] = row['resting_hr']
        if row['hrv'] is not None:
            entry['hrv'] = row['hrv']
        if row['notes']:
            entry['notes'] = row['notes']
        result[row['date']] = entry
    return result


# ── Workout matches ───────────────────────────────────────────────────────────

def upsert_match(match: dict) -> None:
    with _get_db() as conn:
        conn.execute('''
            INSERT OR REPLACE INTO workout_matches
            (imported_workout_id, session_key, match_confidence, matched_at)
            VALUES (?, ?, ?, ?)
        ''', (
            match['importedWorkoutId'],
            match['sessionKey'],
            match['matchConfidence'],
            match['matchedAt'],
        ))


def get_matches() -> list[dict]:
    with _get_db() as conn:
        rows = conn.execute('SELECT * FROM workout_matches').fetchall()
    return [
        {
            'importedWorkoutId': row['imported_workout_id'],
            'sessionKey':        row['session_key'],
            'matchConfidence':   row['match_confidence'],
            'matchedAt':         row['matched_at'],
        }
        for row in rows
    ]


# ── Performance logs ──────────────────────────────────────────────────────────

def add_performance_entry(benchmark_id: str, value: float, logged_at: str) -> None:
    with _get_db() as conn:
        conn.execute(
            'INSERT INTO performance_logs (benchmark_id, value, logged_at) VALUES (?, ?, ?)',
            (benchmark_id, value, logged_at),
        )


def delete_performance_log(benchmark_id: str) -> None:
    with _get_db() as conn:
        conn.execute('DELETE FROM performance_logs WHERE benchmark_id = ?', (benchmark_id,))


def get_performance_logs() -> dict:
    """Return {benchmarkId: [{value, date}, ...]} sorted by logged_at."""
    with _get_db() as conn:
        rows = conn.execute(
            'SELECT benchmark_id, value, logged_at FROM performance_logs ORDER BY logged_at'
        ).fetchall()
    result: dict = {}
    for row in rows:
        bid = row['benchmark_id']
        if bid not in result:
            result[bid] = []
        result[bid].append({'value': row['value'], 'date': row['logged_at']})
    return result
