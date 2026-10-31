"""The equipment an athlete can say they have: data/commons/constraints/equipment.yaml.

The one list. The schemas' enums and the clients' pickers are generated from
it (tools/gen_client_vocab.py); the server reads it here, for /api/equipment
and to read an id a client once stored under another name (`aliases`: the
phone saved "Assault Bike" as `assault_bike`, which no archetype names).
"""
from __future__ import annotations

from functools import lru_cache

from . import loader


@lru_cache(maxsize=1)
def document() -> dict:
    return loader._load_yaml(loader._data_path('commons', 'constraints', 'equipment.yaml')) or {}


def items() -> list[dict]:
    """[{id, label, aliases?}, …] in the list's order."""
    return list(document().get('equipment') or [])


def ids() -> list[str]:
    return [e['id'] for e in items()]


@lru_cache(maxsize=1)
def _alias_map() -> dict[str, str]:
    return {a: e['id'] for e in items() for a in e.get('aliases') or []}


def canonical(equipment) -> list:
    """The athlete's equipment with every alias read as its id, each once, in
    order; an id the list does not know is kept as it came (it simply serves
    nothing)."""
    if not isinstance(equipment, list):
        return equipment
    aliases = _alias_map()
    out: list = []
    for item in equipment:
        item = aliases.get(item, item) if isinstance(item, str) else item
        if item not in out:
            out.append(item)
    return out
