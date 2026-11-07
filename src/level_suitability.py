"""Which exercise suits which level, per package (docs/logic/levels.md).

Computed, never tagged: an exercise's lowest level is the lowest at which the
selector unlocks it (`selector._get_unlocked`: its `requires` chain, the
commons' level concepts, the package's own seeds — a training contract's
included — and an exercise's `min_level`), read on the package's own copies
as generation reads them (`provenance.scope`: the package first, then what it
borrows). Below it a slot that names the exercise takes its scaled versions
(`scaling_down`, nearest first) when its archetype is `scaling_eligible`.
Explore (`/explore/links`) and tools/check_exercise_coverage.py read one
table from here.
"""
from __future__ import annotations

import os

from . import levels, loader, selector


def _package_seeds(pkg: str, file_seeds: dict) -> dict:
    """A package's level seeds: its level_seeds.yaml and every training
    contract track's `level_seeds`, merged per level."""
    seeds = {lv: set(ids) for lv, ids in (file_seeds.get(pkg) or {}).items()}
    from .training_contract import _document
    path = os.path.join(loader._PACKAGES_DIR, pkg, 'training_contract.yaml')
    document = _document(path) if os.path.exists(path) else {}
    for track in (document.get('tracks') or {}).values():
        for lv, ids in (track.get('level_seeds') or {}).items():
            seeds.setdefault(lv, set()).update(ids or ())
    return seeds


def catalog(pkg: str, by_package: dict) -> dict:
    """The exercises a package's programs choose from, its own copies first,
    then those of the packages it borrows from."""
    out = dict(by_package.get(pkg) or {})
    try:
        lenders = loader.load_philosophy(pkg).get('borrows_from') or []
    except FileNotFoundError:          # a catalog with no philosophy borrows nothing
        lenders = []
    for lender in lenders:
        for eid, ex in (by_package.get(lender) or {}).items():
            out.setdefault(eid, ex)
    return out


def min_levels(pkg: str, by_package: dict, file_seeds: dict) -> dict[str, str | None]:
    """{exercise id: the lowest level it is unlocked at, None if never} for
    the exercises the package declares."""
    exercises = catalog(pkg, by_package)
    seeds = {pkg: _package_seeds(pkg, file_seeds)}
    unlocked_at = {lv: selector._get_unlocked(lv, exercises, seeds) for lv in levels.order()}
    return {eid: next((lv for lv in levels.order() if eid in unlocked_at[lv]), None)
            for eid in by_package.get(pkg) or {}}


def table(by_package: dict | None = None, packages: list[str] | None = None) -> dict:
    """{package: {exercise id: {minLevel, scalesTo}}}: `scalesTo` the
    exercise's own scaled versions, nearest first, as a slot reads them."""
    if by_package is None:
        _, by_package = loader.load_all_exercises()
    file_seeds = loader.load_level_seeds()
    out = {}
    for pkg in packages or sorted(by_package):
        own = by_package.get(pkg) or {}
        out[pkg] = {eid: {'minLevel': lv, 'scalesTo': list(own[eid].get('scaling_down') or [])}
                    for eid, lv in min_levels(pkg, by_package, file_seeds).items()}
    return out
