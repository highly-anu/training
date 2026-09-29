"""Skill primitive: what has been practised, and what that unlocks next.

Complexity-based methodologies (Ido Portal, Wildman's general practice,
Starrett) progress by acquiring movements, and the ontology already encodes
the graph: every exercise's `requires` and `unlocks`. But skill sessions are
`skill_practice` / `time_domain` slots that log no sets, so this counts at
session granularity: an exercise is *practised* once it has appeared in
`min_sessions` completed sessions, and an exercise becomes *available* when
everything it requires is practised (or seeded for the athlete's level).
"""
from __future__ import annotations

from src import loader
from src.analytics import trend as trend_mod
from src.analytics.primitives import coverage, primitive, result, scoped_hits, trend_dict
from src.provenance import resolve_source_policy


@primitive('unlocks')
def unlocks(entry, ctx) -> dict:
    hits = scoped_hits(entry, ctx)
    counts: dict[str, int] = {}
    names: dict[str, str] = {}
    weekly_practised: dict[int, int] = {}
    practised: set[str] = set()
    in_scope = with_exercises = 0
    min_sessions = max(1, int(entry.min_sessions or 2))

    for h in hits:
        if not h['completed']:
            continue
        in_scope += 1
        seen_here = {ea['exercise']['id'] for ea in h['assignments']}
        if seen_here:
            with_exercises += 1
        for ex_id in seen_here:
            names[ex_id] = next(ea['exercise'].get('name', ex_id) for ea in h['assignments']
                                if ea['exercise']['id'] == ex_id)
            counts[ex_id] = counts.get(ex_id, 0) + 1
            if counts[ex_id] >= min_sessions:
                practised.add(ex_id)
        weekly_practised[h['week_number']] = len(practised)

    policy = resolve_source_policy(ctx.goal)
    level = str(ctx.constraints.get('training_level') or 'intermediate')
    seeds: set[str] = set()
    for pkg, by_level in loader.load_level_seeds().items():
        if pkg in policy.allowed_packages or not policy.owner_packages:
            seeds |= set(by_level.get(level) or ())
    satisfied = practised | seeds

    universe, _ = loader.load_all_exercises()
    available, locked = [], []
    for ex_id, ex in universe.items():
        if policy.owner_packages and not (set(ex.get('_packages') or []) & policy.allowed_packages):
            continue
        reqs = list(ex.get('requires') or [])
        if not reqs or ex_id in practised:
            continue
        missing = [r for r in reqs if r not in satisfied]
        record = {'exerciseId': ex_id, 'name': ex.get('name', ex_id), 'requires': reqs,
                  'missing': missing, 'unlocksNext': list(ex.get('unlocks') or [])}
        (available if not missing else locked).append(record)
    available.sort(key=lambda r: r['name'])

    series = [{'week': wk, 'x': wk, 'value': n, 'isDeload': False}
              for wk, n in sorted(weekly_practised.items())]
    t = trend_mod.fit([trend_mod.Point(p['x'], p['value']) for p in series])
    status = ('on_track' if t.direction == 'improving' else
              'stable_by_design' if t.direction == 'stable' else
              'insufficient_data' if t.direction == 'insufficient_data' else 'behind')
    return result(entry, metric='exercises_practised', unit='exercises', series=series,
                  status=status if series else 'insufficient_data', trend=trend_dict(t),
                  coverage_=coverage(in_scope, with_exercises, 'no_exercises_in_scope'),
                  practised=[{'exerciseId': e, 'name': names[e], 'sessions': counts[e]}
                             for e in sorted(practised, key=lambda e: -counts[e])],
                  inProgress=[{'exerciseId': e, 'name': names[e], 'sessions': c, 'needed': min_sessions}
                              for e, c in sorted(counts.items(), key=lambda kv: -kv[1]) if e not in practised],
                  available=available[:20], lockedCount=len(locked), minSessions=min_sessions)
