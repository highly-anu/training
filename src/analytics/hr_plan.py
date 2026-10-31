"""Which of a session's heart rate counts in the zone minutes — exercise by
exercise, read from the session's own programming.

An exercise's prescription is its slot's `intensity`, or, for a slot that
names none, the zone its load carries (`zone_lower`/`zone_upper`, which
progression writes for a timed slot). A zone token (`zone2`, `zone3_4`) or a
word that names a band (`low`, `moderate`, `high` —
data/commons/intensities.yaml) prescribes heart-rate zones; `heavy`,
`max_effort`, `bodyweight`, `progressing` prescribe load or effort.

**Heart rate counts only where an exercise prescribes zones** (`plan` →
`mode`, `attribute` → `timing`):

- every exercise that prescribes anything prescribes zones (a Zone 2 run, a
  kettlebell ballistic session): the whole recording counts (`whole`);
- some prescribe zones and some load or effort (Fran's Zone 2 warm-up before
  the max-effort piece): only the minutes the watch timed on the zoned
  exercises count (`timeline`, from the session log's `exerciseTimeline` or
  its sets' offsets) and the rest of the session is max effort. Without those
  times nothing counts in zones (`untimed`) — the warm-up's minutes cannot be
  told from the main piece's;
- none prescribes zones: nothing counts (`none`); the session is max effort.

An archetype may say `heart_rate: track | ignore` where its slots do not tell
the whole story. A session stored without its archetype's slots falls back to
the modality family.

Until 2026-10-17 the family alone decided: every strength-family session was
max effort even when it recorded heart rate, so a Wildman ballistic session
the athlete wore a strap for vanished from the per-zone minutes, and
kettlebell weeks read 44 % max effort against a framework that plans none;
and a conditioning session's warm-up and max-effort piece counted alike.

The stored session carries its archetype (slots and all), so this reads any
program, old or new, with no regenerate. Pure.
"""
from __future__ import annotations

import re

from src import intensities, progression
from src.analytics import zones
from src.analytics.families import is_strength

ZONES = 5

# Words progression maps to a band for the HR window it shows, but that
# prescribe load: Starting Strength's `progressing` is the bar going up.
_LOAD_WORDS = intensities.hr_load()   # data/commons/intensities.yaml


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


def _load_zones(load) -> list[int]:
    """The zones an exercise's own prescription carries: the band progression
    wrote for a timed slot, else the intensity a distance slot keeps."""
    if not isinstance(load, dict):
        return []
    lo, hi = load.get('zone_lower'), load.get('zone_upper')
    if isinstance(lo, (int, float)) and isinstance(hi, (int, float)) and 1 <= lo <= hi <= ZONES:
        return list(range(int(lo), int(hi) + 1))
    return slot_zones(load.get('intensity'))


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


def _exercise(ea: dict) -> dict:
    return ea.get('exercise') if isinstance(ea.get('exercise'), dict) else {}


def _slots(session: dict) -> list[dict]:
    """Each slot that prescribes something, with what: `zones` (and the
    minutes it plans in them) or `load`. A slot whose every exercise an
    injury removed prescribes nothing; an AMRAP's movements belong to it."""
    arch = session.get('archetype') if isinstance(session.get('archetype'), dict) else {}
    exercises = [ea for ea in (session.get('exercises') or []) if isinstance(ea, dict)]
    out = []
    for slot in arch.get('slots') or []:
        if not isinstance(slot, dict) or slot.get('parent_slot_role'):
            continue
        role = slot.get('role')
        assigned = [ea for ea in exercises if ea.get('slot_role') == role]
        if assigned and all(ea.get('injury_skip') for ea in assigned):
            continue
        live = [ea for ea in assigned if not ea.get('injury_skip')]
        intensity = slot.get('intensity')
        named = isinstance(intensity, str) and bool(intensity.strip())
        zs = slot_zones(intensity) if named else next(
            (z for z in (_load_zones(ea.get('load')) for ea in live) if z), [])
        if not zs and not named:
            continue
        names = []
        for ea in live:
            name = _exercise(ea).get('name') or _exercise(ea).get('id')
            if name and name not in names:
                names.append(name)
        out.append({'role': role, 'intensity': intensity, 'zones': zs,
                    'prescribes': 'zones' if zs else 'load',
                    'minutes': slot_minutes(slot, assigned) if zs else 0.0,
                    'exercises': names})
    return out


def plan(session: dict) -> dict:
    """{track, mode, source, plannedMinutes [Z1..Z5], notZoned [role: intensity], slots}.

    `mode` is what counts: `whole` (the recording), `exercises` (only the
    zoned exercises' timed minutes) or `none`. `source` says what decided:
    `declared` (the archetype's `heart_rate`), `slots` or `modality` (no
    slots stored). Planned minutes are the zoned slots' minutes, a slot
    spanning zones split evenly."""
    arch = session.get('archetype') if isinstance(session.get('archetype'), dict) else {}
    slots = _slots(session)
    zoned = [s for s in slots if s['prescribes'] == 'zones']
    loaded = [s for s in slots if s['prescribes'] == 'load']
    declared = arch.get('heart_rate')
    if declared in ('track', 'ignore'):
        mode, source = ('whole' if declared == 'track' else 'none'), 'declared'
    elif arch.get('slots'):
        mode, source = ('none' if not zoned else 'exercises' if loaded else 'whole'), 'slots'
    else:
        mode, source = ('none' if is_strength(session.get('modality')) else 'whole'), 'modality'
    return {'track': mode != 'none', 'mode': mode, 'source': source,
            'plannedMinutes': _spread(zoned), 'notZoned': [f"{s['role']}: {s['intensity']}" for s in loaded],
            'slots': slots}


def _spread(slots: list[dict]) -> list[float]:
    planned = [0.0] * ZONES
    for s in slots:
        for z in s['zones']:
            planned[z - 1] += s['minutes'] / len(s['zones'])
    return [round(m, 1) for m in planned]


def _windows(session: dict, log: dict | None, workout: dict) -> dict[str, list[tuple[float, float]]]:
    """Slot role → the epoch-second windows the watch timed its exercises in.

    The session log's `exerciseTimeline` (each step from when it became
    current to when the athlete moved on: the Garmin app, and the Apple
    Watch since 2026-10-17), else an exercise's sets' offsets (the Apple
    Watch's earlier builds). An entry's `startAt`/`endAt` are absolute; its
    offsets count from the workout's start. Entries are keyed by exercise id,
    or by name where the Garmin app had no id."""
    if not log:
        return {}
    role_of: dict[str, str] = {}
    for ea in session.get('exercises') or []:
        if not isinstance(ea, dict):
            continue
        role = ea.get('parent_slot_role') or ea.get('slot_role')
        for key in (_exercise(ea).get('id'), _exercise(ea).get('name')):
            if key and role:
                role_of.setdefault(str(key), role)
                role_of.setdefault(str(key).casefold(), role)
    origin = zones.epoch(workout.get('startTime'))
    out: dict[str, list[tuple[float, float]]] = {}

    def add(key, start, end, start_at=None, end_at=None) -> bool:
        role = role_of.get(str(key)) or role_of.get(str(key).casefold())
        if role is None:
            return False
        s, e = zones.epoch(start_at), zones.epoch(end_at)
        if s is None or e is None:
            if origin is None or not isinstance(start, (int, float)) or not isinstance(end, (int, float)):
                return False
            s, e = origin + float(start), origin + float(end)
        if e <= s:
            return False
        out.setdefault(role, []).append((s, e))
        return True

    timed = set()
    for entry in log.get('exerciseTimeline') or []:
        if isinstance(entry, dict) and add(entry.get('exerciseId'), entry.get('startOffset'),
                                           entry.get('endOffset'), entry.get('startAt'), entry.get('endAt')):
            timed.add(str(entry.get('exerciseId')))
    for key, done in (log.get('exercises') or {}).items():
        if str(key) in timed or not isinstance(done, dict):
            continue
        sets = [s for s in done.get('sets') or [] if isinstance(s, dict)]
        starts = [s['startOffset'] for s in sets if isinstance(s.get('startOffset'), (int, float))]
        ends = [s['endOffset'] for s in sets if isinstance(s.get('endOffset'), (int, float))]
        if starts and ends:
            add(key, min(starts), max(ends))
    return out


def _recorded(workout: dict | None, max_hr: float, bounds: list[float] | None) -> dict | None:
    """The whole recording's minutes per zone — the row's cached metrics on
    the shared edges, the athlete's own edges for one workout's screen —
    or None when it recorded no heart rate."""
    if not workout:
        return None
    if bounds is None:
        split = zones.zone_minutes(workout, max_hr)
    else:
        f = zones.zone_fractions(workout, max_hr, bounds)
        split = {'method': f['method'],
                 'minutes': [x * float(workout.get('durationMinutes') or 0) for x in f['fractions']]}
    return None if split['method'] == 'none' else split


def attribute(session: dict, log: dict | None, workout: dict | None, max_hr: float,
              bounds: list[float] | None = None) -> dict:
    """What a completed session's heart rate counts for in the zone minutes.

    {track, mode, source, timing, plannedMinutes, zoneMinutes, countedMinutes,
     method, notZoned, slots}. `timing`: `whole`, `timeline`, `untimed`,
    `unrecorded` (it should count but recorded no heart rate) or `none`.
    `zoneMinutes` are the recorded minutes that count and `plannedMinutes`
    the planned minutes of the same exercises, so the two compare. Each slot
    carries its own `recordedMinutes` when the watch timed it, and whether it
    `counted`."""
    p = plan(session)
    recorded = _recorded(workout, max_hr, bounds)
    windows = _windows(session, log, workout) if workout else {}
    slots = []
    for s in p['slots']:
        cut = (zones.minutes_in_windows(workout, max_hr, windows[s['role']], bounds)
               if s['role'] in windows else None)
        slots.append({'role': s['role'], 'intensity': s['intensity'], 'zones': s['zones'],
                      'prescribes': s['prescribes'], 'exercises': s['exercises'],
                      'plannedMinutes': round(s['minutes'], 1),
                      'recordedMinutes': [round(m, 2) for m in cut] if cut is not None else None,
                      '_minutes': s['minutes']})
    counted_minutes = [0.0] * ZONES
    planned = [0.0] * ZONES
    mode = p['mode']
    if mode == 'none':
        timing = 'none'
    elif recorded is None:
        timing = 'unrecorded'
    elif mode == 'whole':
        timing = 'whole'
        counted_minutes = list(recorded['minutes'])
        planned = list(p['plannedMinutes'])
    else:
        timed = [s for s in slots if s['prescribes'] == 'zones' and s['recordedMinutes'] is not None]
        timing = 'timeline' if timed else 'untimed'
        for s in timed:
            counted_minutes = [a + b for a, b in zip(counted_minutes, s['recordedMinutes'])]
        planned = _spread([{'zones': s['zones'], 'minutes': s['_minutes']} for s in timed])
    for s in slots:
        s['counted'] = s['prescribes'] == 'zones' and (
            timing == 'whole' or (timing == 'timeline' and s['recordedMinutes'] is not None))
        del s['_minutes']
    return {'track': p['track'], 'mode': mode, 'source': p['source'], 'timing': timing,
            'plannedMinutes': [round(m, 1) for m in planned],
            'zoneMinutes': [round(m, 2) for m in counted_minutes],
            'countedMinutes': round(sum(counted_minutes), 2),
            'method': (recorded or {}).get('method', 'none'),
            'notZoned': p['notZoned'], 'slots': slots}
