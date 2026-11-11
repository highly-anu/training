"""Which exercise suits which level, per package (docs/logic/levels.md).

Computed, never tagged: an exercise's lowest level is the lowest at which the
selector unlocks it (`selector._get_unlocked`: its `requires` chain, the
commons' level concepts, the package's own seeds — a training contract's
included — and an exercise's `min_level`), raised to the lowest level the
package's sessions name it for (a version written for advanced athletes names
its moves for them), read on the package's own copies
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


def _named_by(pkg: str, archetypes: list | None = None) -> dict[str, set]:
    """{exercise id: the lowest level of each session the package names it in}:
    its archetypes' slots and its training contracts' blocks, each for the
    levels it lists (Ido's advanced routine's moves are an advanced athlete's;
    a scaled session lists the levels that do it scaled)."""
    if archetypes is None:
        archetypes = [a for a in loader.load_all_archetypes() if a.get('_package') == pkg]
    out: dict[str, set] = {}

    def note(ids, written_for):
        lowest = min(written_for, key=levels.rank) if written_for else levels.order()[0]
        for eid in ids or []:
            out.setdefault(eid, set()).add(lowest)

    for a in archetypes:
        for slot in a.get('slots') or []:
            note((slot.get('exercise_filter') or {}).get('exercise_ids'), a.get('training_levels'))
    from .training_contract import _document
    path = os.path.join(loader._PACKAGES_DIR, pkg, 'training_contract.yaml')
    for track in ((_document(path) if os.path.exists(path) else {}).get('tracks') or {}).values():
        for module in track.get('modules') or []:
            written_for = module.get('training_levels') or track.get('training_levels')
            blocks = list(module.get('blocks') or []) + [b for v in module.get('variants') or []
                                                         for b in v.get('blocks') or []]
            note([i for b in blocks for i in [b.get('exercise_id')] + list(b.get('alternatives') or []) if i],
                 written_for)
    return out


def min_levels(pkg: str, by_package: dict, file_seeds: dict, archetypes: list | None = None) -> dict[str, str | None]:
    """{exercise id: the lowest level it suits, None if never} for the
    exercises the package declares: the lowest level that unlocks it, raised
    to the lowest level any of the package's sessions names it for (an
    exercise no session names, only a slot's filter reaches, keeps its
    unlock level)."""
    exercises = catalog(pkg, by_package)
    seeds = {pkg: _package_seeds(pkg, file_seeds)}
    unlocked_at = {lv: selector._get_unlocked(lv, exercises, seeds) for lv in levels.order()}
    named = _named_by(pkg, archetypes)
    out = {}
    for eid in by_package.get(pkg) or {}:
        unlock = next((lv for lv in levels.order() if eid in unlocked_at[lv]), None)
        floor = min(named[eid], key=levels.rank) if eid in named else None
        out[eid] = unlock if unlock is None or floor is None else max(unlock, floor, key=levels.rank)
    return out


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
