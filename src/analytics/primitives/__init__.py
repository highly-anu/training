"""The engine's metric vocabulary.

A primitive is one function `(entry, ctx) -> result` that knows how to
measure one kind of thing over what the athlete logged — best set load,
rounds in a time cap, minutes in a heart-rate bucket, exercises unlocked —
and nothing about any methodology. A package's analytics.yaml names the
primitives that mean progress for it; src/analytics/spec.py resolves which
sessions and assignments each looks at; this package computes.

Every result has the same shape, and **coverage is part of it**: the share of
in-scope completed sessions that actually produced the metric, with a reason
when it is low. A methodology whose native currency is not being captured
yet gets an honest "not measurable — log rounds" rather than an empty chart.

One failing primitive must never take the document down: `run` catches and
reports per entry.
"""
from __future__ import annotations

import traceback
from datetime import date

from src.analytics import spec as spec_mod
from src.analytics import zones
from src.analytics.context import Context

PRIMITIVES: dict = {}


def primitive(name: str):
    def deco(fn):
        PRIMITIVES[name] = fn
        return fn
    return deco


# ── shared helpers ───────────────────────────────────────────────────────────

def scoped_hits(entry: spec_mod.Entry, ctx: Context) -> list[dict]:
    """Elapsed, in-scope sessions with their assignments, log and workout, in order."""
    hits = []
    ordinal = 0
    for h in spec_mod.select(entry, ctx.weeks):
        d = ctx.session_date(h['week_index'], h['day'])
        if d is None or d > ctx.today:
            continue
        ordinal += 1
        h = dict(h)
        h.update({
            'date': d, 'ordinal': ordinal,
            'week_number': h['week'].get('week_number', h['week_index'] + 1),
            'is_deload': ctx.is_deload_week(h['week']),
            'log': ctx.log_for(h), 'workout': ctx.workout_for(h),
        })
        h['completed'] = bool((h['log'] or {}).get('completedAt')) or h['workout'] is not None
        hits.append(h)
    return hits


def max_hr_for(ctx: Context) -> float:
    """hrConfig override → 220 − age → the data file's default.

    The server used to ignore date of birth and use 190 flat, so its zones
    disagreed with the browser's for anyone who had set a DOB but no override.
    """
    hr = (ctx.profile.get('hrConfig') or {})
    override = hr.get('maxHROverride')
    if override and float(override) > 0:
        return float(override)
    dob = ctx.profile.get('dateOfBirth')
    if dob:
        try:
            born = date.fromisoformat(str(dob)[:10])
            age = ctx.today.year - born.year - ((ctx.today.month, ctx.today.day) < (born.month, born.day))
            if 5 < age < 110:
                return float(220 - age)
        except ValueError:
            pass
    return float(zones.default_max_hr())


def expected_value(entry: spec_mod.Entry, ea: dict | None, ctx: Context, week: dict | None) -> float | None:
    """Resolve an entry's `expected` for one assignment."""
    exp = entry.expected
    load = (ea or {}).get('load') or {}
    if isinstance(exp, dict):
        if 'load_field' in exp:
            v = load.get(exp['load_field'])
            return float(v) if isinstance(v, (int, float)) else None
        if 'constant' in exp:
            return float(exp['constant'])
        return None
    return None


def coverage(in_scope: int, measured: int, reason: str | None) -> dict:
    return {
        'inScope': in_scope,
        'measured': measured,
        'pct': round(100.0 * measured / in_scope, 1) if in_scope else 0.0,
        'reason': reason if (in_scope and measured == 0) else None,
    }


def series_point(h: dict, value, **extra) -> dict:
    p = {'week': h['week_number'], 'x': h['ordinal'], 'date': h['date'].isoformat(),
         'value': value, 'isDeload': h['is_deload']}
    p.update(extra)
    return p


def result(entry: spec_mod.Entry, *, metric: str, unit: str, series: list, expected: list | None = None,
           status: str = 'insufficient_data', trend: dict | None = None, coverage_: dict | None = None,
           evidence: list | None = None, **extra) -> dict:
    out = {
        'id': entry.id, 'label': entry.label or entry.id, 'primitive': entry.primitive,
        'philosophy': entry.philosophy, 'weight': entry.weight, 'headline': entry.headline,
        'source': entry.source, 'metric': metric, 'unit': unit,
        'series': series, 'expected': expected or [], 'status': status,
        'trend': trend or {'direction': 'insufficient_data', 'slopePct': 0.0, 'pointsUsed': 0},
        'coverage': coverage_ or coverage(0, 0, None), 'evidence': evidence or [],
    }
    out.update(extra)
    return out


def trend_dict(t) -> dict:
    return {'direction': t.direction, 'slope': round(t.slope, 4),
            'slopePct': round(t.slope_pct, 2), 'pointsUsed': t.points_used}


def run(entry: spec_mod.Entry, ctx: Context) -> dict:
    fn = PRIMITIVES.get(entry.primitive)
    if fn is None:
        return result(entry, metric=entry.primitive, unit='', series=[], status='error',
                      evidence=[f'unknown primitive {entry.primitive!r}'])
    try:
        return fn(entry, ctx)
    except Exception as e:  # one bad entry must not take the document down
        return result(entry, metric=entry.primitive, unit='', series=[], status='error',
                      evidence=[f'{type(e).__name__}: {e}', traceback.format_exc().splitlines()[-1]])


# Register every primitive module.
from src.analytics.primitives import load, outcome, aerobic, skill, standards  # noqa: E402,F401
