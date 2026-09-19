"""Which philosophy packages a program is allowed to draw from.

A philosophy package is meant to be self-contained: a Horsemen program should
contain Horsemen content. It did not work out that way, because several code
paths fell back to the full cross-package library whenever the requested
package could not fill a slot. Measured on a 5-day/75-min request, 12 of 20
Horsemen sessions came from CrossFit, Gym Jones, Starting Strength, Uphill
Athlete and Wildman.

Borrowing is legitimate — Horsemen's own notes say it draws on Gym Jones,
Mountain Athlete, CrossFit and Dan John — but it has to be *declared*, in
`philosophy.yaml`, so it is authored intent rather than an accident of glob
order, and so the UI can label it:

    borrows_from:
      - package: gym_jones
        label: "Gym Jones"
        reason: "The strength block is explicitly Twight-derived."
        modalities: [max_strength]     # omit or ['*'] for any
        kinds: [exercises]             # movements only, not session designs

This module is the single place that answers "is this allowed", so the
validate path in api.py and the generate path in generator.py cannot drift
into checking different libraries again.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

from . import loader

ANY = '*'


@dataclass(frozen=True)
class Borrow:
    package: str
    label: str
    reason: str
    modalities: frozenset       # frozenset({'*'}) means any modality
    archetypes: frozenset       # empty means any archetype in the package
    exercises: frozenset        # empty means any exercise in the package
    kinds: frozenset            # {'archetypes', 'exercises'} — what may be taken

    def allows_modality(self, modality: str | None) -> bool:
        if ANY in self.modalities:
            return True
        if modality is None:
            return True
        return modality in self.modalities


@dataclass(frozen=True)
class SourcePolicy:
    """The packages a goal may draw from, and on what terms."""
    owner_packages: frozenset = frozenset()
    borrows: dict = field(default_factory=dict)   # package -> Borrow
    strict: bool = False

    @property
    def allowed_packages(self) -> frozenset:
        return self.owner_packages | frozenset(self.borrows)

    def owns(self, package: str | None) -> bool:
        return package in self.owner_packages

    def describe(self) -> str:
        owners = ', '.join(sorted(self.owner_packages)) or '(none)'
        if not self.borrows:
            return owners
        return f"{owners} (+ borrows: {', '.join(sorted(self.borrows))})"


def _as_frozenset(value) -> frozenset:
    if value is None:
        return frozenset()
    if isinstance(value, str):
        return frozenset({value})
    return frozenset(value)


def _parse_borrows(phil: dict) -> dict:
    borrows: dict = {}
    for entry in phil.get('borrows_from', []) or []:
        if isinstance(entry, str):
            entry = {'package': entry}
        pkg = entry.get('package')
        if not pkg or pkg == phil.get('id'):
            continue  # self-reference is meaningless
        modalities = _as_frozenset(entry.get('modalities')) or frozenset({ANY})
        # Default is both. `kinds: [exercises]` borrows the movements while the
        # borrowing philosophy keeps its own session designs — usually what is
        # meant when a package needs a barbell it does not define.
        kinds = _as_frozenset(entry.get('kinds')) or frozenset({'archetypes', 'exercises'})
        borrows[pkg] = Borrow(
            package=pkg,
            label=entry.get('label') or pkg.replace('_', ' ').title(),
            reason=entry.get('reason', ''),
            modalities=modalities,
            archetypes=_as_frozenset(entry.get('archetypes')),
            exercises=_as_frozenset(entry.get('exercises')),
            kinds=kinds,
        )
    return borrows


def resolve_source_policy(goal: dict) -> SourcePolicy:
    """Build the policy for a goal from its `primary_sources`.

    `strict` is opt-in per philosophy via `self_contained: true`, so enforcement
    can land package-by-package. A blend is strict only if every member is.
    """
    owners = [p for p in goal.get('primary_sources', []) if p]
    if not owners:
        # No philosophy context (e.g. a custom-priority program): allow everything.
        return SourcePolicy()

    borrows: dict = {}
    strict_flags: list = []
    for owner in owners:
        try:
            phil = loader.load_philosophy(owner)
        except (FileNotFoundError, KeyError):
            strict_flags.append(False)
            continue
        strict_flags.append(bool(phil.get('self_contained')))
        for pkg, borrow in _parse_borrows(phil).items():
            if pkg in owners:
                continue  # already an owner in a blend
            borrows[pkg] = borrow

    return SourcePolicy(
        owner_packages=frozenset(owners),
        borrows=borrows,
        strict=bool(strict_flags) and all(strict_flags),
    )


# ---------------------------------------------------------------------------
# Membership tests
# ---------------------------------------------------------------------------

def allows_archetype(arch: dict, policy: SourcePolicy) -> bool:
    if not policy.owner_packages:
        return True
    pkg = arch.get('_package')
    if pkg is None or policy.owns(pkg):
        return True
    borrow = policy.borrows.get(pkg)
    if borrow is None:
        return False
    if 'archetypes' not in borrow.kinds:
        return False
    if borrow.archetypes and arch.get('id') not in borrow.archetypes:
        return False
    return borrow.allows_modality(arch.get('modality'))


def exercise_packages(ex: dict) -> list:
    """Every package declaring this exercise id.

    `_package` is only the first declarer; 76 ids are declared by more than one
    package, so provenance must read `_packages`.
    """
    packages = ex.get('_packages')
    if packages:
        return list(packages)
    pkg = ex.get('_package')
    return [pkg] if pkg else []


def allows_exercise(ex: dict, policy: SourcePolicy, modality: str | None = None) -> bool:
    if not policy.owner_packages:
        return True
    packages = exercise_packages(ex)
    if not packages:
        return True  # unattributed — treat as commons
    if any(policy.owns(p) for p in packages):
        return True
    for pkg in packages:
        borrow = policy.borrows.get(pkg)
        if borrow is None:
            continue
        if 'exercises' not in borrow.kinds:
            continue
        if borrow.exercises and ex.get('id') not in borrow.exercises:
            continue
        if borrow.allows_modality(modality):
            return True
    return False


def origin(entity: dict, policy: SourcePolicy, kind: str = 'archetype') -> dict | None:
    """Provenance tag for the API response, or None when the entity is owned."""
    packages = (
        [entity.get('_package')] if kind == 'archetype'
        else exercise_packages(entity)
    )
    packages = [p for p in packages if p]
    if not packages:
        return None
    owned = next((p for p in packages if policy.owns(p)), None)
    if owned:
        return {'package': owned, 'borrowed': False}
    for pkg in packages:
        borrow = policy.borrows.get(pkg)
        if borrow:
            return {
                'package': pkg,
                'borrowed': True,
                'label': borrow.label,
                'reason': borrow.reason,
            }
    return {'package': packages[0], 'borrowed': True}


# ---------------------------------------------------------------------------
# Library scoping
# ---------------------------------------------------------------------------

def scope(data: dict, policy: SourcePolicy) -> dict:
    """Narrow a `loader.load_all_data()` dict to what the policy permits.

    Returns the same keys, so call sites change by one line. Modalities and
    injury flags are genuinely shared (data/commons/) and pass through.
    """
    if not policy.owner_packages:
        return data

    archetypes = [a for a in data.get('archetypes', []) if allows_archetype(a, policy)]

    by_package = data.get('exercises_by_package', {}) or {}
    exercises: dict = {}
    # Owners first, so an id declared by both an owner and a borrow keeps the
    # owner's prescription fields (starting loads differ per package).
    for pkg in sorted(policy.owner_packages):
        for ex_id, ex in (by_package.get(pkg) or {}).items():
            exercises.setdefault(ex_id, ex)
    for pkg in sorted(policy.borrows):
        for ex_id, ex in (by_package.get(pkg) or {}).items():
            if ex_id in exercises:
                continue
            if allows_exercise(ex, policy):
                exercises[ex_id] = ex

    scoped_by_package = {
        pkg: exs for pkg, exs in by_package.items()
        if pkg in policy.allowed_packages
    }

    scoped_seeds = {
        pkg: seeds for pkg, seeds in (data.get('level_seeds') or {}).items()
        if pkg in policy.allowed_packages
    }

    return {
        **data,
        'archetypes': archetypes,
        'exercises': exercises,
        'exercises_by_package': scoped_by_package,
        'level_seeds': scoped_seeds,
        'all_archetypes': data.get('archetypes', []),
        'all_exercises': data.get('exercises', {}),
    }


def uncovered_modalities(
    modalities: Iterable[str], archetypes: list, phases: Iterable[str] | None = None,
) -> list:
    """Modalities with no archetype in the scoped pool (optionally per phase)."""
    have: set = set()
    for arch in archetypes:
        mod = arch.get('modality')
        if mod is None:
            continue
        if phases is None:
            have.add(mod)
        elif set(arch.get('applicable_phases', [])) & set(phases):
            have.add(mod)
    return sorted(m for m in set(modalities) if m not in have)
