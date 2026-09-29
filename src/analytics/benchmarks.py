"""The standards this program is measured by, and where the athlete stands.

Selection is authored, not guessed: a standard belongs here when its `sources`
name one of the program's philosophies, when its `domain` is a modality the
goal prioritises, or when the package's analytics.yaml lists it. Each carries
the athlete's PRs from performance_logs, the level reached and the gap to the
next one.

Bodyweight is a benchmark series too (`bodyweight_kg`), so a strength standard
expressed as a ratio can be derived from an estimated 1RM ÷ the latest
bodyweight at or before that session — which is how a lifter who never tests a
true 1RM still sees where their squat sits.
"""
from __future__ import annotations

from datetime import date

from src.analytics import benchmarks_data as bd
from src.analytics.context import Context

# benchmark id → exercise ids whose logged sets estimate it
_DERIVED_FROM = {
    'back_squat_bw_ratio':   ('back_squat',),
    'deadlift_bw_ratio':     ('deadlift', 'trap_bar_deadlift', 'sumo_deadlift'),
    'strict_press_bw_ratio': ('strict_press', 'overhead_press'),
    'bench_press_bw_ratio':  ('bench_press',),
    'power_clean_bw_ratio':  ('power_clean',),
}


def _series(ctx: Context, benchmark_id: str) -> list[dict]:
    rows = []
    for e in ctx.performance_logs.get(benchmark_id) or []:
        raw = e.get('date') or e.get('loggedAt') or e.get('logged_at')
        try:
            when = date.fromisoformat(str(raw)[:10])
        except (TypeError, ValueError):
            continue
        if when <= ctx.today and isinstance(e.get('value'), (int, float)):
            rows.append({'date': when, 'value': float(e['value'])})
    return sorted(rows, key=lambda r: r['date'])


def _bodyweight_at(ctx: Context, when: date) -> float | None:
    hist = [r for r in _series(ctx, 'bodyweight_kg') if r['date'] <= when]
    return hist[-1]['value'] if hist else None


def _best_est1rm(ctx: Context, exercise_ids: tuple) -> tuple[float, date] | None:
    from src.analytics.primitives.load import best_completed_set
    best = None
    for hit in ctx.sessions(elapsed_only=True):
        logged = (ctx.log_for(hit) or {}).get('exercises') or {}
        for ex_id in exercise_ids:
            b = best_completed_set(logged.get(ex_id))
            if b and b.get('est1rm') and (best is None or b['est1rm'] > best[0]):
                best = (b['est1rm'], hit['date'])
    return best


def build(ctx: Context, specs: list) -> dict:
    sources = set(ctx.goal.get('primary_sources') or [])
    priority_domains = {m for m, w in (ctx.goal.get('priorities') or {}).items() if w}
    declared = {b for s in specs for b in (s.benchmarks or [])}
    declared |= {b for s in specs for e in s.entries for b in (e.benchmarks or [])}
    sex = (ctx.profile.get('sex') or 'male').lower()
    sex = sex if sex in ('male', 'female') else 'male'

    out = []
    for b in bd.load_benchmarks():
        why = []
        if set(b.get('sources') or []) & sources:
            why.append('philosophy')
        if b.get('domain') in priority_domains:
            why.append('priority_modality')
        if b['id'] in declared:
            why.append('declared')
        if not why:
            continue
        hist = _series(ctx, b['id'])
        latest = hist[-1] if hist else None
        derived = None
        if b['metric_type'] == 'bw_ratio' and b['id'] in _DERIVED_FROM:
            est = _best_est1rm(ctx, _DERIVED_FROM[b['id']])
            if est:
                bw = _bodyweight_at(ctx, est[1])
                if bw:
                    derived = {'value': round(est[0] / bw, 2), 'est1rm': est[0], 'bodyweightKg': bw,
                               'date': est[1].isoformat()}
                else:
                    derived = {'value': None, 'est1rm': est[0], 'bodyweightKg': None,
                               'reason': 'no_bodyweight_logged'}
        value = latest['value'] if latest else (derived or {}).get('value')
        lv = bd.level_of(b, value, sex)
        out.append({
            'benchmarkId': b['id'], 'name': b['name'], 'category': b['category'], 'domain': b.get('domain'),
            'unit': b['unit'], 'metricType': b['metric_type'], 'lowerIsBetter': b['lower_is_better'],
            'why': why, 'sources': b.get('sources', []),
            'standards': {lvl: b['levels'][lvl].get(sex, b['levels'][lvl]['male']) for lvl in b['levels']},
            'latest': latest['value'] if latest else None,
            'latestDate': latest['date'].isoformat() if latest else None,
            'derived': derived, 'value': value, 'valueSource': 'logged' if latest else ('derived' if value is not None else None),
            'level': lv['level'], 'levelIndex': lv['index'], 'next': lv['next'], 'gapToNext': lv['gap'],
            'history': [{'date': r['date'].isoformat(), 'value': r['value']} for r in hist],
        })
    order = {'declared': 0, 'philosophy': 1, 'priority_modality': 2}
    out.sort(key=lambda r: (min(order[w] for w in r['why']), r['name']))
    bw = _series(ctx, 'bodyweight_kg')
    return {
        'sex': sex,
        'bodyweightKg': bw[-1]['value'] if bw else None,
        'bodyweightDate': bw[-1]['date'].isoformat() if bw else None,
        'benchmarks': out,
    }
