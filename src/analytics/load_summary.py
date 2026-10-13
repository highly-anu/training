"""Analytics ▸ Load's totals, mixes and consistency, for both clients.

`GET /api/health/load/summary` serves this. The web's Load tab and the
phone's (it was "Overview") each summed the same workouts on the device,
with small differences that made the two screens disagree: the phone read
distance without its unit, the web's zone minutes were an estimate from the
mean HR only, the phone's from the samples it happened to have, with its own
zone edges. Here every number reads the workout summaries the load routes
already read (api._workouts_for_load — never a series), and zone minutes come
from the per-workout metrics cache, so they add up to the same TRIMP the PMC
and weekly-load charts use.

Windows are the athlete's days: the client sends its local `today`, because
the server's date is UTC.

Pure: no Flask, no database.
"""
from __future__ import annotations

from datetime import date, timedelta

from src.analytics import zones

PERIOD_DAYS = {'7d': 7, '30d': 30, '3m': 90, '1y': 365, 'all': None}
CONSISTENCY_WEEKS = 12
FOCUS_DAYS = 28
TOP_ACTIVITIES = 8


def _day(w: dict) -> date | None:
    try:
        return date.fromisoformat(str(w.get('date'))[:10])
    except (TypeError, ValueError):
        return None


def _km(w: dict) -> float | None:
    d = w.get('distance')
    if not isinstance(d, dict) or d.get('value') is None:
        return None
    try:
        v = float(d['value'])
    except (TypeError, ValueError):
        return None
    return v / 1000 if d.get('unit') == 'm' else v


def _num(v) -> float | None:
    try:
        return None if v is None else float(v)
    except (TypeError, ValueError):
        return None


def _totals(ws: list[dict]) -> dict:
    minutes = sum(float(w.get('durationMinutes') or 0) for w in ws)
    kms = [k for w in ws if (k := _km(w)) is not None]
    gains = [g for w in ws if (g := _num((w.get('elevation') or {}).get('gain'))) is not None]
    losses = [x for w in ws if (x := _num((w.get('elevation') or {}).get('loss'))) is not None]
    cals = [c for w in ws if (c := _num(w.get('calories'))) is not None]
    return {
        'sessions': len(ws),
        'minutes': round(minutes, 1),
        # None, not 0, when no workout in the window carries the measure.
        'distanceKm': round(sum(kms), 2) if kms else None,
        'elevationGainM': round(sum(gains)) if gains else None,
        'elevationLossM': round(sum(losses)) if losses else None,
        'calories': round(sum(cals)) if cals else None,
    }


def summarize(workouts: list[dict], max_hr: float, period: str, today: date) -> dict:
    """The Load tab's document for one period ending on `today` (inclusive)."""
    days = PERIOD_DAYS.get(period, 30)
    dated = [(d, w) for w in workouts if (d := _day(w)) is not None and d <= today]
    if days is None:
        current = [w for _, w in dated]
        prior = None
        start = min((d for d, _ in dated), default=today)
    else:
        start = today - timedelta(days=days)
        current = [w for d, w in dated if d >= start]
        prior_start = start - timedelta(days=days)
        prior = _totals([w for d, w in dated if prior_start <= d < start])

    total_min = sum(float(w.get('durationMinutes') or 0) for w in current)

    by_modality: dict[str | None, float] = {}
    for w in current:
        key = w.get('inferredModalityId') or None
        by_modality[key] = by_modality.get(key, 0.0) + float(w.get('durationMinutes') or 0)
    modalities = sorted(
        ({'id': k, 'minutes': round(m, 1), 'pct': round(m / total_min * 100) if total_min else 0}
         for k, m in by_modality.items()),
        key=lambda r: -r['minutes'])

    by_activity: dict[str, dict] = {}
    for w in current:
        raw = str(w.get('activityType') or 'other')
        a = by_activity.setdefault(raw.lower(), {'activityType': raw, 'minutes': 0.0, 'sessions': 0,
                                                 'modalityId': w.get('inferredModalityId')})
        a['minutes'] += float(w.get('durationMinutes') or 0)
        a['sessions'] += 1
    activities = sorted(by_activity.values(), key=lambda a: -a['minutes'])[:TOP_ACTIVITIES]
    for a in activities:
        a['minutes'] = round(a['minutes'], 1)

    # Monday-anchored weeks, the last twelve, regardless of the period.
    this_monday = today - timedelta(days=today.weekday())
    consistency = []
    for i in range(CONSISTENCY_WEEKS - 1, -1, -1):
        monday = this_monday - timedelta(weeks=i)
        sunday = monday + timedelta(days=6)
        consistency.append({'weekStart': monday.isoformat(),
                            'sessions': sum(1 for d, _ in dated if monday <= d <= sunday)})

    zone_totals = [0.0] * 5
    measured = estimated = 0
    for w in current:
        zm = zones.zone_minutes(w, max_hr)
        if zm['method'] == 'none':
            continue
        measured += zm['method'] == 'samples'
        estimated += zm['method'] != 'samples'
        for i, m in enumerate(zm['minutes']):
            zone_totals[i] += m

    focus = {'base': 0.0, 'threshold': 0.0, 'anaerobic': 0.0}
    focus_start = today - timedelta(days=FOCUS_DAYS)
    for d, w in dated:
        if d < focus_start:
            continue
        zm = zones.zone_minutes(w, max_hr)
        if zm['method'] == 'none':
            continue
        m = zm['minutes']
        focus['base'] += m[0] + m[1]
        focus['threshold'] += m[2]
        focus['anaerobic'] += m[3] + m[4]

    return {
        'period': period if period in PERIOD_DAYS else '30d',
        'from': start.isoformat(),
        'to': today.isoformat(),
        'maxHr': int(round(max_hr)),
        'totals': _totals(current),
        'prior': prior,
        'modalities': modalities,
        'activities': activities,
        'consistency': consistency,
        'zones': None if measured + estimated == 0 else {
            'minutes': [round(m, 1) for m in zone_totals],
            'workoutsMeasured': measured,
            'workoutsEstimated': estimated,
        },
        'focus28d': {k: round(v, 1) for k, v in focus.items()},
    }
