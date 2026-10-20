"""Load primitives: what went on the bar.

`set_load` is the native currency of every load-based methodology (Starting
Strength, Gym Jones blocks, Filly's strength work): the heaviest completed set
per session on the lifts the entry scopes, with an Epley estimated 1RM. Weight
and reps are paired **per set** — the old tracker paired two independently
filtered lists, so a set with a weight but no reps shifted every pairing after
it (src/progression_tracker.py:338-349).

Expected comes from the stored prescription (`ea.load.weight_kg`) or, for
`achieved_plus_increment`, from what the athlete last achieved plus the
exercise's own increment — which survives phase boundaries and unknown
starting loads, where re-running the generator does not.

A lift with no kg — none prescribed and none logged (air squats, pull-ups,
a dead hang in sets) — is measured in **reps**: the best completed set
against the prescribed reps. Gym Jones' strength and BJJ's pulling strength
sit on such lifts, and logging their reps read "no sets logged". Each
exercise says its own unit; one never mixes kg and reps. Reps logged on a
lift prescribed in kg, without the kg, say so (`no_kg_logged`).
"""
from __future__ import annotations

from src.analytics import trend as trend_mod
from src.analytics.primitives import (coverage, primitive, result, scoped_hits, series_point,
                                      trend_dict)
from src.progression import _DEFAULT_INCREMENT_KG

# The per-exercise statuses in words for the evidence lines both clients show
# as they are; "Front Squat: insufficient_data" was the engine's own code.
_STATUS_WORDS = {'insufficient_data': 'not enough data yet', 'on_track': 'on track',
                 'stable_by_design': 'holding'}

DEFAULT_STALL_SESSIONS = 3
EPLEY = 0.0333


def best_completed_set(ex_log: dict | None) -> dict | None:
    """The heaviest completed set, with its own reps; plus session volume."""
    best = None
    volume = 0.0
    for s in (ex_log or {}).get('sets') or []:
        if not s.get('completed'):
            continue
        w = s.get('weightKg')
        if w is None:
            continue
        w = float(w)
        r = s.get('repsActual')
        r = int(r) if r is not None else None
        if r:
            volume += w * r
        if best is None or w > best['weight']:
            best = {'weight': w, 'reps': r}
    if best is None:
        return None
    best['volume'] = round(volume, 1)
    best['est1rm'] = round(best['weight'] * (1 + EPLEY * best['reps']), 1) if best['reps'] else None
    return best


def best_reps(ex_log: dict | None) -> int | None:
    """The most reps in one completed set, or None."""
    reps = [int(s['repsActual']) for s in (ex_log or {}).get('sets') or []
            if s.get('completed') and isinstance(s.get('repsActual'), (int, float)) and s['repsActual'] > 0]
    return max(reps) if reps else None


def prescribed_reps(load: dict) -> float | None:
    """The prescription's reps: a number, or the low end of "8-10"."""
    r = (load or {}).get('reps')
    if isinstance(r, (int, float)):
        return float(r)
    if isinstance(r, str):
        head = r.replace('–', '-').split('-')[0].strip()
        try:
            return float(head)
        except ValueError:
            return None
    return None


def increment_for(ctx, exercise_id: str) -> float:
    """The exercise's own `weekly_increment_kg`, else the generator's default —
    the same two places progression.py reads. A prescription that carries
    `increment_kg` (a training contract's lift) overrides it in `set_load`."""
    ex = ctx.exercise_def(exercise_id)
    inc = ex.get('weekly_increment_kg')
    if isinstance(inc, (int, float)) and inc > 0:
        return float(inc)
    return float(_DEFAULT_INCREMENT_KG)


@primitive('set_load')
def set_load(entry, ctx) -> dict:
    hits = scoped_hits(entry, ctx)
    per_ex: dict[str, dict] = {}
    in_scope = measured = 0
    stall_sessions = int((entry.stall or {}).get('sessions') or DEFAULT_STALL_SESSIONS)
    tolerance = float((entry.stall or {}).get('tolerance_pct') or 1.0)

    for h in hits:
        if not h['completed'] or not h['assignments']:
            continue
        in_scope += 1
        logged = (h['log'] or {}).get('exercises') or {}
        got_any = False
        for ea in h['assignments']:
            ex_id = ea['exercise']['id']
            rec = per_ex.setdefault(ex_id, {
                'exerciseId': ex_id, 'name': ea['exercise'].get('name', ex_id),
                'points': [], 'expected': [], 'last': None, 'prescribedNow': None,
                'increment': increment_for(ctx, ex_id),
                'kg': False, 'repPoints': [], 'repExpected': [], 'repsWithoutKg': False,
            })
            # An RPE prescription suggests a starting weight rather than
            # fixing one (progression._rpe_autoregulation): it is still the
            # program's word on the load.
            load_ = ea.get('load') or {}
            # A training contract's lift carries its own step (Starting
            # Strength: 5 kg on the squat at first, 2.5 later): it wins.
            if isinstance(load_.get('increment_kg'), (int, float)) and not isinstance(load_['increment_kg'], bool):
                rec['increment'] = float(load_['increment_kg'])
            prescribed = load_.get('weight_kg')
            if not isinstance(prescribed, (int, float)):
                prescribed = load_.get('suggested_weight_kg')
            prescribed = float(prescribed) if isinstance(prescribed, (int, float)) else None
            rec['prescribedNow'] = prescribed
            if prescribed is not None:
                rec['kg'] = True
            # The reps reading of the same session, used if the lift turns out
            # to carry no kg at all.
            p_reps = prescribed_reps(ea.get('load') or {})
            rec['repExpected'].append({'week': h['week_number'], 'x': h['ordinal'], 'value': p_reps})
            top_reps = best_reps(logged.get(ex_id))
            if entry.expected == 'achieved_plus_increment':
                exp = rec['last'] + rec['increment'] if rec['last'] is not None else prescribed
            elif entry.expected == 'prescribed':
                exp = prescribed
            else:
                exp = None
            rec['expected'].append({'week': h['week_number'], 'x': h['ordinal'], 'value': exp})
            best = best_completed_set(logged.get(ex_id))
            if best:
                rec['kg'] = True
                rec['points'].append(series_point(
                    h, best['weight'], reps=best['reps'], est1rm=best['est1rm'],
                    volume=best['volume'], prescribed=prescribed, expected=exp))
                rec['last'] = best['weight']
                got_any = True
            elif top_reps is not None:
                rec['repPoints'].append(series_point(h, float(top_reps), reps=top_reps, prescribed=p_reps,
                                                     expected=p_reps))
                if prescribed is not None:
                    rec['repsWithoutKg'] = True
                else:
                    got_any = True
        if got_any:
            measured += 1

    exercises = []
    for rec in per_ex.values():
        unit = 'kg' if rec['kg'] else 'reps'
        if unit == 'reps':
            # No kg prescribed or logged for this lift: its currency is reps,
            # against the prescribed reps, and it rises a rep at a time.
            rec['points'], rec['expected'] = rec['repPoints'], rec['repExpected']
            rec['increment'] = 1.0
        pts = [trend_mod.Point(p['x'], p['value'], p['isDeload']) for p in rec['points']]
        t = trend_mod.fit(pts)
        exp_vals = [e['value'] for e in rec['expected'] if e['value'] is not None]
        if entry.expected == 'achieved_plus_increment':
            expected_slope = rec['increment']
        elif len(exp_vals) >= 2:
            expected_slope = trend_mod.fit([trend_mod.Point(i, v) for i, v in enumerate(exp_vals)]).slope
        else:
            expected_slope = None
        base = pts[0].value if pts else None
        stalled = trend_mod.stalled(pts, stall_sessions, tolerance)
        status = 'stalled' if stalled else trend_mod.status(t, expected_slope, base)
        exercises.append({
            'exerciseId': rec['exerciseId'], 'name': rec['name'], 'unit': unit,
            'series': rec['points'], 'expected': rec['expected'],
            'trend': trend_dict(t), 'status': status, 'stalled': stalled,
            'increment': rec['increment'], 'prescribedNow': rec['prescribedNow'],
            'latest': rec['points'][-1] if rec['points'] else None,
            'bestEst1rm': max((p['est1rm'] for p in rec['points'] if p.get('est1rm')), default=None),
        })
    exercises.sort(key=lambda e: -len(e['series']))

    # Measured = a session that put a point on some exercise's final series:
    # reps read on a lift that turned out to carry kg add nothing.
    measured = len({p['x'] for e in exercises for p in e['series']})
    lead = exercises[0] if exercises else None
    reason = None
    if not measured and in_scope:
        reason = ('no_kg_logged' if any(r['repsWithoutKg'] for r in per_ex.values()) else 'no_sets_logged')
    unit = lead['unit'] if lead else 'kg'
    return result(
        entry, metric='best_set_kg' if unit == 'kg' else 'best_set_reps', unit=unit,
        series=lead['series'] if lead else [], expected=lead['expected'] if lead else [],
        status=lead['status'] if lead else 'insufficient_data',
        trend=lead['trend'] if lead else None,
        coverage_=coverage(in_scope, measured, reason),
        evidence=[f"{e['name']}: {_STATUS_WORDS.get(e['status'], e['status'].replace('_', ' '))}"
                  for e in exercises if e['series']],
        exercises=exercises, leadExerciseId=lead['exerciseId'] if lead else None,
        stallRule={'sessions': stall_sessions, 'source': 'declared' if entry.stall else 'default'},
    )


def _rpe_target(ea: dict, session: dict) -> float | None:
    load = ea.get('load') or {}
    for key in ('target_rpe', 'rpe_target', 'rpe'):
        v = load.get(key)
        if isinstance(v, (int, float)):
            return float(v)
    for slot in (session.get('archetype') or {}).get('slots') or []:
        if slot.get('role') == ea.get('slot_role'):
            for key in ('target_rpe', 'rpe_target', 'rpe'):
                v = slot.get(key)
                if isinstance(v, (int, float)):
                    return float(v)
    return None


@primitive('load_at_rpe')
def load_at_rpe(entry, ctx) -> dict:
    """Load at the prescribed effort: the heaviest completed set within ±1 RPE
    of the target. Rising load at the same RPE, or falling RPE at the same
    load, is what feel-based progression means by progress."""
    hits = scoped_hits(entry, ctx)
    per_ex: dict[str, dict] = {}
    in_scope = measured = 0
    any_target = any_rpe = False
    for h in hits:
        if not h['completed'] or not h['assignments']:
            continue
        in_scope += 1
        logged = (h['log'] or {}).get('exercises') or {}
        got_any = False
        for ea in h['assignments']:
            ex_id = ea['exercise']['id']
            target = _rpe_target(ea, h['session'])
            rec = per_ex.setdefault(ex_id, {'exerciseId': ex_id, 'name': ea['exercise'].get('name', ex_id),
                                            'points': [], 'expected': [], 'target': target})
            if target is None:
                continue
            any_target = True
            sets = [s for s in ((logged.get(ex_id) or {}).get('sets') or [])
                    if s.get('completed') and s.get('weightKg') is not None]
            with_rpe = [s for s in sets if s.get('rpe') is not None]
            if with_rpe:
                any_rpe = True
            near = [s for s in with_rpe if abs(float(s['rpe']) - target) <= 1.0]
            suggested = (ea.get('load') or {}).get('suggested_weight_kg')
            rec['expected'].append({'week': h['week_number'], 'x': h['ordinal'],
                                    'value': float(suggested) if isinstance(suggested, (int, float)) else None})
            if near:
                best = max(near, key=lambda s: float(s['weightKg']))
                rec['points'].append(series_point(h, float(best['weightKg']), rpe=float(best['rpe']),
                                                  targetRpe=target, reps=best.get('repsActual')))
                got_any = True
        if got_any:
            measured += 1

    exercises = []
    for rec in per_ex.values():
        pts = [trend_mod.Point(p['x'], p['value'], p['isDeload']) for p in rec['points']]
        t = trend_mod.fit(pts)
        exercises.append({'exerciseId': rec['exerciseId'], 'name': rec['name'], 'targetRpe': rec['target'],
                          'series': rec['points'], 'expected': rec['expected'], 'trend': trend_dict(t),
                          'status': trend_mod.status(t, None, pts[0].value if pts else None)})
    exercises.sort(key=lambda e: -len(e['series']))
    lead = exercises[0] if exercises else None
    reason = None
    if in_scope and not measured:
        reason = 'no_rpe_target' if not any_target else ('rpe_not_logged' if not any_rpe else 'no_sets_near_target')
    return result(entry, metric='load_at_target_rpe', unit='kg',
                  series=lead['series'] if lead else [], expected=lead['expected'] if lead else [],
                  status=lead['status'] if lead else 'insufficient_data',
                  trend=lead['trend'] if lead else None,
                  coverage_=coverage(in_scope, measured, reason), exercises=exercises,
                  leadExerciseId=lead['exerciseId'] if lead else None)
