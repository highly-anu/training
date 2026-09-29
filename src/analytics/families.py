"""The canonical grouping of modalities into families.

Loaded from data/commons/modality_families.json, which the frontend reads too.
There used to be five copies of this grouping across Python and TypeScript;
two named modalities that do not exist and all of them dropped `combat_sport`
and `rehab` on the floor. Analytics needs a rollup that covers every modality a
program can schedule, and needs the browser to agree with the server about it.
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

_PATH = Path(__file__).resolve().parent.parent.parent / 'data' / 'commons' / 'modality_families.json'


@lru_cache(maxsize=1)
def _load() -> dict:
    with open(_PATH, encoding='utf-8') as f:
        return json.load(f)


def families() -> dict[str, list[str]]:
    """{family: [modality ids]}"""
    return dict(_load()['families'])


def family_of(modality: str | None) -> str:
    """The family a modality belongs to; 'other' for anything unknown.

    'other' is deliberate rather than an error: a stored program may carry a
    modality id from a package that has since been renamed, and analytics must
    degrade to "unclassified" rather than refuse to run.
    """
    return _family_index().get(modality or '', 'other')


def label_of(family: str) -> str:
    return _load().get('labels', {}).get(family, family.replace('_', ' ').title())


def is_strength(modality: str | None) -> bool:
    """Strength-family work: prescribed by load, and typically logged without HR."""
    return family_of(modality) == 'strength'


@lru_cache(maxsize=1)
def _family_index() -> dict[str, str]:
    return {m: fam for fam, mods in _load()['families'].items() for m in mods}
