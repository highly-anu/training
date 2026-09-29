"""What you moved, by pattern, against what was prescribed.

Two tables that are never summed: pattern **sets** (from set-based work,
weighted by completed sets) and pattern **minutes** (from time-domain work,
weighted by prescribed minutes — `assumed` when the session was completed but
not matched). Both are rolled up on the raw patterns exercises declare, not
on movement_patterns.yaml's aliases, which are slot *filters* (`press` and
`push` are the same set there).

Balance ratios are information by default and warnings only when the package
declares them: a push:pull warning on a Starting Strength block that
deliberately has no pull slot is noise, and Filly, Gym Jones and Horsemen say
in their analytics.yaml that they want it.
"""
from __future__ import annotations

from collections import defaultdict

from src.analytics.context import Context
from src.analytics.primitives.load import best_completed_set

ROLLUPS = {
    'push':       ('horizontal_push', 'vertical_push'),
    'pull':       ('horizontal_pull', 'vertical_pull'),
    'hinge':      ('hip_hinge',),
    'squat':      ('squat',),
    'carry':      ('loaded_carry', 'farmer_carry', 'rack_carry'),
    'locomotion': ('locomotion', 'aerobic_monostructural'),
    'rotation':   ('rotation',),
    'isometric':  ('isometric',),
    'ballistic':  ('ballistic',),
    'olympic':    ('olympic_lift',),
}
SET_SLOT_TYPES = frozenset({'sets_reps', 'static_hold', 'amrap_movement'})
DEFAULT_BALANCE = [{'a': 'push', 'b': 'pull', 'min': 0.6, 'max': 1.6},
                   {'a': 'hinge', 'b': 'squat', 'min': 0.5, 'max': 1.5}]


def _patterns(ctx: Context, ea: dict) -> list[str]:
    ex = ea.get('exercise') or {}
    pats = ex.get('movement_patterns')
    if not pats:
        pats = ctx.exercise_def(ex.get('id', '')).get('movement_patterns') or []
    return list(pats)


def _bilateral(ctx: Context, ea: dict) -> bool | None:
    ex = ea.get('exercise') or {}
    if 'bilateral' in ex:
        return bool(ex['bilateral'])
    d = ctx.exercise_def(ex.get('id', ''))
    return bool(d['bilateral']) if 'bilateral' in d else None


def build(ctx: Context, specs: list) -> dict:
    planned_sets = defaultdict(float)
    done_sets = defaultdict(float)
    planned_min = defaultdict(float)
    done_min = defaultdict(float)
    assumed_min = 0.0
    unilateral = {'planned': 0, 'done': 0, 'total_planned': 0, 'total_done': 0}
    by_category = defaultdict(lambda: {'plannedSessions': 0, 'completedSessions': 0})

    for hit in ctx.sessions(elapsed_only=True):
        session = hit['session']
        completed = ctx.completed(hit) or ctx.workout_for(hit) is not None
        logged = (ctx.log_for(hit) or {}).get('exercises') or {}
        cat = (session.get('archetype') or {}).get('category') or 'other'
        by_category[cat]['plannedSessions'] += 1
        by_category[cat]['completedSessions'] += int(completed)
        measured_session = ctx.workout_for(hit) is not None
        for ea in session.get('exercises') or []:
            if ea.get('meta') or ea.get('injury_skip') or ea.get('coverage_gap'):
                continue
            ex = ea.get('exercise') or {}
            if not ex.get('id'):
                continue
            pats = _patterns(ctx, ea)
            if not pats:
                continue
            load = ea.get('load') or {}
            bil = _bilateral(ctx, ea)
            if ea.get('slot_type') in SET_SLOT_TYPES or (load.get('sets') and not load.get('duration_minutes')):
                p_sets = float(load.get('sets') or 0)
                d_sets = 0.0
                if completed:
                    sets = [s for s in ((logged.get(ex['id']) or {}).get('sets') or []) if s.get('completed')]
                    d_sets = float(len(sets)) if sets else 0.0
                for pat in pats:
                    planned_sets[pat] += p_sets
                    done_sets[pat] += d_sets
                if bil is False:
                    unilateral['planned'] += p_sets
                    unilateral['done'] += d_sets
                unilateral['total_planned'] += p_sets
                unilateral['total_done'] += d_sets
            else:
                p_min = float(load.get('duration_minutes') or 0)
                if p_min <= 0:
                    continue
                d_min = 0.0
                if completed:
                    d_min = p_min
                    if not measured_session:
                        assumed_min += p_min
                for pat in pats:
                    planned_min[pat] += p_min
                    done_min[pat] += d_min

    def rollup(table: dict) -> dict:
        return {name: round(sum(table.get(p, 0.0) for p in pats), 1) for name, pats in ROLLUPS.items()}

    sets_roll_planned, sets_roll_done = rollup(planned_sets), rollup(done_sets)
    min_roll_planned, min_roll_done = rollup(planned_min), rollup(done_min)

    declared = [b for s in specs for b in (s.balance or [])]
    balance_rules = declared or DEFAULT_BALANCE
    balance = []
    for rule in balance_rules:
        a, b = rule['a'], rule['b']
        num = sets_roll_done.get(a, done_sets.get(a, 0.0))
        den = sets_roll_done.get(b, done_sets.get(b, 0.0))
        ratio = round(num / den, 2) if den else None
        lo, hi = float(rule.get('min', 0.6)), float(rule.get('max', 1.6))
        outside = ratio is not None and not (lo <= ratio <= hi)
        balance.append({'a': a, 'b': b, 'ratio': ratio, 'min': lo, 'max': hi,
                        'level': ('warning' if outside and declared else 'info'),
                        'outside': outside, 'declared': bool(declared)})

    return {
        'sets': {
            'patterns': sorted(({'pattern': p, 'planned': round(planned_sets[p], 1), 'done': round(done_sets[p], 1)}
                                for p in set(planned_sets) | set(done_sets)), key=lambda r: -r['planned']),
            'rollups': {k: {'planned': sets_roll_planned[k], 'done': sets_roll_done[k]} for k in ROLLUPS
                        if sets_roll_planned[k] or sets_roll_done[k]},
        },
        'minutes': {
            'patterns': sorted(({'pattern': p, 'planned': round(planned_min[p]), 'done': round(done_min[p])}
                                for p in set(planned_min) | set(done_min)), key=lambda r: -r['planned']),
            'rollups': {k: {'planned': round(min_roll_planned[k]), 'done': round(min_roll_done[k])} for k in ROLLUPS
                        if min_roll_planned[k] or min_roll_done[k]},
            'assumed': round(assumed_min),
        },
        'unilateralShare': {
            'planned': round(100.0 * unilateral['planned'] / unilateral['total_planned'], 1) if unilateral['total_planned'] else None,
            'done': round(100.0 * unilateral['done'] / unilateral['total_done'], 1) if unilateral['total_done'] else None,
        },
        'balance': balance,
        'byArchetypeCategory': dict(by_category),
    }
