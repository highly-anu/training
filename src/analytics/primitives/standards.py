"""Standards primitives: where you stand on the ladder, and did you show up.

`benchmark_level` reads the athlete's PRs against the benchmark standards a
methodology names as its end state — Starting Strength's "novice completion"
is `intermediate` on the squat, deadlift and press ratios, and it already
exists in data/benchmarks with `sources: [starting_strength]`.

`session_completion` is plain attendance for the scope, per week.
"""
from __future__ import annotations

from datetime import date

from src.analytics import benchmarks_data as bd
from src.analytics import trend as trend_mod
from src.analytics.primitives import coverage, primitive, result, scoped_hits, trend_dict

LEVEL_INDEX = {lvl: i + 1 for i, lvl in enumerate(bd.LEVELS)}


def _pr_history(ctx, benchmark_id: str) -> list[dict]:
    rows = []
    for entry in ctx.performance_logs.get(benchmark_id) or []:
        d = entry.get('date') or entry.get('loggedAt') or entry.get('logged_at')
        try:
            when = date.fromisoformat(str(d)[:10])
        except (TypeError, ValueError):
            continue
        if when <= ctx.today and isinstance(entry.get('value'), (int, float)):
            rows.append({'date': when, 'value': float(entry['value'])})
    rows.sort(key=lambda r: r['date'])
    return rows


@primitive('benchmark_level')
def benchmark_level(entry, ctx) -> dict:
    defs = bd.by_id()
    sex = (ctx.profile.get('sex') or 'male').lower()
    if sex not in ('male', 'female'):
        sex = 'male'
    target = entry.target_level
    ids = list(entry.benchmarks or [])
    rows, series = [], []
    measured = 0
    met_count = 0
    for i, bid in enumerate(ids):
        b = defs.get(bid)
        if not b:
            rows.append({'benchmarkId': bid, 'missing': True})
            continue
        hist = _pr_history(ctx, bid)
        latest = hist[-1] if hist else None
        lv = bd.level_of(b, latest['value'] if latest else None, sex)
        met = target is not None and lv['index'] >= LEVEL_INDEX.get(target, 99)
        if latest:
            measured += 1
            met_count += int(met)
        target_value = (b['levels'].get(target) or {}).get(sex) if target else None
        if target_value is None and target:
            target_value = (b['levels'].get(target) or {}).get('male')
        rows.append({
            'benchmarkId': bid, 'name': b['name'], 'unit': b['unit'],
            'lowerIsBetter': b['lower_is_better'], 'metricType': b['metric_type'],
            'latest': latest['value'] if latest else None,
            'latestDate': latest['date'].isoformat() if latest else None,
            'level': lv['level'], 'levelIndex': lv['index'], 'next': lv['next'], 'gapToNext': lv['gap'],
            'target': target, 'targetValue': target_value, 'met': met if latest else None,
            'standards': {lvl: b['levels'][lvl].get(sex, b['levels'][lvl]['male']) for lvl in b['levels']},
            'history': [{'date': r['date'].isoformat(), 'value': r['value']} for r in hist],
        })
        for k, r in enumerate(hist):
            series.append({'week': None, 'x': i * 1000 + k, 'value': r['value'], 'isDeload': False,
                           'date': r['date'].isoformat(), 'benchmarkId': bid})
    if not measured:
        status = 'insufficient_data'
    elif target is None:
        status = 'on_track'
    elif met_count == measured:
        status = 'met'
    elif met_count:
        status = 'partial'
    else:
        status = 'below'
    return result(entry, metric='benchmark_level', unit='level', series=series, status=status,
                  coverage_=coverage(len(ids), measured, 'no_pr_logged'),
                  benchmarks=rows, targetLevel=target, sex=sex)


@primitive('session_completion')
def session_completion(entry, ctx) -> dict:
    hits = scoped_hits(entry, ctx)
    weekly: dict = {}
    for h in hits:
        wk = weekly.setdefault(h['week_number'], {'week': h['week_number'], 'planned': 0, 'completed': 0,
                                                  'isDeload': h['is_deload']})
        wk['planned'] += 1
        wk['completed'] += int(h['completed'])
    weeks = sorted(weekly.values(), key=lambda w: w['week'])
    series = [{'week': w['week'], 'x': w['week'], 'isDeload': w['isDeload'],
               'value': round(100.0 * w['completed'] / w['planned'], 1) if w['planned'] else None,
               'planned': w['planned'], 'completed': w['completed']} for w in weeks]
    planned = sum(w['planned'] for w in weeks)
    done = sum(w['completed'] for w in weeks)
    pct = round(100.0 * done / planned, 1) if planned else None
    status = ('insufficient_data' if pct is None else 'on_track' if pct >= 85 else
              'behind' if pct >= 60 else 'off_plan')
    t = trend_mod.fit([trend_mod.Point(p['x'], p['value'], p['isDeload']) for p in series if p['value'] is not None])
    return result(entry, metric='completion_pct', unit='%', series=series, status=status,
                  trend=trend_dict(t), coverage_=coverage(planned, planned, None),
                  totals={'planned': planned, 'completed': done, 'pct': pct})
