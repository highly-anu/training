"""Daily wellness from the Connect IQ watch app: validation and the merge that
readiness scores.

Pure — no Flask, no DB. The store is src/wellness_store.py, the route
POST /api/health/wellness in api.py.

The watch reads what the open SDK exposes (docs/roadmap.md, *Garmin wellness
via Connect IQ*): resting heart rate and its 7-day average from UserProfile,
the heart-rate and Body Battery history from SensorHistory, recovery time from
ActivityMonitor. Nightly HRV and sleep are not readable, so the Apple Health
relay's daily_bio stays the only source of those.
"""
from __future__ import annotations

from datetime import date as _date, datetime as _datetime, timedelta as _timedelta, timezone as _tz

SOURCE = 'garmin_ciq'

# body key -> (column, low, high, kind). Bounds reject a sensor glitch or a
# unit mix-up, not an unusual athlete: a resting HR of 28 is real.
FIELDS: dict[str, tuple[str, float, float, type]] = {
    'restingHr':         ('resting_hr',          25, 200, int),
    'restingHr7dAvg':    ('resting_hr_7d_avg',   25, 200, int),
    'hrMin':             ('hr_min',              25, 230, int),
    'hrLow5':            ('hr_low5',             25, 230, float),
    'hrSamples':         ('hr_samples',           0, 100000, int),
    'bodyBatteryMax':    ('body_battery_max',     0, 100, int),
    'bodyBatteryMin':    ('body_battery_min',     0, 100, int),
    'bodyBatteryLatest': ('body_battery_latest',  0, 100, int),
    'recoveryTimeH':     ('recovery_time_h',      0, 240, int),
    'vo2max':            ('vo2max',              10, 100, int),
    'stress':            ('stress',               0, 100, int),
}
TEXT_FIELDS = {'partNumber': ('part_number', 32), 'firmware': ('firmware', 32)}

# A watch posts its own local day. More than a day ahead of UTC is a clock
# error; older than this is a backlog nothing scores any more.
MAX_AGE_DAYS = 30


def validate(body, today: _date | None = None) -> tuple[dict | None, list[str]]:
    """Check one posted reading. Returns (row, []) or (None, errors).

    `row` uses the column names. Unknown keys are ignored, so an older server
    accepts a newer watch build. A reading with no metric at all is an error:
    an empty row would only overwrite nothing and report success.
    """
    if not isinstance(body, dict):
        return None, ['body must be a JSON object']
    errors: list[str] = []
    today = today or _datetime.now(_tz.utc).date()

    row: dict = {}
    raw_date = body.get('date')
    try:
        day = _date.fromisoformat(raw_date) if isinstance(raw_date, str) else None
    except ValueError:
        day = None
    if day is None:
        errors.append('date must be YYYY-MM-DD')
    elif day > today + _timedelta(days=1):
        errors.append(f'date {day} is in the future')
    elif day < today - _timedelta(days=MAX_AGE_DAYS):
        errors.append(f'date {day} is older than {MAX_AGE_DAYS} days')
    else:
        row['date'] = day.isoformat()

    read_at = body.get('readAt')
    if read_at is not None:
        # Epoch seconds: what Time.now().value() gives on the watch.
        if isinstance(read_at, bool) or not isinstance(read_at, (int, float)) or read_at <= 0:
            errors.append('readAt must be epoch seconds')
        else:
            row['read_at'] = _datetime.fromtimestamp(read_at, _tz.utc).isoformat()

    metrics = 0
    for key, (col, lo, hi, kind) in FIELDS.items():
        v = body.get(key)
        if v is None:
            continue
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            errors.append(f'{key} must be a number')
            continue
        if not lo <= v <= hi:
            errors.append(f'{key} {v} is outside {lo}..{hi}')
            continue
        row[col] = int(round(v)) if kind is int else float(v)
        metrics += 1

    for key, (col, limit) in TEXT_FIELDS.items():
        v = body.get(key)
        if v is None:
            continue
        if not isinstance(v, str) or len(v) > limit:
            errors.append(f'{key} must be a string of at most {limit} characters')
            continue
        row[col] = v

    if not errors and metrics == 0:
        errors.append('no metric in the reading')
    return (None, errors) if errors else (row, [])


def merge_for_scoring(bio_logs: list[dict], wellness_rows: list[dict]) -> tuple[list[dict], dict]:
    """The bio list readiness scores, and where each component came from.

    Resting HR comes from **one series**: whichever of daily_bio and
    daily_wellness has more readings in the window, ties to daily_bio. Mixing
    them day by day would score the difference between two methods as a
    change in the athlete — Apple's resting HR and Garmin's are computed
    differently and sit a few beats apart. HRV and sleep always come from
    daily_bio; the watch cannot read them.

    With no wellness rows the result equals `bio_logs`, so readiness is
    unchanged for anyone who never pairs a watch. Inputs are not mutated.
    """
    merged = [dict(b) for b in bio_logs]
    bio_rhr = sum(1 for b in bio_logs if b.get('resting_hr') is not None)
    w_rhr = {str(w['date']): w['resting_hr'] for w in wellness_rows
             if w.get('resting_hr') is not None}

    if len(w_rhr) > bio_rhr:
        rhr_source = SOURCE
        by_date = {}
        for b in merged:
            b.pop('resting_hr', None)
            by_date[b['date']] = b
        for d, v in w_rhr.items():
            if d in by_date:
                by_date[d]['resting_hr'] = v
            else:
                merged.append({'date': d, 'resting_hr': v, 'source': SOURCE})
        merged.sort(key=lambda b: b['date'], reverse=True)
    else:
        rhr_source = 'daily_bio' if bio_rhr else None

    sources = {
        'rhr':   rhr_source,
        'hrv':   'daily_bio' if any(b.get('hrv') is not None for b in bio_logs) else None,
        'sleep': 'daily_bio' if any(b.get('sleep_duration_min') is not None for b in bio_logs) else None,
    }
    return merged, sources
