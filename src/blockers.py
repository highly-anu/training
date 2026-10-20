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


def held_back(weeks: list) -> dict:
    """How much of a program (the API's weeks: day name → sessions) its
    constraints held back: the slots left empty for a reason — `blocked_by`
    or the older flags — and the sessions with any, or standing in for
    another modality, or scaled for missing equipment, or with no archetype.
    Served with every generate, so both clients show the server's count."""
    slots = sessions = 0
    for week in weeks or []:
        for day_sessions in (week.get('schedule') or {}).values():
            for s in day_sessions or []:
                n = sum(1 for ea in s.get('exercises') or []
                        if ea.get('exercise') is None and not ea.get('meta') and not ea.get('skip_exercise')
                        and (ea.get('blocked_by') or ea.get('injury_skip') or ea.get('equipment_gap')
                             or ea.get('coverage_gap')))
                slots += n
                if n or s.get('substituted_for') or s.get('equipment_scaled') \
                        or (not s.get('archetype') and s.get('error')):
                    sessions += 1
    return {'slots': slots, 'sessions': sessions}


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
