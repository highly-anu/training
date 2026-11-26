"""Sessions an athlete composes by hand, kept as a package of their own.

The builder speaks blocks, never YAML: a session is a list of blocks (straight
sets, a superset, rounds, an AMRAP, an EMOM, a piece for time, intervals,
timed and zone work, a distance, a hold, practice), each with its movements —
existing exercises, by id. `to_archetype` writes one as an archetype the
engine already runs (a piece is its first movement's slot with the others as
`amrap_movement` children, a superset slots sharing a `group`, every stage
written), `from_archetype` reads it back, and `compose` lays every session of
an athlete out as one package, "My sessions", that passes the gates
(src/package_gate.py) and is stored like any other of theirs
(src/package_store.py). Its one track exists so the package generates; the
program builder gives it real ones.

Every slot is prescribed as written; a movement's own `start_kg` and
`progress` are the only things that move (progression.written_progress).

Pure but for `catalog()`, which reads the exercises and modalities the caller
can see. docs/roadmap.md item 24; test_manual_builder.py.
"""
from __future__ import annotations

import json
import math
import os
import re

import yaml

PACKAGE_SUFFIX = 'manual'
PACKAGE_NAME = 'My sessions'
SESSION_MARK = 'ms_'
MAX_SESSIONS = 60
MAX_BLOCKS = 24
MAX_MOVEMENTS = 12
NAME_MAX = 80
NOTE_MAX = 2000

STAGES = ('prep', 'main', 'finisher', 'cooldown')

LIBRARY_TRACK = 'library'
# The validator refuses a program whose sessions have under twenty minutes
# (validator._check_session_time): a short session is given that much room.
MIN_SESSION_ROOM = 20
MAX_TRACKS = 6
MAX_PHASES = 8
MAX_TEMPLATE_WEEKS = 8
MAX_DAY_SESSIONS = 2
MAX_PHASE_WEEKS = 52
DAY_NAMES = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')

# kind → (the lead slot's type, whether it is a piece whose other movements
# are its children, the most movements it takes; None is MAX_MOVEMENTS).
KINDS: dict[str, tuple[str, bool, int | None]] = {
    'sets': ('sets_reps', False, 1),
    'superset': ('sets_reps', False, None),
    'alternate': ('sets_reps', False, None),
    'rounds': ('rounds_for_time', True, None),
    'amrap': ('amrap', True, None),
    'emom': ('emom', True, None),
    'for_time': ('for_time', True, None),
    'interval': ('emom', True, None),
    'timed': ('time_domain', False, 1),
    'distance': ('distance', False, 1),
    'hold': ('static_hold', False, 1),
    'practice': ('skill_practice', False, 1),
}
GROUPED = ('superset', 'alternate')

PROGRESS_KEYS = ('add_kg', 'add_reps', 'top_reps', 'add_sec', 'add_m', 'add_rounds', 'every_weeks')

# The archetype category a session of a modality files under.
_CATEGORY = {
    'max_strength': 'strength', 'relative_strength': 'strength', 'power': 'strength',
    'strength_endurance': 'conditioning', 'aerobic_base': 'conditioning',
    'anaerobic_intervals': 'conditioning', 'mixed_modal_conditioning': 'conditioning',
    'durability': 'gpp_durability', 'mobility': 'recovery', 'rehab': 'rehab',
    'movement_skill': 'movement_skill', 'combat_sport': 'combat_sport',
}

_HERE = os.path.dirname(os.path.abspath(__file__))


# ─── What the caller can see ─────────────────────────────────────────────────

def catalog() -> dict:
    """The exercises and modalities in view, and the equipment ids an
    archetype may require: what a session is checked against."""
    from src import loader, phases
    exercises = loader.load_all_exercises()
    exercises = exercises[0] if isinstance(exercises, tuple) else exercises
    with open(os.path.join(_HERE, '..', 'docs', 'schemas', 'archetype.schema.json'), encoding='utf-8') as fh:
        schema = json.load(fh)
    return {'exercises': exercises, 'modalities': loader.load_all_modalities(),
            # Every session in view, by id: a program may lay any of them on a day.
            'archetypes': {a['id']: a for a in loader.load_all_archetypes() if a.get('id')},
            'equipment': set(schema['properties']['required_equipment']['items']['enum']),
            'intensities': set(schema['properties']['slots']['items']['properties']['intensity']['enum']),
            'schema': schema, 'kinds': phases.kinds()}


def package_id(prefix: str) -> str:
    return f'{prefix}{PACKAGE_SUFFIX}'


def _slug(text: str, limit: int = 32) -> str:
    return re.sub(r'[^a-z0-9]+', '_', str(text or '').lower()).strip('_')[:limit].strip('_')


def new_session_id(prefix: str, name: str, taken) -> str:
    """An id for a new session: the owner's prefix, the builder's mark and
    the name, numbered when taken. It never changes with the name after."""
    base = f'{prefix}{SESSION_MARK}{_slug(name) or "session"}'
    taken = set(taken)
    candidate, n = base, 2
    while candidate in taken:
        candidate, n = f'{base}_{n}', n + 1
    return candidate


# ─── Reading the request ─────────────────────────────────────────────────────

def _problem(message: str, block: int | None = None, movement: int | None = None, field: str | None = None) -> dict:
    return {'block': block, 'movement': movement, 'field': field, 'message': message}


def _int(value, low: int = 1, high: int = 100000) -> int | None:
    if isinstance(value, bool) or value is None or value == '':
        return None
    try:
        n = int(float(value))
    except (TypeError, ValueError):
        return None
    return n if low <= n <= high else None


def _num(value, low: float = 0, high: float = 2000) -> float | None:
    if isinstance(value, bool) or value is None or value == '':
        return None
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if not (low <= n <= high) or math.isnan(n):
        return None
    return int(n) if n.is_integer() else round(n, 2)


def _text(value, limit: int = NOTE_MAX) -> str | None:
    if not isinstance(value, str):
        return None
    value = ' '.join(value.split()) if limit <= NAME_MAX else value.strip()
    return value[:limit] or None


def _reps(value):
    """Reps as written: a number, or the author's words ("max", "8-12",
    "5-3-1", "5 each side")."""
    n = _int(value, 1, 1000)
    if n is not None and not isinstance(value, str):
        return n
    if isinstance(value, str):
        value = value.strip()
        if value.isdigit():
            return _int(value, 1, 1000)
        return value[:40] or None
    return n


def _scheme(value) -> list[int] | None:
    """A count that changes round by round: [21, 15, 9] or "21-15-9"."""
    if isinstance(value, str):
        value = [p for p in re.split(r'[^0-9]+', value) if p]
    if not isinstance(value, (list, tuple)):
        return None
    out = [_int(v, 1, 10000) for v in value]
    return out if len(out) >= 2 and all(out) else None


def _progress(value) -> dict | None:
    if not isinstance(value, dict):
        return None
    out = {}
    for key in PROGRESS_KEYS:
        n = _num(value.get(key), 0.01, 100000) if key == 'add_kg' else _int(value.get(key), 1, 100000)
        if n:
            out[key] = n
    if set(out) <= {'every_weeks'} or set(out) <= {'top_reps', 'every_weeks'}:
        return None
    if out.get('every_weeks') == 1:
        del out['every_weeks']
    if value.get('earned') is True:
        out['earned'] = True
        out.pop('every_weeks', None)
    return out


# ─── A session → an archetype ────────────────────────────────────────────────

def _movement_slot(m: dict, role: str, slot_type: str, child_of: str | None) -> dict:
    """One movement as a slot: its exercise, its count, its weight."""
    slot: dict = {'role': role, 'slot_type': slot_type}
    if child_of:
        slot['parent_slot_role'] = child_of
    slot['exercise_filter'] = {'exercise_ids': [m['exercise_id']], 'ordered': True}
    return slot


def _weight(slot: dict, m: dict) -> None:
    kg = _num(m.get('start_kg'), 0, 1000)
    if kg is not None:
        slot['start_kg'] = kg
    text = _text(m.get('load_text'), 120)
    if text:
        slot['load'] = text
    note = _text(m.get('note'))
    if note:
        slot['notes'] = note


def _count_in_piece(slot: dict, m: dict, i: int, j: int, problems: list) -> None:
    """What a movement of a piece does each round: reps, a round-by-round
    scheme, metres or seconds."""
    scheme = _scheme(m.get('rep_scheme'))
    metres = _int(m.get('distance_m'), 1, 100000)
    seconds = _int(m.get('seconds'), 1, 36000)
    reps = _int(m.get('reps'), 1, 10000) if not isinstance(m.get('reps'), str) or str(m.get('reps')).strip().isdigit() else None
    if scheme:
        slot['rep_scheme'] = scheme
    elif metres:
        slot['distance_m'] = metres
    elif seconds and slot['slot_type'] == 'amrap_movement':
        slot['duration_sec'] = seconds
    elif reps:
        slot['reps_per_round'] = reps
    elif isinstance(m.get('reps'), str) and m['reps'].strip():
        slot['notes'] = ' · '.join(p for p in (m['reps'].strip()[:40], slot.get('notes')) if p)
    else:
        problems.append(_problem('Say how many each round: reps, metres or seconds.', i, j, 'reps'))


def _block_slots(block: dict, i: int, problems: list, cat: dict) -> list[dict]:
    kind = block.get('kind')
    if kind not in KINDS:
        problems.append(_problem('Pick what kind of block this is.', i, None, 'kind'))
        return []
    slot_type, piece, most = KINDS[kind]
    movements = [m for m in block.get('movements') or [] if isinstance(m, dict)]
    if not movements:
        problems.append(_problem('Add an exercise to this block.', i))
        return []
    if len(movements) > (most or MAX_MOVEMENTS):
        problems.append(_problem('This kind of block takes one exercise.' if most == 1
                                 else f'A block takes at most {MAX_MOVEMENTS} exercises.', i))
        return []
    if kind in GROUPED and len(movements) < 2:
        problems.append(_problem('A superset needs at least two exercises.', i))
    stage = block.get('stage') if block.get('stage') in STAGES else 'main'
    intensity = block.get('intensity') if block.get('intensity') in cat['intensities'] else None
    rest = _int(block.get('rest_sec'), 0, 3600)
    slots: list[dict] = []
    lead_role = f'b{i + 1}'
    for j, m in enumerate(movements):
        ex_id = m.get('exercise_id')
        if ex_id not in cat['exercises']:
            problems.append(_problem('This exercise is no longer available.' if ex_id else 'Pick an exercise.',
                                     i, j, 'exercise_id'))
            continue
        first = j == 0
        if piece:
            role = lead_role if first else f'{lead_role}_{j + 1}'
            slot = _movement_slot(m, role, slot_type if first else 'amrap_movement', None if first else lead_role)
        else:
            role = lead_role if len(movements) == 1 else f'{lead_role}_{j + 1}'
            slot = _movement_slot(m, role, slot_type, None)
        slot['stage'] = stage
        _weight(slot, m)

        if kind in ('sets', 'superset', 'alternate'):
            sets = _int(m.get('sets') if kind == 'sets' else block.get('rounds', m.get('sets')), 1, 50)
            reps = _reps(m.get('reps'))
            if not sets:
                problems.append(_problem('How many sets?', i, j if kind == 'sets' else None,
                                         'sets' if kind == 'sets' else 'rounds'))
            if reps is None:
                problems.append(_problem('How many reps? A number, or words such as "max" or "8-12".', i, j, 'reps'))
            slot.update({k: v for k, v in (('sets', sets), ('reps', reps)) if v is not None})
            own_rest = _int(m.get('rest_sec'), 0, 3600) if kind == 'sets' else None
            if kind == 'sets' and (own_rest if own_rest is not None else rest) is not None:
                slot['rest_sec'] = own_rest if own_rest is not None else rest
            if kind in GROUPED:
                slot['group'] = {'id': lead_role, 'kind': kind}
                if rest is not None and j == len(movements) - 1:
                    slot['rest_sec'] = rest
            if intensity:
                slot['intensity'] = intensity
        elif kind == 'hold':
            sets, seconds = _int(m.get('sets'), 1, 50) or 1, _int(m.get('hold_sec'), 1, 3600)
            if not seconds:
                problems.append(_problem('How many seconds is the hold?', i, j, 'hold_sec'))
            slot.update({'sets': sets, **({'hold_seconds': seconds} if seconds else {})})
            if rest is not None:
                slot['rest_sec'] = rest
        elif kind in ('timed', 'practice'):
            minutes = _int(block.get('minutes'), 1, 600)
            if not minutes:
                problems.append(_problem('How many minutes?', i, None, 'minutes'))
            else:
                slot['duration_minutes'] = minutes
            if intensity and kind == 'timed':
                slot['intensity'] = intensity
        elif kind == 'distance':
            metres, sets = _int(m.get('distance_m'), 1, 500000), _int(m.get('sets'), 1, 100)
            if not metres:
                problems.append(_problem('How far? Give the metres.', i, j, 'distance_m'))
            else:
                slot['distance_m'] = metres
            if sets and sets > 1:
                slot['sets'] = sets
            if rest is not None:
                slot['rest_sec'] = rest
            if intensity:
                slot['intensity'] = intensity
        else:  # a piece
            if not (kind == 'interval' and first and not any(
                    m.get(k) for k in ('reps', 'rep_scheme', 'distance_m'))):
                # An interval's own movement is its seconds of work.
                _count_in_piece(slot, m, i, j, problems)
            if first:
                rounds, minutes = _int(block.get('rounds'), 1, 200), _int(block.get('minutes'), 1, 600)
                cap = _int(block.get('cap_min'), 1, 600)
                if kind == 'amrap':
                    if not minutes:
                        problems.append(_problem('How many minutes is the AMRAP?', i, None, 'minutes'))
                    else:
                        slot['duration_sec'] = minutes * 60
                elif kind == 'emom':
                    if not minutes:
                        problems.append(_problem('How many minutes is the EMOM?', i, None, 'minutes'))
                    else:
                        slot['duration_minutes'] = minutes
                elif kind == 'interval':
                    work, hr = _int(block.get('work_sec'), 1, 3600), _int(block.get('rest_until_hr_pct'), 50, 90)
                    if not rounds:
                        problems.append(_problem('How many rounds?', i, None, 'rounds'))
                    if not work:
                        problems.append(_problem('How many seconds of work each round?', i, None, 'work_sec'))
                    slot.update({k: v for k, v in (('sets', rounds), ('work_sec', work)) if v})
                    slot['rest_sec'] = rest or 0
                    if hr and rest:
                        slot['rest_until_hr_pct'] = hr
                    elif hr:
                        problems.append(_problem('A rest that ends on heart rate needs a longest rest in seconds.',
                                                 i, None, 'rest_sec'))
                else:  # rounds, for_time
                    if not rounds:
                        problems.append(_problem('How many rounds?', i, None, 'rounds'))
                    else:
                        slot['rounds'] = rounds
                    if cap:
                        slot['time_cap_sec'] = cap * 60
                    if kind == 'rounds':
                        slot['rest_sec'] = rest or 0
                if intensity:
                    slot['intensity'] = intensity
                note = _text(block.get('note'))
                if note:
                    slot['notes'] = ' · '.join(p for p in (note, slot.get('notes')) if p)
        rule = _progress(block.get('progress') if piece and first else m.get('progress'))
        if rule:
            slot['progress'] = rule
        slots.append(slot)
    if not piece and slots:
        note = _text(block.get('note'))
        if note and 'notes' not in slots[0]:
            slots[0]['notes'] = note
    return slots


def minutes_of(slots: list[dict]) -> int:
    """About how long the session takes, from what its blocks write."""
    total = 0.0
    for s in slots:
        kind, sets, rest = s['slot_type'], s.get('sets') or 1, s.get('rest_sec') or 0
        if kind == 'sets_reps':
            reps = s.get('reps') if isinstance(s.get('reps'), int) else 8
            total += sets * (reps * 4 + (rest or 60))
        elif kind == 'static_hold':
            total += sets * ((s.get('hold_seconds') or 30) + (rest or 30))
        elif kind in ('time_domain', 'skill_practice'):
            total += (s.get('duration_minutes') or 5) * 60
        elif kind == 'distance':
            total += sets * ((s.get('distance_m') or 400) * 0.36 + rest)
        elif kind == 'amrap':
            total += s.get('duration_sec') or 600
        elif kind == 'emom' and s.get('work_sec'):
            total += sets * (s['work_sec'] + rest)
        elif kind == 'emom':
            total += (s.get('duration_minutes') or 10) * 60
        elif kind in ('for_time', 'rounds_for_time'):
            total += s.get('time_cap_sec') or (s.get('rounds') or 1) * (180 + rest)
    return max(5, int(math.ceil(total / 60 / 5.0) * 5))


def to_archetype(session: dict, archetype_id: str, cat: dict | None = None) -> tuple[dict | None, list[dict]]:
    """One session as an archetype, and what stops it (each problem names its
    block and movement by index, in the athlete's words)."""
    cat = cat or catalog()
    problems: list[dict] = []
    if not isinstance(session, dict):
        return None, [_problem('This session could not be read.')]
    name = _text(session.get('name'), NAME_MAX)
    if not name:
        problems.append(_problem('Give the session a name.', field='name'))
    modality = session.get('modality')
    if modality not in cat['modalities']:
        problems.append(_problem('Pick what kind of training this is.', field='modality'))
    blocks = [b for b in session.get('blocks') or [] if isinstance(b, dict)]
    if not blocks:
        problems.append(_problem('Add a block to the session.'))
    if len(blocks) > MAX_BLOCKS:
        problems.append(_problem(f'A session takes at most {MAX_BLOCKS} blocks.'))
        blocks = blocks[:MAX_BLOCKS]
    slots: list[dict] = []
    for i, block in enumerate(blocks):
        slots += _block_slots(block, i, problems, cat)
    if problems:
        return None, problems
    used = [cat['exercises'][s['exercise_filter']['exercise_ids'][0]] for s in slots]
    equipment = sorted({e for ex in used for e in ex.get('equipment') or [] if e in cat['equipment']})
    arch: dict = {
        'id': archetype_id, 'name': name, 'modality': modality,
        'category': _CATEGORY.get(modality, 'conditioning'),
        'duration_estimate_minutes': _int(session.get('minutes'), 5, 600) or minutes_of(slots),
        'pool_only': True,
        **({'required_equipment': equipment} if equipment else {}),
        'slots': slots,
        'sources': ['Composed by the athlete.'],
    }
    notes = _text(session.get('notes'))
    if notes:
        arch['notes'] = notes
    import jsonschema
    for err in sorted(jsonschema.Draft7Validator(cat['schema']).iter_errors(arch), key=lambda e: list(e.path)):
        path = list(err.path)
        at = None
        if len(path) >= 2 and path[0] == 'slots':
            role = slots[path[1]]['role']
            at = int(re.match(r'b(\d+)', role).group(1)) - 1
        problems.append(_problem(f'This cannot be saved as written ({err.message}).', at))
    return (None, problems) if problems else (arch, [])


# ─── An archetype → a session ────────────────────────────────────────────────

def _movement_of(slot: dict, kind: str, lead: bool) -> dict:
    m: dict = {'exercise_id': ((slot.get('exercise_filter') or {}).get('exercise_ids') or [None])[0]}
    for src, dst in (('start_kg', 'start_kg'), ('load', 'load_text')):
        if slot.get(src) is not None:
            m[dst] = slot[src]
    piece = KINDS[kind][1]
    if piece:
        for src, dst in (('rep_scheme', 'rep_scheme'), ('reps_per_round', 'reps'), ('distance_m', 'distance_m')):
            if slot.get(src) is not None:
                m[dst] = slot[src]
        if not lead and slot.get('duration_sec'):
            m['seconds'] = slot['duration_sec']
    elif kind in ('sets', 'superset', 'alternate'):
        m.update({k: slot[k] for k in ('sets', 'reps') if slot.get(k) is not None})
        if kind == 'sets' and slot.get('rest_sec') is not None:
            m['rest_sec'] = slot['rest_sec']
    elif kind == 'hold':
        m.update({'sets': slot.get('sets') or 1, 'hold_sec': slot.get('hold_seconds')})
    elif kind == 'distance':
        m['distance_m'] = slot.get('distance_m')
        if slot.get('sets'):
            m['sets'] = slot['sets']
    if slot.get('notes') and not (piece and lead):
        m['note'] = slot['notes']
    if slot.get('progress') and not (piece and lead):
        m['progress'] = dict(slot['progress'])
    return m


def _kind_of(slot: dict) -> str:
    t = slot.get('slot_type')
    if t == 'sets_reps':
        return (slot.get('group') or {}).get('kind') or 'sets'
    if t == 'emom':
        return 'interval' if slot.get('work_sec') else 'emom'
    return {'rounds_for_time': 'rounds', 'amrap': 'amrap', 'for_time': 'for_time', 'time_domain': 'timed',
            'distance': 'distance', 'static_hold': 'hold', 'skill_practice': 'practice'}.get(t, 'sets')


def from_archetype(arch: dict) -> dict:
    """An archetype `to_archetype` wrote, as the session it was written from."""
    blocks: list[dict] = []
    by_lead: dict[str, dict] = {}
    for slot in arch.get('slots') or []:
        parent, group = slot.get('parent_slot_role'), (slot.get('group') or {}).get('id')
        home = by_lead.get(parent or group or '')
        if home is not None and (parent or home['kind'] in GROUPED):
            home['movements'].append(_movement_of(slot, home['kind'], False))
            if home['kind'] in GROUPED and slot.get('rest_sec') is not None:
                home['rest_sec'] = slot['rest_sec']
            continue
        kind = _kind_of(slot)
        block: dict = {'kind': kind, 'stage': slot.get('stage') or 'main',
                       'movements': [_movement_of(slot, kind, True)]}
        piece = KINDS[kind][1]
        if kind in GROUPED:
            block['rounds'] = slot.get('sets')
            if slot.get('rest_sec') is not None:
                block['rest_sec'] = slot['rest_sec']
        elif kind == 'amrap':
            block['minutes'] = round((slot.get('duration_sec') or 0) / 60) or None
        elif kind in ('emom', 'timed', 'practice'):
            block['minutes'] = slot.get('duration_minutes')
        elif kind == 'interval':
            block.update({'rounds': slot.get('sets'), 'work_sec': slot.get('work_sec'),
                          'rest_sec': slot.get('rest_sec') or 0})
            if slot.get('rest_until_hr_pct'):
                block['rest_until_hr_pct'] = slot['rest_until_hr_pct']
        elif kind in ('rounds', 'for_time'):
            block['rounds'] = slot.get('rounds')
            if slot.get('time_cap_sec'):
                block['cap_min'] = round(slot['time_cap_sec'] / 60)
            if kind == 'rounds':
                block['rest_sec'] = slot.get('rest_sec') or 0
        elif kind in ('hold', 'distance') and slot.get('rest_sec') is not None:
            block['rest_sec'] = slot['rest_sec']
        if slot.get('intensity'):
            block['intensity'] = slot['intensity']
        if piece and slot.get('notes'):
            block['note'] = slot['notes']
        if piece and slot.get('progress'):
            block['progress'] = dict(slot['progress'])
        blocks.append({k: v for k, v in block.items() if v is not None})
        by_lead[group or slot.get('role')] = blocks[-1]
    out = {'id': arch.get('id'), 'name': arch.get('name'), 'modality': arch.get('modality'),
           'minutes': arch.get('duration_estimate_minutes'), 'blocks': blocks}
    if arch.get('notes'):
        out['notes'] = arch['notes']
    return out


# ─── Every session → one package ─────────────────────────────────────────────

def _category(archetype_id: str, prefix: str) -> str:
    """The day category of one session: `c_` and its own name for a session
    of the athlete's, `x_` and the whole id for another package's."""
    if archetype_id.startswith(f'{prefix}{SESSION_MARK}'):
        return f'c_{archetype_id[len(prefix):]}'
    return f'x_{archetype_id}'


def _session_of(category: str, prefix: str) -> str:
    return category[2:] if category.startswith('x_') else f'{prefix}{category[2:]}'


def sessions_in_view(archetypes: list[dict], cat: dict) -> dict:
    """Every session a program may lay on a day, by id: the athlete's own
    (as given, which may be newer than what is stored) and every other
    package's in view."""
    library = {i: a for i, a in (cat.get('archetypes') or {}).items()
               # A stored hand-built session is in view only as given: one just
               # deleted is no longer a session of anyone's.
               if not (str(a.get('_package') or '').endswith(PACKAGE_SUFFIX) and SESSION_MARK in i)}
    return {**library, **{a['id']: a for a in archetypes}}


def _lead_exercise(slot: dict) -> str | None:
    return ((slot.get('exercise_filter') or {}).get('exercise_ids') or [None])[0]


def borrowed_sessions(tracks: list[dict], archetypes: list[dict], cat: dict) -> list[dict]:
    """The sessions of other packages the tracks have on a day, in the
    order first laid."""
    own = {a['id'] for a in archetypes}
    library = sessions_in_view([], cat)
    out, seen = [], set()
    for t in tracks or []:
        for ph in t['phases']:
            for row in ph['template']:
                for day in row:
                    for sid in day['sessions']:
                        if sid not in own and sid not in seen and sid in library:
                            seen.add(sid)
                            out.append(library[sid])
    return out


def _categories(archetypes: list[dict], prefix: str) -> dict:
    """One day category per session — every session, since a session the
    package holds must be in some framework's pool."""
    return {_category(a['id'], prefix): {'name': a['name'], 'modality': a['modality'],
                                         'archetypes': [a['id']], 'warm_up': False} for a in archetypes}


def _library(archetypes: list[dict], prefix: str, pkg: str) -> tuple[dict, dict]:
    """The track a package has before the athlete lays one out: its sessions
    three a week, in turn, so the package generates."""
    framework_id = f'{pkg}_week'
    days = (0, 2, 4)
    templates = []
    for at in range(0, len(archetypes), len(days)):
        week = ['rest'] * 7
        for day, arch in zip(days, archetypes[at:at + len(days)]):
            week[day] = _category(arch['id'], prefix)
        templates.append(week)
    first_week = archetypes[:len(days)]
    modalities = list(dict.fromkeys(a['modality'] for a in archetypes))
    per_week = {m: sum(1 for a in first_week if a['modality'] == m) for m in modalities}
    per_week = {m: n for m, n in per_week.items() if n} or {modalities[0]: 1}
    track = {
        'id': LIBRARY_TRACK, 'name': 'Library',
        'description': 'Every session I built, in turn.',
        'phases': [{
            'id': 'library', 'name': 'Library', 'kind': 'build', 'weeks': 4, 'repeatable': True,
            'framework_id': framework_id, 'focus': 'As written',
            'week_templates': templates,
        }],
    }
    framework = {
        'id': framework_id, 'name': PACKAGE_NAME, 'source_philosophy': pkg,
        'sessions_per_week': per_week,
        'prescription_policy': 'framework', 'progression_model': 'as_written',
        'applicable_when': {'days_per_week_min': 1, 'days_per_week_max': 7},
        'expectations': {'min_weeks': 1, 'ideal_weeks': 4,
                         'min_days_per_week': 1, 'ideal_days_per_week': min(len(days), len(archetypes)),
                         'min_session_minutes': min(a['duration_estimate_minutes'] for a in archetypes),
                         'ideal_session_minutes': max(MIN_SESSION_ROOM, *(a['duration_estimate_minutes'] for a in archetypes)),
                         'supports_split_days': False},
        'categories': _categories(archetypes, prefix),
    }
    return track, framework


# ─── A track laid out by hand ────────────────────────────────────────────────
#
# The wire shape: {id?, name, description?, deload_every?, phases: [{id?, name,
# kind, weeks, template: [[day × 7] …]}]}, a day {sessions: [session id, at
# most two], light?}. The weeks of a template repeat through the phase; a day
# with two sessions is one session of both (week_template.compose).

def _track_problem(message: str, phase: int | None = None, week: int | None = None, day: int | None = None,
                   field: str | None = None) -> dict:
    return {'phase': phase, 'week': week, 'day': day, 'field': field, 'message': message}


def new_track_id(name: str, taken) -> str:
    base = _slug(name, 24) or 'track'
    if base == LIBRARY_TRACK:
        base = 'my_library'
    taken = set(taken)
    candidate, n = base, 2
    while candidate in taken:
        candidate, n = f'{base}_{n}', n + 1
    return candidate


def _day_of(value) -> dict:
    """A day as sent: {sessions, light}; anything else is a rest day."""
    if isinstance(value, dict):
        sessions = [s for s in value.get('sessions') or [] if isinstance(s, str)]
        return {'sessions': sessions, 'light': bool(value.get('light')) and bool(sessions)}
    if isinstance(value, (list, tuple)):
        return {'sessions': [s for s in value if isinstance(s, str)], 'light': False}
    return {'sessions': [], 'light': False}


def read_track(track, track_id: str, archetypes: list[dict], cat: dict) -> tuple[dict | None, list[dict]]:
    """A track as sent, made whole (ids given, days normalised), and what
    stops it: each problem names its phase, template week and day by index."""
    problems: list[dict] = []
    if not isinstance(track, dict):
        return None, [_track_problem('This program could not be read.')]
    by_id = sessions_in_view(archetypes, cat)
    name = _text(track.get('name'), NAME_MAX)
    if not name:
        problems.append(_track_problem('Give the program a name.', field='name'))
    deload = track.get('deload_every')
    if deload in (None, '', 0, False):
        deload = None
    else:
        deload = _int(deload, 2, 12)
        if deload is None:
            problems.append(_track_problem('A lighter week comes every 2 to 12 weeks.', field='deload_every'))
    raw_phases = [p for p in track.get('phases') or [] if isinstance(p, dict)]
    if not raw_phases:
        problems.append(_track_problem('Add a phase.'))
    if len(raw_phases) > MAX_PHASES:
        problems.append(_track_problem(f'A program takes at most {MAX_PHASES} phases.'))
        raw_phases = raw_phases[:MAX_PHASES]
    phases, taken = [], set()
    for i, ph in enumerate(raw_phases):
        ph_name = _text(ph.get('name'), NAME_MAX)
        if not ph_name:
            problems.append(_track_problem('Give the phase a name.', i, field='name'))
        kind = ph.get('kind')
        if kind not in cat['kinds']:
            problems.append(_track_problem('Pick what kind of phase this is.', i, field='kind'))
        weeks = _int(ph.get('weeks'), 1, MAX_PHASE_WEEKS)
        if not weeks:
            problems.append(_track_problem(f'A phase runs 1 to {MAX_PHASE_WEEKS} weeks.', i, field='weeks'))
        rows = [r for r in ph.get('template') or [] if isinstance(r, (list, tuple))]
        if not rows:
            problems.append(_track_problem('Lay out a week for this phase.', i))
        if len(rows) > MAX_TEMPLATE_WEEKS:
            problems.append(_track_problem(f'A phase takes at most {MAX_TEMPLATE_WEEKS} different weeks.', i))
            rows = rows[:MAX_TEMPLATE_WEEKS]
        template = []
        for w, row in enumerate(rows):
            days = [_day_of(d) for d in list(row)[:7]] + [_day_of(None)] * max(0, 7 - len(row))
            for d, day in enumerate(days):
                if len(day['sessions']) > MAX_DAY_SESSIONS:
                    problems.append(_track_problem(f'A day takes at most {MAX_DAY_SESSIONS} sessions.', i, w, d))
                for sid in day['sessions']:
                    arch = by_id.get(sid)
                    if arch is None:
                        problems.append(_track_problem('This session is no longer available.', i, w, d))
                    elif kind and cat['kinds'].get(kind, {}).get('excludes_max_effort') and any(
                            (cat['exercises'].get(_lead_exercise(s)) or {}).get('effort') == 'max'
                            for s in arch.get('slots') or []):
                        problems.append(_track_problem(
                            f'{arch["name"]} has a maximal-effort exercise, which a {kind} phase leaves out. '
                            'Pick another kind of phase or another session.', i, w, d))
            template.append(days)
        if template and not any(day['sessions'] for day in template[0]):
            problems.append(_track_problem('The first week of a phase needs at least one session.', i, 0))
        ph_id = ph.get('id') if isinstance(ph.get('id'), str) and re.fullmatch(r'[a-z0-9_]{1,40}', ph['id']) \
            and ph['id'] not in taken else None
        if ph_id is None:
            base = _slug(ph_name or '', 24) or f'phase_{i + 1}'
            ph_id, n = base, 2
            while ph_id in taken:
                ph_id, n = f'{base}_{n}', n + 1
        taken.add(ph_id)
        phases.append({'id': ph_id, 'name': ph_name, 'kind': kind, 'weeks': weeks, 'template': template})
    if problems:
        return None, problems
    out = {'id': track_id, 'name': name, 'deload_every': deload, 'phases': phases}
    description = _text(track.get('description'))
    if description:
        out['description'] = description
    return out, []


def _day_minutes(day: dict, by_id: dict) -> int:
    return sum((by_id.get(s) or {}).get('duration_estimate_minutes') or 0 for s in day['sessions'])


def track_files(track: dict, archetypes: list[dict], prefix: str, pkg: str, cat: dict | None = None) -> tuple[dict, dict]:
    """A whole track (read_track's) as the philosophy's track and the
    framework that builds its weeks: a category for every session of the
    athlete's, and one for each session of another package it lays on a day."""
    cat = cat or catalog()
    by_id = sessions_in_view(archetypes, cat)
    pooled = archetypes + borrowed_sessions([track], archetypes, cat)
    framework_id = f'{pkg}_t_{track["id"]}'

    def day_out(day: dict):
        cats = [_category(s, prefix) for s in day['sessions']]
        if not cats:
            return 'rest'
        if day['light']:
            return {'categories': cats, 'light': True}
        return cats[0] if len(cats) == 1 else cats

    rows = [row for ph in track['phases'] for row in ph['template']]
    busiest = max(sum(1 for d in row if d['sessions']) for row in rows)
    minutes = [m for row in rows for d in row for m in [_day_minutes(d, by_id)] if m]
    first = track['phases'][0]['template'][0]
    per_week: dict = {}
    for day in first:
        if day['sessions']:
            modality = by_id[day['sessions'][0]]['modality']
            per_week[modality] = per_week.get(modality, 0) + 1
    defaults = {'written_weeks': 'track'}
    framework = {
        'id': framework_id, 'name': track['name'], 'source_philosophy': pkg,
        'sessions_per_week': per_week,
        'prescription_policy': 'framework', 'progression_model': 'as_written',
        'fixed_days': True,
        'applicable_when': {'days_per_week_min': 1, 'days_per_week_max': 7},
        'expectations': {'min_weeks': 1, 'ideal_weeks': sum(ph['weeks'] for ph in track['phases']),
                         'min_days_per_week': 1, 'ideal_days_per_week': busiest,
                         'min_session_minutes': min(minutes or [MIN_SESSION_ROOM]),
                         'ideal_session_minutes': max(MIN_SESSION_ROOM, *minutes),
                         'supports_split_days': False},
        'categories': _categories(pooled, prefix),
    }
    if track.get('deload_every'):
        framework['deload_protocol'] = {'frequency_weeks': track['deload_every'], 'volume_reduction_pct': 1.0,
                                        'intensity_change': 'reduce_slightly'}
        defaults['deload_light'] = True
    framework['progression_defaults'] = defaults
    doc = {'id': track['id'], 'name': track['name'],
           **({'description': track['description']} if track.get('description') else {}),
           'phases': [{'id': ph['id'], 'name': ph['name'], 'kind': ph['kind'], 'weeks': ph['weeks'],
                       'framework_id': framework_id, 'focus': 'As written',
                       'week_templates': [[day_out(d) for d in row] for row in ph['template']]}
                      for ph in track['phases']]}
    return doc, framework


def stored_tracks(files: dict | None, prefix: str) -> list[dict]:
    """A stored package's hand-laid tracks, as read_track gives them, in the
    philosophy's order. The Library track is the package's own, never one."""
    if not files or 'philosophy.yaml' not in files:
        return []
    frameworks = {}
    for path, text in files.items():
        if path.startswith('frameworks/'):
            doc = yaml.safe_load(text) or {}
            frameworks[doc.get('id')] = doc

    def day_in(day) -> dict:
        if day == 'rest' or not day:
            return {'sessions': [], 'light': False}
        if isinstance(day, str):
            return {'sessions': [_session_of(day, prefix)], 'light': False}
        if isinstance(day, list):
            return {'sessions': [_session_of(c, prefix) for c in day], 'light': False}
        return {'sessions': [_session_of(c, prefix) for c in day.get('categories') or []], 'light': bool(day.get('light'))}

    out = []
    for doc in (yaml.safe_load(files['philosophy.yaml']) or {}).get('tracks') or []:
        if doc.get('id') == LIBRARY_TRACK:
            continue
        phases_out = doc.get('phases') or []
        framework = frameworks.get((phases_out[0] if phases_out else {}).get('framework_id')) or {}
        track = {'id': doc['id'], 'name': doc.get('name'),
                 'deload_every': (framework.get('deload_protocol') or {}).get('frequency_weeks'),
                 'phases': [{'id': ph['id'], 'name': ph.get('name'), 'kind': ph.get('kind'), 'weeks': ph.get('weeks'),
                             'template': [[day_in(d) for d in row] for row in ph.get('week_templates') or []]}
                            for ph in phases_out]}
        if doc.get('description'):
            track['description'] = doc['description']
        out.append(track)
    return out


def tracks_placing(tracks: list[dict], session_id: str) -> list[str]:
    """The names of the tracks that have a session on a day."""
    return [t['name'] for t in tracks
            if any(session_id in d['sessions'] for ph in t['phases'] for row in ph['template'] for d in row)]


def framework_id_of(track_id: str, prefix: str) -> str:
    return f'{package_id(prefix)}_t_{track_id}'


# ─── Every session and track → one package ───────────────────────────────────

def _dump(doc) -> str:
    return yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, width=100)


def compose(archetypes: list[dict], prefix: str, cat: dict | None = None, tracks: list[dict] | None = None) -> dict:
    """The file map of the athlete's "My sessions" package: its sessions in
    the order given, and its tracks (read_track's). With no track of the
    athlete's, one "Library" track lays the sessions out so the package
    generates; nothing else is invented."""
    cat = cat or catalog()
    pkg = package_id(prefix)
    modalities = list(dict.fromkeys(a['modality'] for a in archetypes)) or list(dict.fromkeys(
        a['modality'] for a in borrowed_sessions(tracks or [], archetypes, cat)))
    owners = {o for a in archetypes for s in a['slots']
              for o in [(cat['exercises'].get(s['exercise_filter']['exercise_ids'][0]) or {}).get('_package')]
              if o and o != pkg}
    # A session of another package laid on a day is borrowed whole, with the
    # movements its own package borrows in turn (so it fills as it does there).
    lenders = {a['_package'] for a in borrowed_sessions(tracks or [], archetypes, cat) if a.get('_package')} - {pkg}
    for lender in lenders:
        owners |= _lends_from(lender) - {pkg}
    owners -= lenders
    built = [track_files(t, archetypes, prefix, pkg, cat) for t in tracks or []] or [_library(archetypes, prefix, pkg)]
    philosophy = {
        'id': pkg, 'name': PACKAGE_NAME,
        'core_principles': ['Sessions composed by hand, done as written.'],
        'scope': modalities, 'bias': modalities[:3],
        'self_contained': True,
        **({'borrows_from': [{'package': o, **_label(o), 'kinds': ['archetypes', 'exercises'],
                              'reason': 'A program of mine has its sessions.'} for o in sorted(lenders)]
                            + [{'package': o, 'kinds': ['exercises'],
                                'reason': 'A session of mine uses its movements.'} for o in sorted(owners)]}
           if owners or lenders else {}),
        'notes': 'The sessions and programs I built myself.',
        'primary_track_id': built[0][0]['id'],
        'tracks': [track for track, _ in built],
    }
    files = {'philosophy.yaml': _dump(philosophy), 'exercises.yaml': _dump({'exercises': []})}
    for _, framework in built:
        files[f'frameworks/{framework["id"]}.yaml'] = _dump(framework)
    for a in archetypes:
        files[f'archetypes/{a["id"]}.yaml'] = _dump(a)
    return files


def _label(package: str) -> dict:
    """The lender's own name, for the "via …" a borrowed session carries."""
    from src import loader
    try:
        name = loader.load_philosophy(package).get('name')
    except (FileNotFoundError, KeyError):
        name = None
    return {'label': name} if name else {}


def _lends_from(package: str) -> set:
    """The packages a package borrows from itself."""
    from src import loader
    try:
        phil = loader.load_philosophy(package)
    except (FileNotFoundError, KeyError):
        return set()
    return {(b if isinstance(b, str) else b.get('package')) for b in phil.get('borrows_from') or []} - {None, package}


def stored_archetypes(files: dict | None) -> list[dict]:
    """A stored package's sessions as archetypes, in the order its frameworks
    list them."""
    if not files:
        return []
    found = {}
    for path, text in files.items():
        if path.startswith('archetypes/'):
            doc = yaml.safe_load(text) or {}
            if doc.get('id'):
                found[doc['id']] = doc
    order = []
    for path, text in files.items():
        if path.startswith('frameworks/'):
            for cat_def in ((yaml.safe_load(text) or {}).get('categories') or {}).values():
                order += [a for a in cat_def.get('archetypes') or [] if a in found and a not in order]
    return [found[a] for a in order] + [a for i, a in found.items() if i not in order]


# ─── What the builder shows ──────────────────────────────────────────────────

def described(arch: dict, cat: dict | None = None, weeks: int = 4) -> dict:
    """A session with what the server derives from it: the blocks every
    client draws, its minutes and equipment, and each movement's first weeks
    in words (the progression as the athlete will be prescribed it)."""
    from src import session_blocks
    from src.analytics.exercise_series import prescribed_text
    from src.progression import calculate_load
    cat = cat or catalog()
    pools = {}
    forecast = []
    for slot in arch['slots']:
        ex = cat['exercises'].get(slot['exercise_filter']['exercise_ids'][0]) or {}
        pools[slot['role']] = {'exercises': [{'id': ex.get('id'), 'name': ex.get('name')}], 'listed': True}
        if slot.get('progress') or slot.get('start_kg') is not None:
            lines = [prescribed_text(calculate_load(ex, slot, 'as_written', w, 'build', 'intermediate', False))
                     for w in range(1, weeks + 1)]
            forecast.append({'role': slot['role'], 'exercise': ex.get('name'), 'weeks': lines})
    return {**from_archetype(arch), 'archetypeId': arch['id'],
            'minutes': arch['duration_estimate_minutes'],
            'equipment': arch.get('required_equipment') or [],
            'preview': session_blocks.for_archetype(arch, pools=pools),
            'forecast': forecast}


class _Sessions(dict):
    """Sessions by id; one that has since left its package still has a name."""

    def __missing__(self, key):
        return {'id': key, 'name': 'A session no longer available', 'modality': None,
                'duration_estimate_minutes': 0, 'slots': []}


def described_track(track: dict, archetypes: list[dict], prefix: str, cat: dict | None = None, weeks: int = 16) -> dict:
    """A track with what the server derives from it: each phase's weeks with
    their sessions named and timed, which weeks of the track are lighter, the
    equipment it needs, each moving exercise's numbers week by week across the
    phases, and the constraints that generate it as laid (`startWith`)."""
    from src.analytics.exercise_series import prescribed_text
    from src.progression import calculate_load
    cat = cat or catalog()
    own = {a['id'] for a in archetypes}
    by_id = _Sessions(sessions_in_view(archetypes, cat))
    deload = track.get('deload_every')
    phases_out, calendar, at = [], [], 0
    for ph in track['phases']:
        rows = []
        for row in ph['template']:
            rows.append([{'day': DAY_NAMES[d], 'light': day['light'], 'minutes': _day_minutes(day, by_id),
                          'sessions': [{'id': s, 'name': by_id[s]['name'], 'modality': by_id[s]['modality'],
                                        'minutes': by_id[s].get('duration_estimate_minutes') or 0,
                                        **({} if s in own else {'from': by_id[s].get('_package')})}
                                       for s in day['sessions']]}
                         for d, day in enumerate(row)])
        lighter = []
        for w in range(1, ph['weeks'] + 1):
            is_deload = bool(deload) and w % deload == 0
            calendar.append((at + w, w, is_deload, ph['template'][(w - 1) % len(ph['template'])]))
            if is_deload:
                lighter.append(at + w)
        per_week = [sum(1 for d in row if d['sessions']) for row in rows]
        phases_out.append({**{k: ph[k] for k in ('id', 'name', 'kind', 'weeks')},
                           'template': ph['template'], 'weeksDescribed': rows,
                           'firstWeek': at + 1, 'lastWeek': at + ph['weeks'], 'lighterWeeks': lighter,
                           'sessionsPerWeek': round(sum(per_week) / len(per_week), 1),
                           'minutesPerWeek': round(sum(d['minutes'] for row in rows for d in row) / len(rows))})
        at += ph['weeks']
    used = [by_id[s] for ph in track['phases'] for row in ph['template'] for d in row for s in d['sessions']]
    forecast, seen = [], set()
    for arch in used:
        for slot in arch.get('slots') or []:
            key = (arch['id'], slot['role'])
            if key in seen or not (slot.get('progress') or slot.get('start_kg') is not None):
                continue
            seen.add(key)
            ex = cat['exercises'].get(_lead_exercise(slot)) or {}
            lines = []
            for week, _, is_deload, row in calendar[:weeks]:
                day = next((d for d in row if arch['id'] in d['sessions']), None)
                if day is None:
                    continue
                light = day['light'] or is_deload
                view = {**slot, 'light_share': 0.8} if light and slot.get('start_kg') is not None else slot
                load = calculate_load(ex, view, 'as_written', 1, 'build', 'intermediate', is_deload, written_week=week)
                lines.append({'week': week, 'text': prescribed_text(load), 'light': light})
            if lines:
                forecast.append({'session': arch['name'], 'exercise': ex.get('name'), 'weeks': lines})
    minutes = [d['minutes'] for ph in phases_out for row in ph['weeksDescribed'] for d in row if d['minutes']]
    return {'id': track['id'], 'name': track['name'], 'description': track.get('description'),
            'deload_every': deload, 'phases': phases_out, 'totalWeeks': at,
            'frameworkId': framework_id_of(track['id'], prefix),
            'equipment': sorted({e for a in used for e in a.get('required_equipment') or []}),
            'forecast': forecast,
            'startWith': {'days_per_week': max(1, round(max(p['sessionsPerWeek'] for p in phases_out))),
                          'session_time_minutes': max(MIN_SESSION_ROOM, *minutes) if minutes else 60}}
