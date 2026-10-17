"""Whether a session's heart rate counts, and the minutes it plans per zone —
read from the session's own programming.

Each slot's `intensity` is its prescription. A zone token (`zone2`, `zone3_4`)
or a word that names a band (`low`, `moderate`, `high` —
progression._INTENSITY_ZONES) prescribes heart-rate zones; `heavy`,
`max_effort`, `bodyweight` prescribe load or effort instead. A session
**tracks heart rate** when what it prescribes is zones throughout: at least
one slot names a zone and none prescribes load or effort. A kettlebell
ballistic session does, whatever its modality family; a Starting Strength
day, a Horsemen strength block or a PT test do not, and their minutes count
as max effort. An archetype may say so outright — `heart_rate: track |
ignore` — where its slots do not tell the whole story. A session that
prescribes nothing either way falls back to the modality family.

Until 2026-10-17 the family alone decided: every strength-family session was
max effort even when it recorded heart rate, so a Wildman ballistic session
the athlete wore a strap for vanished from the per-zone minutes, and
kettlebell weeks read 44 % max effort against a framework that plans none.

The stored session carries its archetype (slots and all), so this reads any
program, old or new, with no regenerate. Pure.
"""
from __future__ import annotations

import re

from src import progression
from src.analytics.families import is_strength

ZONES = 5

# Words progression maps to a band for the HR window it shows, but that
# prescribe load: Starting Strength's `progressing` is the bar going up.
_LOAD_WORDS = {'progressing'}


def slot_zones(intensity) -> list[int]:
    """The zones (1-5) a slot's intensity token prescribes. `zoneN` is that
    zone and `zoneA_B` the zones from A to B, read off the token itself —
    progression's band widens `zone2` to 1-2 for the HR window it shows, but
    a Zone 2 session is planned as Zone 2. Words (`light`, `hard`) take
    progression's band. Anything else (`heavy`, `bodyweight`) has no zone."""
    if not isinstance(intensity, str) or intensity.strip().lower() in _LOAD_WORDS:
        return []
    m = re.fullmatch(r'zone([1-5])(?:_([1-5]))?', intensity.strip().lower())
    if m:
        lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
    else:
        lo, hi, _ = progression.zone_band(intensity)
        if lo is None:
            return []
    return list(range(lo, hi + 1))


def _num(value) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def slot_minutes(slot: dict, assignments: list[dict]) -> float:
    """A slot's planned minutes: its assignments' prescribed time (the
    longest, so a circuit of three exercises in one block counts once),
    else the slot's own authored duration."""
    loads = [ea.get('load') if isinstance(ea.get('load'), dict) else {}
             for ea in assignments if not ea.get('injury_skip')]
    prescribed = [_num(load.get('duration_minutes')) or _num(load.get('time_minutes')) for load in loads]
    if any(prescribed):
        return max(prescribed)
    if _num(slot.get('duration_minutes')):
        return _num(slot['duration_minutes'])
    work = _num(slot.get('work_sec')) or _num(slot.get('duration_sec'))
    if work and _num(slot.get('sets')):
        return _num(slot['sets']) * (work + _num(slot.get('rest_sec'))) / 60.0
    return _num(slot.get('duration_sec')) / 60.0


def plan(session: dict) -> dict:
    """{track, source, plannedMinutes [Z1..Z5], notZoned [role: intensity]}.

    `source` says what decided: `declared` (the archetype's `heart_rate`),
    `slots` (its prescriptions) or `modality` (nothing prescribed either way).
    Planned minutes are the zoned slots' minutes, a slot spanning zones split
    evenly; a slot whose every exercise an injury removed plans nothing."""
    arch = session.get('archetype') if isinstance(session.get('archetype'), dict) else {}
    exercises = [ea for ea in (session.get('exercises') or []) if isinstance(ea, dict)]
    planned = [0.0] * ZONES
    zoned, not_zoned = 0, []
    for slot in arch.get('slots') or []:
        assigned = [ea for ea in exercises if ea.get('slot_role') == slot.get('role')]
        if assigned and all(ea.get('injury_skip') for ea in assigned):
            continue
        intensity = slot.get('intensity')
        zs = slot_zones(intensity)
        if zs:
            zoned += 1
            minutes = slot_minutes(slot, assigned)
            for z in zs:
                planned[z - 1] += minutes / len(zs)
        elif isinstance(intensity, str) and intensity.strip():
            not_zoned.append(f"{slot.get('role')}: {intensity}")
    declared = arch.get('heart_rate')
    if declared in ('track', 'ignore'):
        track, source = declared == 'track', 'declared'
    elif zoned or not_zoned:
        track, source = bool(zoned) and not not_zoned, 'slots'
    else:
        track, source = not is_strength(session.get('modality')), 'modality'
    return {'track': track, 'source': source, 'plannedMinutes': [round(m, 1) for m in planned],
            'notZoned': not_zoned}


def tracks(session: dict) -> bool:
    return plan(session)['track']
