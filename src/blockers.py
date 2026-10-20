"""What in the athlete's constraints rules out one exercise, read from the exercise.

Shared by the selector, which names what emptied a slot (`blocked_by`), and
the constraint-impact comparison, which words the same reasons for a change.
"""
from __future__ import annotations

NOT_EQUIPMENT = frozenset({'none', 'open_space'})


def missing_equipment(required, available) -> list[str]:
    """The items `required` asks for that `available` lacks (open space and
    'none' are never missing)."""
    return sorted(set(required or []) - set(available or []) - NOT_EQUIPMENT)


def flag_hits(ex: dict, flags, flag_data: dict) -> list[tuple[str, list[str]]]:
    """Each of `flags` that rules `ex` out, with the excluded patterns it hits
    (empty when the flag names the exercise itself)."""
    out = []
    patterns = set(ex.get('movement_patterns') or [])
    for fid in flags or []:
        flag = flag_data.get(fid) or {}
        hit = sorted(patterns & set(flag.get('excluded_movement_patterns') or []))
        if ex.get('id') in (flag.get('excluded_exercises') or []) or fid in (ex.get('contraindicated_with') or []):
            out.append((fid, []))
        elif hit:
            out.append((fid, hit))
    return out
