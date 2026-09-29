"""The one document GET /api/analytics/program serves.

Pure over its inputs: the endpoint gathers, this assembles. Sections are
independent and each is guarded, so a failure in one becomes an `error` field
on that section rather than a 500 for the athlete.
"""
from __future__ import annotations

import traceback
from datetime import date

from src.analytics import archetypes, benchmarks, frame, intensity, movement, scorecard
from src.analytics import spec as spec_mod
from src.analytics.context import AnalyticsInputs, Context
from src.analytics.primitives import run as run_primitive

DELOAD_TSB_NOTE = ('A negative training-stress balance is expected while the block is loading; '
                   'it becomes a flag in a taper.')


def _guard(name: str, fn):
    try:
        return fn()
    except Exception as e:
        return {'error': f'{type(e).__name__}: {e}',
                'trace': traceback.format_exc().splitlines()[-3:], 'section': name}


def compute_program_analytics(inputs: AnalyticsInputs, *, load: dict | None = None,
                              frameworks: dict | None = None, modalities: dict | None = None) -> dict:
    ctx = Context(inputs, frameworks=frameworks, modalities=modalities)
    specs = spec_mod.compose(ctx.goal, ctx.philosophy_weights)

    progress = []
    for s in specs:
        for entry in s.entries:
            progress.append(run_primitive(entry, ctx))

    methodologies = []
    for s in specs:
        entries = [p for p in progress if p['philosophy'] == s.philosophy]
        lead = next((p for p in entries if p['headline']), entries[0] if entries else None)
        methodologies.append({
            'philosophy': s.philosophy, 'weight': s.entries[0].weight if s.entries else 0.0,
            'analytics': s.source, 'headlineId': lead['id'] if lead else None,
            'entryIds': [p['id'] for p in entries],
            'measurable': sum(1 for p in entries if p['coverage']['measured']),
            'total': len(entries),
        })

    doc = {
        'generatedAt': date.today().isoformat(),
        'frame': _guard('frame', lambda: frame.build(ctx, specs)),
        'scorecard': _guard('scorecard', lambda: scorecard.build(ctx)),
        'intensity': _guard('intensity', lambda: intensity.build(ctx)),
        'methodologies': methodologies,
        'progress': progress,
        'movement': _guard('movement', lambda: movement.build(ctx, specs)),
        'archetypes': _guard('archetypes', lambda: archetypes.build(ctx)),
        'benchmarks': _guard('benchmarks', lambda: benchmarks.build(ctx, specs)),
        'load': _reframe_load(load, ctx),
    }
    return doc


def _reframe_load(load: dict | None, ctx: Context) -> dict:
    """The existing TRIMP / PMC / readiness numbers, read in the light of the phase."""
    load = dict(load or {})
    cur = ctx.current_week_index
    week = ctx.weeks[cur] if cur is not None else None
    phase = (week or {}).get('phase')
    deload = ctx.is_deload_week(week) if week else False
    pmc = load.get('pmc') or []
    tsb = pmc[-1].get('tsb') if pmc else None
    reading = None
    # A PMC that never saw a workout is all zeros: TSB 0 is not "fresh", it is
    # "nothing to read".
    has_load = any((e.get('trimp') or 0) > 0 or (e.get('ctl') or 0) > 0 for e in pmc)
    if tsb is not None and not has_load:
        reading = 'no_load_data'
    elif tsb is not None:
        if deload or phase == 'taper':
            reading = ('fresh' if tsb >= 0 else 'still_fatigued_in_recovery')   # deload or taper
        else:
            reading = ('loading_as_expected' if -25 <= tsb < 5 else
                       'very_fatigued' if tsb < -25 else 'fresh')
    load['phase'] = phase
    load['isDeload'] = deload
    load['tsb'] = tsb
    load['reading'] = reading
    load['note'] = DELOAD_TSB_NOTE
    return load


# ── Compatibility: the shape the old progression review served ───────────────

def progression_findings(doc: dict) -> list[dict]:
    """The engine's per-lift results in the `ExerciseFinding` shape.

    GET /api/progression/review still has consumers — the Dashboard's
    ProgressionTab on the web and ProgressionView on iOS — and both improve
    for free when its findings come from here rather than from the old
    replay-based tracker. One finding per exercise with a series, across every
    load and outcome primitive in the document.
    """
    out: list[dict] = []
    seen: set[str] = set()
    unit_metric = {'kg': 'weight', 'min': 'time', 'km': 'distance', 'rounds': 'rounds',
                   's': 'time', 'rpm': 'reps', 'exercises': 'complexity'}
    for pr in doc.get('progress') or []:
        exercises = pr.get('exercises')
        if exercises is None:
            exercises = [{'exerciseId': pr['id'], 'name': pr.get('label') or pr['id'],
                          'series': pr.get('series') or [], 'expected': pr.get('expected') or [],
                          'status': pr.get('status'), 'trend': pr.get('trend') or {}}]
        for ex in exercises:
            key = ex.get('exerciseId') or pr['id']
            if key in seen or not ex.get('series'):
                continue
            seen.add(key)
            series = ex['series']
            latest = series[-1]
            expected_vals = [e['value'] for e in (ex.get('expected') or []) if e.get('value') is not None]
            first, last = series[0]['value'], latest['value']
            delta = (last - first) if isinstance(first, (int, float)) and isinstance(last, (int, float)) else None
            weeks = (latest.get('week') or 0) - (series[0].get('week') or 0)
            unit = pr.get('unit', '')
            change = (f"{'+' if delta >= 0 else ''}{round(delta, 1)}{unit} over {max(weeks, 1)} wk"
                      if delta is not None else 'Not enough data — log at least 2 sessions.')
            status = ex.get('status') or pr.get('status')
            out.append({
                'exercise_id': key, 'name': ex.get('name') or key,
                'metric_type': unit_metric.get(unit, 'weight'),
                'expected_value': expected_vals[-1] if expected_vals else None,
                'actual_value': last, 'unit': unit,
                'status': status if status in ('ahead', 'on_track', 'behind', 'stalled', 'insufficient_data')
                          else ('on_track' if status in ('met', 'on_target', 'stable_by_design') else 'insufficient_data'),
                'trend': (ex.get('trend') or {}).get('direction', 'stable').replace('insufficient_data', 'stable'),
                'change_summary': change,
            })
    return out
