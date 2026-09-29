"""Aerobic primitives: where the heart rate went, and how efficiently.

`zone_minutes` is the intensity split — minutes in each framework bucket
against the framework's declared `intensity_distribution`. A session
contributes to the HR buckets **or**, when it is strength-family work with no
strap, to `max_effort`; never both. Sessions with neither are `unclassified`
and counted, not dropped.

`aerobic_efficiency` is the server twin of lib/hrZones.ts::computeAerobicDecoupling
plus a metres-per-beat index, from GPS + HR of matched workouts, and only for
running and riding: pace ÷ HR is meaningless for a hike with elevation, which
is Uphill's signature session.
"""
from __future__ import annotations

import bisect
from datetime import datetime

from src.analytics import trend as trend_mod
from src.analytics import zones
from src.analytics.families import is_strength
from src.analytics.primitives import (coverage, max_hr_for, primitive, result, scoped_hits,
                                      series_point, trend_dict)

BUCKETS = ('zone1_2_pct', 'zone3_pct', 'zone4_5_pct', 'max_effort_pct')
ON_TARGET_TOLERANCE_PTS = 10.0
RUN_RIDE_TOKENS = ('run', 'ride', 'cycl', 'bike', 'row')


def _framework_id(week: dict) -> str | None:
    fw = week.get('framework')
    return fw.get('id') if isinstance(fw, dict) else fw


@primitive('zone_minutes')
def zone_minutes(entry, ctx) -> dict:
    hits = scoped_hits(entry, ctx)
    max_hr = max_hr_for(ctx)
    weeks: dict = {}
    by_fw: dict = {}
    in_scope = measured = 0
    methods: dict = {}
    for h in hits:
        if not h['completed']:
            continue
        in_scope += 1
        wk = weeks.setdefault(h['week_number'], {
            'week': h['week_number'], 'isDeload': h['is_deload'],
            'frameworkId': _framework_id(h['week']),
            **{b: 0.0 for b in BUCKETS}, 'unclassified': 0.0, 'sessions': 0})
        wk['sessions'] += 1
        minutes, _ = ctx.duration_minutes(h)
        w = h['workout']
        # Strength-family work is max-effort by definition and is counted as
        # such even when it wore a strap; otherwise a lifting session with HR
        # would land in zone1_2 AND its minutes would be strength minutes.
        if is_strength(h['session'].get('modality')):
            wk['max_effort_pct'] += minutes
            measured += 1
            methods['strength_minutes'] = methods.get('strength_minutes', 0) + 1
            continue
        split = zones.zone_minutes(w, max_hr) if w else {'method': 'none', 'minutes': [0] * 5}
        if split['method'] != 'none':
            for b, v in zones.to_framework_buckets(split['minutes']).items():
                wk[b] += v
            measured += 1
            methods[split['method']] = methods.get(split['method'], 0) + 1
        else:
            wk['unclassified'] += minutes

    series, expected = [], []
    deviation_sum = {b: 0.0 for b in BUCKETS}
    weeks_out = []
    for wk in sorted(weeks.values(), key=lambda w: w['week']):
        classified = sum(wk[b] for b in BUCKETS)
        fw = ctx.frameworks.get(wk['frameworkId'] or '') or {}
        planned = fw.get('intensity_distribution') or {}
        shares = {b: (round(100.0 * wk[b] / classified, 1) if classified else None) for b in BUCKETS}
        planned_pct = {b: round(100.0 * float(planned.get(b, 0)), 1) for b in BUCKETS} if planned else None
        wk_out = dict(wk, classifiedMinutes=round(classified), actualPct=shares, plannedPct=planned_pct)
        for b in BUCKETS:
            wk_out[b] = round(wk_out[b])
        wk_out['unclassified'] = round(wk_out['unclassified'])
        weeks_out.append(wk_out)
        agg = by_fw.setdefault(wk['frameworkId'], {'frameworkId': wk['frameworkId'],
                                                   **{b: 0.0 for b in BUCKETS}, 'plannedPct': planned_pct})
        for b in BUCKETS:
            agg[b] += wk[b]
        if classified:
            series.append({'week': wk['week'], 'x': wk['week'], 'value': shares['zone1_2_pct'],
                           'isDeload': wk['isDeload'], 'classifiedMinutes': round(classified)})
        expected.append({'week': wk['week'], 'x': wk['week'],
                         'value': planned_pct['zone1_2_pct'] if planned_pct else None})

    by_fw_out = []
    max_dev = 0.0
    for agg in by_fw.values():
        classified = sum(agg[b] for b in BUCKETS)
        actual = {b: (round(100.0 * agg[b] / classified, 1) if classified else None) for b in BUCKETS}
        dev = None
        if classified and agg['plannedPct']:
            dev = {b: round(actual[b] - agg['plannedPct'][b], 1) for b in BUCKETS}
            max_dev = max(max_dev, max(abs(v) for v in dev.values()))
        by_fw_out.append({'frameworkId': agg['frameworkId'], 'classifiedMinutes': round(classified),
                          'actualPct': actual, 'plannedPct': agg['plannedPct'], 'deviationPts': dev})

    t = trend_mod.fit([trend_mod.Point(p['x'], p['value'], p['isDeload']) for p in series])
    if not series:
        status = 'insufficient_data'
    elif any(f['plannedPct'] for f in by_fw_out):
        status = 'on_target' if max_dev <= ON_TARGET_TOLERANCE_PTS else 'off_target'
    else:
        status = 'no_target'
    return result(entry, metric='zone1_2_share_pct', unit='%', series=series, expected=expected,
                  status=status, trend=trend_dict(t),
                  coverage_=coverage(in_scope, measured, 'no_heart_rate'),
                  weeks=weeks_out, byFramework=by_fw_out, maxHr=max_hr, methods=methods,
                  maxDeviationPts=round(max_dev, 1))


# ── aerobic efficiency ───────────────────────────────────────────────────────

def _ts(value) -> float | None:
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00')).timestamp()
    except (TypeError, ValueError):
        return None


def decoupling(gps_track: list, hr_samples: list) -> dict | None:
    """Pa:HR drift between the two halves of a session; port of the TS."""
    MIN_PAIRS_PER_HALF, SPEED_THRESHOLD, WINDOW = 10, 0.3, 10.0
    hr = sorted(((t, float(s['bpm'])) for s in hr_samples
                 if (t := _ts(s.get('timestamp'))) is not None and s.get('bpm') is not None))
    if not hr:
        return None
    hr_ts = [t for t, _ in hr]
    pairs = []
    for pt in gps_track or []:
        speed = pt.get('speed')
        if speed is None or float(speed) < SPEED_THRESHOLD:
            continue
        t = _ts(pt.get('timestamp'))
        if t is None:
            continue
        i = bisect.bisect_left(hr_ts, t)
        cands = [c for c in (i, i - 1) if 0 <= c < len(hr)]
        nearest = min(cands, key=lambda c: abs(hr_ts[c] - t))
        if abs(hr_ts[nearest] - t) > WINDOW:
            continue
        pairs.append((1000.0 / float(speed), hr[nearest][1]))
    if len(pairs) < MIN_PAIRS_PER_HALF * 2:
        return None
    mid = len(pairs) // 2
    h1, h2 = pairs[:mid], pairs[mid:]
    mean = lambda xs: sum(xs) / len(xs)  # noqa: E731
    r1 = mean([p for p, _ in h1]) / mean([b for _, b in h1])
    r2 = mean([p for p, _ in h2]) / mean([b for _, b in h2])
    if r2 == 0:
        return None
    pct = abs((r1 / r2 - 1) * 100)
    return {'pct': round(pct, 1), 'label': 'efficient' if pct < 5 else 'moderate' if pct < 10 else 'high'}


def _is_run_or_ride(workout: dict) -> bool:
    kind = ((workout or {}).get('activityType') or '').lower()
    return any(tok in kind for tok in RUN_RIDE_TOKENS)


@primitive('aerobic_efficiency')
def aerobic_efficiency(entry, ctx) -> dict:
    hits = scoped_hits(entry, ctx)
    series = []
    in_scope = measured = 0
    skipped_terrain = 0
    for h in hits:
        if not h['completed']:
            continue
        in_scope += 1
        w = h['workout']
        if not w:
            continue
        gps = w.get('gpsTrack') or []
        samples = (w.get('heartRate') or {}).get('samples') or []
        if not gps or not samples:
            continue
        if not _is_run_or_ride(w):
            skipped_terrain += 1
            continue
        speeds = [float(p['speed']) for p in gps if isinstance(p.get('speed'), (int, float)) and float(p['speed']) >= 0.3]
        bpms = [float(s['bpm']) for s in samples if s.get('bpm')]
        if not speeds or not bpms:
            continue
        avg_speed = sum(speeds) / len(speeds)
        avg_hr = sum(bpms) / len(bpms)
        metres_per_beat = round(avg_speed * 60.0 / avg_hr, 3)
        dec = decoupling(gps, samples)
        series.append(series_point(h, metres_per_beat, avgSpeedMps=round(avg_speed, 2),
                                   avgHr=round(avg_hr), decouplingPct=dec['pct'] if dec else None,
                                   decouplingLabel=dec['label'] if dec else None,
                                   activityType=w.get('activityType')))
        measured += 1
    t = trend_mod.fit([trend_mod.Point(p['x'], p['value'], p['isDeload']) for p in series])
    status = trend_mod.status(t, None, series[0]['value'] if series else None) if series else 'insufficient_data'
    evidence = []
    if skipped_terrain:
        evidence.append(f'{skipped_terrain} session(s) skipped: pace ÷ HR is not meaningful for hiking or rucking.')
    return result(entry, metric='metres_per_beat', unit='m/beat', series=series, status=status,
                  trend=trend_dict(t), coverage_=coverage(in_scope, measured, 'no_gps_hr'),
                  evidence=evidence)
