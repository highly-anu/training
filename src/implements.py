"""The implement a training contract's loaded blocks are done with.

A contract declares it (`implement: {equipment, count}` — the document's,
which a track may override; Wildman's is the kettlebell, two for its
double-bell track) instead of the engine knowing kettlebells. The athlete's
side keeps the wire names the builders and stored programs already use, read
for any implement: `<equipment>_count` (how many matching ones they have) and
`<equipment>_weights_kg` (the weights they own). A load note and a refusal
name it in its own words: an equipment item's `noun` in
data/commons/constraints/equipment.yaml (the kettlebell's "bell"), else its
label.
"""
from __future__ import annotations

from . import equipment

_WORDS = {1: 'one', 2: 'two', 3: 'three', 4: 'four'}


def count_key(equipment_id: str) -> str:
    return f'{equipment_id}_count'


def weights_key(equipment_id: str) -> str:
    return f'{equipment_id}_weights_kg'


def _item(equipment_id: str) -> dict:
    return next((e for e in equipment.items() if e['id'] == equipment_id), {})


def noun(equipment_id: str) -> tuple[str, str]:
    """(one, many) as a note says it: ('bell', 'bells') for the kettlebell."""
    own = _item(equipment_id).get('noun')
    if own:
        return own[0], own[1]
    one = (_item(equipment_id).get('label') or equipment_id.replace('_', ' ')).lower()
    return one, f'{one}s'


def plural_label(equipment_id: str) -> str:
    """The item's label in the plural, as a refusal names it ('kettlebells')."""
    label = (_item(equipment_id).get('label') or equipment_id.replace('_', ' ')).lower()
    return f'{label}s'


def number(n: int) -> str:
    return _WORDS.get(n, str(n))


def merged(document: dict, track: dict) -> dict | None:
    """The track's implement: the document's, with the track's keys over it,
    `count` 1 unless one says more."""
    implement = {**(document.get('implement') or {}), **(track.get('implement') or {})}
    if not implement:
        return None
    return {'count': 1, **implement}


def requirement(contract: dict | None) -> dict:
    """The constraint a track asks the athlete to confirm: `{<equipment>_count: n}`
    when it needs more than one matching implement, else nothing."""
    implement = (contract or {}).get('implement') or {}
    if implement.get('count', 1) > 1:
        return {count_key(implement['equipment']): implement['count']}
    return {}


def confirm(constraints: dict, contract: dict | None) -> dict:
    """The constraints of an athlete who has what the track asks for."""
    need = requirement(contract)
    return {**constraints, **{k: max(constraints.get(k) or 0, n) for k, n in need.items()}}


def count_keys(d: dict) -> list[tuple[str, str]]:
    """(equipment, key) for each `<equipment>_count` in `d`."""
    return [(eq, count_key(eq)) for eq in equipment.ids() if count_key(eq) in d]


def weights_keys(d: dict) -> list[tuple[str, str]]:
    """(equipment, key) for each `<equipment>_weights_kg` in `d`."""
    return [(eq, weights_key(eq)) for eq in equipment.ids() if weights_key(eq) in d]


def words(contract: dict | None) -> str | None:
    """What the track asks for, in words: 'a pair of bells'; None for nothing."""
    implement = (contract or {}).get('implement') or {}
    n = implement.get('count', 1)
    if n < 2:
        return None
    many = noun(implement['equipment'])[1]
    return f'a pair of {many}' if n == 2 else f'{number(n)} matching {many}'
