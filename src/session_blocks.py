"""A workout as blocks: what opens it, what repeats in rounds or every minute,
what the rests are, what closes it.

A session is a list of slots, and a list is all either client drew: Fran's
pull-ups as an exercise after the thrusters, a complex's eight movements as
eight lines. The data says more. A movement names the piece it belongs to
(`parent_slot_role`), the piece carries its rounds, minutes and rest, and a
role says whether a slot warms up or cools down. This module reads that once,
for an archetype as its package writes it (Explore) and for a session of a
stored program (Today), so both draw the same blocks:

    {id, stage, stageLabel, shape, title, headline, repeat, rest, again, cap, load, intensity,
     rpe, note, standard, group, roles, movements: [{role, name, count,
     perRound, eachSide, note, exercises, more}]}

Every word a block shows is written here. Nothing is stored: a program's
sessions take `blocks` on read and lose them on save, as they do `icon`.
"""
from __future__ import annotations

import fnmatch
import os
import re
from functools import lru_cache

import yaml

_STAGES_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                            'data', 'commons', 'slot_stages.yaml')

# Slot types that are a piece: they carry the rounds or the minutes the
# movements under them share.
_PIECES = ('for_time', 'rounds_for_time', 'amrap', 'emom')
_LADDER = re.compile(r'^\s*(\d+(?:\s*-\s*\d+)+)\s*(.*)$')
_EACH_SIDE = re.compile(r'\b(each|per|a)\s+(side|hand|arm|leg)\b|/\s*side', re.I)


@lru_cache(maxsize=1)
def _table() -> dict:
    with open(_STAGES_PATH, encoding='utf-8') as f:
        return yaml.safe_load(f) or {}


def stages() -> list[str]:
    return list(_table().get('stages') or [])


def stage_label(stage: str) -> str:
    return (_table().get('labels') or {}).get(stage) or _words(stage)


def stage_of(role: str | None, declared: str | None = None) -> str:
    """The slot's own `stage`, else its role read through the commons' table,
    else main work. A composed day's warm-up (`warm_up__<id>__<role>`) opens it."""
    if declared in stages():
        return declared
    role = str(role or '')
    parts = role.split('__')
    if len(parts) == 3 and parts[0] == 'warm_up':
        return 'prep'
    bare = parts[-1]
    for stage, patterns in (_table().get('roles') or {}).items():
        if any(fnmatch.fnmatch(bare, p) for p in patterns):
            return stage
    return 'main'


# ─── Words ───────────────────────────────────────────────────────────────────

def _words(identifier) -> str:
    text = str(identifier or '').replace('_', ' ').strip()
    return text[:1].upper() + text[1:]


def _num(n) -> str:
    return f'{n:g}' if isinstance(n, (int, float)) else str(n)


def _span(seconds) -> str:
    """90 → "1 min 30 s", 45 → "45 s", 5400 → "1 h 30 min"."""
    seconds = int(round(seconds))
    if seconds >= 3600:
        h, rem = divmod(seconds, 3600)
        m = rem // 60
        return f'{h} h' + (f' {m} min' if m else '')
    if seconds >= 60:
        m, s = divmod(seconds, 60)
        return f'{m} min' + (f' {s} s' if s else '')
    return f'{seconds} s'


def _distance(metres) -> str:
    return f'{metres / 1000:g} km' if metres >= 1000 else f'{_num(metres)} m'


def _scheme_text(scheme: list) -> str:
    return '-'.join(_num(n) for n in scheme)


def _pattern(scheme: list | None) -> str | None:
    """`ladder` when the counts only rise, `pyramid` when they rise and come
    back down; a falling scheme (21-15-9) is neither."""
    if not scheme or len(scheme) < 3 or not all(isinstance(n, (int, float)) for n in scheme):
        return None
    steps = [b - a for a, b in zip(scheme, scheme[1:])]
    if all(s > 0 for s in steps):
        return 'ladder'
    peak = scheme.index(max(scheme))
    if 0 < peak < len(scheme) - 1 and all(s > 0 for s in steps[:peak]) and all(s < 0 for s in steps[peak:]):
        return 'pyramid'
    return None


# ─── One slot, normalised ────────────────────────────────────────────────────

def _written_reps(reps) -> tuple[list | None, str | None, bool]:
    """A slot's `reps` as (scheme, text, each side): "1-2-3-4-5 each side" is a
    scheme done on both sides, "max" stays a word."""
    if reps is None:
        return None, None, False
    if isinstance(reps, str):
        each = bool(_EACH_SIDE.search(reps))
        m = _LADDER.match(reps)
        if m:
            return [int(n) for n in re.split(r'\s*-\s*', m.group(1))], None, each
        text = _EACH_SIDE.sub('', reps).strip(' ,·') if each else reps.strip()
        return None, text or None, each
    return None, _num(reps), False


def _from_slot(slot: dict) -> dict:
    """An archetype's slot as the fields a block reads."""
    scheme, reps, each = _written_reps(slot.get('reps'))
    minutes = slot.get('duration_minutes')
    seconds = slot.get('duration_sec')
    return {
        'role': slot.get('role'), 'parent': slot.get('parent_slot_role'),
        'type': slot.get('slot_type') or 'sets_reps',
        'technique': bool(slot.get('skip_exercise')),
        'sets': slot.get('sets'), 'reps': reps, 'rounds': slot.get('rounds'),
        'scheme': list(slot['rep_scheme']) if slot.get('rep_scheme') else scheme,
        'per_round': slot.get('reps_per_round'),
        'each_side': bool(slot.get('each_side')) or each,
        'work_sec': slot.get('work_sec'), 'rest_sec': slot.get('rest_sec'),
        'seconds': minutes * 60 if minutes else seconds,
        'cap_sec': slot.get('time_cap_sec'),
        'distance_m': slot.get('distance_m'),
        'hold_sec': slot.get('hold_seconds') or slot.get('hold_sec'),
        'load': slot.get('load') or _written_kg(slot), 'intensity': slot.get('intensity'), 'rpe': slot.get('rpe_target'),
        'note': (slot.get('notes') or '').strip() or None,
        'stage': slot.get('stage'), 'group': slot.get('group'),
        'standard': _standard_id(slot.get('standard')),
    }


def _standard_id(std):
    return (std.get('id') if isinstance(std, dict) else std) or None


def _written_kg(slot: dict) -> str | None:
    """A slot's own starting weight ("80 kg"), where its author wrote one."""
    kg = slot.get('start_kg')
    if kg is None:
        return None
    return f"{int(kg) if float(kg).is_integer() else kg} kg"


def _first_rest(*written) -> int | None:
    """The first rest that is some seconds, else a written zero (rounds with
    no rest between them are still rounds), else none written."""
    for seconds in written:
        if seconds:
            return seconds
    return 0 if any(seconds == 0 and seconds is not False for seconds in written) else None


def _from_assignment(ea: dict, written: dict | None) -> dict:
    """A stored session's exercise as the same fields: its load is what the
    generator prescribed, its slot's `stage` and `group` what the archetype
    wrote (`written`, when the session still carries its slots)."""
    load = ea.get('load') or {}
    written = written or {}
    kind = ea.get('slot_type') or written.get('slot_type') or 'sets_reps'
    scheme, reps, each = _written_reps(load.get('reps'))
    interval = bool(load.get('work_sec'))
    minutes = load.get('duration_minutes') or load.get('time_minutes')
    metres = load.get('distance_m') or (load['distance_km'] * 1000 if load.get('distance_km') else None)
    return {
        'role': ea.get('slot_role'), 'parent': ea.get('parent_slot_role'), 'type': kind,
        'technique': bool(ea.get('skip_exercise') or ea.get('meta')),
        'sets': load.get('sets'), 'reps': reps,
        # An AMRAP's or EMOM's forecast of rounds is the generator's, never the
        # workout's; only an interval's rounds are written.
        'rounds': load.get('target_rounds') if (interval or kind not in ('amrap', 'emom')) else None,
        'scheme': list(load['rep_scheme']) if load.get('rep_scheme') else scheme,
        'per_round': load.get('reps_per_round'),
        'each_side': bool(load.get('each_side')) or each,
        'work_sec': load.get('work_sec'),
        'rest_sec': load.get('rest_sec') if interval else _first_rest(ea.get('rest_sec'), load.get('rest_sec'), load.get('round_rest_sec')),
        'seconds': minutes * 60 if minutes and kind not in ('for_time', 'rounds_for_time') else None,
        'cap_sec': minutes * 60 if minutes and kind in ('for_time', 'rounds_for_time') else None,
        'distance_m': metres,
        'hold_sec': load.get('hold_seconds'),
        'load': ea.get('load_note') or load.get('load_note'),
        'intensity': written.get('intensity'), 'rpe': load.get('rpe_target') or load.get('target_rpe'),
        'note': (ea.get('notes') or '').strip() or None,
        'stage': written.get('stage'), 'group': written.get('group'),
        'standard': _standard_id(ea.get('standard')),
    }


# ─── A block ─────────────────────────────────────────────────────────────────

def _count(item: dict, in_piece: bool) -> tuple[str | None, list | None]:
    """What one movement does each round — "5", "21-15-9", "400 m", "30 s" —
    and the round-by-round list when it changes. Outside a piece the headline
    says it and the movement says nothing."""
    if item['scheme'] and in_piece:
        return _scheme_text(item['scheme']), list(item['scheme'])
    if not in_piece:
        return None, None
    if item['per_round']:
        return _num(item['per_round']), None
    if item['distance_m']:
        return _distance(item['distance_m']), None
    if item['type'] == 'amrap_movement' and item['seconds']:
        return _span(item['seconds']), None
    if item['hold_sec']:
        return f"{_num(item['hold_sec'])} s hold", None
    if item['reps']:
        return item['reps'], None
    return None, None


def _shape(lead: dict, has_children: bool) -> str:
    kind = lead['type']
    if lead['technique']:
        return 'note'
    if kind in ('for_time', 'rounds_for_time'):
        # Rounds with a written rest between them — even none — are not raced.
        return 'rounds' if kind == 'rounds_for_time' and lead['rest_sec'] is not None else 'for_time'
    if kind == 'amrap':
        return 'interval' if lead['work_sec'] else 'amrap'
    if kind == 'emom':
        return 'emom'
    if lead['work_sec'] or (kind in ('time_domain', 'skill_practice') and lead['seconds']
                            and lead['seconds'] < 60 and (lead['sets'] or 1) > 1):
        return 'interval'
    if has_children:
        return 'rounds'
    if kind == 'static_hold':
        return 'hold'
    if kind == 'time_domain':
        return 'timed'
    if kind == 'distance':
        return 'distance'
    if kind == 'skill_practice':
        return 'practice'
    return 'sets'


def _headline(shape: str, lead: dict, repeat: dict, alone: str | None = None) -> str:
    rounds, scheme = repeat.get('rounds'), repeat.get('scheme')
    minutes = repeat.get('minutes')
    if shape == 'for_time':
        if scheme:
            return f'{_scheme_text(scheme)} for time'
        if rounds and rounds != 1:
            return f'{_num(rounds)} rounds for time'
        # One movement raced once is said whole: "500 m for time".
        return f'{alone} for time' if alone else 'For time'
    if shape == 'rounds':
        if scheme:
            return f'{len(scheme)} rounds'
        return f'{_num(rounds)} rounds' if rounds and rounds != 1 else 'One round'
    if shape == 'amrap':
        return f'{_num(minutes)} min AMRAP' if minutes else 'AMRAP'
    if shape == 'emom':
        every = repeat.get('everySec')
        lead_in = 'Every minute' if every == 60 else f'Every {_span(every)}' if every else 'EMOM'
        if rounds:
            return f'{lead_in} × {_num(rounds)}'
        return f'{lead_in} · {_num(minutes)} min' if minutes else lead_in
    if shape == 'interval':
        work = f"{_span(repeat['workSec'])} on" if repeat.get('workSec') else ''
        off = f" / {_span(repeat['restSec'])} off" if repeat.get('restSec') else ''
        return f'{_num(rounds)} × {work}{off}' if rounds and rounds != 1 else f'{work}{off}'.strip(' /')
    sets = repeat.get('sets')
    if shape == 'hold':
        hold = f"{_num(lead['hold_sec'] or lead['seconds'] or 0)} s hold"
        return f'{_num(sets)} × {hold}' if sets and sets != 1 else hold
    if shape in ('timed', 'practice'):
        if not lead['seconds']:
            return f'{_num(sets)} sets' if sets and sets != 1 else ''
        span = _span(lead['seconds'])
        return f'{_num(sets)} × {span}' if sets and sets != 1 else span
    if shape == 'distance':
        if not lead['distance_m']:
            return ''
        return (f"{_num(sets)} × " if sets and sets != 1 else '') + _distance(lead['distance_m'])
    if shape == 'note':
        return ''
    # sets
    each = ' each side' if lead['each_side'] else ''
    what = _scheme_text(scheme) if scheme else lead['reps']
    if sets and what:
        return f'{_num(sets)} × {what}{each}'
    if what:
        return f'{what}{each}' if scheme else f'{what} reps{each}'
    return f'{_num(sets)} sets' if sets else ''


def _repeat(shape: str, lead: dict) -> dict:
    out: dict = {}
    scheme = lead['scheme']
    if shape in ('for_time', 'rounds', 'amrap', 'emom', 'interval'):
        rounds = lead['rounds'] or (lead['sets'] if shape in ('emom', 'interval') else None)
        if scheme and not rounds:
            rounds = len(scheme)
        if rounds:
            out['rounds'] = rounds
        if lead['work_sec']:
            out['workSec'] = lead['work_sec']
            if lead['rest_sec']:
                out['restSec'] = lead['rest_sec']
        elif shape == 'interval' and lead['seconds']:
            out['workSec'] = lead['seconds']
            if lead['rest_sec']:
                out['restSec'] = lead['rest_sec']
        if shape == 'emom':
            if lead['work_sec']:
                out['everySec'] = lead['work_sec'] + (lead['rest_sec'] or 0)
            elif rounds and lead['seconds'] and lead['seconds'] % rounds == 0:
                out['everySec'] = lead['seconds'] // rounds
            else:
                out['everySec'] = 60
                if not rounds and lead['seconds']:
                    out['rounds'] = round(lead['seconds'] / 60)
        if lead['seconds'] and shape in ('amrap', 'emom'):
            out['minutes'] = round(lead['seconds'] / 60)
        cap = lead['cap_sec'] or (lead['seconds'] if shape == 'for_time' else None)
        if cap and shape in ('for_time', 'rounds'):
            out['capMin'] = max(1, round(cap / 60))
    elif lead['sets'] and lead['sets'] != 1:
        out['sets'] = lead['sets']
    if scheme:
        out['scheme'] = list(scheme)
    return out


def _rest(shape: str, lead: dict, repeat: dict) -> dict | None:
    """The rest a reader is told about once: between rounds, between sets, or
    after the block. An interval's rest is in its headline already."""
    seconds = lead['rest_sec']
    if not seconds or repeat.get('restSec') or (shape == 'emom' and lead['work_sec']):
        return None
    if shape in ('for_time', 'rounds', 'amrap', 'emom'):
        between = 'rounds'
    elif repeat.get('sets'):
        between = 'sets'
    else:
        between = 'after'
    text = f'{_span(seconds)} rest' + ('' if between == 'after' else f' between {between}')
    return {'seconds': seconds, 'between': between, 'text': text}


def _again(shape: str, repeat: dict, movements: int) -> str | None:
    """What happens at the foot of a round, in words: the loop a reader
    follows back to the top."""
    rounds = repeat.get('rounds')
    if shape in ('for_time', 'rounds') and rounds and rounds != 1 and not repeat.get('scheme'):
        return f'{_num(rounds)} rounds in all'
    if shape == 'amrap':
        return 'Again, until the time is up'
    if shape == 'emom' and (movements > 1 or rounds):
        every = repeat.get('everySec')
        return 'Start again every minute' if every in (None, 60) else f'Start again every {_span(every)}'
    return None


def _block(items: list[dict], names: dict, pools: dict) -> dict:
    lead = items[0]
    in_piece = len(items) > 1 or lead['type'] in _PIECES
    shape = _shape(lead, len(items) > 1)
    repeat = _repeat(shape, lead)
    pattern = _pattern(repeat.get('scheme')) if shape in ('sets', 'rounds') else None
    movements = []
    for item in items:
        count, per_round = _count(item, in_piece)
        entry = pools.get(item['role']) or {}
        pool = entry.get('exercises') or []
        # A slot that lists its movements names the first as written; one that
        # filters has no movement of its own, only its role.
        written = pool[0]['name'] if pool and entry.get('listed') else None
        movements.append({
            'role': item['role'],
            'name': names.get(item['role']) or written or _words(_bare(item['role'])),
            'count': count, 'perRound': per_round,
            'eachSide': item['each_side'],
            # The lead's note is the block's.
            'note': item['note'] if item is not lead else None,
            'exercises': pool[:6],
            'listed': bool(entry.get('listed')),
            'more': max(0, len(pool) - 6),
            **({'technique': True} if item['technique'] else {}),
        })
    cap = repeat.get('capMin')
    return {
        'id': lead['role'],
        'stage': (stage := stage_of(lead['role'], lead['stage'])),
        'stageLabel': stage_label(stage),
        'shape': pattern or shape,
        'title': _title(lead['role']),
        'headline': _headline(shape, lead, repeat,
                              movements[0]['count'] if len(items) == 1 and not movements[0]['perRound'] else None),
        'repeat': repeat or None,
        'rest': _rest(shape, lead, repeat),
        'again': _again(shape, repeat, len(items)),
        'cap': f'{cap} min cap' if cap else None,
        'load': lead['load'] or None,
        'intensity': _words(lead['intensity']).lower() if lead['intensity'] else None,
        'rpe': lead['rpe'],
        'note': lead['note'],
        'standard': lead['standard'],
        'group': lead['group'] if isinstance(lead['group'], dict) else None,
        'roles': [i['role'] for i in items],
        'movements': movements,
    }


_POSITIONAL = re.compile(r'b\d+(_\d+)?')


def _title(role) -> str:
    """A block's name from its role; none where the role only counts (a
    session composed by hand numbers its blocks b1, b2…)."""
    bare = _bare(role)
    return '' if _POSITIONAL.fullmatch(bare) else _words(bare)


def _bare(role) -> str:
    """A composed day's `warm_up__<id>__<role>` or `<id>__<role>` as its role."""
    return str(role or '').split('__')[-1]


def _grouped(items: list[dict]) -> list[list[dict]]:
    """Each piece with the movements that name it; a slot naming no piece is a
    block of its own. A movement whose piece is missing follows the block
    before it only when that block is a piece (the watches' rule)."""
    groups: list[list[dict]] = []
    by_lead: dict = {}
    for item in items:
        parent = item['parent']
        if parent and parent in by_lead:
            by_lead[parent].append(item)
            continue
        if item['type'] == 'amrap_movement' and not parent and groups and groups[-1][0]['type'] in _PIECES:
            groups[-1].append(item)
            continue
        group = [item]
        groups.append(group)
        by_lead[item['role']] = group
    return groups


def build(items: list[dict], names: dict | None = None, pools: dict | None = None) -> list[dict]:
    """Blocks of normalised slots, in the order written. `names` is each
    role's movement by name when one is chosen (a session), `pools` what a
    role may take (an archetype)."""
    return [_block(group, names or {}, pools or {}) for group in _grouped(items)]


# ─── The two readers ─────────────────────────────────────────────────────────

def for_archetype(arch: dict, pools: dict | None = None) -> list[dict]:
    """An archetype as its package writes it. `pools`: role → {exercises:
    [{id, name}], listed}, what the selector would consider for the slot
    (explore_links.slot_exercises)."""
    return build([_from_slot(s) for s in arch.get('slots') or [] if s.get('role')], pools=pools)


def for_session(session: dict) -> list[dict]:
    """A session of a program: its exercises as prescribed."""
    arch = session.get('archetype') if isinstance(session.get('archetype'), dict) else {}
    written = {s.get('role'): s for s in arch.get('slots') or [] if isinstance(s, dict)}
    items, names = [], {}
    for ea in session.get('exercises') or []:
        if not isinstance(ea, dict) or not ea.get('slot_role'):
            continue
        items.append(_from_assignment(ea, written.get(ea['slot_role'])))
        ex = ea.get('exercise')
        if isinstance(ex, dict) and ex.get('name'):
            names[ea['slot_role']] = ex['name']
    return build(items, names=names)


def _sessions(weeks: list):
    for wk in weeks or []:
        sched = wk.get('schedule') if isinstance(wk, dict) else None
        if isinstance(sched, dict):
            for sessions in sched.values():
                for s in sessions or []:
                    if isinstance(s, dict):
                        yield s


def _map_sessions(weeks: list, fn) -> list:
    out = []
    for wk in weeks or []:
        sched = wk.get('schedule') if isinstance(wk, dict) else None
        if not isinstance(sched, dict):
            out.append(wk)
            continue
        out.append({**wk, 'schedule': {
            day: [fn(s) if isinstance(s, dict) else s for s in sessions or []]
            for day, sessions in sched.items()}})
    return out


def with_blocks(weeks: list) -> list:
    """The weeks with each session's `blocks` set (derived on read)."""
    def add(session: dict) -> dict:
        session = {k: v for k, v in session.items() if k != 'blocks'}
        blocks = for_session(session)
        return {**session, 'blocks': blocks} if blocks else session
    return _map_sessions(weeks, add)


def strip(current_program: dict) -> dict:
    """`current_program` without any session's `blocks`."""
    weeks = current_program.get('weeks') if isinstance(current_program, dict) else None
    if not any('blocks' in s for s in _sessions(weeks)):
        return current_program
    return {**current_program,
            'weeks': _map_sessions(weeks, lambda s: {k: v for k, v in s.items() if k != 'blocks'})}
