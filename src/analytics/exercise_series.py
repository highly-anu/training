"""Every exercise of the program, session by session: what was prescribed and
what was done.

The Progress tab's one chart draws from this section. Each point is one
planned session of the exercise — elapsed or not — with the stored
prescription (`ea.load`) and, once logged, what the athlete did, read set by
set from the session log: the top set, every set's reps, the sets completed.
A session with no log but a matched workout gives a time or distance point to
its endurance exercise. Future sessions carry only the prescription, so the
plan line runs ahead of what has been done.

The methodology measures (`progress` entries) are the chart's other series;
they are named here (`measures`) and their points stay in `progress`.

Weight and reps are paired per set, as `set_load` pairs them — the old
tracker paired two separately filtered lists (src/progression_tracker.py).
"""
from __future__ import annotations

from src.analytics.context import Context
from src.analytics.primitives.load import _rpe_target, best_completed_set, prescribed_reps
from src.output import _fmt_load

# id, label, unit — the order the clients offer them in.
METRICS = [
    ('weight', 'Top set', 'kg'),
    ('reps', 'Reps', 'reps'),
    ('sets', 'Sets', 'sets'),
    ('totalReps', 'Total reps', 'reps'),
    ('volume', 'Volume', 'kg'),
    ('est1rm', 'Est. 1RM', 'kg'),
    ('rpe', 'RPE', 'RPE'),
    ('time', 'Time', 'min'),
    ('hold', 'Hold', 's'),
    ('rounds', 'Rounds', 'rounds'),
    ('distance', 'Distance', 'km'),
]
_METRIC_IDS = [m[0] for m in METRICS]
# The metric an exercise opens on: the first it has a value for.
_DEFAULT_ORDER = ['weight', 'rounds', 'distance', 'time', 'hold', 'reps']
_ENDURANCE_SLOT_TYPES = frozenset({'time_domain', 'distance', 'for_time', 'skill_practice'})
# A measure whose points are several standards at once has no single line.
_UNCHARTED_PRIMITIVES = frozenset({'benchmark_level'})


def _num(v) -> float | None:
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def _round(v: float | None, nd: int = 1) -> float | None:
    return round(v, nd) if v is not None else None


def prescribed_values(ea: dict, session: dict) -> dict:
    """The stored prescription in the chart's metrics; None where it says nothing."""
    load = ea.get('load') or {}
    weight = _num(load.get('weight_kg'))
    if weight is None:
        weight = _num(load.get('suggested_weight_kg'))
    sets = _num(load.get('sets'))
    reps = prescribed_reps(load)
    if reps is None:
        reps = _num(load.get('reps_per_round'))
    total = sets * reps if sets is not None and reps is not None else None
    distance = _num(load.get('distance_km'))
    if distance is None and _num(load.get('distance_m')) is not None:
        distance = _num(load.get('distance_m')) / 1000.0
    # A lift's minutes are its time budget (Starting Strength's 20 for three
    # sets of five, chin-ups to failure), not something to do: only a
    # prescription that names no reps prescribes time.
    time = None
    if load.get('reps') is None and load.get('reps_per_round') is None:
        time = _num(load.get('duration_minutes'))
        if time is None:
            time = _num(load.get('time_minutes'))
    return {
        'weight': weight,
        'reps': reps,
        'sets': sets,
        'totalReps': total,
        'volume': _round(total * weight) if total is not None and weight is not None else None,
        'est1rm': None,
        'rpe': _rpe_target(ea, session),
        'time': time,
        'hold': _num(load.get('hold_seconds')),
        'rounds': _num(load.get('target_rounds')),
        'distance': _round(distance, 2),
    }


def done_values(ex_log: dict | None) -> tuple[dict, list]:
    """What the log says was done, in the chart's metrics, and the completed sets."""
    ex_log = ex_log or {}
    completed = [s for s in ex_log.get('sets') or [] if s.get('completed')]
    sets_done = [{'weightKg': _num(s.get('weightKg')), 'reps': _num(s.get('repsActual')),
                  'seconds': _num(s.get('durationSeconds')), 'rpe': _num(s.get('rpe'))}
                 for s in completed]
    best = best_completed_set(ex_log)
    reps = [s['reps'] for s in sets_done if s['reps']]
    holds = [s['seconds'] for s in sets_done if s['seconds']]
    rpe = _num(ex_log.get('rpe'))
    if rpe is None:
        rpes = [s['rpe'] for s in sets_done if s['rpe'] is not None]
        rpe = max(rpes) if rpes else None
    dur = _num(ex_log.get('durationSec'))
    weight = best['weight'] if best else None
    return {
        'weight': weight,
        # The top set's own reps; a lift with no kg, the most reps in a set.
        'reps': (best['reps'] or None) if best else (max(reps) if reps else None),
        'sets': float(len(completed)) if completed else None,
        'totalReps': float(sum(reps)) if reps else None,
        'volume': (best['volume'] or None) if best else None,
        'est1rm': best['est1rm'] if best else None,
        'rpe': rpe,
        'time': _round(dur / 60.0) if dur else None,
        'hold': max(holds) if holds and weight is None else None,
        'rounds': _num(ex_log.get('rounds')),
        'distance': _round(_num(ex_log.get('distanceKm')), 2),
    }, sets_done


def _workout_km(workout: dict) -> float | None:
    d = workout.get('distance')
    if isinstance(d, dict):
        v = _num(d.get('value'))
        if not v:
            return None
        return round(v if d.get('unit', 'km') == 'km' else v / 1000.0, 2)
    return _round(_num(workout.get('distanceKm')), 2)


def _endurance_exercise(session: dict) -> str | None:
    """The one exercise a matched workout's minutes and distance belong to:
    the session's endurance slot with the most prescribed, if it has one."""
    best, best_amount = None, -1.0
    for ea in session.get('exercises') or []:
        if ea.get('meta') or ea.get('injury_skip') or ea.get('coverage_gap'):
            continue
        if ea.get('slot_type') not in _ENDURANCE_SLOT_TYPES:
            continue
        load = ea.get('load') or {}
        amount = _num(load.get('duration_minutes')) or _num(load.get('distance_km')) or 0.0
        if amount > best_amount:
            best, best_amount = (ea.get('exercise') or {}).get('id'), amount
    return best


def _fmt_n(v: float | None) -> str:
    return '' if v is None else (f'{v:g}')


def prescribed_text(load: dict) -> str | None:
    """The stored load in output.py's words, whole kilos without the ".0"."""
    tidy = {k: (int(v) if isinstance(v, float) and v.is_integer() else v) for k, v in load.items()}
    return _fmt_load(tidy) or None


def done_text(done: dict, sets_done: list) -> str:
    """"100×5, 100×5, 100×4" — what the log says, in the order it was done."""
    parts = []
    if sets_done:
        if any(s['weightKg'] for s in sets_done):
            parts.append(', '.join(f"{_fmt_n(s['weightKg'])}×{_fmt_n(s['reps'])}" if s['reps']
                                   else f"{_fmt_n(s['weightKg'])} kg" for s in sets_done))
        elif any(s['reps'] for s in sets_done):
            parts.append(', '.join(_fmt_n(s['reps']) for s in sets_done if s['reps']) + ' reps')
        elif any(s['seconds'] for s in sets_done):
            parts.append(', '.join(f"{_fmt_n(s['seconds'])} s" for s in sets_done if s['seconds']))
    if done.get('rounds') is not None:
        n = done['rounds']
        parts.append(f"{_fmt_n(n)} round{'' if n == 1 else 's'}")
    if done.get('time') is not None and not sets_done:
        parts.append(f"{_fmt_n(done['time'])} min")
    if done.get('distance') is not None:
        parts.append(f"{_fmt_n(done['distance'])} km")
    if done.get('rpe') is not None:
        parts.append(f"RPE {_fmt_n(done['rpe'])}")
    return ' · '.join(parts)


def build(ctx: Context, progress: list | None = None) -> dict:
    per_ex: dict[str, dict] = {}
    order: list[str] = []
    for hit in ctx.sessions(elapsed_only=False):
        session = hit['session']
        d = hit['date']
        elapsed = d is not None and d <= ctx.today
        log = ctx.log_for(hit) if elapsed else None
        workout = ctx.workout_for(hit) if elapsed else None
        logged = (log or {}).get('exercises') or {}
        endurance = _endurance_exercise(session) if workout is not None else None
        for ea in session.get('exercises') or []:
            if ea.get('meta') or ea.get('injury_skip') or ea.get('coverage_gap'):
                continue
            ex = ea.get('exercise') or {}
            ex_id = ex.get('id')
            if not ex_id:
                continue
            if ex_id not in per_ex:
                order.append(ex_id)
                per_ex[ex_id] = {'exerciseId': ex_id, 'name': ex.get('name', ex_id),
                                 'modality': session.get('modality'), 'points': []}
            rec = per_ex[ex_id]
            prescribed = prescribed_values(ea, session)
            ex_log = logged.get(ex_id) if isinstance(logged.get(ex_id), dict) else None
            source = None
            sets_done: list = []
            done = {m: None for m in _METRIC_IDS}
            if ex_log:
                done, sets_done = done_values(ex_log)
                source = 'log' if any(v is not None for v in done.values()) else None
            if source is None and workout is not None and ex_id == endurance:
                minutes = _num(workout.get('durationMinutes'))
                done = dict(done, time=_round(minutes), distance=_workout_km(workout))
                source = 'workout' if minutes or done['distance'] else None
            rec['points'].append({
                'date': d.isoformat() if d else None,
                'week': hit['week'].get('week_number', hit['week_index'] + 1),
                'x': len(rec['points']) + 1,
                'isDeload': ctx.is_deload_session(hit),
                'elapsed': elapsed,
                'source': source,
                'sessionName': (session.get('archetype') or {}).get('name'),
                # Only the metrics with a value: every null in every future
                # session made a 16-week document ~240 KB.
                'done': {k: v for k, v in done.items() if v is not None},
                'prescribed': {k: v for k, v in prescribed.items() if v is not None},
                'doneText': done_text(done, sets_done) if source else None,
                'prescribedText': prescribed_text(ea.get('load') or {}),
                'setsDone': sets_done,
            })

    exercises = []
    for ex_id in order:
        rec = per_ex[ex_id]
        pts = rec['points']
        metrics = [m for m in _METRIC_IDS if any(m in p['done'] or m in p['prescribed'] for p in pts)]
        if not metrics:
            continue
        with_done = [m for m in _DEFAULT_ORDER if any(m in p['done'] for p in pts)]
        planned = [m for m in _DEFAULT_ORDER if m in metrics]
        default = (with_done or planned or metrics)[0]
        exercises.append(dict(rec, metrics=metrics, defaultMetric=default,
                              scheduled=len(pts), logged=sum(1 for p in pts if p['source'])))
    # What has been logged leads; then the program's own order.
    exercises.sort(key=lambda e: 0 if e['logged'] else 1)

    measures = [{'id': p['id'], 'label': p.get('label') or p['id'], 'unit': p.get('unit'),
                 'philosophy': p.get('philosophy'), 'primitive': p.get('primitive')}
                for p in (progress or [])
                if p.get('applies') is not False and p.get('primitive') not in _UNCHARTED_PRIMITIVES
                and p.get('status') != 'error']
    return {
        'metrics': [{'id': i, 'label': label, 'unit': unit} for i, label, unit in METRICS],
        'exercises': exercises,
        'measures': measures,
    }
