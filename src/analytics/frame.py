"""What this program is, and where the athlete is in it.

The one section that is almost entirely static: the philosophy's own
description of itself, the framework in force this week, the phase and its
`focus` prose (authored in every package and rendered nowhere until now), and
plan fidelity — the framework's `expectations` against the constraints the
program was generated under, which is the most direct statement of what the
program asks for.
"""
from __future__ import annotations

from src import loader
from src.analytics.context import Context

_FIDELITY_FIELDS = (
    # (expectations key, constraints key, unit, lower_is_worse)
    ('ideal_days_per_week', 'days_per_week', 'days', True),
    ('ideal_session_minutes', 'session_time_minutes', 'min', True),
)


def build(ctx: Context, specs: list) -> dict:
    sources = [p for p in (ctx.goal.get('primary_sources') or []) if p]
    by_id = {s.philosophy: s for s in specs}
    philosophies = []
    for pid in sources:
        try:
            phil = loader.load_philosophy(pid)
        except (FileNotFoundError, KeyError):
            phil = {'id': pid, 'name': pid}
        philosophies.append({
            'id': pid,
            'name': phil.get('name', pid),
            'progressionPhilosophy': phil.get('progression_philosophy'),
            'intensityModel': phil.get('intensity_model'),
            'corePrinciples': list(phil.get('core_principles') or []),
            'weight': float(ctx.philosophy_weights.get(pid, 1.0 if len(sources) == 1 else 0.0) or 0.0),
            'analytics': by_id[pid].source if pid in by_id else 'default',
        })

    cur_idx = ctx.current_week_index
    cur_week = ctx.weeks[cur_idx] if cur_idx is not None else None
    fw = ctx.framework_for_week(cur_week) if cur_week else None

    phase = None
    if cur_week is not None:
        phase = {
            'name': cur_week.get('phase'),
            'weekInPhase': cur_week.get('week_in_phase'),
            'weekInProgram': cur_idx + 1,
            'totalWeeks': len(ctx.weeks),
            'focus': _phase_focus(ctx.goal, cur_week.get('phase')),
            'isDeload': ctx.is_deload_week(cur_week),
        }

    status = 'not_started' if ctx.today < ctx.start_date else (
        'complete' if cur_idx is None else 'active')

    return {
        'status': status,
        'startDate': ctx.start_date.isoformat(),
        'today': ctx.today.isoformat(),
        'plannedWeeks': len(ctx.weeks),
        'elapsedWeeks': len(ctx.elapsed_week_indexes),
        'deloadWeeks': [w.get('week_number', i + 1) for i, w in enumerate(ctx.weeks)
                        if ctx.is_deload_week(w)],
        'philosophies': philosophies,
        'framework': _framework_summary(fw),
        'phase': phase,
        'phaseSequence': [
            {'phase': e.get('phase'), 'weeks': e.get('weeks'),
             'frameworkId': e.get('framework_id'), 'focus': e.get('focus')}
            for e in (ctx.goal.get('phase_sequence') or [])],
        'planFidelity': _plan_fidelity(fw, ctx),
    }


def _framework_summary(fw: dict | None) -> dict | None:
    if not fw:
        return None
    return {
        'id': fw.get('id'),
        'name': fw.get('name'),
        'progressionModel': fw.get('progression_model'),
        'intensityDistribution': fw.get('intensity_distribution'),
        'sessionsPerWeek': fw.get('sessions_per_week'),
        'modalityPriority': fw.get('modality_priority'),
        'deloadProtocol': fw.get('deload_protocol'),
        'notes': fw.get('notes'),
    }


def _phase_focus(goal: dict, phase: str | None) -> str | None:
    for entry in goal.get('phase_sequence') or []:
        if entry.get('phase') == phase and entry.get('focus'):
            return entry['focus']
    return None


def _plan_fidelity(fw: dict | None, ctx: Context) -> list[dict]:
    """The framework's ideal against what the program was generated with."""
    out = []
    exp = (fw or {}).get('expectations') or {}
    if not exp:
        return out
    for exp_key, con_key, unit, lower_is_worse in _FIDELITY_FIELDS:
        ideal = exp.get(exp_key)
        actual = ctx.constraints.get(con_key)
        if ideal is None or actual is None:
            continue
        minimum = exp.get(exp_key.replace('ideal_', 'min_'))
        if minimum is not None and actual < minimum:
            status = 'below_minimum'
        elif actual < ideal:
            status = 'below_ideal'
        else:
            status = 'meets_ideal'
        out.append({'field': con_key, 'ideal': ideal, 'minimum': minimum,
                    'actual': actual, 'unit': unit, 'status': status})
    ideal_weeks = exp.get('ideal_weeks')
    if ideal_weeks:
        n = len(ctx.weeks)
        min_weeks = exp.get('min_weeks')
        status = ('below_minimum' if min_weeks and n < min_weeks
                  else 'below_ideal' if n < ideal_weeks else 'meets_ideal')
        out.append({'field': 'weeks', 'ideal': ideal_weeks, 'minimum': min_weeks,
                    'actual': n, 'unit': 'wk', 'status': status})
    return out
