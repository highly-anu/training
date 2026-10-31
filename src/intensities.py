"""The slot intensities and what each reader makes of one: data/commons/intensities.yaml.

Progression's zone bands, the selector's main-lift words, fidelity's buckets,
the heart-rate plan's load words and the recovery regions' weights each kept a
table of their own until 2026-10-31; the file says where they still disagree.
"""
from __future__ import annotations

import os
from functools import lru_cache

import yaml

_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     'data', 'commons', 'intensities.yaml')


@lru_cache(maxsize=1)
def table() -> dict:
    with open(_FILE, encoding='utf-8') as fh:
        return (yaml.safe_load(fh) or {}).get('intensities') or {}


def zones() -> dict[str, tuple[int, int, str]]:
    """token -> (lower, upper, label), for the tokens that have a band."""
    return {t: tuple(e['zone']) for t, e in table().items() if e.get('zone')}


def main_lift() -> frozenset:
    return frozenset(t for t, e in table().items() if e.get('main_lift'))


def fidelity_buckets() -> dict[str, str]:
    return {t: e['fidelity_bucket'] for t, e in table().items() if e.get('fidelity_bucket')}


def hr_load() -> frozenset:
    return frozenset(t for t, e in table().items() if e.get('hr_load'))


def recovery_weights() -> dict[str, float]:
    return {t: e['recovery_weight'] for t, e in table().items() if 'recovery_weight' in e}


def authoring() -> list[str]:
    """The tokens an author may write (the schema's enum, the dialogs' list)."""
    return [t for t, e in table().items() if e.get('authoring', True)]
