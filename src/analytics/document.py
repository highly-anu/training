"""The one document GET /api/analytics/program serves.

Pure over its inputs: the endpoint gathers, this assembles. Sections are
independent and each is guarded, so a failure in one becomes an `error` field
on that section rather than a 500 for the athlete.
"""
from __future__ import annotations

import traceback
from datetime import date

from src.analytics import (archetypes, benchmarks, exercise_series, frame, intensity, movement, scorecard,
                           vocabulary)
from src.analytics import spec as spec_mod
from src import loader, phases
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
    phil_cache: dict = {}
    for s in specs:
        for entry in s.entries:
            r = run_primitive(entry, ctx)
            r['programScope'] = _program_scope(entry, ctx)
            r['about'] = vocabulary.about(entry.primitive, entry.notes)
            r['applies'] = r['programScope']['planned'] > 0
            if not r['applies']:
                r['appliesIn'] = _applies_in(entry, phil_cache)
            progress.append(r)

    methodologies = []
    for s in specs:
        entries = [p for p in progress if p['philosophy'] == s.philosophy]
        lead = _lead_entry(entries, s, ctx, phil_cache)
        for p in entries:
            p['headline'] = p is lead
        applicable = [p for p in entries if p['applies']]
        methodologies.append({
            'headlineSummary': headline_summary(lead) if lead else None,
            'philosophy': s.philosophy, 'weight': s.entries[0].weight if s.entries else 0.0,
            'analytics': s.source, 'headlineId': lead['id'] if lead else None,
            'entryIds': [p['id'] for p in entries],
            'measurable': sum(1 for p in applicable if p['coverage']['measured']),
            'applicable': len(applicable),
            'total': len(entries),
        })

    doc = {
        'generatedAt': date.today().isoformat(),
        'frame': _guard('frame', lambda: frame.build(ctx, specs)),
        'scorecard': _guard('scorecard', lambda: scorecard.build(ctx)),
        'intensity': _guard('intensity', lambda: intensity.build(ctx)),
        'methodologies': methodologies,
        'progress': progress,
        'exerciseSeries': _guard('exerciseSeries', lambda: exercise_series.build(ctx, progress)),
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
        if deload or phase in phases.deload_kinds():
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


def _philosophy(pid: str, cache: dict) -> dict:
    """One parse per philosophy per document: loader.load_philosophy re-reads
    every philosophy and framework file on each call."""
    if pid not in cache:
        try:
            cache[pid] = loader.load_philosophy(pid)
        except (FileNotFoundError, KeyError):
            cache[pid] = {}
    return cache[pid]


def _lead_entry(entries: list[dict], spec, ctx: Context, phil_cache: dict) -> dict | None:
    """The entry a methodology's section leads with, among those that apply.

    The spec's headline is chosen per package, but a package can offer tracks
    with different currencies: Wildman's cadence leads in Pentathlon Prep and
    measures nothing in General Practice, where a movement earned is the unit.
    So a headline that does not apply to this program gives way — first to the
    primitive of the framework the program is running (its
    `progression_model`), then to the philosophy's preferred primitive, then to
    the first entry that applies."""
    if not entries:
        return None
    applicable = [p for p in entries if p['applies']]
    declared = next((p for p in entries if p['headline']), None)
    if not applicable:
        return declared or entries[0]
    if declared is not None and declared['applies']:
        return declared
    wanted = []
    idx = ctx.current_week_index
    if idx is None and ctx.weeks:
        # Before the start the first week leads; after the end, the last.
        idx = 0 if ctx.today < ctx.start_date else len(ctx.weeks) - 1
    week = ctx.weeks[idx] if idx is not None else None
    fw = ctx.framework_for_week(week) if week else None
    # In a blend the week runs one philosophy's framework; its model says
    # nothing about another methodology's currency.
    if fw and fw.get('source_philosophy') in (None, spec.philosophy):
        model = fw.get('progression_model')
        if model in spec_mod.DEFAULT_FOR_MODEL:
            wanted.append(spec_mod.DEFAULT_FOR_MODEL[model][0])
    phil = _philosophy(spec.philosophy, phil_cache)
    pref = spec_mod.HEADLINE_FOR_PHILOSOPHY.get(phil.get('progression_philosophy') or '')
    if pref:
        wanted.append(pref)
    for primitive in wanted:
        hit = next((p for p in applicable if p['primitive'] == primitive), None)
        if hit is not None:
            return hit
    return applicable[0]


_UNIT_WORDS = {'min': 'min', 'kg': 'kg', 'km': 'km', 'rounds': 'rounds', 's': 's',
               'rpm': 'rpm', 'm/beat': 'm/beat', '%': '%'}


def _num(v) -> str:
    v = round(float(v), 1)
    return str(int(v)) if v == int(v) else str(v)


def headline_summary(entry: dict) -> dict:
    """The methodology's headline in a sentence, for Today's Progress card on
    both clients — the number its own currency is counted in, and which way it
    is moving. Words are written here so the web and the phone cannot phrase
    one number two ways."""
    prim = entry.get('primitive')
    cov = entry.get('coverage') or {}
    trend = entry.get('trend') or {}
    series = [p for p in entry.get('series') or [] if p.get('value') is not None]
    out = {'entryId': entry['id'], 'label': entry.get('label') or entry['id'], 'primitive': prim,
           'status': entry.get('status'), 'measurable': bool(cov.get('measured')),
           'reason': cov.get('reason'), 'inScope': cov.get('inScope', 0),
           'value': None, 'unit': entry.get('unit'), 'text': None, 'subject': None,
           'trendDirection': trend.get('direction'), 'trendText': None}

    if prim == 'unlocks':
        n, total = len(entry.get('practised') or []), entry.get('programTotal')
        out['value'], out['unit'] = n, 'movements'
        out['text'] = f'{n} of {total} movements practised' if total else f'{n} movements practised'
        out['measurable'] = bool(cov.get('inScope'))
    elif prim == 'benchmark_level':
        rows = [r for r in entry.get('benchmarks') or [] if r.get('value', r.get('latest')) is not None]
        if rows:
            target = entry.get('targetLevel')
            met = sum(1 for r in rows if r.get('met'))
            out['value'] = met if target else len(rows)
            out['text'] = (f'{met} of {len(rows)} standards at {target}' if target
                           else f'{len(rows)} standards levelled')
    elif prim == 'session_completion':
        pct = (entry.get('totals') or {}).get('pct')
        if pct is not None:
            out['value'], out['text'] = pct, f'{_num(pct)}% of sessions done'
    elif measured_points := [p for p in series if not p.get('assumed')]:
        # A duration filled in from the prescription is not a measurement:
        # "60 min last session" beside "Not enough data" read as one.
        v = measured_points[-1]['value']
        out['value'] = v
        lead = next((e for e in entry.get('exercises') or []
                     if e.get('exerciseId') == entry.get('leadExerciseId')), None)
        out['subject'] = (lead or {}).get('name')
        unit = _UNIT_WORDS.get(entry.get('unit') or '', entry.get('unit') or '')
        sep = '' if unit in ('kg', '%', 's') else ' '
        if prim == 'zone_minutes':
            out['text'] = f'{_num(v)}% of minutes in Zone 1–2'
        else:
            out['text'] = (f"{out['subject']} {_num(v)}{sep}{unit}" if out['subject']
                           else f'{_num(v)}{sep}{unit} last session')

    if out['text'] and trend.get('direction') in ('improving', 'declining', 'stable'):
        per = 'week' if prim in ('unlocks', 'zone_minutes') else 'session'
        pct = trend.get('slopePct') or 0
        out['trendText'] = ('Holding steady' if trend['direction'] == 'stable'
                            else f"{'+' if pct >= 0 else ''}{_num(pct)}% per {per}")
    return out


def _applies_in(entry, phil_cache: dict) -> list[dict]:
    """The tracks and phases of the entry's own philosophy that run a framework
    its scope names — "applies in Pentathlon Prep" for a cadence measure that
    General Practice never schedules. Empty when the scope is not framework-bound
    or names no framework a track runs."""
    frameworks = set(entry.scope.get('frameworks') or [])
    if not frameworks:
        return []
    phil = _philosophy(entry.philosophy, phil_cache)
    out = []
    for track in phases.tracks_of(phil):
        names = [ph.get('name') or ph.get('id') for ph in track.get('phases') or []
                 if ph.get('framework_id') in frameworks]
        if names:
            out.append({'trackId': track.get('id'), 'track': track.get('name') or track.get('id'),
                        'phases': names})
    return out


# ── Compatibility: the shape the old progression review served ───────────────

def _program_scope(entry, ctx: Context) -> dict:
    """How many sessions this entry measures across the whole program, and
    when the next one is — elapsed or not. Zero means the entry does not
    apply to this program at all (a pentathlon cadence in General Practice);
    the review leaves those out instead of listing them as waiting."""
    narrowed = any(entry.scope.get(k) for k in ('exercises', 'patterns', 'slot_types', 'slot_roles'))
    planned, upcoming = 0, None
    for h in spec_mod.select(entry, ctx.weeks):
        if narrowed and not h['assignments']:
            continue
        planned += 1
        d = ctx.session_date(h['week_index'], h['day'])
        if d is not None and d > ctx.today and (upcoming is None or d < upcoming):
            upcoming = d
    return {'planned': planned, 'nextDate': upcoming.isoformat() if upcoming else None}


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
                   's': 'time', 'rpm': 'reps', 'reps': 'reps', 'exercises': 'complexity'}
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
            unit = ex.get('unit') or pr.get('unit', '')
            # A symbol sits on the number ("+5kg", "+3%"); a word is spaced
            # ("+2 exercises", not "+2exercises").
            sep = '' if unit in ('kg', '%', 's', 'km', 'm') else ' '
            change = (f"{'+' if delta >= 0 else ''}{round(delta, 1)}{sep}{unit} over {max(weeks, 1)} wk"
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
