"""Heart-rate zones, from the one file the server and the browser both read.

data/commons/hr_zones.json carries the zone edges (fractions of max HR), the
Banister weights TRIMP uses, and the map from the five zones to the three
buckets every framework's `intensity_distribution` is written in. Bucketing a
workout here and in frontend/src/lib/hrZones.ts must agree sample for sample;
test_hr_zone_parity.py asserts that against a shared fixture.

Two implementations of the per-workout zone split, matching the existing
behaviour in api._calc_workout_trimp:

  * with ≥ 2 timestamped samples, integrate time per zone (gaps capped at 60 s);
  * otherwise estimate from the session's mean and peak HR with a normal model,
    and say so (`method: summary_estimate`) — the client already distinguishes
    the two and analytics must not present an estimate as a measurement.
"""
from __future__ import annotations

import json
import math
from datetime import datetime
from functools import lru_cache
from pathlib import Path

_PATH = Path(__file__).resolve().parent.parent.parent / 'data' / 'commons' / 'hr_zones.json'

ZONE_KEYS = ('z1', 'z2', 'z3', 'z4', 'z5')
SAMPLE_GAP_CAP_SEC = 60.0


@lru_cache(maxsize=1)
def config() -> dict:
    with open(_PATH, encoding='utf-8') as f:
        return json.load(f)


def version() -> int:
    """Bump in the data file when edges change; cached workout metrics key on it."""
    return int(config()['version'])


def upper_bounds() -> list[float]:
    return list(config()['upper_bounds'])


def banister_weights() -> list[float]:
    return list(config()['banister_weights'])


def default_max_hr() -> int:
    return int(config().get('default_max_hr', 190))


def assign_zone(bpm: float, max_hr: float, bounds: list[float] | None = None) -> int:
    """0-4 for Z1-Z5."""
    pct = bpm / max_hr if max_hr else 0
    for i, edge in enumerate(bounds or upper_bounds()):
        if pct < edge:
            return i
    return 4


def zone_fractions(workout: dict, max_hr: float) -> dict:
    """{'fractions': [5 floats summing to 1], 'method': 'samples'|'summary_estimate'|'none',
        'measured_seconds': float}

    `workout` is the health_store shape: heartRate.samples[{timestamp,bpm}],
    heartRate.avg, heartRate.max, durationMinutes.
    """
    hr = workout.get('heartRate') or {}
    samples = hr.get('samples') or []

    if len(samples) >= 2:
        by_zone = [0.0] * 5
        total = 0.0
        try:
            ordered = sorted(samples, key=lambda s: s['timestamp'])
            for a, b in zip(ordered, ordered[1:]):
                dt = _seconds_between(a['timestamp'], b['timestamp'])
                if dt <= 0:
                    continue
                dt = min(dt, SAMPLE_GAP_CAP_SEC)
                by_zone[assign_zone(float(a['bpm']), max_hr)] += dt
                total += dt
        except (KeyError, TypeError, ValueError):
            total = 0.0
        if total > 0:
            return {'fractions': [t / total for t in by_zone], 'method': 'samples',
                    'measured_seconds': total}

    avg = hr.get('avg')
    if avg:
        peak = hr.get('max') or max_hr
        std = max(float(peak) - float(avg), 1.0) / 2.5
        edges_bpm = [0.0] + [e * max_hr for e in upper_bounds()] + [math.inf]
        raw = []
        for lo, hi in zip(edges_bpm, edges_bpm[1:]):
            p_lo = 0.0 if lo == 0 else _norm_cdf(lo, float(avg), std)
            p_hi = 1.0 if hi == math.inf else _norm_cdf(hi, float(avg), std)
            raw.append(max(0.0, p_hi - p_lo))
        total = sum(raw) or 1.0
        return {'fractions': [p / total for p in raw], 'method': 'summary_estimate',
                'measured_seconds': 0.0}

    return {'fractions': [0.0] * 5, 'method': 'none', 'measured_seconds': 0.0}


def zone_minutes(workout: dict, max_hr: float) -> dict:
    """Minutes per zone for one workout, plus how they were obtained — from
    the row's cached metrics when they were computed for this max HR and
    these edges, else from the series (or the summary estimate)."""
    cached = cached_metrics(workout, max_hr)
    if cached is not None:
        return {
            'minutes': [float(x) for x in cached['zoneMinutes']],
            'method': cached.get('method', 'samples'),
            'total_minutes': float(cached.get('totalMinutes') or workout.get('durationMinutes') or 0),
        }
    return _zone_minutes_raw(workout, max_hr)


def _zone_minutes_raw(workout: dict, max_hr: float) -> dict:
    """Minutes per zone computed from what the row carries, cache ignored."""
    split = zone_fractions(workout, max_hr)
    minutes = float(workout.get('durationMinutes') or 0)
    return {
        'minutes': [f * minutes for f in split['fractions']],
        'method': split['method'],
        'total_minutes': minutes,
    }


def trimp(workout: dict, max_hr: float) -> float:
    """Banister zone-minute TRIMP. 0 for a session with no HR — a strength
    session without a strap contributes nothing, which is why the intensity
    section counts strength minutes separately rather than through HR."""
    zm = zone_minutes(workout, max_hr)
    if zm['method'] == 'none':
        return 0.0
    return sum(m * w for m, w in zip(zm['minutes'], banister_weights()))


def to_framework_buckets(minutes_by_zone: list[float]) -> dict[str, float]:
    """Five zones → the three buckets frameworks declare (zone1_2, zone3, zone4_5)."""
    buckets = config()['framework_buckets']
    idx = {k: i for i, k in enumerate(ZONE_KEYS)}
    return {bucket: sum(minutes_by_zone[idx[z]] for z in zones)
            for bucket, zones in buckets.items()}


def _seconds_between(a: str, b: str) -> float:
    ta = datetime.fromisoformat(str(a).replace('Z', '+00:00')).timestamp()
    tb = datetime.fromisoformat(str(b).replace('Z', '+00:00')).timestamp()
    return tb - ta


def _norm_cdf(x: float, mean: float, sigma: float) -> float:
    return 0.5 * (1.0 + math.erf((x - mean) / (sigma * math.sqrt(2))))


# ── Per-workout cache ─────────────────────────────────────────────────────────
# A workout's zone minutes depend on its HR series, the athlete's max HR and
# the zone edges' version — nothing else. health_store keeps the result on
# the row (`workouts.metrics`), so the load maths over a whole library reads
# one small object per workout instead of every HR series and GPS track;
# api._workouts_for_load fills the cache a few rows at a time.

def compute_metrics(workout: dict, max_hr: float) -> dict:
    """What to cache for one workout, computed from its series (or, without
    one, from its summary) — never from an existing cache."""
    zm = _zone_minutes_raw(workout, max_hr)
    t = 0.0 if zm['method'] == 'none' else sum(m * w for m, w in zip(zm['minutes'], banister_weights()))
    return {
        'version': version(),
        'maxHr': int(round(float(max_hr))),
        'method': zm['method'],
        'zoneMinutes': [round(m, 3) for m in zm['minutes']],
        'totalMinutes': round(float(zm['total_minutes']), 3),
        'trimp': round(t, 3),
    }


def cached_metrics(workout: dict, max_hr: float) -> dict | None:
    """The row's cached metrics if they were computed for this max HR and
    these zone edges; None when absent, stale or malformed."""
    m = workout.get('metrics')
    if not isinstance(m, dict):
        return None
    try:
        if int(m.get('version', -1)) != version():
            return None
        if int(m.get('maxHr', -1)) != int(round(float(max_hr))):
            return None
        if not isinstance(m.get('zoneMinutes'), list) or len(m['zoneMinutes']) != 5:
            return None
        float(m.get('trimp', 0))
    except (TypeError, ValueError):
        return None
    return m
