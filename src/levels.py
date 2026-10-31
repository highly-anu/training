"""The athlete's training levels: data/commons/training_levels.yaml.

One list for every reader — the selector's seed cascade and its elite rule,
a distance slot's share, every sort by level and the default. Until
2026-10-31 each kept its own copy (eleven on the server, more in the clients
and schemas, which tools/gen_client_vocab.py now writes from the same file).
"""
from __future__ import annotations

import os
from functools import lru_cache

import yaml

_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     'data', 'commons', 'training_levels.yaml')


@lru_cache(maxsize=1)
def _doc() -> dict:
    with open(_FILE, encoding='utf-8') as fh:
        return yaml.safe_load(fh) or {}


@lru_cache(maxsize=1)
def order() -> tuple[str, ...]:
    """The level ids, lowest first."""
    return tuple(lv['id'] for lv in _doc()['levels'])


def default() -> str:
    return _doc().get('default') or order()[0]


def rank(level: str | None) -> int:
    """A level's place in the order; an unknown level sorts last."""
    return order().index(level) if level in order() else len(order())


def up_to(level: str | None) -> tuple[str, ...]:
    """The levels at or below this one (the lowest alone for an unknown level)."""
    i = order().index(level) if level in order() else 0
    return order()[:i + 1]


def _entry(level: str | None) -> dict:
    return next((lv for lv in _doc()['levels'] if lv['id'] == level), {})


def unlocks_all(level: str | None) -> bool:
    return bool(_entry(level).get('unlocks_all'))


def distance_multiplier(level: str | None) -> float:
    """A distance slot's share of its metres at this level; the default
    level's for an unknown one."""
    return float(_entry(level).get('distance_multiplier') or _entry(default())['distance_multiplier'])


def label(level: str | None) -> str:
    return _entry(level).get('label') or (level or '')
