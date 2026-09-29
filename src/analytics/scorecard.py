"""Did you train what this program is for.

Per modality, planned-to-date against completed, and minutes against both the
plan and the modality's own dose band. Planned counts come from the stored
`weeks[].schedule`, not from `goal.priorities`: a phased program changes
`sessions_per_week` per phase and a blend can list modalities it never
schedules.

The headline is a gate, not a weighted sum. Σ priority × completion is
arithmetically the plain overall completion — priorities *are* the session
shares — so it could not tell an athlete who skipped every committed session
from one who skipped every supplementary one. Committed-tier completion under
70 % is `off_plan` however good the rest looks.
"""
from __future__ import annotations

from collections import defaultdict

from src.analytics.context import Context

OFF_PLAN_BELOW_PCT = 70.0
TIER_ORDER = ('committed', 'core', 'supplementary', 'unscheduled')


def build(ctx: Context) -> dict:
    planned = defaultdict(int)
    completed = defaultdict(int)
    planned_min = defaultdict(float)
    actual_min = defaultdict(float)
    tier_votes: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    minutes_source: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    tier_planned = defaultdict(int)
    tier_completed = defaultdict(int)

    for hit in ctx.sessions(elapsed_only=True):
        mod = hit['session'].get('modality') or 'unknown'
        tier = ctx.tier_of(mod, hit['week'])
        tier_votes[mod][tier] += 1
        planned[mod] += 1
        tier_planned[tier] += 1
        prescribed = _prescribed_minutes(ctx, hit)
        planned_min[mod] += prescribed
        if ctx.completed(hit) or ctx.workout_for(hit) is not None:
            completed[mod] += 1
            tier_completed[tier] += 1
            minutes, source = ctx.duration_minutes(hit)
            actual_min[mod] += minutes
            minutes_source[mod][source] += 1

    elapsed_weeks = max(1, len(ctx.elapsed_week_indexes))
    priorities = ctx.goal.get('priorities') or {}
    order = sorted(planned, key=lambda m: (-float(priorities.get(m, 0)), m))

    rows = []
    for mod in order:
        mdef = ctx.modality_def(mod)
        lo, hi = mdef.get('min_weekly_minutes'), mdef.get('max_weekly_minutes')
        tier = max(tier_votes[mod].items(), key=lambda kv: kv[1])[0]
        weekly_actual = actual_min[mod] / elapsed_weeks
        weekly_planned = planned_min[mod] / elapsed_weeks
        rows.append({
            'modality': mod,
            'family': ctx.family(mod),
            'tier': tier,
            'priority': float(priorities.get(mod, 0)),
            'plannedSessions': planned[mod],
            'completedSessions': completed[mod],
            'completionPct': _pct(completed[mod], planned[mod]),
            'plannedMinutes': round(planned_min[mod]),
            'actualMinutes': round(actual_min[mod]),
            'weeklyPlannedMinutes': round(weekly_planned),
            'weeklyActualMinutes': round(weekly_actual),
            'minWeeklyMinutes': lo,
            'maxWeeklyMinutes': hi,
            'doseStatus': _dose(weekly_actual, lo, hi),
            'planDoseStatus': _dose(weekly_planned, lo, hi),
            'minutesSource': dict(minutes_source[mod]),
        })

    tiers = {t: {'planned': tier_planned[t], 'completed': tier_completed[t],
                 'pct': _pct(tier_completed[t], tier_planned[t])}
             for t in TIER_ORDER if tier_planned[t]}
    total_planned = sum(planned.values())
    total_done = sum(completed.values())
    committed_pct = tiers.get('committed', {}).get('pct')
    if total_planned == 0:
        headline = 'not_started'
    elif committed_pct is not None and committed_pct < OFF_PLAN_BELOW_PCT:
        headline = 'off_plan'
    else:
        headline = 'on_plan'

    return {
        'headline': headline,
        'overallPct': _pct(total_done, total_planned),
        'tiers': tiers,
        'elapsedWeeks': len(ctx.elapsed_week_indexes),
        'modalities': rows,
    }


def _prescribed_minutes(ctx: Context, hit: dict) -> float:
    session = hit['session']
    mins = sum(float((ea.get('load') or {}).get('duration_minutes') or 0)
               for ea in (session.get('exercises') or [])
               if not (ea.get('meta') or ea.get('injury_skip') or ea.get('coverage_gap')))
    if mins > 0:
        return mins
    est = float((session.get('archetype') or {}).get('duration_estimate_minutes') or 0)
    return est * (0.7 if ctx.is_deload_week(hit['week']) else 1.0)


def _dose(weekly: float, lo, hi) -> str:
    if lo is None and hi is None:
        return 'unknown'
    if lo is not None and weekly < float(lo):
        return 'under'
    if hi is not None and weekly > float(hi):
        return 'over'
    return 'on'


def _pct(num: int, den: int) -> float | None:
    return round(100.0 * num / den, 1) if den else None
