"""Progression tracking: compares actual exercise performance against program expectations."""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone

from src import phases
from src.workout_matcher import modality_family
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


def _to_km(distance_field: dict | None) -> float | None:
    """Convert a {value, unit} distance dict to kilometres."""
    if not distance_field:
        return None
    val = distance_field.get('value') or 0
    if not val:
        return None
    unit = distance_field.get('unit', 'km')
    return round(val if unit == 'km' else val / 1000, 3)


# Ordered metric keys per dominant philosophy priority
_PHILOSOPHY_METRICS: dict[str, list[str]] = {
    'aerobic_base':    ['distance', 'duration', 'hr', 'elevation'],
    'durability':      ['distance', 'duration', 'elevation', 'hr'],
    'rehab':           ['duration', 'hr', 'distance'],
    'mobility':        ['duration', 'hr', 'distance'],
    'max_strength':    ['duration', 'hr'],
    'power':           ['duration', 'hr'],
    'mixed_modal':     ['duration', 'hr', 'distance'],
    'kettlebell':      ['duration', 'hr'],
    'skill':           ['duration', 'hr'],
}


def _relevant_metrics(priorities: dict) -> list[str]:
    """Return ordered metric keys for the dominant philosophy priority."""
    if not priorities:
        return ['duration', 'hr']
    dominant = max(priorities, key=lambda k: priorities[k])
    return _PHILOSOPHY_METRICS.get(dominant, ['duration', 'hr', 'distance'])


def _session_records(program: dict, history_sessions: list[dict] | None = None,
                     active_version_id: str | None = None) -> list[dict]:
    """Every planned session worth considering, across the athlete's history.

    Previously both readers below walked `program['weeks']` — the ONE stored
    program — and dropped anything they could not resolve there, so every
    matched session and every logged set from a block the athlete had replaced
    silently vanished from progression. History records come first and carry a
    `session_uid`, which is unambiguous; the current program is then added only
    for sessions history does not already cover, so a program that has not been
    archived yet (or a local dev run with no database) still works exactly as
    before.
    """
    records: list[dict] = []
    covered: set[tuple] = set()
    active_prefix = (active_version_id + ':') if active_version_id else None

    for h in (history_sessions or []):
        legacy = h['legacy_key']
        records.append({
            'week_number':   h['week_number'],
            'day_name':      h['day_name'],
            'session_index': h['session_index'],
            'session':       h['session'],
            'date':          h.get('date') or '',
            'session_uid':   h['session_uid'],
            'version_id':    h['program_version_id'],
            'phase':         h.get('phase'),
            # Most specific first: a day-level key is shared by every program's
            # same weekday, so it must never win over an exact one.
            'keys':          [legacy, legacy.rsplit('-', 1)[0]],
        })
        if active_prefix and h['session_uid'].startswith(active_prefix):
            covered.add((h['week_number'], h['day_name'], h['session_index']))

    for week in program.get('weeks', []):
        week_num = week.get('week_number', 1)
        for day_name, sessions in (week.get('schedule') or {}).items():
            for s_idx, session in enumerate(sessions or []):
                if (week_num, day_name, s_idx) in covered:
                    continue
                base = f'{week_num}-{day_name}'
                records.append({
                    'week_number':   week_num,
                    'day_name':      day_name,
                    'session_index': s_idx,
                    'session':       session,
                    'date':          '',
                    'session_uid':   None,
                    'version_id':    None,
                    'phase':         week.get('phase'),
                    'keys':          [f'{base}-{s_idx}', base],
                })
    return records


def compute_matched_sessions(
    matches: list[dict],
    workout_map: dict,
    program: dict,
    history_sessions: list[dict] | None = None,
    active_version_id: str | None = None,
) -> list[dict]:
    """
    Return a session-level summary for every non-rejected matched workout.

    Each summary joins the imported workout to its program session context
    (archetype name, modality, prescribed duration) and computes compliance
    signals (duration delta, modality match quality).  Results are sorted
    by date descending so the most recent session appears first.
    """
    records = _session_records(program, history_sessions, active_version_id)

    # Two indexes. `by_uid` is exact — it names one session of one program
    # version. `by_key` is the legacy program-relative key, which means a
    # different session in every plan, so it is only consulted for a match that
    # has no uid (one stored before this existed, or one nothing could resolve).
    by_uid: dict[str, dict] = {}
    by_key: dict[str, dict] = {}
    for record in records:
        if record['session_uid']:
            by_uid[record['session_uid']] = record
        for key in record['keys']:
            by_key.setdefault(key, record)

    priorities     = (program.get('goal') or {}).get('priorities') or {}
    relevant_mets  = _relevant_metrics(priorities)

    summaries: list[dict] = []
    for match in matches:
        session_key = match.get('sessionKey', '')
        workout     = workout_map.get(match.get('importedWorkoutId', ''))
        if not workout:
            continue

        record = by_uid.get(match.get('sessionUid') or '') or by_key.get(session_key)
        if not record:
            continue
        week_num  = record['week_number']
        day_name  = record['day_name']
        session   = record['session']

        archetype       = session.get('archetype') or {}
        modality        = session.get('modality') or session.get('primary_modality') or ''
        prescribed_min  = (
            archetype.get('duration_estimate_minutes')
            or archetype.get('duration_minutes')
            or 60
        )
        archetype_name  = archetype.get('name') or archetype.get('id') or 'Session'

        actual_min   = workout.get('durationMinutes') or 0
        delta_pct: int | None = None
        if prescribed_min and actual_min:
            delta_pct = round(((actual_min - prescribed_min) / prescribed_min) * 100)

        # Modality match quality
        inferred = workout.get('inferredModalityId') or ''
        if inferred == modality:
            modality_match = 'exact'
        # The matcher's similarity families (data/matching_rules.json), the
        # grouping that linked this workout to the session — not the display
        # rollup. This file kept its own copy, keyed partly by ids that are
        # no modality.
        elif modality_family(inferred) != 'other' and modality_family(inferred) == modality_family(modality):
            modality_match = 'family'
        else:
            modality_match = 'other'

        hr = workout.get('heartRate') or {}
        elev = workout.get('elevation') or {}

        summaries.append({
            'sessionKey':        session_key,
            'weekNumber':        week_num,
            'dayName':           day_name,
            'date':              workout.get('date', ''),
            'importedWorkoutId': match.get('importedWorkoutId', ''),
            'archetype': {
                'name':              archetype_name,
                'modality':          modality,
                'prescribedMinutes': int(prescribed_min),
            },
            'workout': {
                'durationMinutes': actual_min,
                'distanceKm':      _to_km(workout.get('distance')),
                'hrAvg':           int(hr['avg']) if hr.get('avg') else None,
                'hrMax':           int(hr['max']) if hr.get('max') else None,
                'activityType':    workout.get('activityType', ''),
                'source':          workout.get('source', ''),
                'elevationGainM':  elev.get('gain'),
            },
            'matchConfidence':  match.get('matchConfidence', 'auto'),
            'durationDeltaPct': delta_pct,
            'modalityMatch':    modality_match,
            'relevantMetrics':  relevant_mets,
        })

    summaries.sort(key=lambda s: s['date'], reverse=True)
    return summaries


def _workout_to_history_point(workout: dict, week_num: int, session_key: str) -> dict:
    """Build a history point from an imported workout (no set-level data)."""
    duration_min = workout.get('durationMinutes') or 0
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
        'distance_km':      _to_km(workout.get('distance')),
        'rounds_completed': None,
        'hr_avg':           int(hr_avg) if hr_avg else None,
        'hr_max':           int(hr_max) if hr_max else None,
        'source':           'matched_workout',
    }


def exercises_scheduled_by(weeks: list, start_date: str | None, today: str) -> set:
    """Exercise ids in sessions whose calendar day has come (<= today).

    The Progress tab's middle count: "20 in this program · 12 so far · 3 with
    data". Before it, the tab offered Tracked (3) / All (20) — the 20 counting
    every week to come and the 3 counting earlier programs' history — which
    read as three of twenty measured with no way to tell what was owed yet.
    Dates are `workout_matcher.session_calendar_date`, keyed on the week's
    array index, as every other reader of the plan's calendar."""
    from src.workout_matcher import session_calendar_date
    if not start_date:
        return set()
    out: set = set()
    for wi, week in enumerate(weeks or []):
        for day, sessions in (week.get('schedule') or {}).items():
            d = session_calendar_date(start_date, wi, day)    # '' when it cannot say
            if not d or d > today:
                continue
            for session in sessions or []:
                for ea in session.get('exercises') or []:
                    if ea.get('meta') or ea.get('injury_skip'):
                        continue
                    ex_id = (ea.get('exercise') or {}).get('id')
                    if ex_id:
                        out.add(ex_id)
    return out


def compute_exercise_history(
    session_logs: dict,
    program: dict,
    matched_workouts: list[dict] | None = None,
    history_sessions: list[dict] | None = None,
    logs_by_uid: dict | None = None,
    active_version_id: str | None = None,
) -> dict:
    """
    Returns {exerciseId: [HistoryPoint, ...]} sorted by date.

    Sorted by date, not by week number: week 3 of two different training blocks
    is not one point in a progression, and ordering by week number interleaved
    them into a sawtooth. `history_sessions` is what makes more than one block
    visible at all — without it this walked only the stored program and every
    set logged under a replaced one was invisible.

    HistoryPoint: {
        date, week_number, session_key, session_uid, program_version_id,
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
    logs_by_uid = logs_by_uid or {}

    # Matched workouts, indexed both ways. The uid is exact; the legacy key is
    # program-relative and only consulted for a match that has no uid.
    match_by_key: dict[str, dict] = {}
    match_by_uid: dict[str, dict] = {}
    for mw in (matched_workouts or []):
        wo = mw.get('workout')
        if not wo:
            continue
        if mw.get('sessionUid'):
            match_by_uid[mw['sessionUid']] = wo
        key = mw.get('sessionKey', '')
        if key:
            match_by_key.setdefault(key, wo)

    for record in _session_records(program, history_sessions, active_version_id):
        week_num  = record['week_number']
        session   = record['session']
        uid       = record['session_uid']
        key_idx   = record['keys'][0]
        key_base  = record['keys'][1]
        planned_date = record.get('date') or ''

        log = logs_by_uid.get(uid) if uid else None
        if log is None:
            log = session_logs.get(key_idx) or session_logs.get(key_base)

        if log:
            # ── Manual log path ──────────────────────────────────────
            completed_at  = log.get('completedAt') or planned_date
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
                    'session_uid':      uid,
                    'program_version_id': record['version_id'],
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
            workout = (match_by_uid.get(uid) if uid else None)
            if workout is None:
                workout = match_by_key.get(key_idx) or match_by_key.get(key_base)
            if not workout:
                continue
            result = _primary_endurance_exercise(session)
            if not result:
                continue
            ex_id, _ex, _slot = result
            point = _workout_to_history_point(workout, week_num, key_base)
            point['session_uid'] = uid
            point['program_version_id'] = record['version_id']
            history.setdefault(ex_id, []).append(point)

    for ex_id in history:
        # By date, so two blocks' week 3 do not interleave. Points with no date
        # (a log that was never completed) sort first rather than being dropped.
        history[ex_id].sort(key=lambda p: (p.get('date') or '', p['week_number']))

    return history


# ---------------------------------------------------------------------------
# Expected trajectory
# ---------------------------------------------------------------------------

# slot type → (metric, unit, the stored load's field for it)
_PRESCRIBED = {
    'sets_reps':       ('weight', 'kg', 'weight_kg'),
    'static_hold':     ('time', 's', 'hold_seconds'),
    'time_domain':     ('time', 'min', 'duration_minutes'),
    'skill_practice':  ('time', 'min', 'duration_minutes'),
    'for_time':        ('time', 'min', 'time_minutes'),
    'distance':        ('distance', 'km', 'distance_km'),
    'amrap':           ('rounds', 'rounds', 'target_rounds'),
    'emom':            ('rounds', 'rounds', 'target_rounds'),
    'rounds_for_time': ('rounds', 'rounds', 'target_rounds'),
    'amrap_movement':  ('reps', 'reps', 'reps_per_round'),
}
# A sets slot with no kg anywhere (chin-ups, dips, a plank in sets) counts reps.
_BODYWEIGHT_SETS = ('reps', 'reps', 'reps')


def _slot_type_of(ea: dict) -> str:
    return ea.get('slot_type') or ('static_hold' if (ea.get('load') or {}).get('hold_seconds') is not None
                                   else 'sets_reps')


def prescribed_trajectory(weeks: list, exercise_id: str, start_date: str | None = None,
                          today: str | None = None) -> dict:
    """What the stored program prescribed for one exercise, week by week.

    The exercise cards' expected line. It was `compute_expected_trajectory`,
    which re-ran the generator against the assignment's slot — but the stored
    program has no slot (api._clean_exercise_assignment strips it), so every
    exercise was replayed as sets × reps and a run's expected line came from a
    weight calculation. The analytics engine stopped replaying on the same
    grounds; this reads `ea.load`, as it does.

    One slot type per exercise — the one it is prescribed under most often —
    and only that slot type's field: a press that is a sets slot one day and
    skill practice another must not plot kg and minutes as one line.

    Returns {metricType, unit, expected: [{week_number, week_index,
    expected_value, unit, metric_type}], target: {value, weekNumber} | None}.
    The target is the prescription of the latest week the exercise has come
    up in by `today`, else its first week — not week one's, which is what the
    card used to call the target all program long.
    """
    from collections import Counter
    from src.workout_matcher import session_calendar_date

    rows = []      # (week_index, day, slot_type, load)
    for wi, week in enumerate(weeks or []):
        for day, sessions in (week.get('schedule') or {}).items():
            for session in sessions or []:
                for ea in session.get('exercises') or []:
                    if (ea.get('exercise') or {}).get('id') == exercise_id and not ea.get('meta'):
                        rows.append((wi, day, _slot_type_of(ea), ea.get('load') or {}))
    if not rows:
        return {'metricType': 'weight', 'unit': 'kg', 'expected': [], 'target': None}

    counts = Counter(r[2] for r in rows)
    slot_type = max(counts, key=lambda st: (counts[st], -next(i for i, r in enumerate(rows) if r[2] == st)))
    metric, unit, field = _PRESCRIBED.get(slot_type, ('weight', 'kg', 'weight_kg'))
    if slot_type == 'sets_reps' and not any(
            isinstance(r[3].get('weight_kg'), (int, float)) for r in rows if r[2] == slot_type):
        metric, unit, field = _BODYWEIGHT_SETS

    by_week: dict[int, dict] = {}
    for wi, day, st, load in rows:
        w = by_week.setdefault(wi, {'best': None, 'due': False})
        if start_date and today:
            d = session_calendar_date(start_date, wi, day)
            w['due'] = w['due'] or bool(d and d <= today)
        if st != slot_type:
            continue
        v = load.get(field)
        if isinstance(v, (int, float)) and (w['best'] is None or v > w['best']):
            w['best'] = float(v)

    expected, target, first = [], None, None
    for wi in sorted(by_week):
        w = by_week[wi]
        point = {'week_number': (weeks[wi] or {}).get('week_number', wi + 1), 'week_index': wi,
                 'expected_value': w['best'], 'unit': unit, 'metric_type': metric}
        expected.append(point)
        if w['best'] is not None:
            first = first or point
            if w['due']:
                target = point
    target = target or first
    return {'metricType': metric, 'unit': unit, 'expected': expected,
            'target': {'value': target['expected_value'], 'weekNumber': target['week_number']} if target else None}


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
    deload_weeks: set | None = None,
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
        actual_points, expected_val, progression_model, metric_type, deload_weeks
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
    deload_weeks: set | None = None,
) -> str:
    if not actual_points:
        return 'insufficient_data'

    latest_val = actual_points[-1][1]

    # Stall: no meaningful change across last N data points. Deload weeks are
    # the program asking for less, not the athlete failing to progress.
    stall_sessions, _, _ = _STALL_RULES.get(progression_model, (2, 'weight', 'kg'))
    live_points = [(wk, v) for wk, v in actual_points if wk not in (deload_weeks or ())]
    if len(live_points) >= stall_sessions + 1:
        window = [v for _, v in live_points[-(stall_sessions + 1):]]
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
    history_sessions: list[dict] | None = None,
    logs_by_uid: dict | None = None,
    active_version_id: str | None = None,
    completion: tuple[int, int] | None = None,
) -> dict:
    """
    Builds a full ProgressionReview dict.

    `completion` is (completed, scheduled) from the program analytics
    scorecard — what the Program tab and Today show. The route passes it so
    the three can never disagree; the count below is the fallback.
    Returns a minimal result with insufficient_data flag when data is sparse.

    The history arguments are passed straight through to
    compute_exercise_history: a review that can only see the stored program
    reports "insufficient data" for an athlete whose training is all in blocks
    they have since replaced.
    """
    period_key  = _current_period_key(period)
    weeks       = program.get('weeks', [])
    constraints = program.get('constraints', {})
    level       = constraints.get('training_level', 'intermediate')

    philosophy_weights: dict = program.get('philosophy_weights') or {}
    progression_model  = _infer_progression_model(program)

    # Compliance — over the sessions whose day has come, as the program
    # analytics scorecard counts them (context.sessions(elapsed_only=True)).
    # Counting every week of a 16-week program in week 2 reported ~12% by
    # construction; counting the whole current week read 2 of 2 sessions done
    # by Wednesday as 50%, beside the Program tab's 100%.
    #
    # The fallback reads this version's logs only: moving one session mints a
    # new version, and the logs of the days before it stay with the old one
    # (production on 2026-10-16: Friday moved to Saturday, Progress read 0 of
    # 2 beside Today's 2 of 2). The scorecard matches logs by date and finds them.
    if completion is not None:
        total_completed, total_scheduled = completion
    else:
        due = _due_sessions(program, weeks)
        total_scheduled = len(due)
        total_completed = sum(
            1 for week_number, day_name, s_idx in due
            if (f"{week_number}-{day_name}" in session_logs
                or f"{week_number}-{day_name}-{s_idx}" in session_logs)
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

    if program.get('training_contract'):
        # Replaying a modality's kg/rounds heuristic would reinterpret an EMOM
        # density cycle as stalled because its round count deliberately holds.
        # Report earned module positions; the stored prescriptions remain the
        # source for charts, and generic load adjustments are inapplicable.
        from . import training_contract
        identity = program['training_contract']['id']
        package_track = identity.split('@')[0]
        package, track_id = package_track.split('/', 1)
        try:
            contract = training_contract.load_contract(package, track_id)
            state = training_contract.confirmed_state(program, session_logs, contract) if contract else {}
        except training_contract.ContractError:
            state = {}  # a contract renamed or broken since: report no confirmed positions
        recommendations = [f"{mid.replace('_', ' ').title()}: {s.get('completed', 0)} clean exposures confirmed. "
                           "Regenerate after logging outcomes to update the next prescription."
                           for mid, s in state.items()]
        return {'period_key': period_key, 'period_type': period,
                'generated_at': datetime.utcnow().isoformat(), 'overall_score': None,
                'readiness_trend': readiness_trend, 'avg_readiness': avg_readiness,
                'compliance_pct': compliance_pct, 'exercise_findings': [],
                'flags': ['module_progression'], 'recommendations': recommendations,
                'adjustments': [], 'module_progression': state}

    # Exercise history
    ex_history = compute_exercise_history(
        session_logs, program,
        history_sessions=history_sessions,
        logs_by_uid=logs_by_uid,
        active_version_id=active_version_id,
    )

    # Need ≥ 2 exercises with ≥ 2 data points
    usable = {eid: pts for eid, pts in ex_history.items() if len(pts) >= 2}
    if len(usable) < 1:
        # No lift series yet — but missed sessions are still worth saying:
        # this branch used to drop the low-completion advice, so 2 of 7 done
        # read "nothing to change".
        flags = ['insufficient_data']
        recommendations = ['Log at least 2 sessions with set data to see progression analysis.']
        if total_scheduled and compliance_pct < 60:
            flags.append('low_compliance')
            recommendations.append('Session completion rate is low — prioritise showing up over intensity.')
        review = {
            'period_key':        period_key,
            'period_type':       period,
            'generated_at':      datetime.utcnow().isoformat(),
            'overall_score':     None,
            'readiness_trend':   readiness_trend,
            'avg_readiness':     avg_readiness,
            'compliance_pct':    compliance_pct,
            'exercise_findings': [],
            'flags':             flags,
            'recommendations':   recommendations,
            'adjustments':       [],
        }
        if total_scheduled:
            review['adjustments'] = suggest_adjustments(review, program)
        return review

    # Build per-exercise findings. A deload week — flagged, or a taper — is the
    # program asking for less, and must not read as a stall.
    deload_weeks = {w.get('week_number') for w in weeks
                    if w.get('is_deload') or w.get('phase') in phases.deload_kinds()}
    exercise_findings = []
    for w in weeks:
        for day_sessions in w.get('schedule', {}).values():
            for session in day_sessions:
                modality = session.get('modality', '')
                prog_model = _infer_progression_model(program, modality)
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
                        deload_weeks,
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

def _due_sessions(program: dict, weeks: list, today=None) -> list[tuple]:
    """(week_number, day name, index) of every session dated on or before
    today. Without a start date every session counts, as before."""
    from datetime import date
    from src.workout_matcher import session_calendar_date
    start_raw = program.get('program_start_date') or program.get('programStartDate')
    today = (today or date.today()).isoformat()
    out = []
    for i, w in enumerate(weeks):
        for day_name, day_sessions in (w.get('schedule') or {}).items():
            when = session_calendar_date(str(start_raw), i, day_name) if start_raw else ''
            if start_raw and when and when > today:
                continue
            out.extend((w.get('week_number'), day_name, s_idx) for s_idx in range(len(day_sessions)))
    return out


def _infer_progression_model(program: dict, modality: str | None = None) -> str:
    """The progression model that actually prescribed a modality's load.

    This used to read `goal.progression_model`, which goals.py never writes, so
    every program was analysed as linear_load. Generation reads the model from
    the modality yaml (src/generator.py:360-363), and so does this.
    """
    if modality:
        try:
            from src import loader
            model = (loader.load_all_modalities().get(modality) or {}).get('progression_model')
            if model:
                return model
        except Exception:
            pass
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
