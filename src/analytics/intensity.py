"""Planned intensity split against actual, over the whole program.

A thin frame around the `zone_minutes` primitive run with an empty scope: every
completed session in the block, bucketed against the framework that governed
its week. The primitive already refuses to double-count a strength session
that wore a strap and reports what it could not classify; this section adds
the per-phase reading and, for a pure-strength framework where the declared
split is `max_effort_pct: 1.0`, the %1RM view that actually says something.
"""
from __future__ import annotations

from src.analytics import hr_plan
from src.analytics import spec as spec_mod
from src.analytics import zones
from src.analytics.context import Context
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


# The slot helpers live with the rule that reads them (src/analytics/hr_plan.py);
# the names stay for the readers that import them from here.
_slot_zones = hr_plan.slot_zones
_slot_minutes = hr_plan.slot_minutes


def _zone_detail(ctx: Context) -> list[dict]:
    """Planned against recorded minutes per HR zone (Z1-Z5), over the
    completed sessions that track heart rate (src/analytics/hr_plan.py).

    The session's programming decides, not its modality family: a session
    whose slots prescribe zones plans minutes in them (a slot spanning zones
    splits its minutes evenly) and its matched workout's heart rate records
    them; one that prescribes load or effort (a heavy lifting day) is left
    out, and the bucket split counts it as max effort. Planned minutes count
    only for a session whose heart rate was recorded, so both sides cover the
    same sessions. A zone with nothing on either side is left out."""
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
        prescription = hr_plan.plan(session)
        if not prescription['track']:
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
        for i, v in enumerate(prescription['plannedMinutes']):
            planned[i] += v
    return [{'zone': f'z{i + 1}', 'label': f'Z{i + 1}',
             'plannedMinutes': round(planned[i]), 'actualMinutes': round(actual[i])}
            for i in range(5) if round(planned[i]) or round(actual[i])]
