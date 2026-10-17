"""Standards primitives: where you stand on the ladder, and did you show up.

`benchmark_level` reads the athlete's results (or, for a ×BW standard, the
estimate from logged sets) against the standards a
methodology names as its end state — Starting Strength's "novice completion"
is `intermediate` on the squat, deadlift and press ratios, and it already
exists in data/benchmarks with `sources: [starting_strength]`.

`session_completion` is plain attendance for the scope, per week.
"""
from __future__ import annotations

from datetime import date

from src.analytics import benchmarks_data as bd
from src.analytics.benchmarks import standing
from src.analytics import trend as trend_mod
from src.analytics.primitives import coverage, primitive, result, scoped_hits, trend_dict

LEVEL_INDEX = {lvl: i + 1 for i, lvl in enumerate(bd.LEVELS)}


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
        # The same reading as the program's ladder (benchmarks.standing): the
        # latest result, else the estimate from logged sets, flagged.
        st = standing(ctx, b, sex)
        hist, latest, value, lv = st['hist'], st['latest'], st['value'], st['level']
        met = target is not None and lv['index'] >= LEVEL_INDEX.get(target, 99)
        if value is not None:
            measured += 1
            met_count += int(met)
        ladder = bd.thresholds(b, sex)
        target_value = ladder.get(target) if target else None
        rows.append({
            'benchmarkId': bid, 'name': b['name'], 'unit': b['unit'],
            'lowerIsBetter': b['lower_is_better'], 'metricType': b['metric_type'],
            'domain': b.get('domain'),
            'latest': latest['value'] if latest else None,
            'latestText': bd.format_value(b, latest['value']) if latest else None,
            'latestDate': latest['date'].isoformat() if latest else None,
            'value': value, 'valueText': bd.format_value(b, value), 'valueSource': st['valueSource'],
            'best': st['best']['value'] if st['best'] else None,
            'bestText': bd.format_value(b, st['best']['value']) if st['best'] else None,
            'level': lv['level'], 'levelIndex': lv['index'], 'next': lv['next'], 'gapToNext': lv['gap'],
            'target': target, 'targetValue': target_value, 'met': met if value is not None else None,
            'targetText': bd.format_value(b, target_value) if target_value is not None else None,
            'standards': ladder,
            'standardsText': {lvl: bd.format_value(b, v) for lvl, v in ladder.items()},
            'history': [{'date': r['date'].isoformat(), 'value': r['value'],
                         'valueText': bd.format_value(b, r['value'])} for r in hist],
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
