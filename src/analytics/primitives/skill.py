"""Skill primitive: what has been practised, and what that unlocks next.

Complexity-based methodologies (Ido Portal, Wildman's general practice,
Starrett) progress by acquiring movements, and the ontology already encodes
the graph: every exercise's `requires` and `unlocks`. But skill sessions are
`skill_practice` / `time_domain` slots that log no sets, so this counts at
session granularity: an exercise is *practised* once it has appeared in
`min_sessions` completed sessions, and an exercise becomes *available* when
practice opens it: everything it requires is practised or known at the
athlete's level (the generator's own resolution), and the level alone had not
already opened it.

Attendance is exposure, not mastery. An entry with `require_clean: true`
counts a session for an exercise only when the athlete ticked it **clean**
(every rep owned; `exercises[id].clean` in the session log, a toggle on
both clients' skill-practice rows) — Ido's and Wildman's movements are
earned that way. Until a clean tick exists the coverage says so
(`clean_not_logged`) rather than a silent zero.
"""
from __future__ import annotations

from src import loader
from src import selector as _selector
from src.analytics import spec as spec_mod
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
    require_clean = bool(getattr(entry, 'require_clean', False))
    any_clean = False

    for h in hits:
        if not h['completed']:
            continue
        in_scope += 1
        seen_here = {ea['exercise']['id'] for ea in h['assignments']}
        if require_clean:
            logged = (h['log'] or {}).get('exercises') or {}
            seen_here = {e for e in seen_here if isinstance(logged.get(e), dict) and logged[e].get('clean') is True}
            any_clean = any_clean or bool(seen_here)
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
    seeds = {pkg: by_level for pkg, by_level in loader.load_level_seeds().items()
             if pkg in policy.allowed_packages or not policy.owner_packages}
    universe, by_package = loader.load_all_exercises()
    if policy.owner_packages:
        # The program's own packages' definitions: an id several packages
        # declare (chin_up) carries each one's prerequisites, and the global
        # index keeps only the first declarer's (CrossFit's dead hang).
        pool = {}
        for pkg in sorted(policy.allowed_packages - set(policy.owner_packages)) + sorted(policy.owner_packages):
            pool.update(by_package.get(pkg) or {})
    else:
        pool = dict(universe)
    # What the generator already treats as open at this level — the same
    # resolution, concepts and seeds it selects with — and what is open once
    # the practised movements count too. A movement is "now available" when
    # practice opened it, not when the level granted it on day one: before, the
    # level's concepts (hip_hinge, bracing_mechanics…) were never consulted, so
    # Wildman's swing and press read as locked for an intermediate who was
    # already being programmed them.
    by_level = _selector._get_unlocked(level, pool, seeds)
    by_practice = _selector._get_unlocked(level, pool, seeds, also_known=practised)
    satisfied = practised | by_practice | by_level | _selector._level_known(level, seeds)
    available, locked = [], []
    for ex_id, ex in pool.items():
        reqs = list(ex.get('requires') or [])
        if not reqs or ex_id in practised or ex_id in by_level:
            continue
        record = {'exerciseId': ex_id, 'name': ex.get('name', ex_id), 'requires': reqs,
                  'missing': [r for r in reqs if r not in satisfied],
                  'unlocksNext': list(ex.get('unlocks') or [])}
        (available if ex_id in by_practice else locked).append(record)
    available.sort(key=lambda r: r['name'])

    # The movements the whole program draws on in this scope, elapsed or not:
    # the ceiling the practised count climbs toward over the block.
    in_program = {ea['exercise']['id'] for h in spec_mod.select(entry, ctx.weeks)
                  for ea in h['assignments']}

    series = [{'week': wk, 'x': wk, 'date': ctx.week_date(wk), 'value': n, 'isDeload': False}
              for wk, n in sorted(weekly_practised.items())]
    t = trend_mod.fit([trend_mod.Point(p['x'], p['value']) for p in series])
    status = ('on_track' if t.direction == 'improving' else
              'stable_by_design' if t.direction == 'stable' else
              'insufficient_data' if t.direction == 'insufficient_data' else 'behind')
    return result(entry, metric='exercises_practised', unit='exercises', series=series,
                  status=status if series else 'insufficient_data', trend=trend_dict(t),
                  coverage_=coverage(in_scope, with_exercises,
                                     'clean_not_logged' if require_clean and not any_clean else 'no_exercises_in_scope'),
                  practised=[{'exerciseId': e, 'name': names[e], 'sessions': counts[e]}
                             for e in sorted(practised, key=lambda e: -counts[e])],
                  inProgress=[{'exerciseId': e, 'name': names[e], 'sessions': c, 'needed': min_sessions}
                              for e, c in sorted(counts.items(), key=lambda kv: -kv[1]) if e not in practised],
                  available=available[:20], lockedCount=len(locked), minSessions=min_sessions,
                  requireClean=require_clean,
                  programTotal=len(in_program | practised),
                  assumedCount=sum(1 for e in by_level if e in pool and (pool[e].get('requires') or [])))
