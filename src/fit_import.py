"""FIT activity parsing, plus the two sample-cleaning helpers it shares.

Lifted out of the `POST /api/workouts/parse` request handler so that anything
holding FIT bytes can use it — in particular the Garmin Connect webhook, which
receives the very same file format the athlete would otherwise export by hand.

This module is deliberately pure: no Flask, no `g`, no database. Callers do
their own persistence.
"""
from __future__ import annotations

from datetime import datetime as _dt, timezone as _tz

from src.workout_ids import deterministic_id

# Sport / sub-sport from the FIT file → our modality ontology.
FIT_SPORT_MAP = {
    'running':           'aerobic_base',
    'cycling':           'aerobic_base',
    'swimming':          'aerobic_base',
    'walking':           'durability',
    'hiking':            'durability',
    'rowing':            'aerobic_base',
    'elliptical':        'aerobic_base',
    'yoga':              'mobility',
    'flexibility':       'mobility',
    'training':          'mixed_modal_conditioning',
    'generic':           'mixed_modal_conditioning',
    'strength_training': 'max_strength',
    'cardio':            'aerobic_base',
    'cross_training':    'mixed_modal_conditioning',
    'hiit':              'anaerobic_intervals',
    'boxing':            'combat_sport',
    'martial_arts':      'combat_sport',
}

# FIT stores coordinates in semicircles.
SEMI_TO_DEG = 180.0 / (2 ** 31)


def calc_elevation(points: list, noise_floor: float = 1.0) -> tuple[float, float]:
    """Cumulative gain/loss from a list of dicts carrying an `altitude` key.

    Also used as a callback by `health_store.recalculate_workouts_elevation`, so
    the signature is load-bearing.
    """
    gain = loss = 0.0
    prev = None
    for p in points:
        alt = p.get('altitude')
        if alt is None:
            continue
        if prev is not None:
            diff = alt - prev
            if diff >= noise_floor:
                gain += diff
            elif diff <= -noise_floor:
                loss += abs(diff)
        prev = alt
    return gain, loss


def clean_hr_samples(samples: list, session_avg_hr: float | None = None) -> list:
    """Remove sensor lock-on artifacts and smooth outliers from HR sample lists.

    1. Startup trim  — drop readings in the first 30 s that are below 75 % of
       session average HR, but only for real exercise sessions (avg > 100 bpm).
       This eliminates the optical-HR cold-start lag common on Apple Watch.
    2. Rolling median — replace every sample with the median of its ±7.5 s
       neighbourhood (min 3 neighbours required) to suppress mid-workout spikes
       without distorting genuine effort changes.
    """
    from statistics import median as _median
    from datetime import datetime, timezone

    if not samples:
        return samples

    # Parse timestamps once
    parsed: list[tuple[float, int, str]] = []  # (unix_ts, bpm, iso_str)
    for s in samples:
        try:
            dt = datetime.fromisoformat(s['timestamp'])
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            parsed.append((dt.timestamp(), int(s['bpm']), s['timestamp']))
        except Exception:
            continue

    if not parsed:
        return samples

    # Filter physiologically impossible readings (sensor dropout or overflow artifacts)
    parsed = [(ts, bpm, iso) for ts, bpm, iso in parsed if 30 <= bpm <= 250]

    if not parsed:
        return samples

    # 1 — Startup trim: drop all leading readings below threshold until HR first
    #     stabilises at exercise level. Handles cold-start lag of any duration
    #     (Apple Watch can take 3-5 min to lock on). Guard: never trim > 5 min.
    avg = session_avg_hr or (sum(b for _, b, _ in parsed) / len(parsed))
    if avg > 100:
        threshold = avg * 0.75
        start_ts = parsed[0][0]
        first_valid = next(
            (i for i, (ts, bpm, _) in enumerate(parsed)
             if bpm >= threshold or ts - start_ts > 300),
            0,
        )
        parsed = parsed[first_valid:]

    if not parsed:
        return samples

    # 2 — Rolling median (±7.5 s window)
    cleaned = []
    for ts, bpm, iso in parsed:
        window = sorted(b for t, b, _ in parsed if abs(t - ts) <= 7.5)
        smoothed = int(round(_median(window))) if len(window) >= 3 else bpm
        cleaned.append({'timestamp': iso, 'bpm': smoothed})

    return cleaned


class FitNotAvailable(RuntimeError):
    """`fitparse` is not installed."""


def parse_fit(stream, source: str = 'fit_file') -> list[dict]:
    """Parse a FIT activity into ImportedWorkout-shaped dicts.

    `stream` is anything `fitparse.FitFile` accepts — a file object, a path, or
    raw bytes (so the webhook can hand over `io.BytesIO(response.content)`).

    `source` tags the resulting rows and feeds the deterministic id, so the same
    file imported by hand (`fit_file`) and pushed by Garmin (`garmin`) produces
    distinct ids. That is intentional; the dedup layer collapses them.

    Raises FitNotAvailable when the library is missing; lets fitparse's own
    exceptions through so the caller can decide between a 422 and a retry.
    """
    try:
        import fitparse as _fitparse
    except ImportError as exc:  # pragma: no cover - depends on the environment
        raise FitNotAvailable('fitparse library not installed — run pip install fitparse') from exc

    fit = _fitparse.FitFile(stream)

    # ── Collect all record-level data (GPS, HR, altitude, cadence, power) ──
    records = []
    for rec in fit.get_messages('record'):
        ts = rec.get_value('timestamp')
        if ts is None:
            continue
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=_tz.utc)

        lat_semi = rec.get_value('position_lat')
        lon_semi = rec.get_value('position_long')
        lat = float(lat_semi) * SEMI_TO_DEG if lat_semi is not None else None
        lng = float(lon_semi) * SEMI_TO_DEG if lon_semi is not None else None

        records.append({
            'timestamp': ts.isoformat(),
            'lat':       lat,
            'lng':       lng,
            'altitude':  float(rec.get_value('enhanced_altitude') or rec.get_value('altitude') or 0) if (rec.get_value('enhanced_altitude') or rec.get_value('altitude')) is not None else None,
            'bpm':       int(rec.get_value('heart_rate')) if rec.get_value('heart_rate') is not None else None,
            'cadence':   int(rec.get_value('cadence')) if rec.get_value('cadence') is not None else None,
            'power':     int(rec.get_value('power')) if rec.get_value('power') is not None else None,
            'speed':     float(rec.get_value('enhanced_speed') or rec.get_value('speed') or 0) if (rec.get_value('enhanced_speed') or rec.get_value('speed')) is not None else None,
        })

    # Build GPS track (only points with coordinates)
    gps_track = [
        {'lat': r['lat'], 'lng': r['lng'], 'altitude': r['altitude'],
         'timestamp': r['timestamp'], 'bpm': r['bpm'], 'speed': r['speed']}
        for r in records if r['lat'] is not None and r['lng'] is not None
    ]

    # Build HR samples (all points with valid HR, filter zeros)
    hr_samples = clean_hr_samples(
        [{'timestamp': r['timestamp'], 'bpm': r['bpm']}
         for r in records if r['bpm'] is not None and r['bpm'] > 0]
    )

    # ── Session-level summary ──
    results = []
    for session in fit.get_messages('session'):
        sport = str(session.get_value('sport') or 'generic').lower()
        sub_sport = str(session.get_value('sub_sport') or '').lower()

        start_time = session.get_value('start_time')  # UTC naive datetime
        elapsed = float(
            session.get_value('total_elapsed_time')
            or session.get_value('total_timer_time')
            or 0
        )

        if not start_time:
            continue

        if start_time.tzinfo is None:
            start_time = start_time.replace(tzinfo=_tz.utc)
        end_time = _dt.fromtimestamp(start_time.timestamp() + elapsed, tz=_tz.utc)

        # Prefer sub_sport, but skip 'generic' since it's uninformative
        modality = (
            (FIT_SPORT_MAP.get(sub_sport) if sub_sport not in ('generic', 'none', '') else None)
            or FIT_SPORT_MAP.get(sport)
        )
        avg_hr  = session.get_value('avg_heart_rate')
        max_hr  = session.get_value('max_heart_rate')
        calories = session.get_value('total_calories')
        dist_m   = session.get_value('total_distance')  # meters

        # Prefer GPS-computed cumulative gain/loss (same algorithm as
        # WorkoutDetail frontend) so all views agree.  Fall back to the
        # device barometric session total only when no GPS altitude data
        # is present at all (e.g. treadmill, indoor cycling).
        # Check presence of altitude data explicitly — don't use a zero
        # result as a proxy, or genuinely flat runs fall back to barometric.
        has_gps_altitude = any(r.get('altitude') is not None for r in records)
        if has_gps_altitude:
            elev_gain, elev_loss = calc_elevation(records)
        else:
            total_ascent  = session.get_value('total_ascent')
            total_descent = session.get_value('total_descent')
            elev_gain = float(total_ascent  or 0)
            elev_loss = float(total_descent or 0)

        # Use sub_sport for display when it adds meaning
        display_type = (
            sub_sport
            if sub_sport and sub_sport not in ('generic', 'none', '')
            else sport
        ).replace('_', ' ').title()

        fit_dur = round(elapsed / 60)
        results.append({
            'id':                deterministic_id(source, start_time.isoformat(), display_type, fit_dur),
            'source':            source,
            'date':              start_time.strftime('%Y-%m-%d'),
            'startTime':         start_time.isoformat(),
            'endTime':           end_time.isoformat(),
            'durationMinutes':   fit_dur,
            'activityType':      display_type,
            'inferredModalityId': modality,
            'heartRate': {
                'avg': float(avg_hr)  if avg_hr  is not None else None,
                'max': float(max_hr)  if max_hr  is not None else None,
                'min': None,
                'samples': hr_samples,
            },
            'calories':  int(calories) if calories is not None else None,
            'distance':  {'value': round(float(dist_m) / 1000, 3), 'unit': 'km'} if dist_m else None,
            'gpsTrack':  gps_track if gps_track else None,
            'elevation': {'gain': round(elev_gain), 'loss': round(elev_loss)} if elev_gain or elev_loss else None,
            'rawData':   {'sport': sport, 'sub_sport': sub_sport},
        })

    return results
