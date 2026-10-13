"""One recorded workout, analysed once, for every client.

`GET /api/health/workouts/<id>` carries the result as `analysis`. Before this
the browser (lib/hrZones.ts) and the phone (AnalyticsEngine.swift) each
computed the same numbers on the device and disagreed:

  * the phone bucketed with the old Friel edges (60/70/80/90 %), hard-coded,
    while the browser and the server read data/commons/hr_zones.json — honest
    Zone 2 at 72 % was Z2 on the web and Z3 on the phone;
  * the phone raised max HR to the workout's own peak, the browser did not;
  * the browser's age was a difference of calendar years, the phone's and the
    server's an exact age;
  * the web's session card ignored the athlete's max-HR override and edges.

The choices made here, which both clients now display rather than recompute:

  * **Max HR** is `resolve_max_hr` — override → 220 − exact age → the data
    file's default — the same number the load maths use. A workout's own peak
    never raises it: an athlete whose strap spikes would see every other
    workout's zones shift.
  * **Zone edges** are the athlete's `hrConfig.zoneBoundaries` when valid,
    else the shared edges. Only this per-workout view honours custom edges;
    the cached load maths (TRIMP over the library, PMC, intensity split) stay
    on the shared edges so frameworks' intensity distributions read alike.
  * **Zone split** is `zones.zone_fractions`: time-weighted samples with gaps
    capped at 60 s, else a normal estimate from the mean and peak HR.
    Percentages are rounded to integers that sum to 100 (largest bucket takes
    the remainder), as both clients did.
  * **TRIMP** is Banister zone-minutes from the exact split, rounded — the
    clients multiplied rounded percentages, a difference of under one point.
  * **Training effect** and **recovery hours** are the phone's thresholds,
    unchanged; the web had none.
  * **Aerobic decoupling** is Pa:HR drift between halves, as both clients
    computed it (GPS points ≥ 0.3 m/s paired with the HR sample within 10 s,
    at least 10 pairs per half).
  * **Best efforts** are the phone's fastest 1/5/10 km windows over the GPS
    speed series. The phone's "personal record" flag compared against
    whole-workout averages including the workout itself and was effectively
    never set; it is not carried over.

Pure: no Flask, no database.
"""
from __future__ import annotations

from bisect import bisect_left
from datetime import date, datetime

from src.analytics import zones
from src.analytics.primitives import resolve_max_hr

TRAINING_EFFECTS = ('Recovery', 'Maintenance', 'Base Development',
                    'Aerobic Capacity', 'Threshold', 'Highly Impacting')

_EFFORT_TARGETS = (('1 km', 1.0), ('5 km', 5.0), ('10 km', 10.0))
_SPEED_FLOOR_MPS = 0.3
_HR_MATCH_WINDOW_S = 10.0
_MIN_PAIRS_PER_HALF = 10


def zone_boundaries(profile: dict) -> tuple[list[float], str]:
    """The athlete's four zone edges when they are usable, else the shared ones."""
    raw = ((profile or {}).get('hrConfig') or {}).get('zoneBoundaries')
    try:
        edges = [float(x) for x in raw] if isinstance(raw, list) else []
    except (TypeError, ValueError):
        edges = []
    if len(edges) == 4 and all(0 < e <= 1 for e in edges) and all(a < b for a, b in zip(edges, edges[1:])):
        return edges, 'custom'
    return zones.upper_bounds(), 'shared'


def rounded_percentages(fractions: list[float]) -> list[int]:
    """Integers summing to 100; the largest bucket absorbs the rounding."""
    pct = [round(f * 100) for f in fractions]
    if sum(fractions) <= 0:
        return [0] * len(fractions)
    pct[pct.index(max(pct))] += 100 - sum(pct)
    return pct


def training_effect(trimp: int, pct: list[int]) -> str:
    """Garmin-style label from TRIMP and the zone split (the phone's rules)."""
    high_base = pct[0] + pct[1]
    mid_range = pct[1] + pct[2]
    high_anaerobic = pct[3] + pct[4]
    if trimp < 15:
        return 'Recovery'
    if trimp < 35:
        return 'Base Development' if high_base > 60 else 'Maintenance'
    if trimp < 60:
        if high_anaerobic > 40:
            return 'Threshold'
        if mid_range > 50:
            return 'Aerobic Capacity'
        return 'Maintenance'
    return 'Highly Impacting' if high_anaerobic > 40 else 'Aerobic Capacity'


def recovery_hours(trimp: int) -> int:
    if trimp < 20:
        return 8
    if trimp < 40:
        return 12
    if trimp < 70:
        return 18
    if trimp < 100:
        return 24
    return 36


def _ts(value) -> float | None:
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00')).timestamp()
    except (TypeError, ValueError):
        return None


def aerobic_decoupling(gps_track: list[dict], hr_samples: list[dict]) -> dict | None:
    """{'pct': float, 'label': 'efficient'|'moderate'|'high'} or None."""
    hr = sorted(((t, float(s['bpm'])) for s in hr_samples or []
                 if (t := _ts(s.get('timestamp'))) is not None and s.get('bpm') is not None),
                key=lambda p: p[0])
    if not hr:
        return None
    times = [t for t, _ in hr]
    pairs: list[tuple[float, float]] = []
    for pt in gps_track or []:
        speed = pt.get('speed')
        if speed is None or speed < _SPEED_FLOOR_MPS:
            continue
        t = _ts(pt.get('timestamp'))
        if t is None:
            continue
        i = bisect_left(times, t)
        candidates = [j for j in (i, i - 1) if 0 <= j < len(hr)]
        j = min(candidates, key=lambda k: abs(times[k] - t))
        if abs(times[j] - t) > _HR_MATCH_WINDOW_S:
            continue
        pairs.append((1000.0 / float(speed), hr[j][1]))
    if len(pairs) < _MIN_PAIRS_PER_HALF * 2:
        return None
    mid = len(pairs) // 2

    def ratio(half):
        pace = sum(p for p, _ in half) / len(half)
        bpm = sum(h for _, h in half) / len(half)
        return pace / bpm if bpm else 0.0

    r1, r2 = ratio(pairs[:mid]), ratio(pairs[mid:])
    if r2 == 0:
        return None
    pct = abs((r1 / r2 - 1) * 100)
    label = 'efficient' if pct < 5 else 'moderate' if pct < 10 else 'high'
    return {'pct': round(pct, 2), 'label': label}


def best_efforts(gps_track: list[dict]) -> list[dict]:
    """Fastest 1/5/10 km windows: [{'label', 'km', 'seconds', 'secPerKm'}]."""
    pts = sorted(((t, float(p['speed'])) for p in gps_track or []
                  if p.get('speed') is not None and float(p['speed']) > _SPEED_FLOOR_MPS
                  and (t := _ts(p.get('timestamp'))) is not None),
                 key=lambda p: p[0])
    if len(pts) < 10:
        return []
    cum = [(0.0, 0.0)]                                # (metres, seconds from start)
    for (t0, s0), (t1, _) in zip(pts, pts[1:]):
        cum.append((cum[-1][0] + s0 * (t1 - t0), t1 - pts[0][0]))
    total_km = cum[-1][0] / 1000.0
    out = []
    for label, km in _EFFORT_TARGETS:
        target = km * 1000.0
        if total_km < km * 0.9:
            continue
        best = None
        lo = 0
        for hi in range(1, len(cum)):
            while lo < hi and cum[hi][0] - cum[lo][0] > target:
                if cum[hi][0] - cum[lo][0] >= target * 0.95:
                    el = cum[hi][1] - cum[lo][1]
                    if el > 0:
                        best = el if best is None else min(best, el)
                lo += 1
            if cum[hi][0] - cum[lo][0] >= target * 0.95:
                el = cum[hi][1] - cum[lo][1]
                if el > 0:
                    best = el if best is None else min(best, el)
        if best is not None:
            out.append({'label': label, 'km': km, 'seconds': round(best, 1),
                        'secPerKm': round(best / km, 1)})
    return out


def analyse(workout: dict, profile: dict, today: date | None = None) -> dict:
    """The `analysis` object for one workout in the health_store shape."""
    max_hr, max_source = resolve_max_hr(profile or {}, today or date.today())
    edges, edge_source = zone_boundaries(profile or {})
    split = zones.zone_fractions(workout, max_hr, edges)
    duration = float(workout.get('durationMinutes') or 0)
    hr = workout.get('heartRate') or {}

    zone_block = None
    trimp = effect = recovery = None
    if split['method'] != 'none':
        pct = rounded_percentages(split['fractions'])
        minutes = [round(f * duration, 2) for f in split['fractions']]
        zone_block = {'method': split['method'], 'pct': pct, 'minutes': minutes}
        if duration > 0:
            trimp = int(round(sum(m * w for m, w in zip(
                [f * duration for f in split['fractions']], zones.banister_weights()))))
            effect = training_effect(trimp, pct)
            recovery = recovery_hours(trimp)

    gps = workout.get('gpsTrack') or []
    return {
        'version': zones.version(),
        'maxHr': int(round(max_hr)),
        'maxHrSource': max_source,
        'zoneBoundaries': edges,
        'zoneBoundariesSource': edge_source,
        'zones': zone_block,
        'trimp': trimp,
        'trainingEffect': effect,
        'recoveryHours': recovery,
        'decoupling': aerobic_decoupling(gps, hr.get('samples') or []),
        'bestEfforts': best_efforts(gps),
    }
