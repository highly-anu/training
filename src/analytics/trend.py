"""Trend and stall over a progress series.

Replaces progression_tracker._trend_direction, which compared the mean of the
first third of the points to the mean of the last third — with three points
that is just point 1 against point 3, and it swung wildly when one week was
missing. This fits a least-squares slope over the non-deload points instead,
expressed as a percentage of the series' first value per point, so a 2.5 kg
weekly gain on a 100 kg squat and a 5-minute gain on a 200-minute long run
read on the same scale.

Deload points are excluded from the fit and from stall windows but never from
the series itself: the athlete should see the dip, and should not be told they
regressed because the program asked them to.
"""
from __future__ import annotations

from dataclasses import dataclass

IMPROVING_PCT_PER_POINT = 1.0     # slope ≥ +1 %/point → improving; ≤ −1 % → declining.
                                  # Points are sessions for load series: a 2.5 kg/week squat
                                  # at two sessions a week is 1.25 %/session, and is progress.
MIN_POINTS = 3


@dataclass(frozen=True)
class Point:
    x: float            # week number, or session ordinal
    value: float
    is_deload: bool = False


@dataclass(frozen=True)
class Trend:
    direction: str      # improving | stable | declining | insufficient_data
    slope: float        # units per point
    slope_pct: float    # % of first value per point
    points_used: int


def fit(points: list[Point], min_points: int = MIN_POINTS) -> Trend:
    live = [p for p in points if not p.is_deload and p.value is not None]
    if len(live) < min_points:
        return Trend('insufficient_data', 0.0, 0.0, len(live))

    xs = [p.x for p in live]
    ys = [float(p.value) for p in live]
    n = len(live)
    sx, sy = sum(xs), sum(ys)
    sxy = sum(x * y for x, y in zip(xs, ys))
    sxx = sum(x * x for x in xs)
    denom = n * sxx - sx * sx
    slope = (n * sxy - sx * sy) / denom if denom else 0.0

    base = abs(ys[0]) or 1.0
    slope_pct = slope / base * 100.0
    if slope_pct >= IMPROVING_PCT_PER_POINT:
        direction = 'improving'
    elif slope_pct <= -IMPROVING_PCT_PER_POINT:
        direction = 'declining'
    else:
        direction = 'stable'
    return Trend(direction, slope, slope_pct, n)


def stalled(points: list[Point], sessions: int, tolerance_pct: float = 1.0) -> bool:
    """True when the last `sessions` non-deload points show no progress.

    Starting Strength's rule — "3 consecutive sessions without progress" — is
    per session, not per week, so callers pass session-ordinal points. The
    window needs `sessions + 1` points: a stall is `sessions` consecutive
    attempts that failed to beat the one before them.
    """
    live = [p for p in points if not p.is_deload and p.value is not None]
    if sessions < 1 or len(live) < sessions + 1:
        return False
    window = [float(p.value) for p in live[-(sessions + 1):]]
    first = window[0]
    tol = abs(first) * tolerance_pct / 100.0
    return max(window) - first <= max(tol, 0.5)


def status(trend: Trend, expected_slope: float | None, base: float | None) -> str:
    """ahead | on_track | behind | stable_by_design | insufficient_data

    Relative to what the methodology expects the slope to be, when it says. A
    linear-load block expects increment × sessions per week; anything under
    half of that is behind. With no expectation, the trend's own direction is
    the status, and 'stable' is reported as such rather than as failure —
    holding a load through a base block is often the plan.
    """
    if trend.direction == 'insufficient_data':
        return 'insufficient_data'
    if expected_slope is None or not base:
        return {'improving': 'on_track', 'stable': 'stable_by_design',
                'declining': 'behind'}[trend.direction]
    expected_pct = expected_slope / abs(base) * 100.0
    if expected_pct <= 0:
        return 'on_track'
    ratio = trend.slope_pct / expected_pct
    if ratio >= 1.10:
        return 'ahead'
    if ratio >= 0.50:
        return 'on_track'
    return 'behind'
