"""Planned intensity split against actual, over the whole program.

A thin frame around the `zone_minutes` primitive run with an empty scope: every
completed session in the block, bucketed against the framework that governed
its week. The primitive already refuses to double-count a strength session
that wore a strap and reports what it could not classify; this section adds
the per-phase reading and, for a pure-strength framework where the declared
split is `max_effort_pct: 1.0`, the %1RM view that actually says something.
"""
from __future__ import annotations

import re

from src import progression
from src.analytics import spec as spec_mod
from src.analytics import zones
from src.analytics.context import Context
from src.analytics.families import is_strength
from src.analytics.primitives import max_hr_for, run
from src.analytics.primitives.load import best_completed_set


def build(ctx: Context) -> dict:
    entry = spec_mod.Entry(id='intensity', primitive='zone_minutes', philosophy='program',
                           label='Intensity split', expected={'framework_field': 'intensity_distribution'})
    r = run(entry, ctx)
    out = {
        'status': r['status'],
        'coverage': r['coverage'],
        'maxHr': r.get('maxHr'),
        'methods': r.get('methods', {}),
        'weeks': r.get('weeks', []),
        'byFramework': r.get('byFramework', []),
        'maxDeviationPts': r.get('maxDeviationPts'),
        'zones': _zone_detail(ctx),
    }
    cur = ctx.current_week_index
    fw = ctx.framework_for_week(ctx.weeks[cur]) if cur is not None else None
    dist = (fw or {}).get('intensity_distribution') or {}
    if float(dist.get('max_effort_pct') or 0) >= 0.95:
        out['pct1rm'] = _pct_1rm(ctx)
    return out


def _pct_1rm(ctx: Context) -> dict:
    """How heavy the work actually was, as a share of estimated 1RM, against the
    slot's `intensity_pct_1rm` — the only intensity question a Starting
    Strength block can be asked."""
    rows = []
    for hit in ctx.sessions(elapsed_only=True):
        if not ctx.completed(hit):
            continue
        log = ctx.log_for(hit) or {}
        logged = log.get('exercises') or {}
        slots = {s.get('role'): s for s in ((hit['session'].get('archetype') or {}).get('slots') or [])}
        for ea in hit['session'].get('exercises') or []:
            if ea.get('meta') or ea.get('injury_skip') or not (ea.get('exercise') or {}).get('id'):
                continue
            ex_id = ea['exercise']['id']
            best = best_completed_set(logged.get(ex_id))
            if not best or not best.get('est1rm'):
                continue
            target = (slots.get(ea.get('slot_role')) or {}).get('intensity_pct_1rm')
            rows.append({'week': hit['week'].get('week_number'), 'exerciseId': ex_id,
                         'pctOf1rm': round(100.0 * best['weight'] / best['est1rm'], 1),
                         'targetPct': round(100.0 * float(target), 1) if isinstance(target, (int, float)) else None})
    if not rows:
        return {'sessions': 0, 'meanPct': None, 'rows': []}
    return {'sessions': len(rows), 'meanPct': round(sum(r['pctOf1rm'] for r in rows) / len(rows), 1),
            'rows': rows[-12:]}


def _slot_zones(intensity) -> list[int]:
    """The zones (1-5) a slot's intensity token prescribes. `zoneN` is that
    zone and `zoneA_B` the zones from A to B, read off the token itself —
    progression's band widens `zone2` to 1-2 for the HR window it shows, but
    a Zone 2 session is planned as Zone 2. Words (`light`, `hard`) take
    progression's band. Anything else (`heavy`, `bodyweight`) has no zone."""
    if not isinstance(intensity, str):
        return []
    m = re.fullmatch(r'zone([1-5])(?:_([1-5]))?', intensity.strip().lower())
    if m:
        lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
    else:
        lo, hi, _ = progression.zone_band(intensity)
        if lo is None:
            return []
    return list(range(lo, hi + 1))


def _num(value) -> float:
    """A number from authored or stored data, 0 for anything that is not one
    ("20-30", None) — one odd value must not error the whole section."""
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def _slot_minutes(slot: dict, assignments: list[dict]) -> float:
    """A slot's planned minutes: its assignments' prescribed time (the
    longest, so a circuit of three exercises in one block counts once),
    else the slot's own authored duration."""
    loads = [ea.get('load') if isinstance(ea.get('load'), dict) else {}
             for ea in assignments if not ea.get('injury_skip')]
    prescribed = [_num(load.get('duration_minutes')) or _num(load.get('time_minutes')) for load in loads]
    if any(prescribed):
        return max(prescribed)
    if _num(slot.get('duration_minutes')):
        return _num(slot['duration_minutes'])
    work = _num(slot.get('work_sec')) or _num(slot.get('duration_sec'))
    if work and _num(slot.get('sets')):
        return _num(slot['sets']) * (work + _num(slot.get('rest_sec'))) / 60.0
    return _num(slot.get('duration_sec')) / 60.0


def _zone_detail(ctx: Context) -> list[dict]:
    """Planned against recorded minutes per HR zone (Z1-Z5), over the
    completed sessions only.

    A completed session's slots plan minutes in the zones their intensity
    names (a slot spanning zones splits its minutes evenly); its matched
    workout's heart rate records them. Planned minutes count only for a
    session whose heart rate was recorded, so both sides cover the same
    sessions. Strength-family sessions are left out: their effort is load,
    not heart rate, and the bucket split already counts them as max effort.
    A zone with nothing on either side is left out."""
    max_hr = max_hr_for(ctx)
    planned = [0.0] * 5
    actual = [0.0] * 5
    # A day-level match can hand one workout to both sessions of a day; its
    # heart rate is recorded once, against the first.
    seen_workouts: set = set()
    for hit in ctx.sessions(elapsed_only=True):
        log = ctx.log_for(hit) or {}
        workout = ctx.workout_for(hit)
        if not (log.get('completedAt') or workout is not None):
            continue
        session = hit['session']
        if is_strength(session.get('modality')):
            continue
        wid = (workout or {}).get('id')
        if wid is not None and wid in seen_workouts:
            continue
        split = zones.zone_minutes(workout, max_hr) if workout else {'method': 'none'}
        if split['method'] == 'none':
            continue
        seen_workouts.add(wid)
        for i, v in enumerate(split['minutes']):
            actual[i] += v
        exercises = session.get('exercises') or []
        for slot in (session.get('archetype') or {}).get('slots') or []:
            zs = _slot_zones(slot.get('intensity'))
            if not zs:
                continue
            assigned = [ea for ea in exercises if ea.get('slot_role') == slot.get('role')]
            if assigned and all(ea.get('injury_skip') for ea in assigned):
                continue
            minutes = _slot_minutes(slot, assigned)
            for z in zs:
                planned[z - 1] += minutes / len(zs)
    return [{'zone': f'z{i + 1}', 'label': f'Z{i + 1}',
             'plannedMinutes': round(planned[i]), 'actualMinutes': round(actual[i])}
            for i in range(5) if round(planned[i]) or round(actual[i])]
