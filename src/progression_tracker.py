"""Progression tracking: compares actual exercise performance against program expectations."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone

from src.progression import calculate_load


# ---------------------------------------------------------------------------
# Philosophy-level rules
# ---------------------------------------------------------------------------

# Slot types whose primary metric comes from workout duration or distance
_ENDURANCE_SLOT_TYPES = frozenset({'time_domain', 'distance', 'for_time', 'skill_practice'})

# Maps progression_model → stall detection: (sessions_without_increase, metric_type, unit)
_STALL_RULES: dict[str, tuple[int, str, str]] = {
    'linear_load':       (2, 'weight',   'kg'),
    'rpe_autoregulation':(3, 'weight',   'kg'),   # RPE stays high with same load
    'volume_block':      (2, 'weight',   'kg'),
    'density':           (2, 'rounds',   'rounds'),
    'concurrent_training':(2,'weight',   'kg'),
}

_SLOT_METRIC: dict[str, tuple[str, str]] = {
    'sets_reps':      ('weight',   'kg'),
    'time_domain':    ('time',     'min'),
    'distance':       ('distance', 'km'),
    'amrap':          ('rounds',   'rounds'),
    'emom':           ('rounds',   'rounds'),
    'for_time':       ('time',     'min'),
    'skill_practice': ('time',     'min'),
    'static_hold':    ('time',     'sec'),
    'amrap_movement': ('reps',     'reps'),
}


# ---------------------------------------------------------------------------
# Session hash — used to detect staleness
# ---------------------------------------------------------------------------

def compute_session_hash(session_logs: dict) -> str:
    """Stable hash of session keys + completedAt + exercise count so cache
    invalidates when set data is added to an existing session."""
    parts = sorted(
        f"{k}:{v.get('completedAt','')}/{len(v.get('exercises') or {})}"
        for k, v in session_logs.items()
    )
    return hashlib.md5('\n'.join(parts).encode()).hexdigest()


# ---------------------------------------------------------------------------
# Exercise history extraction
# ---------------------------------------------------------------------------

def _primary_endurance_exercise(session: dict) -> tuple[str, dict, dict] | None:
    """Return (ex_id, exercise, slot) for the dominant endurance exercise in the session.

    Picks the exercise with the highest prescribed duration among time/distance slots.
    Returns None if the session has no endurance exercises.
    """
    candidates: list[tuple[float, str, dict, dict]] = []
    for ea in session.get('exercises', []):
        if ea.get('meta') or ea.get('injury_skip'):
            continue
        ex = ea.get('exercise') or {}
        ex_id = ex.get('id', '')
        if not ex_id:
            continue
        slot = ea.get('slot') or {}
        if slot.get('slot_type') not in _ENDURANCE_SLOT_TYPES:
            continue
        loads = ea.get('loads') or {}
        prescribed_sec = (
            loads.get('duration_sec')
            or loads.get('time_to_task_sec')
            or loads.get('work_duration_sec')
            or 0
        )
        candidates.append((prescribed_sec, ex_id, ex, slot))
    if not candidates:
        return None
    candidates.sort(reverse=True)
    _, ex_id, ex, slot = candidates[0]
    return ex_id, ex, slot


def _workout_to_history_point(workout: dict, week_num: int, session_key: str) -> dict:
    """Build a history point from an imported workout (no set-level data)."""
    duration_min = workout.get('durationMinutes') or 0
    dist_raw = workout.get('distance')
    dist_km: float | None = None
    if dist_raw:
        val = dist_raw.get('value') or 0
        unit = dist_raw.get('unit', 'km')
        dist_km = round(val if unit == 'km' else val / 1000, 3) if val else None

    hr = workout.get('heartRate') or {}
    hr_avg = hr.get('avg')
    hr_max = hr.get('max')

    return {
        'date':             workout.get('date', ''),
        'week_number':      week_num,
        'session_key':      session_key,
        'best_weight_kg':   None,
        'total_volume':     None,
        'est_1rm':          None,
        'best_reps':        None,
        'rpe':              None,
        'duration_sec':     int(duration_min * 60) if duration_min else None,
        'distance_km':      dist_km,
        'rounds_completed': None,
        'hr_avg':           int(hr_avg) if hr_avg else None,
        'hr_max':           int(hr_max) if hr_max else None,
        'source':           'matched_workout',
    }


def compute_exercise_history(
    session_logs: dict,
    program: dict,
    matched_workouts: list[dict] | None = None,
) -> dict:
    """
    Returns {exerciseId: [HistoryPoint, ...]} sorted by week_number.

    HistoryPoint: {
        date, week_number, session_key,
        best_weight_kg, total_volume, est_1rm,
        best_reps, rpe, duration_sec, distance_km, rounds_completed,
        source?  # 'matched_workout' when synthesized from an import
    }

    When a session has no manual log but a matched workout exists, the primary
    endurance exercise in that session gets a history point derived from the
    workout's duration/distance (time_domain, distance, for_time, skill_practice
    slot types only).  Manual logs always take priority over matched workouts.
    """
    history: dict[str, list[dict]] = {}

    # Index matched workouts by session key (rejected matches excluded by caller)
    match_by_key: dict[str, dict] = {}
    for mw in (matched_workouts or []):
        key = mw.get('sessionKey', '')
        wo  = mw.get('workout')
        if key and wo:
            match_by_key[key] = wo

    for week in program.get('weeks', []):
        week_num = week.get('week_number', 1)
        for day_name, sessions in week.get('schedule', {}).items():
            for s_idx, session in enumerate(sessions):
                key_base = f"{week_num}-{day_name}"
                key_idx  = f"{key_base}-{s_idx}"
                log = session_logs.get(key_base) or session_logs.get(key_idx)

                if log:
                    # ── Manual log path ──────────────────────────────────────
                    completed_at  = log.get('completedAt') or ''
                    log_exercises = log.get('exercises') or {}

                    for ea in session.get('exercises', []):
                        if ea.get('meta') or ea.get('injury_skip'):
                            continue
                        ex    = ea.get('exercise') or {}
                        ex_id = ex.get('id', '')
                        if not ex_id:
                            continue

                        ex_log = log_exercises.get(ex_id)
                        if not ex_log:
                            continue

                        sets_data      = ex_log.get('sets') or []
                        completed_sets = [s for s in sets_data if s.get('completed')]

                        point: dict = {
                            'date':             completed_at,
                            'week_number':      week_num,
                            'session_key':      key_base,
                            'best_weight_kg':   None,
                            'total_volume':     None,
                            'est_1rm':          None,
                            'best_reps':        None,
                            'rpe':              ex_log.get('rpe'),
                            'duration_sec':     None,
                            'distance_km':      None,
                            'rounds_completed': None,
                            'hr_avg':           None,
                            'hr_max':           None,
                        }

                        weights   = [s['weightKg']   for s in completed_sets if s.get('weightKg')]
                        reps_list = [s['repsActual']  for s in completed_sets if s.get('repsActual')]

                        if weights:
                            point['best_weight_kg'] = max(weights)
                        if reps_list:
                            point['best_reps'] = max(reps_list)
                        if weights and reps_list:
                            best_idx = weights.index(max(weights))
                            w = weights[best_idx]
                            r = reps_list[min(best_idx, len(reps_list) - 1)]
                            point['est_1rm'] = round(w * (1 + 0.0333 * r), 1)
                            point['total_volume'] = round(
                                sum(w2 * r2 for w2, r2 in zip(weights, reps_list)), 1
                            )

                        if ex_log.get('durationSec'):
                            point['duration_sec'] = ex_log['durationSec']
                        if ex_log.get('distanceKm'):
                            point['distance_km'] = ex_log['distanceKm']
                        if ex_log.get('rounds'):
                            point['rounds_completed'] = ex_log['rounds']

                        history.setdefault(ex_id, []).append(point)

                else:
                    # ── Matched workout fallback ──────────────────────────────
                    workout = match_by_key.get(key_base) or match_by_key.get(key_idx)
                    if not workout:
                        continue
                    result = _primary_endurance_exercise(session)
                    if not result:
                        continue
                    ex_id, _ex, _slot = result
                    point = _workout_to_history_point(workout, week_num, key_base)
                    history.setdefault(ex_id, []).append(point)

    for ex_id in history:
        history[ex_id].sort(key=lambda p: (p['week_number'], p['date']))

    return history


# ---------------------------------------------------------------------------
# Expected trajectory
# ---------------------------------------------------------------------------

def compute_expected_trajectory(
    exercise: dict,
    slot: dict,
    progression_model: str,
    philosophy_weights: dict,
    weeks: list[dict],
    level: str,
) -> list[dict]:
    """
    Returns [{week_number, expected_value, unit, metric_type}] for all program weeks.
    For blended packages, weights the expected values by philosophy_weights.
    """
    slot_type = slot.get('slot_type', 'sets_reps')
    metric_type, unit = _SLOT_METRIC.get(slot_type, ('weight', 'kg'))

    trajectory = []
    for week in weeks:
        week_num = week.get('week_number', 1)
        phase    = week.get('phase', 'base')
        is_deload = week.get('is_deload', False)

        load = calculate_load(
            exercise=exercise,
            slot=slot,
            progression_model=progression_model,
            week_number=week_num,
            phase=phase,
            training_level=level,
            is_deload=is_deload,
        )

        expected: float | None = None
        if slot_type == 'sets_reps':
            expected = load.get('weight_kg') or load.get('suggested_weight_kg')
            metric_type, unit = 'weight', 'kg'
        elif slot_type == 'time_domain':
            expected = load.get('duration_minutes')
            metric_type, unit = 'time', 'min'
        elif slot_type == 'distance':
            expected = load.get('distance_km')
            metric_type, unit = 'distance', 'km'
        elif slot_type in ('amrap', 'emom', 'for_time'):
            expected = load.get('target_rounds')
            metric_type, unit = 'rounds', 'rounds'

        trajectory.append({
            'week_number':   week_num,
            'expected_value': expected,
            'unit':          unit,
            'metric_type':   metric_type,
        })

    return trajectory


# ---------------------------------------------------------------------------
# Exercise finding
# ---------------------------------------------------------------------------

def _exercise_finding(
    exercise_id: str,
    name: str,
    history: list[dict],
    expected_trajectory: list[dict],
    progression_model: str,
) -> dict:
    """Compares actual history against expected trajectory for one exercise."""
    if not expected_trajectory:
        metric_type, unit = 'weight', 'kg'
    else:
        metric_type = expected_trajectory[-1]['metric_type']
        unit        = expected_trajectory[-1]['unit']

    # Pull actual metric values
    def actual_val(pt: dict) -> float | None:
        if metric_type == 'weight':
            return pt.get('best_weight_kg')
        if metric_type == 'time':
            d = pt.get('duration_sec')
            return round(d / 60, 1) if d else None
        if metric_type == 'distance':
            return pt.get('distance_km')
        if metric_type == 'rounds':
            return pt.get('rounds_completed')
        if metric_type == 'reps':
            return pt.get('best_reps')
        return pt.get('best_weight_kg')

    actual_points = [(p['week_number'], actual_val(p)) for p in history]
    actual_points = [(wn, v) for wn, v in actual_points if v is not None]

    if len(actual_points) < 2:
        return {
            'exercise_id':    exercise_id,
            'name':           name,
            'metric_type':    metric_type,
            'expected_value': None,
            'actual_value':   None,
            'unit':           unit,
            'status':         'insufficient_data',
            'trend':          'stable',
            'change_summary': 'Not enough data — log at least 2 sessions.',
        }

    latest_week, latest_val = actual_points[-1]
    first_week,  first_val  = actual_points[0]

    # Expected at latest logged week
    exp_entry = next(
        (e for e in reversed(expected_trajectory) if e['week_number'] <= latest_week),
        expected_trajectory[-1] if expected_trajectory else None,
    )
    expected_val = exp_entry['expected_value'] if exp_entry else None

    # Trend direction
    values = [v for _, v in actual_points]
    trend = _trend_direction(values)

    # Status
    status = _status(
        actual_points, expected_val, progression_model, metric_type
    )

    # Change summary
    delta = latest_val - first_val
    weeks_span = latest_week - first_week or 1
    if metric_type in ('weight', 'distance', 'time'):
        sign = '+' if delta >= 0 else ''
        change_summary = f'{sign}{delta:.1f}{unit} over {weeks_span} wk'
    elif metric_type == 'rounds':
        sign = '+' if delta >= 0 else ''
        change_summary = f'{sign}{delta:.1f} rounds over {weeks_span} wk'
    else:
        change_summary = f'{latest_val:.0f} {unit}'

    return {
        'exercise_id':    exercise_id,
        'name':           name,
        'metric_type':    metric_type,
        'expected_value': expected_val,
        'actual_value':   latest_val,
        'unit':           unit,
        'status':         status,
        'trend':          trend,
        'change_summary': change_summary,
    }


def _trend_direction(values: list[float]) -> str:
    if len(values) < 3:
        # For 2 points just compare directly
        if len(values) == 2:
            delta = (values[-1] - values[0]) / (abs(values[0]) or 1)
            if delta > 0.03:
                return 'improving'
            if delta < -0.03:
                return 'declining'
        return 'stable'
    third = max(1, len(values) // 3)
    first_avg = sum(values[:third]) / third
    last_avg  = sum(values[-third:]) / third
    delta = (last_avg - first_avg) / (abs(first_avg) or 1)
    if delta > 0.05:
        return 'improving'
    if delta < -0.05:
        return 'declining'
    return 'stable'


def _status(
    actual_points: list[tuple[int, float]],
    expected_val: float | None,
    progression_model: str,
    metric_type: str,
) -> str:
    if not actual_points:
        return 'insufficient_data'

    latest_val = actual_points[-1][1]

    # Stall: no meaningful change across last N data points
    stall_sessions, _, _ = _STALL_RULES.get(progression_model, (2, 'weight', 'kg'))
    if len(actual_points) >= stall_sessions + 1:
        window = [v for _, v in actual_points[-(stall_sessions + 1):]]
        max_delta = max(window) - min(window)
        # stall if less than 1% change across window
        threshold = abs(window[0]) * 0.01 if window[0] else 0.5
        if max_delta <= threshold:
            return 'stalled'

    if expected_val is None:
        return 'on_track'

    ratio = latest_val / expected_val if expected_val else 1.0
    if ratio >= 1.10:
        return 'ahead'
    if ratio >= 0.90:
        return 'on_track'
    return 'behind'


# ---------------------------------------------------------------------------
# Adjustments
# ---------------------------------------------------------------------------

def suggest_adjustments(review: dict, program: dict) -> list[dict]:
    adjustments = []

    avg_readiness = review.get('avg_readiness')
    compliance    = review.get('compliance_pct', 100)
    findings      = review.get('exercise_findings', [])

    if avg_readiness is not None and avg_readiness < 50:
        adjustments.append({
            'type':      'hold_load',
            'target':    'all',
            'direction': 'hold',
            'reason':    f'Average readiness {avg_readiness}/100 — body is not recovered.',
            'magnitude': None,
        })

    elif avg_readiness is not None and avg_readiness < 55 and compliance > 70:
        adjustments.append({
            'type':      'reduce_volume_10pct',
            'target':    'all',
            'direction': 'reduce',
            'reason':    f'Low readiness ({avg_readiness}/100) with good compliance — reduce total volume 10%.',
            'magnitude': '10%',
        })

    if compliance < 50:
        adjustments.append({
            'type':      'rebuild_habit',
            'target':    'schedule',
            'direction': 'maintain',
            'reason':    f'Only {compliance}% of sessions completed — focus on consistency before intensity.',
            'magnitude': None,
        })

    stalled_strength = [f for f in findings if f['status'] == 'stalled' and f['metric_type'] == 'weight']
    if stalled_strength:
        names = ', '.join(f['name'] for f in stalled_strength[:2])
        adjustments.append({
            'type':      'early_deload',
            'target':    names,
            'direction': 'reduce',
            'reason':    f'{names} show no load increase — consider a deload week.',
            'magnitude': '10%',
        })

    ahead_strength = [f for f in findings if f['status'] == 'ahead' and f['metric_type'] == 'weight']
    if ahead_strength:
        names = ', '.join(f['name'] for f in ahead_strength[:2])
        adjustments.append({
            'type':      'increase_increment',
            'target':    names,
            'direction': 'increase',
            'reason':    f'{names} consistently exceeding targets — increase weekly increment.',
            'magnitude': '5%',
        })

    return adjustments


# ---------------------------------------------------------------------------
# Period helpers
# ---------------------------------------------------------------------------

def _iso_week_key(dt: datetime) -> str:
    iso = dt.isocalendar()
    return f'{iso[0]}-W{iso[1]:02d}'


def _current_period_key(period: str) -> str:
    now = datetime.now(timezone.utc)
    if period == 'biweekly':
        iso = now.isocalendar()
        # Pair odd + even weeks: W01-W02, W03-W04, …
        pair_start = iso[1] - ((iso[1] - 1) % 2)
        return f'{iso[0]}-W{pair_start:02d}-W{pair_start+1:02d}'
    return _iso_week_key(now)


def _period_week_numbers(period_key: str, weeks: list[dict]) -> list[int]:
    """Return week_numbers from the program that fall within the requested period."""
    # Heuristic: treat all weeks as candidates (we don't have real start dates),
    # use all weeks up to the most recently completed one with session data.
    return [w['week_number'] for w in weeks]


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def compute_progression_review(
    user_id: str,
    program: dict,
    bio_logs: list[dict],
    session_logs: dict,
    period: str = 'weekly',
) -> dict:
    """
    Builds a full ProgressionReview dict.
    Returns a minimal result with insufficient_data flag when data is sparse.
    """
    period_key  = _current_period_key(period)
    weeks       = program.get('weeks', [])
    constraints = program.get('constraints', {})
    level       = constraints.get('training_level', 'intermediate')

    philosophy_weights: dict = program.get('philosophy_weights') or {}
    progression_model  = _infer_progression_model(program)

    # Compliance
    total_scheduled = sum(
        len(sessions)
        for w in weeks
        for sessions in w.get('schedule', {}).values()
    )
    total_completed = sum(
        1
        for w in weeks
        for day_name, day_sessions in w.get('schedule', {}).items()
        for s_idx, _ in enumerate(day_sessions)
        if (f"{w['week_number']}-{day_name}" in session_logs
            or f"{w['week_number']}-{day_name}-{s_idx}" in session_logs)
    )
    compliance_pct = round(total_completed / total_scheduled * 100) if total_scheduled else 0

    # Readiness trend
    avg_readiness = None
    readiness_trend = 'stable'
    hrv_vals = [b.get('hrv') for b in bio_logs if b.get('hrv') is not None]
    if hrv_vals:
        avg_readiness = None  # HRV not a 0–100 score; skip direct mapping
    rhr_vals = [b.get('resting_hr') for b in bio_logs if b.get('resting_hr') is not None]
    if len(rhr_vals) >= 3:
        readiness_trend = _trend_direction(rhr_vals)
        # Invert: falling RHR = improving readiness
        if readiness_trend == 'improving':
            readiness_trend = 'declining'
        elif readiness_trend == 'declining':
            readiness_trend = 'improving'

    # Exercise history
    ex_history = compute_exercise_history(session_logs, program)

    # Need ≥ 2 exercises with ≥ 2 data points
    usable = {eid: pts for eid, pts in ex_history.items() if len(pts) >= 2}
    if len(usable) < 1:
        return {
            'period_key':        period_key,
            'period_type':       period,
            'generated_at':      datetime.utcnow().isoformat(),
            'overall_score':     None,
            'readiness_trend':   readiness_trend,
            'avg_readiness':     avg_readiness,
            'compliance_pct':    compliance_pct,
            'exercise_findings': [],
            'flags':             ['insufficient_data'],
            'recommendations':   ['Log at least 2 sessions with set data to see progression analysis.'],
            'adjustments':       [],
        }

    # Build per-exercise findings
    exercise_findings = []
    for w in weeks:
        for day_sessions in w.get('schedule', {}).values():
            for session in day_sessions:
                modality = session.get('modality', '')
                prog_model = progression_model
                for ea in session.get('exercises', []):
                    if ea.get('meta') or ea.get('injury_skip'):
                        continue
                    ex = ea.get('exercise') or {}
                    ex_id = ex.get('id', '')
                    if not ex_id or ex_id not in usable:
                        continue
                    slot = ea.get('slot') or {'slot_type': ea.get('slot_type', 'sets_reps')}
                    trajectory = compute_expected_trajectory(
                        exercise=ex,
                        slot=slot,
                        progression_model=prog_model,
                        philosophy_weights=philosophy_weights,
                        weeks=weeks,
                        level=level,
                    )
                    finding = _exercise_finding(
                        ex_id,
                        ex.get('name', ex_id),
                        usable[ex_id],
                        trajectory,
                        prog_model,
                    )
                    # De-duplicate by exercise_id — keep first occurrence
                    if not any(f['exercise_id'] == ex_id for f in exercise_findings):
                        exercise_findings.append(finding)

    # Overall score: weighted compliance + on-track ratio
    if exercise_findings:
        statuses = [f['status'] for f in exercise_findings]
        score_map = {'ahead': 100, 'on_track': 80, 'behind': 40, 'stalled': 20, 'insufficient_data': 50}
        finding_score = round(sum(score_map.get(s, 50) for s in statuses) / len(statuses))
        overall_score = round(compliance_pct * 0.4 + finding_score * 0.6)
    else:
        overall_score = compliance_pct

    # Flags and recommendations
    flags: list[str] = []
    recommendations: list[str] = []

    stalled = [f for f in exercise_findings if f['status'] == 'stalled']
    behind  = [f for f in exercise_findings if f['status'] == 'behind']
    ahead   = [f for f in exercise_findings if f['status'] == 'ahead']

    if stalled:
        names = ', '.join(f['name'] for f in stalled[:3])
        flags.append(f'stalled: {names}')
        recommendations.append(f'No progress on {names} — deload or vary stimulus.')
    if behind:
        names = ', '.join(f['name'] for f in behind[:2])
        flags.append(f'behind_target: {names}')
        recommendations.append(f'{names} behind expected targets — review recovery and sleep.')
    if ahead:
        names = ', '.join(f['name'] for f in ahead[:2])
        recommendations.append(f'{names} exceeding targets — ready to increase increment.')
    if compliance_pct < 60:
        flags.append('low_compliance')
        recommendations.append('Session completion rate is low — prioritise showing up over intensity.')

    review = {
        'period_key':        period_key,
        'period_type':       period,
        'generated_at':      datetime.utcnow().isoformat(),
        'overall_score':     overall_score,
        'readiness_trend':   readiness_trend,
        'avg_readiness':     avg_readiness,
        'compliance_pct':    compliance_pct,
        'exercise_findings': exercise_findings,
        'flags':             flags,
        'recommendations':   recommendations,
        'adjustments':       [],
    }
    review['adjustments'] = suggest_adjustments(review, program)
    return review


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _infer_progression_model(program: dict) -> str:
    """Best-effort: extract progression_model from the first framework reference in the program."""
    goal = program.get('goal') or {}
    return goal.get('progression_model') or 'linear_load'


def _session_completed(session_logs: dict, week_num: int, day_names: list[str],
                        day_sessions: list, session_idx: int) -> bool:
    for day in day_names:
        key = f'{week_num}-{day}'
        if key in session_logs:
            return True
        indexed = f'{key}-{session_idx}'
        if indexed in session_logs:
            return True
    return False
