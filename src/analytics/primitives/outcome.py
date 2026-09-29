"""Outcome primitives: rounds, minutes, kilometres, seconds held, reps per minute.

These read the `ExercisePerformance`-level fields — `rounds`, `durationSec`,
`distanceKm` — that src/progression_tracker.py has always read and that, until
the OutcomeLogger, nothing ever wrote. Each reports its coverage honestly: a
density-based methodology on a program where no rounds have been logged gets
`rounds_not_logged`, not a blank.
"""
from __future__ import annotations

from src.analytics import trend as trend_mod
from src.analytics.primitives import (coverage, expected_value, primitive, result, scoped_hits,
                                      series_point, trend_dict)

_MEASURED_SOURCES = ('workout', 'timeline', 'logged')


def _load(ea: dict) -> dict:
    return ea.get('load') or {}


def _fit(points: list[dict]):
    return trend_mod.fit([trend_mod.Point(p['x'], p['value'], p['isDeload']) for p in points])


def _ratio_status(actual: float, planned: float) -> str:
    if planned <= 0:
        return 'on_track'
    r = actual / planned
    return 'ahead' if r >= 1.10 else 'on_track' if r >= 0.85 else 'behind'


@primitive('rounds')
def rounds(entry, ctx) -> dict:
    hits = scoped_hits(entry, ctx)
    series, expected = [], []
    in_scope = measured = 0
    for h in hits:
        if not h['completed'] or not h['assignments']:
            continue
        in_scope += 1
        logged = (h['log'] or {}).get('exercises') or {}
        got = False
        for ea in h['assignments']:
            ex_id = ea['exercise']['id']
            target = expected_value(entry, ea, ctx, h['week'])
            if target is None:
                t = _load(ea).get('target_rounds')
                target = float(t) if isinstance(t, (int, float)) else None
            expected.append({'week': h['week_number'], 'x': h['ordinal'], 'value': target})
            r = (logged.get(ex_id) or {}).get('rounds')
            if isinstance(r, (int, float)):
                series.append(series_point(h, float(r), exerciseId=ex_id, target=target))
                got = True
        if got:
            measured += 1
    t = _fit(series)
    planned = sum(e['value'] for e in expected if e['value'])
    actual = sum(p['value'] for p in series if p.get('target'))
    status = _ratio_status(actual, sum(p['target'] for p in series if p.get('target'))) if series else 'insufficient_data'
    return result(entry, metric='rounds', unit='rounds', series=series, expected=expected,
                  status=status, trend=trend_dict(t),
                  coverage_=coverage(in_scope, measured, 'rounds_not_logged'),
                  totals={'planned': planned, 'actual': actual})


@primitive('duration')
def duration(entry, ctx) -> dict:
    """Session minutes against the prescription, with the sources that
    produced them. Aerobic entries also get weekly totals, the longest
    session, vertical metres (from matched workouts) and pack load — Uphill's
    real specificity signals."""
    hits = scoped_hits(entry, ctx)
    series, expected = [], []
    weekly: dict = {}
    in_scope = measured = 0
    vertical, pack = [], []
    for h in hits:
        if not h['completed']:
            continue
        in_scope += 1
        planned = sum(float(_load(ea).get('duration_minutes') or 0) for ea in h['assignments'])
        if planned <= 0:
            planned = float((h['session'].get('archetype') or {}).get('duration_estimate_minutes') or 0)
            if h['is_deload']:
                planned *= 0.7
        logged = (h['log'] or {}).get('exercises') or {}
        logged_secs = sum(float((logged.get(ea['exercise']['id']) or {}).get('durationSec') or 0)
                          for ea in h['assignments'])
        if logged_secs > 0:
            minutes, source = logged_secs / 60.0, 'logged'
        else:
            minutes, source = ctx.duration_minutes(h)
        is_measured = source in _MEASURED_SOURCES
        if is_measured:
            measured += 1
        expected.append({'week': h['week_number'], 'x': h['ordinal'], 'value': planned or None})
        series.append(series_point(h, round(minutes, 1), source=source, assumed=not is_measured,
                                   planned=planned))
        wk = weekly.setdefault(h['week_number'], {'week': h['week_number'], 'planned': 0.0,
                                                  'actual': 0.0, 'assumed': 0.0, 'sessions': 0})
        wk['planned'] += planned
        wk['actual'] += minutes
        wk['sessions'] += 1
        if not is_measured:
            wk['assumed'] += minutes
        w = h['workout']
        if w and (w.get('elevation') or {}).get('gain'):
            vertical.append(series_point(h, float(w['elevation']['gain'])))
        loads = [float(_load(ea)['pack_load_kg']) for ea in h['assignments']
                 if isinstance(_load(ea).get('pack_load_kg'), (int, float))]
        if loads:
            pack.append(series_point(h, max(loads)))

    real = [p for p in series if not p['assumed']]
    t = _fit(real)
    if real:
        status = _ratio_status(sum(p['value'] for p in real), sum(p['planned'] for p in real))
    else:
        status = 'insufficient_data'
    weeks = [dict(w, planned=round(w['planned']), actual=round(w['actual']), assumed=round(w['assumed']))
             for w in sorted(weekly.values(), key=lambda w: w['week'])]
    longest_planned = max((e['value'] for e in expected if e['value']), default=None)
    longest_actual = max((p['value'] for p in real), default=None)
    return result(entry, metric='session_minutes', unit='min', series=series, expected=expected,
                  status=status, trend=trend_dict(t),
                  coverage_=coverage(in_scope, measured, 'duration_not_logged'),
                  weeks=weeks, longest={'planned': longest_planned, 'actual': longest_actual},
                  vertical=vertical, packLoad=pack)


@primitive('distance')
def distance(entry, ctx) -> dict:
    hits = scoped_hits(entry, ctx)
    series, expected = [], []
    in_scope = measured = 0
    for h in hits:
        if not h['completed']:
            continue
        in_scope += 1
        planned = 0.0
        for ea in h['assignments']:
            ld = _load(ea)
            if isinstance(ld.get('distance_km'), (int, float)):
                planned += float(ld['distance_km'])
            elif isinstance(ld.get('distance_m'), (int, float)):
                planned += float(ld['distance_m']) / 1000.0
        expected.append({'week': h['week_number'], 'x': h['ordinal'], 'value': planned or None})
        km = None
        source = None
        w = h['workout']
        d = (w or {}).get('distance') or {}
        if isinstance(d.get('value'), (int, float)) and d['value'] > 0:
            unit = (d.get('unit') or 'km').lower()
            km = float(d['value']) / (1000.0 if unit in ('m', 'meters', 'metres') else 1.0)
            source = 'workout'
        else:
            logged = (h['log'] or {}).get('exercises') or {}
            total = sum(float((logged.get(ea['exercise']['id']) or {}).get('distanceKm') or 0)
                        for ea in h['assignments'])
            if total > 0:
                km, source = total, 'logged'
        if km is not None:
            measured += 1
            minutes, _ = ctx.duration_minutes(h)
            pace = round(minutes / km, 2) if km > 0 and minutes > 0 else None
            series.append(series_point(h, round(km, 2), source=source, planned=planned or None,
                                       paceMinPerKm=pace))
    t = _fit(series)
    status = (_ratio_status(sum(p['value'] for p in series),
                            sum(p['planned'] or 0 for p in series)) if series else 'insufficient_data')
    return result(entry, metric='distance_km', unit='km', series=series, expected=expected,
                  status=status, trend=trend_dict(t),
                  coverage_=coverage(in_scope, measured, 'distance_not_logged'))


@primitive('hold_seconds')
def hold_seconds(entry, ctx) -> dict:
    """Longest completed hold per session. A proxy for range: the ROM itself is
    never captured anywhere, and the coverage reason says so when nothing is."""
    hits = scoped_hits(entry, ctx)
    series, expected = [], []
    in_scope = measured = 0
    for h in hits:
        if not h['completed'] or not h['assignments']:
            continue
        in_scope += 1
        logged = (h['log'] or {}).get('exercises') or {}
        got = False
        for ea in h['assignments']:
            ex_id = ea['exercise']['id']
            target = expected_value(entry, ea, ctx, h['week'])
            if target is None:
                hs = _load(ea).get('hold_seconds')
                target = float(hs) if isinstance(hs, (int, float)) else None
            expected.append({'week': h['week_number'], 'x': h['ordinal'], 'value': target})
            holds = [float(s['durationSeconds']) for s in ((logged.get(ex_id) or {}).get('sets') or [])
                     if s.get('completed') and isinstance(s.get('durationSeconds'), (int, float))]
            if holds:
                series.append(series_point(h, max(holds), exerciseId=ex_id, target=target))
                got = True
        if got:
            measured += 1
    t = _fit(series)
    status = (_ratio_status(sum(p['value'] for p in series if p.get('target')),
                            sum(p['target'] for p in series if p.get('target')))
              if any(p.get('target') for p in series) else
              trend_mod.status(t, None, series[0]['value'] if series else None))
    return result(entry, metric='hold_seconds', unit='s', series=series, expected=expected,
                  status=status if series else 'insufficient_data', trend=trend_dict(t),
                  coverage_=coverage(in_scope, measured, 'hold_not_logged'),
                  evidence=['Hold time is a proxy: range of motion itself is not captured.'])


@primitive('rate')
def rate(entry, ctx) -> dict:
    """Reps per minute — the kettlebell pentathlon's currency. Needs timed sets:
    reps and seconds on the same set, or a logged duration for the exercise."""
    hits = scoped_hits(entry, ctx)
    series, expected = [], []
    in_scope = measured = 0
    target = entry.rpm_target
    for h in hits:
        if not h['completed'] or not h['assignments']:
            continue
        in_scope += 1
        logged = (h['log'] or {}).get('exercises') or {}
        got = False
        for ea in h['assignments']:
            ex_id = ea['exercise']['id']
            ex_log = logged.get(ex_id) or {}
            sets = [s for s in (ex_log.get('sets') or []) if s.get('completed')]
            reps = sum(int(s['repsActual']) for s in sets if s.get('repsActual'))
            secs = sum(float(s['durationSeconds']) for s in sets
                       if isinstance(s.get('durationSeconds'), (int, float)))
            if secs <= 0 and isinstance(ex_log.get('durationSec'), (int, float)):
                secs = float(ex_log['durationSec'])
            expected.append({'week': h['week_number'], 'x': h['ordinal'], 'value': target})
            if reps > 0 and secs > 0:
                series.append(series_point(h, round(reps / (secs / 60.0), 1), exerciseId=ex_id,
                                           reps=reps, seconds=secs, target=target))
                got = True
        if got:
            measured += 1
    t = _fit(series)
    if series and target:
        status = _ratio_status(sum(p['value'] for p in series) / len(series), target)
    else:
        status = trend_mod.status(t, None, series[0]['value'] if series else None) if series else 'insufficient_data'
    return result(entry, metric='reps_per_minute', unit='rpm', series=series, expected=expected,
                  status=status, trend=trend_dict(t),
                  coverage_=coverage(in_scope, measured, 'timed_sets_not_logged'))
