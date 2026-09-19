#!/usr/bin/env python
"""Unit tests for the package source policy.

Run: .venv/bin/python test_provenance.py
"""
from __future__ import annotations

import sys

from src import goals, loader, provenance

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def policy_with_borrow(**borrow) -> provenance.SourcePolicy:
    """A policy owning 'owner' that borrows from 'lender' on the given terms."""
    entry = {'package': 'lender', 'label': 'Lender', 'reason': 'test', **borrow}
    phil = {'id': 'owner', 'borrows_from': [entry]}
    return provenance.SourcePolicy(
        owner_packages=frozenset({'owner'}),
        borrows=provenance._parse_borrows(phil),
        strict=True,
    )


def test_ownership() -> None:
    print('ownership')
    policy = provenance.SourcePolicy(owner_packages=frozenset({'owner'}), strict=True)

    check('own archetype allowed',
          provenance.allows_archetype({'_package': 'owner', 'modality': 'x'}, policy))
    check('foreign archetype blocked',
          not provenance.allows_archetype({'_package': 'other', 'modality': 'x'}, policy))
    check('unattributed archetype allowed',
          provenance.allows_archetype({'_package': None, 'modality': 'x'}, policy))

    check('own exercise allowed',
          provenance.allows_exercise({'id': 'a', '_packages': ['owner']}, policy))
    check('foreign exercise blocked',
          not provenance.allows_exercise({'id': 'a', '_packages': ['other']}, policy))
    check('multi-package exercise allowed when owner is one declarer',
          provenance.allows_exercise({'id': 'a', '_packages': ['other', 'owner']}, policy))
    check('falls back to _package when _packages absent',
          provenance.allows_exercise({'id': 'a', '_package': 'owner'}, policy))


def test_borrows() -> None:
    print('declared borrowing')
    policy = policy_with_borrow(modalities=['max_strength'])

    check('borrowed archetype allowed for declared modality',
          provenance.allows_archetype(
              {'id': 'z', '_package': 'lender', 'modality': 'max_strength'}, policy))
    check('borrowed archetype blocked for other modality',
          not provenance.allows_archetype(
              {'id': 'z', '_package': 'lender', 'modality': 'aerobic_base'}, policy))
    check('undeclared package still blocked',
          not provenance.allows_archetype(
              {'id': 'z', '_package': 'stranger', 'modality': 'max_strength'}, policy))

    any_mod = policy_with_borrow()
    check('omitted modalities means any modality',
          provenance.allows_archetype(
              {'id': 'z', '_package': 'lender', 'modality': 'anything'}, any_mod))

    narrowed = policy_with_borrow(archetypes=['only_this'])
    check('archetype allowlist narrows the borrow',
          provenance.allows_archetype(
              {'id': 'only_this', '_package': 'lender', 'modality': 'm'}, narrowed)
          and not provenance.allows_archetype(
              {'id': 'something_else', '_package': 'lender', 'modality': 'm'}, narrowed))

    ex_narrowed = policy_with_borrow(exercises=['squat'])
    check('exercise allowlist narrows the borrow',
          provenance.allows_exercise({'id': 'squat', '_packages': ['lender']}, ex_narrowed)
          and not provenance.allows_exercise(
              {'id': 'curl', '_packages': ['lender']}, ex_narrowed))

    check('self-reference in borrows_from is ignored',
          provenance._parse_borrows({'id': 'owner', 'borrows_from': [{'package': 'owner'}]}) == {})


def test_origin_tags() -> None:
    print('provenance tags')
    policy = policy_with_borrow(modalities=['max_strength'])

    owned = provenance.origin({'_package': 'owner'}, policy)
    check('owned session is not marked borrowed', owned == {'package': 'owner', 'borrowed': False})

    borrowed = provenance.origin({'_package': 'lender'}, policy)
    check('borrowed session carries label and reason',
          borrowed['borrowed'] and borrowed['label'] == 'Lender' and borrowed['reason'] == 'test',
          str(borrowed))


def test_no_owner_allows_everything() -> None:
    print('unscoped policy')
    policy = provenance.resolve_source_policy({'primary_sources': []})
    check('custom-priority program is unrestricted',
          provenance.allows_archetype({'_package': 'anything', 'modality': 'm'}, policy)
          and not policy.strict)


def test_scope_prefers_owner_prescription() -> None:
    print('scope()')
    data = {
        'archetypes': [
            {'id': 'keep', '_package': 'owner', 'modality': 'm'},
            {'id': 'drop', '_package': 'stranger', 'modality': 'm'},
        ],
        'exercises': {},
        'exercises_by_package': {
            'owner':    {'shared': {'id': 'shared', '_packages': ['owner'], 'starting_load_kg': {'novice': 40}}},
            'lender':   {'shared': {'id': 'shared', '_packages': ['lender'], 'starting_load_kg': {'novice': 60}},
                         'lent':   {'id': 'lent', '_packages': ['lender']}},
            'stranger': {'nope': {'id': 'nope', '_packages': ['stranger']}},
        },
        'modalities': {}, 'injury_flags': {},
    }
    policy = policy_with_borrow()
    lib = provenance.scope(data, policy)

    check('foreign archetype dropped', [a['id'] for a in lib['archetypes']] == ['keep'])
    check('stranger exercise excluded', 'nope' not in lib['exercises'])
    check('borrowed exercise included', 'lent' in lib['exercises'])
    check("owner's prescription wins for a shared id",
          lib['exercises']['shared']['starting_load_kg']['novice'] == 40)
    check('full library retained for non-strict fallback',
          len(lib['all_archetypes']) == 2)


def test_real_philosophies() -> None:
    print('real packages')
    frameworks = list(loader.load_all_frameworks().values())
    for phil in loader.load_philosophies():
        goal = goals.philosophy_to_goal(phil['id'], frameworks)
        policy = provenance.resolve_source_policy(goal)
        check(f"{phil['id']} owns exactly itself",
              policy.owner_packages == frozenset({phil['id']}))
        for pkg in policy.borrows:
            check(f"{phil['id']} borrows from an installed package: {pkg}",
                  pkg in {p['id'] for p in loader.load_philosophies()})


def main() -> int:
    for test in (test_ownership, test_borrows, test_origin_tags,
                 test_no_owner_allows_everything, test_scope_prefers_owner_prescription,
                 test_real_philosophies):
        test()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s): {FAILURES}")
        return 1
    print('All provenance tests passed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
