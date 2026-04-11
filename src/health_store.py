"""Supabase-backed storage for all user health and performance data."""
from __future__ import annotations

import json


def init_db() -> None:
    """No-op: tables are managed in Supabase. Kept for call-site compatibility."""


# ── Workouts ──────────────────────────────────────────────────────────────────

def upsert_workouts(user_id: str, workouts: list[dict]) -> None:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                for w in workouts:
                    hr         = w.get('heartRate') or {}
                    dist       = w.get('distance') or {}
                    elev       = w.get('elevation') or {}
                    gps        = w.get('gpsTrack')
                    hr_samples = hr.get('samples') or []
                    cur.execute('''
                        INSERT INTO workouts
                        (id, user_id, source, date, start_time, end_time, duration_minutes,
                         activity_type, inferred_modality_id,
                         hr_avg, hr_max, hr_min, calories,
                         distance_value, distance_unit, raw_data,
                         gps_track, elevation_gain, elevation_loss, hr_samples)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                                %s::jsonb, %s::jsonb, %s, %s, %s::jsonb)
                        ON CONFLICT (id, user_id) DO UPDATE SET
                            source               = EXCLUDED.source,
                            date                 = EXCLUDED.date,
                            start_time           = EXCLUDED.start_time,
                            end_time             = EXCLUDED.end_time,
                            duration_minutes     = EXCLUDED.duration_minutes,
                            activity_type        = EXCLUDED.activity_type,
                            inferred_modality_id = EXCLUDED.inferred_modality_id,
                            hr_avg               = EXCLUDED.hr_avg,
                            hr_max               = EXCLUDED.hr_max,
                            hr_min               = EXCLUDED.hr_min,
                            calories             = EXCLUDED.calories,
                            distance_value       = EXCLUDED.distance_value,
                            distance_unit        = EXCLUDED.distance_unit,
                            raw_data             = EXCLUDED.raw_data,
                            gps_track            = EXCLUDED.gps_track,
                            elevation_gain       = EXCLUDED.elevation_gain,
                            elevation_loss       = EXCLUDED.elevation_loss,
                            hr_samples           = EXCLUDED.hr_samples
                    ''', (
                        w['id'], user_id, w['source'], w['date'], w['startTime'], w['endTime'],
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
            conn.commit()
    except RuntimeError:
        pass


def delete_workout(user_id: str, workout_id: str) -> None:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'DELETE FROM workouts WHERE id = %s AND user_id = %s',
                    (workout_id, user_id),
                )
                cur.execute(
                    'DELETE FROM workout_matches WHERE imported_workout_id = %s AND user_id = %s',
                    (workout_id, user_id),
                )
            conn.commit()
    except RuntimeError:
        pass


def get_workout(user_id: str, workout_id: str) -> dict | None:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'SELECT * FROM workouts WHERE id = %s AND user_id = %s',
                    (workout_id, user_id),
                )
                row = cur.fetchone()
        return _row_to_workout(row) if row else None
    except RuntimeError:
        return None


def get_workouts(user_id: str) -> list[dict]:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'SELECT * FROM workouts WHERE user_id = %s ORDER BY date DESC',
                    (user_id,),
                )
                rows = cur.fetchall()
        return [_row_to_workout(row) for row in rows]
    except RuntimeError:
        return []


def _row_to_workout(row) -> dict:
    dist = None
    if row['distance_value'] is not None:
        dist = {'value': row['distance_value'], 'unit': row['distance_unit']}
    elev = None
    if row['elevation_gain'] is not None or row['elevation_loss'] is not None:
        elev = {'gain': row['elevation_gain'] or 0, 'loss': row['elevation_loss'] or 0}
    gps = row['gps_track'] if isinstance(row['gps_track'], list) else (
        json.loads(row['gps_track']) if row['gps_track'] else None
    )
    hr_raw = row['hr_samples']
    hr_samples = hr_raw if isinstance(hr_raw, list) else (json.loads(hr_raw) if hr_raw else [])
    raw_raw = row['raw_data']
    raw_data = raw_raw if isinstance(raw_raw, dict) else (json.loads(raw_raw or '{}'))
    return {
        'id':                 row['id'],
        'source':             row['source'],
        'date':               str(row['date']),
        'startTime':          str(row['start_time']),
        'endTime':            str(row['end_time']),
        'durationMinutes':    row['duration_minutes'],
        'activityType':       row['activity_type'],
        'inferredModalityId': row['inferred_modality_id'],
        'heartRate': {
            'avg':     row['hr_avg'],
            'max':     row['hr_max'],
            'min':     row['hr_min'],
            'samples': hr_samples,
        },
        'calories':  row['calories'],
        'distance':  dist,
        'gpsTrack':  gps,
        'elevation': elev,
        'rawData':   raw_data,
    }


# ── Session logs ──────────────────────────────────────────────────────────────

def upsert_session_log(user_id: str, log: dict) -> None:
    from src.db import get_conn
    timeline = log.get('exerciseTimeline')
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                exercises_raw = log.get('exercises', {})
                if isinstance(exercises_raw, str):
                    try:
                        exercises_raw = json.loads(exercises_raw)
                    except (json.JSONDecodeError, TypeError):
                        exercises_raw = {}
                cur.execute('''
                    INSERT INTO session_logs
                    (session_key, user_id, exercises, notes, fatigue_rating, completed_at, source,
                     avg_hr, peak_hr, exercise_timeline)
                    VALUES (%s, %s, %s::jsonb, %s, %s, %s, %s, %s, %s, %s::jsonb)
                    ON CONFLICT (session_key, user_id) DO UPDATE SET
                        exercises         = CASE
                            WHEN EXCLUDED.completed_at >= session_logs.completed_at
                            THEN EXCLUDED.exercises
                            ELSE session_logs.exercises
                        END,
                        notes             = CASE
                            WHEN EXCLUDED.completed_at >= session_logs.completed_at
                            THEN EXCLUDED.notes
                            ELSE session_logs.notes
                        END,
                        fatigue_rating    = COALESCE(EXCLUDED.fatigue_rating, session_logs.fatigue_rating),
                        completed_at      = GREATEST(EXCLUDED.completed_at, session_logs.completed_at),
                        source            = EXCLUDED.source,
                        avg_hr            = COALESCE(EXCLUDED.avg_hr, session_logs.avg_hr),
                        peak_hr           = COALESCE(EXCLUDED.peak_hr, session_logs.peak_hr),
                        exercise_timeline = COALESCE(EXCLUDED.exercise_timeline, session_logs.exercise_timeline)
                ''', (
                    log['sessionKey'],
                    user_id,
                    json.dumps(exercises_raw),
                    log.get('notes', ''),
                    log.get('fatigueRating'),
                    log.get('completedAt') or None,
                    log.get('source', 'web'),
                    log.get('avgHR'),
                    log.get('peakHR'),
                    json.dumps(timeline) if timeline else None,
                ))
            conn.commit()
    except RuntimeError:
        pass


def get_recent_session_logs(user_id: str) -> list[dict]:
    """Return all session logs as a list with snake_case keys (matches iOS SessionLogEntry model)."""
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    '''SELECT sl.session_key, sl.completed_at, sl.source, sl.notes,
                              sl.fatigue_rating, sl.avg_hr, sl.peak_hr,
                              wm.imported_workout_id AS matched_workout_id
                       FROM session_logs sl
                       LEFT JOIN workout_matches wm
                           ON wm.session_key = sl.session_key AND wm.user_id = sl.user_id
                       WHERE sl.user_id = %s
                       ORDER BY sl.completed_at DESC NULLS LAST''',
                    (user_id,),
                )
                rows = cur.fetchall()
        return [
            {
                'session_key':        row['session_key'],
                'completed_at':       str(row['completed_at']) if row['completed_at'] else None,
                'source':             row.get('source') or 'web',
                'notes':              row.get('notes') or '',
                'fatigue_rating':     row.get('fatigue_rating'),
                'avg_hr':             row.get('avg_hr'),
                'peak_hr':            row.get('peak_hr'),
                'matched_workout_id': row.get('matched_workout_id'),
            }
            for row in rows
        ]
    except RuntimeError:
        return []


def get_session_logs(user_id: str) -> dict:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT * FROM session_logs WHERE user_id = %s', (user_id,))
                rows = cur.fetchall()
        result = {}
        for row in rows:
            exercises = row['exercises'] if isinstance(row['exercises'], dict) else (
                json.loads(row['exercises'] or '{}')
            )
            tl_raw = row.get('exercise_timeline')
            timeline = tl_raw if isinstance(tl_raw, list) else (
                json.loads(tl_raw) if tl_raw else None
            )
            entry = {
                'sessionKey':    row['session_key'],
                'exercises':     exercises,
                'notes':         row['notes'] or '',
                'fatigueRating': row['fatigue_rating'],
                'completedAt':   str(row['completed_at']) if row['completed_at'] else '',
                'source':        row.get('source') or 'web',
            }
            if row.get('avg_hr') is not None:
                entry['avgHR'] = row['avg_hr']
            if row.get('peak_hr') is not None:
                entry['peakHR'] = row['peak_hr']
            if timeline is not None:
                entry['exerciseTimeline'] = timeline
            result[row['session_key']] = entry
        return result
    except RuntimeError:
        return {}


# ── Daily bio ─────────────────────────────────────────────────────────────────

def upsert_daily_bio(user_id: str, entry: dict) -> None:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('''
                    INSERT INTO daily_bio (
                        date, user_id, resting_hr, hrv, notes,
                        sleep_duration_min, deep_sleep_min, rem_sleep_min,
                        light_sleep_min, awake_min, sleep_start, sleep_end,
                        spo2_avg, respiratory_rate_avg, source
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (date, user_id) DO UPDATE SET
                        resting_hr           = EXCLUDED.resting_hr,
                        hrv                  = EXCLUDED.hrv,
                        notes                = COALESCE(EXCLUDED.notes, daily_bio.notes),
                        sleep_duration_min   = EXCLUDED.sleep_duration_min,
                        deep_sleep_min       = EXCLUDED.deep_sleep_min,
                        rem_sleep_min        = EXCLUDED.rem_sleep_min,
                        light_sleep_min      = EXCLUDED.light_sleep_min,
                        awake_min            = EXCLUDED.awake_min,
                        sleep_start          = EXCLUDED.sleep_start,
                        sleep_end            = EXCLUDED.sleep_end,
                        spo2_avg             = EXCLUDED.spo2_avg,
                        respiratory_rate_avg = EXCLUDED.respiratory_rate_avg,
                        source               = EXCLUDED.source
                ''', (
                    entry['date'],
                    user_id,
                    entry.get('restingHR'),
                    entry.get('hrv'),
                    entry.get('notes'),
                    entry.get('sleepDurationMin'),
                    entry.get('deepSleepMin'),
                    entry.get('remSleepMin'),
                    entry.get('lightSleepMin'),
                    entry.get('awakeMins'),
                    entry.get('sleepStart') or None,
                    entry.get('sleepEnd') or None,
                    entry.get('spo2Avg'),
                    entry.get('respiratoryRateAvg'),
                    entry.get('source', 'manual'),
                ))
            conn.commit()
    except RuntimeError:
        pass


def get_synced_dates(user_id: str) -> list[str]:
    """Return dates that already have apple_watch-sourced bio data."""
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT date FROM daily_bio WHERE user_id = %s AND source = 'apple_watch'",
                    (user_id,),
                )
                rows = cur.fetchall()
        return [str(row['date']) for row in rows]
    except RuntimeError:
        return []


def get_recent_bio_logs(user_id: str, days: int = 90) -> list[dict]:
    """Return recent bio logs as a list with snake_case keys (matches iOS DailyBioLog model)."""
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'SELECT * FROM daily_bio WHERE user_id = %s '
                    'AND date >= CURRENT_DATE - %s::interval '
                    'ORDER BY date DESC',
                    (user_id, f'{days} days'),
                )
                rows = cur.fetchall()
        result = []
        for row in rows:
            entry: dict = {'date': str(row['date'])}
            for col in ('resting_hr', 'hrv', 'notes', 'sleep_duration_min', 'deep_sleep_min',
                        'rem_sleep_min', 'light_sleep_min', 'spo2_avg',
                        'respiratory_rate_avg', 'source'):
                if row.get(col) is not None:
                    entry[col] = row[col]
            # DB column is awake_min; iOS model CodingKey is awake_mins
            if row.get('awake_min') is not None:
                entry['awake_mins'] = row['awake_min']
            for col in ('sleep_start', 'sleep_end'):
                if row.get(col) is not None:
                    entry[col] = str(row[col])
            result.append(entry)
        return result
    except Exception:
        return []


def get_daily_bio(user_id: str) -> dict:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT * FROM daily_bio WHERE user_id = %s', (user_id,))
                rows = cur.fetchall()
        result = {}
        for row in rows:
            entry: dict = {'date': str(row['date'])}
            if row['resting_hr'] is not None:
                entry['restingHR'] = row['resting_hr']
            if row['hrv'] is not None:
                entry['hrv'] = row['hrv']
            if row['notes']:
                entry['notes'] = row['notes']
            if row.get('sleep_duration_min') is not None:
                entry['sleepDurationMin'] = row['sleep_duration_min']
            if row.get('deep_sleep_min') is not None:
                entry['deepSleepMin'] = row['deep_sleep_min']
            if row.get('rem_sleep_min') is not None:
                entry['remSleepMin'] = row['rem_sleep_min']
            if row.get('light_sleep_min') is not None:
                entry['lightSleepMin'] = row['light_sleep_min']
            if row.get('awake_min') is not None:
                entry['awakeMins'] = row['awake_min']
            if row.get('sleep_start') is not None:
                entry['sleepStart'] = str(row['sleep_start'])
            if row.get('sleep_end') is not None:
                entry['sleepEnd'] = str(row['sleep_end'])
            if row.get('spo2_avg') is not None:
                entry['spo2Avg'] = row['spo2_avg']
            if row.get('respiratory_rate_avg') is not None:
                entry['respiratoryRateAvg'] = row['respiratory_rate_avg']
            entry['source'] = row.get('source') or 'manual'
            result[str(row['date'])] = entry
        return result
    except RuntimeError:
        return {}


# ── Workout matches ───────────────────────────────────────────────────────────

def upsert_match(user_id: str, match: dict) -> None:
    from src.db import get_conn
    from datetime import datetime as _dt
    workout_id = match['importedWorkoutId']
    session_key = match['sessionKey']
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                # Ensure the workout row exists so FK constraints are satisfied.
                # If the parse-time upsert failed silently, this creates a minimal stub.
                cur.execute('''
                    INSERT INTO workouts (id, user_id, source, date, activity_type)
                    VALUES (%s, %s, 'fit_file', CURRENT_DATE, 'unknown')
                    ON CONFLICT (id, user_id) DO NOTHING
                ''', (workout_id, user_id))
                cur.execute('''
                    INSERT INTO workout_matches
                    (imported_workout_id, user_id, session_key, match_confidence, matched_at)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (imported_workout_id, user_id) DO UPDATE SET
                        session_key      = EXCLUDED.session_key,
                        match_confidence = EXCLUDED.match_confidence,
                        matched_at       = EXCLUDED.matched_at
                ''', (
                    workout_id,
                    user_id,
                    session_key,
                    match.get('matchConfidence', 1.0),
                    match.get('matchedAt') or _dt.utcnow().isoformat(),
                ))
            conn.commit()
    except Exception:
        pass


def get_matches(user_id: str) -> list[dict]:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT * FROM workout_matches WHERE user_id = %s', (user_id,))
                rows = cur.fetchall()
        return [
            {
                'importedWorkoutId': row['imported_workout_id'],
                'sessionKey':        row['session_key'],
                'matchConfidence':   row['match_confidence'],
                'matchedAt':         str(row['matched_at']),
            }
            for row in rows
        ]
    except RuntimeError:
        return []


# ── Performance logs ──────────────────────────────────────────────────────────

def add_performance_entry(user_id: str, benchmark_id: str, value: float, logged_at: str) -> None:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'INSERT INTO performance_logs (user_id, benchmark_id, value, logged_at) '
                    'VALUES (%s, %s, %s, %s)',
                    (user_id, benchmark_id, value, logged_at),
                )
            conn.commit()
    except RuntimeError:
        pass


def delete_performance_log(user_id: str, benchmark_id: str) -> None:
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'DELETE FROM performance_logs WHERE benchmark_id = %s AND user_id = %s',
                    (benchmark_id, user_id),
                )
            conn.commit()
    except RuntimeError:
        pass


def get_performance_logs(user_id: str) -> dict:
    """Return {benchmarkId: [{value, date}, ...]} sorted by logged_at."""
    from src.db import get_conn
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    'SELECT benchmark_id, value, logged_at FROM performance_logs '
                    'WHERE user_id = %s ORDER BY logged_at',
                    (user_id,),
                )
                rows = cur.fetchall()
        result: dict = {}
        for row in rows:
            bid = row['benchmark_id']
            if bid not in result:
                result[bid] = []
            result[bid].append({'value': row['value'], 'date': str(row['logged_at'])})
        return result
    except RuntimeError:
        return {}
