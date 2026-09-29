"""Planned intensity split against actual, over the whole program.

A thin frame around the `zone_minutes` primitive run with an empty scope: every
completed session in the block, bucketed against the framework that governed
its week. The primitive already refuses to double-count a strength session
that wore a strap and reports what it could not classify; this section adds
the per-phase reading and, for a pure-strength framework where the declared
split is `max_effort_pct: 1.0`, the %1RM view that actually says something.
"""
from __future__ import annotations

from src.analytics import spec as spec_mod
from src.analytics.context import Context
from src.analytics.primitives import run
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
