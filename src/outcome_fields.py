"""What a slot lets the athlete log, on the server: data/commons/outcome_fields.yaml.

The web (lib/outcomeFields.ts) and the phone (SessionLogging.swift) read the
same table through tools/gen_client_vocab.py; this is the reading the watches'
payload and the scorecard need. `fields_for` is the clients' rule — the slot
type's fields, an exercise rule replacing them, minutes as a clock where the
slot is scored to the second. `logs` is what a watch asks for at the end of a
step: the fields the vocabulary's `capture.asked` names (reps today) that its
screen's template does not record. `needs` is what logged fields give the
analytics (the primitives' need ids), which the scorecard's X3 counts.
"""
from __future__ import annotations

import os
from functools import lru_cache

import yaml

_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     'data', 'commons', 'outcome_fields.yaml')


@lru_cache(maxsize=1)
def table() -> dict:
    with open(_FILE, encoding='utf-8') as fh:
        return yaml.safe_load(fh) or {}


def fields_for(slot_type: str | None, exercise: dict | None = None) -> list[str]:
    """The fields a slot of this type logs for this exercise (no standard:
    a test's scored slot asks for its result instead)."""
    slot = (table().get('slot_types') or {}).get(slot_type or '') or {}
    fields = list(slot.get('fields') or [])
    exercise = exercise or {}
    for rule in slot.get('when') or []:
        if rule.get('exercise_category') and exercise.get('category') != rule['exercise_category']:
            continue
        if rule.get('movement_pattern') and rule['movement_pattern'] not in (exercise.get('movement_patterns') or []):
            continue
        fields = list(rule['fields'])
        break
    if slot.get('clock'):
        fields = ['time' if f == 'minutes' else f for f in fields]
    return fields


def needs(fields) -> set[str]:
    """The analytics needs these logged fields feed."""
    by_field = table().get('needs') or {}
    return {by_field[f] for f in fields if f in by_field}


def logs(fields: list[str], asked: list[str], recorded) -> list[str]:
    """The fields a watch asks for at the end of a step: those it asks for
    (`asked`) whose need its screen does not record (`recorded`, the
    template's need ids)."""
    by_field = table().get('needs') or {}
    recorded = set(recorded or [])
    return [f for f in fields if f in asked and by_field.get(f) not in recorded]
