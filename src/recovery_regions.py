"""Where a session's work lands on the body: lower, upper push, upper pull,
trunk, cardio (data/commons/recovery_regions.yaml).

Derived, never tagged: an exercise's region weights are its movement
patterns'; a session's load on a region is the modality's recovery cost x the
mean over its working slots of the slot's intensity x its exercise's weight.
Modality recovery (`recovery_cost`, `recovery_hours_min`) says how hard a
session is; this says where, so two strength days that load the legs read
differently from a leg day and a pressing day.

Used where the app chooses — the archetype picker (selector.select_archetype)
and a training contract's placement (training_contract._spacing) — as a soft
penalty, and read by fidelity as information. A week a source writes day by
day is never rearranged.
"""
from __future__ import annotations

import os
from functools import lru_cache

from src import intensities, loader

_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     'data', 'commons', 'recovery_regions.yaml')


@lru_cache(maxsize=1)
def config() -> dict:
    with open(_PATH, encoding='utf-8') as f:
        return loader.safe_load(f)


def pattern_weights(patterns) -> dict[str, float]:
    """An exercise's weight on each region: the largest of its patterns'."""
    table = config()['patterns']
    out: dict[str, float] = {}
    for p in patterns or []:
        for region, w in (table.get(p) or {}).items():
            out[region] = max(out.get(region, 0), w)
    return out


def _filter_patterns(ex_filter: dict) -> list[str]:
    """The patterns a slot's movement filter names, through the aliases."""
    from .selector import _PATTERN_ALIASES
    req = ex_filter.get('movement_pattern')
    reqs = req if isinstance(req, list) else [req] if req else []
    out: list[str] = []
    for r in reqs:
        alias = _PATTERN_ALIASES.get(r)
        out += list(alias[1]) if alias else [r]
    return out


def _working(role: str | None) -> bool:
    role = (role or '').lower()
    return not any(w in role for w in config().get('warm_up_roles') or [])


def _load(cost: str | None, slots: list[tuple[float, dict]]) -> dict[str, float]:
    """slots: (intensity weight, region weights) per working slot."""
    if not slots:
        return {}
    cfg = config()
    k = cfg['cost_weight'].get(cost or 'low', cfg['cost_weight']['low'])
    out: dict[str, float] = {}
    for iw, weights in slots:
        for region, w in weights.items():
            out[region] = out.get(region, 0) + iw * w
    return {r: round(k * v / len(slots), 3) for r, v in out.items()}


def _intensity(slot: dict, slot_type: str | None = None) -> float:
    cfg = config()
    return (intensities.recovery_weights().get(str(slot.get('intensity')), 1)
            * (cfg.get('slot_type_weight') or {}).get(slot_type or slot.get('slot_type'), 1))


def archetype_load(arch: dict, exercises: dict, modalities: dict) -> dict[str, float]:
    """A session shape's load, before its exercises are picked: each slot's
    first named exercise (1,748 of 1,762 slots name theirs), else the patterns
    its movement filter asks for. An archetype's `regional_load` overrides."""
    if arch.get('regional_load'):
        return dict(arch['regional_load'])
    slots = []
    for s in arch.get('slots') or []:
        if s.get('skip_exercise') or s.get('is_meta') or not _working(s.get('role')):
            continue
        f = s.get('exercise_filter') or {}
        ids = f.get('exercise_ids') or []
        ex = exercises.get(ids[0]) if ids else None
        patterns = (ex or {}).get('movement_patterns') or _filter_patterns(f)
        slots.append((_intensity(s), pattern_weights(patterns)))
    return _load((modalities.get(arch.get('modality')) or {}).get('recovery_cost'), slots)


def session_load(session: dict, modalities: dict) -> dict[str, float]:
    """A populated session's load, from the exercises it was given."""
    arch = session.get('archetype') or {}
    if isinstance(arch, dict) and arch.get('regional_load'):
        return dict(arch['regional_load'])
    slots = []
    for ea in session.get('exercises') or []:
        ex = ea.get('exercise')
        slot = ea.get('slot') or {}
        if ex is None or ea.get('meta') or not _working(ea.get('slot_role') or slot.get('role')):
            continue
        slots.append((_intensity(slot, ea.get('slot_type')), pattern_weights(ex.get('movement_patterns'))))
    return _load((modalities.get(session.get('modality')) or {}).get('recovery_cost'), slots)


def heavy(load: dict[str, float]) -> frozenset:
    at = config()['heavy_at']
    return frozenset(r for r, v in load.items() if v >= at)


def penalty(regions: frozenset, recent: list[tuple[int, frozenset]]) -> int:
    """What sharing heavy regions with recent sessions costs: per shared region,
    the penalty of the tightest window it falls in; capped."""
    cfg = config()
    windows = sorted((int(h), p) for h, p in cfg['penalty_by_hours'].items())
    total = 0
    for hours, other in recent:
        p = next((p for h, p in windows if hours <= h), 0)
        total += p * len(regions & other)
    return min(total, cfg['penalty_cap'])
