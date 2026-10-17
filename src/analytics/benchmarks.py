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
from src.analytics import spec as spec_mod
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
    """A standard's results up to today, by the athlete's day (src/standards.entries)."""
    from src import standards
    rows = []
    for e in standards.entries(ctx.performance_logs.get(benchmark_id), (ctx.profile or {}).get('timezone')):
        when = date.fromisoformat(e['date'])
        if when <= ctx.today:
            rows.append({'date': when, 'value': e['value']})
    return rows


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


def standing(ctx: Context, b: dict, sex: str) -> dict:
    """Where the athlete stands on one standard — the one reading the program
    document's ladder and the `benchmark_level` measures share (they used to
    disagree: the measure read only logged results while the ladder beside it
    showed the estimate from training sets).

    {hist, latest, best, derived, value, valueSource, level}: `value` is the
    latest result, else the estimate (est. 1RM ÷ bodyweight that day) for a
    ×BW standard a logged lift derives; `best` the best logged result.
    """
    hist = _series(ctx, b['id'])
    latest = hist[-1] if hist else None
    best = (min if b['lower_is_better'] else max)(hist, key=lambda r: r['value']) if hist else None
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
    return {'hist': hist, 'latest': latest, 'best': best, 'derived': derived, 'value': value,
            'valueSource': 'logged' if latest else ('derived' if value is not None else None),
            'level': bd.level_of(b, value, sex)}


def _standard_ref(raw) -> str | None:
    """A standard id from an exercise's or session's `standard` key ("id" or {"id": …})."""
    if isinstance(raw, str):
        return raw or None
    if isinstance(raw, dict):
        return raw.get('id') or None
    return None


def program_standards(goal: dict, weeks: list[dict], specs: list) -> dict[str, list[str]]:
    """{standard id: [why…]} — the standards *this* program is measured by.

    `declared`: its package's analytics.yaml names it (top-level `benchmarks:`,
    framework-scoped to the frameworks the program runs, or a `benchmark_level`
    entry). `tested`: a session the program schedules measures it (a slot's or
    session's `standard`). Everything else a standard can be — in a priority
    modality's domain, citing the philosophy, or merely having a result — is
    not the program's: it waits behind "More standards" on Progress and under
    "Your results" on Profile. (A result alone used to make a standard
    primary, so a logged back squat led a kettlebell block's standards.)
    """
    # A standard scoped to frameworks is declared only for a program that runs
    # one of them: Wildman's pentathlon events in Pentathlon Prep, not in
    # General Practice.
    program_frameworks = {spec_mod.framework_id_of(w) for w in weeks} - {None}
    out: dict[str, list[str]] = {}
    for s in specs:
        for b in (s.benchmarks or []):
            if b not in s.benchmark_frameworks or s.benchmark_frameworks[b] & program_frameworks:
                out.setdefault(b, ['declared'])
        for e in s.entries:
            for b in (e.benchmarks or []):
                out.setdefault(b, ['declared'])
    for w in weeks:
        for sessions in (w.get('schedule') or {}).values():
            for sess in sessions or []:
                if not isinstance(sess, dict):
                    continue
                ids = [_standard_ref(x) for x in ((sess.get('test') or {}).get('standards') or [])]
                ids += [_standard_ref(ea.get('standard')) for ea in (sess.get('exercises') or []) if isinstance(ea, dict)]
                for sid in filter(None, ids):
                    why = out.setdefault(sid, [])
                    if 'tested' not in why:
                        why.append('tested')
    return out


def _at(hist: list[dict], day: date) -> dict | None:
    """The latest result on or before a day."""
    before = [r for r in hist if r['date'] <= day]
    return before[-1] if before else None


def build(ctx: Context, specs: list) -> dict:
    sources = set(ctx.goal.get('primary_sources') or [])
    priority_domains = {m for m, w in (ctx.goal.get('priorities') or {}).items() if w}
    own = program_standards(ctx.goal, ctx.weeks, specs)
    sex = (ctx.profile.get('sex') or 'male').lower()
    sex = sex if sex in ('male', 'female') else 'male'

    out = []
    for b in bd.load_benchmarks():
        why = list(own.get(b['id'], []))
        if set(b.get('sources') or []) & sources:
            why.append('philosophy')
        if b.get('domain') in priority_domains:
            why.append('priority_modality')
        if not why:
            continue
        st = standing(ctx, b, sex)
        hist, latest, derived, value, lv = st['hist'], st['latest'], st['derived'], st['value'], st['level']
        ladder = bd.thresholds(b, sex)
        out.append({
            'benchmarkId': b['id'], 'name': b['name'], 'category': b['category'], 'domain': b.get('domain'),
            'unit': b['unit'], 'metricType': b['metric_type'], 'lowerIsBetter': b['lower_is_better'],
            'why': why, 'sources': b.get('sources', []),
            # The program's own standards (program_standards); the rest wait
            # behind "More standards".
            'primary': bool({'declared', 'tested'} & set(why)),
            'standards': ladder,
            'standardsText': {lvl: bd.format_value(b, v) for lvl, v in ladder.items()},
            'latest': latest['value'] if latest else None,
            'latestDate': latest['date'].isoformat() if latest else None,
            'derived': derived, 'value': value, 'valueSource': st['valueSource'],
            'best': st['best']['value'] if st['best'] else None,
            'bestText': bd.format_value(b, st['best']['value']) if st['best'] else None,
            'valueText': bd.format_value(b, value),
            'level': lv['level'], 'levelIndex': lv['index'], 'next': lv['next'], 'gapToNext': lv['gap'],
            'nextText': bd.format_value(b, ladder.get(lv['next'])) if lv['next'] else None,
            'gapText': bd.format_value(b, lv['gap']) if lv['gap'] is not None else None,
            'history': [{'date': r['date'].isoformat(), 'value': r['value'],
                         'valueText': bd.format_value(b, r['value'])} for r in hist],
            **_this_block(b, hist, ctx, sex, lv),
        })
    order = {'declared': 0, 'tested': 0, 'philosophy': 1, 'priority_modality': 2}
    out.sort(key=lambda r: (min(order[w] for w in r['why']), r['name']))
    bw = _series(ctx, 'bodyweight_kg')
    return {
        'blockStart': ctx.start_date.isoformat(),
        'sex': sex,
        'bodyweightKg': bw[-1]['value'] if bw else None,
        'bodyweightText': bd.format_value(None, bw[-1]['value']) if bw else None,
        'bodyweightDate': bw[-1]['date'].isoformat() if bw else None,
        'benchmarks': out,
    }


def _this_block(b: dict, hist: list[dict], ctx: Context, sex: str, lv: dict) -> dict:
    """Where the athlete stood when this block began, how far they have moved
    since, and the block's results (the standing at its start first, so a
    sparkline starts from where the block did)."""
    start = _at([r for r in hist if r['date'] < ctx.start_date], ctx.start_date)
    in_block = [r for r in hist if r['date'] >= ctx.start_date]
    at_start = None
    if start:
        slv = bd.level_of(b, start['value'], sex)
        at_start = {'value': start['value'], 'valueText': bd.format_value(b, start['value']),
                    'date': start['date'].isoformat(), 'level': slv['level'], 'levelIndex': slv['index']}
    change = (lv['index'] - at_start['levelIndex']) if at_start and in_block else None
    points = ([start] if start else []) + in_block
    return {
        'atBlockStart': at_start,
        # Levels moved this block; None when there is nothing to compare (no
        # result before it, or none in it).
        'levelChange': change,
        'blockHistory': [{'date': r['date'].isoformat(), 'value': r['value'],
                          'valueText': bd.format_value(b, r['value']),
                          'level': bd.level_of(b, r['value'], sex)['level']} for r in points],
    }
