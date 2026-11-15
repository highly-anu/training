"""Before a session: today's numbers beside the earlier times it was done.

`build` is pure. It reads one planned session against the athlete's earlier
occurrences of the same thing — the same contract module, the same named
workout, the same exercise, as the package's briefing spec says
(src/briefing_spec.py) — and answers, per item: today's prescription, each
earlier occurrence with what it was (clean, made, missed, logged, or done but
unconfirmed), where the session stands in its cycle, and one suggestion.

Every sentence is written here; a client lays the document out and formats
nothing. A suggestion is advice: nothing in this module changes a program.
The route (`GET /api/sessions/briefing`) gathers the inputs.
"""
from __future__ import annotations

from datetime import date as _date

from src import briefing_spec, last_time, training_contract
from src.analytics.exercise_series import done_text, done_values, prescribed_text, prescribed_values

_DONE_AS_WRITTEN = ('clean', 'made')
_METRICS = {
    'weight': ('Weight', 'kg'), 'reps': ('Reps', 'reps'), 'sets': ('Sets', 'sets'),
    'total_reps': ('Total reps', 'reps'), 'rounds': ('Rounds', 'rounds'),
    'reps_per_round': ('Reps a round', 'reps'), 'time': ('Time', 'min'), 'hold': ('Hold', 's'),
    'distance': ('Distance', 'km'), 'rpe': ('RPE', ''),
}
_MAX_ITEMS = 12


def _num(v) -> float | None:
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def _n(v: float) -> str:
    return f'{v:g}'


def _plural(n: float, word: str) -> str:
    return f"{_n(n)} {word}{'' if n == 1 else 's'}"


# ── What a session holds ──────────────────────────────────────────────────────

def _assignments(session: dict) -> list[dict]:
    return [ea for ea in session.get('exercises') or []
            if isinstance(ea, dict) and (ea.get('exercise') or {}).get('id')
            and not (ea.get('meta') or ea.get('injury_skip') or ea.get('coverage_gap')
                     or ea.get('equipment_gap') or ea.get('skip_exercise'))]


def _eid(ea: dict) -> str:
    return (ea.get('exercise') or {}).get('id')


def _package(session: dict) -> str | None:
    return (session.get('archetype') or {}).get('_package') or (session.get('provenance') or {}).get('package')


def _records(session: dict) -> dict:
    return {m.get('id'): m for m in session.get('modules') or [] if isinstance(m, dict)}


def _pieces(session: dict) -> list[dict]:
    """The named workouts a templated day is made of; else the session's own archetype."""
    pieces = [p for p in session.get('pieces') or [] if isinstance(p, dict) and p.get('archetype_id')]
    if pieces:
        return [{'id': p['archetype_id'], 'name': p.get('name')} for p in pieces]
    arch = session.get('archetype') or {}
    return [{'id': arch.get('id'), 'name': arch.get('name')}] if arch.get('id') else []


def _piece_of(ea: dict, pieces: list[dict]) -> str | None:
    """Which piece an exercise belongs to; None for the day's warm-up. A
    composed slot's role names its source ('warm_up__<id>__<role>',
    '<id>__<role>'); the first piece keeps its own roles."""
    role = str(ea.get('slot_role') or '')
    if role.startswith('warm_up__'):
        return None
    for piece in pieces[1:]:
        if role.startswith(f"{piece['id']}__"):
            return piece['id']
    return pieces[0]['id'] if pieces else None


def _standard_id(ea: dict) -> str | None:
    s = ea.get('standard')
    return s.get('id') if isinstance(s, dict) else (s if isinstance(s, str) else None)


def _facts(ea: dict, session: dict) -> dict:
    load = ea.get('load') or {}
    return {
        'progression_model': load.get('progression_model'),
        'module': load.get('module_id'),
        'archetypes': [p['id'] for p in _pieces(session)] + [(session.get('archetype') or {}).get('id')],
        'exercise': _eid(ea),
        'slot_type': ea.get('slot_type'),
        'slot_role': ea.get('slot_role'),
        'named_workout': bool(session.get('pieces')),
        'scored': bool(_standard_id(ea)),
    }


def _carries_module(ea: dict, records: dict) -> bool:
    """A contract module's preparation and recovery blocks make no item: only
    what carries its progress does (every block, when nothing does)."""
    record = records.get((ea.get('load') or {}).get('module_id'))
    if not record or not record.get('exercise_ids'):
        return True
    return _eid(ea) in record['exercise_ids']


# ── Numbers and their words ───────────────────────────────────────────────────

def _values(ea: dict, session: dict) -> dict:
    load = ea.get('load') or {}
    pv = prescribed_values(ea, session)
    per_round = _num(load.get('reps_per_round'))
    rounds = pv.get('rounds')
    interval = None
    if rounds is not None and _num(load.get('work_sec')) is not None:
        interval = _num(load.get('work_sec')) + (_num(load.get('rest_sec')) or 0)
    total = rounds * per_round if rounds is not None and per_round is not None else pv.get('totalReps')
    return {
        'sets': pv.get('sets'), 'reps': None if per_round is not None else pv.get('reps'),
        'rounds': rounds, 'reps_per_round': per_round, 'weight': pv.get('weight'), 'interval': interval,
        'time': pv.get('time'), 'hold': pv.get('hold'), 'distance': pv.get('distance'), 'rpe': None,
        'total_reps': total,
    }


def _interval_words(sec: float) -> str:
    if sec == 60:
        return 'on the minute'
    return f'every {_n(sec / 60)} min' if sec % 60 == 0 else f'every {_n(sec)} s'


def _show_text(values: dict, show: list[str]) -> str:
    def has(k):
        return k in show and values.get(k) is not None
    parts, used = [], set()
    if has('rounds') and has('reps_per_round'):
        parts.append(f"{_n(values['rounds'])} × {_n(values['reps_per_round'])}")
        used |= {'rounds', 'reps_per_round'}
    elif has('sets') and has('reps'):
        parts.append(f"{_n(values['sets'])} × {_n(values['reps'])}")
        used |= {'sets', 'reps'}
    words = {
        'sets': lambda v: _plural(v, 'set'), 'reps': lambda v: _plural(v, 'rep'),
        'rounds': lambda v: _plural(v, 'round'), 'reps_per_round': lambda v: f'{_n(v)} a round',
        'weight': lambda v: f'{_n(v)} kg', 'interval': _interval_words, 'time': lambda v: f'{_n(v)} min',
        'hold': lambda v: f'{_n(v)} s hold', 'distance': lambda v: f'{_n(v)} km', 'rpe': lambda v: f'RPE {_n(v)}',
    }
    for k in show:
        if k not in used and has(k):
            parts.append(words[k](values[k]))
    return ' · '.join(parts)


def _text(ea: dict, values: dict, show: list[str]) -> str:
    return _show_text(values, show) or prescribed_text(ea.get('load') or {}) or ''


def _joined(named: list[tuple[str, str]]) -> str:
    texts = [t for _, t in named if t]
    if len(set(texts)) <= 1:
        return texts[0] if texts else ''
    return '; '.join(f'{name}: {t}' for name, t in named if t)


def _day(day: str, today: str) -> tuple[str, str]:
    """("Thursday", "Thursday's") inside a week, else ("12 Nov", "12 Nov's")."""
    try:
        d, t = _date.fromisoformat(day[:10]), _date.fromisoformat(today[:10])
    except (ValueError, TypeError):
        return day, f"{day}'s"
    name = 'yesterday' if (t - d).days == 1 else d.strftime('%A') if 0 < (t - d).days < 7 \
        else f"{d.day} {d.strftime('%b')}"
    return name, f"{name}'s"


# ── Earlier occurrences ───────────────────────────────────────────────────────

def _done(occ: dict) -> bool:
    return bool((occ.get('log') or {}).get('completedAt')) or bool(occ.get('matched'))


def _same(identity: tuple, occ: dict, package: str | None) -> list[dict] | None:
    """The occurrence's exercises that are this item's, or None when the
    occurrence is not one of it."""
    kind, ident, variant = identity
    session = occ.get('session') or {}
    eas = _assignments(session)
    if kind == 'module':
        record = _records(session).get(ident)
        theirs = _package(session)
        if not record or (package and theirs and theirs != package) or (variant and record.get('variant') != variant):
            return None
        records = _records(session)
        return [ea for ea in eas if (ea.get('load') or {}).get('module_id') == ident
                and _carries_module(ea, records)] or None
    if kind == 'archetype':
        pieces = _pieces(session)
        if ident not in [p['id'] for p in pieces]:
            return None
        return [ea for ea in eas if _piece_of(ea, pieces) == ident] or None
    return [ea for ea in eas if _eid(ea) == ident][:1] or None


def _status(kind: str, ident, occ: dict, eas: list[dict]) -> str:
    session, logged = occ.get('session') or {}, (occ.get('log') or {}).get('exercises') or {}
    records = _records(session)
    entries = [logged.get(_eid(ea)) for ea in eas]
    has_log = any(isinstance(e, dict) and e for e in entries)
    lead = eas[0]
    record = records.get((lead.get('load') or {}).get('module_id'))
    lift = ((record or {}).get('lifts') or {}).get(_eid(lead))
    if lift is not None:
        made, _kg = training_contract._lift_outcome(entries[0] if isinstance(entries[0], dict) else {}, lift)
        if made is not None:
            return 'made' if made else 'missed'
        return 'logged' if has_log else 'unconfirmed'
    if kind == 'module' and record and record.get('exercise_ids'):
        try:
            if training_contract.clean_outcomes(record, logged) is not None:
                return 'clean'
        except (KeyError, TypeError):
            pass
    return 'logged' if has_log else 'unconfirmed'


def _occurrence(kind: str, ident, occ: dict, eas: list[dict], show: list[str], today: str) -> dict:
    session, logged = occ.get('session') or {}, (occ.get('log') or {}).get('exercises') or {}
    status = _status(kind, ident, occ, eas)
    # An earlier row says what was done, not how the clock ran: today's line
    # carries the interval, and a change of it is the suggestion's to say.
    show = [k for k in show if k != 'interval']
    named, lead_values, parts = [], None, {}
    for ea in eas:
        entry = logged.get(_eid(ea)) if isinstance(logged.get(_eid(ea)), dict) else {}
        values = _values(ea, session)
        planned = _text(ea, values, show)
        if status != 'unconfirmed' and entry:
            done, sets_done = done_values(entry)
            if _num(entry.get('weightKg')) is not None:
                done['weight'] = _num(entry['weightKg'])
            for k_done, k in (('weight', 'weight'), ('rounds', 'rounds'), ('rpe', 'rpe'), ('hold', 'hold'),
                              ('distance', 'distance')):
                if done.get(k_done) is not None:
                    values[k] = done[k_done]
            if values.get('rounds') is not None and values.get('reps_per_round') is not None:
                values['total_reps'] = values['rounds'] * values['reps_per_round']
            # Rounds of so many reps read the same whether or not they earned
            # the step ("5 × 5 · 20 kg · RPE 8"): the log has the rounds, the
            # plan the reps in each.
            if status in _DONE_AS_WRITTEN or (values.get('rounds') is not None
                                              and values.get('reps_per_round') is not None):
                text = _show_text(values, show + [k for k in ('weight', 'rpe') if k not in show]) or planned
            else:
                text = done_text(done, sets_done) or last_time.describe(entry) or planned
        else:
            text = planned
        named.append(((ea.get('exercise') or {}).get('name') or _eid(ea), text))
        parts.setdefault(_eid(ea), {'text': text, 'values': {k: v for k, v in values.items() if v is not None}})
        lead_values = lead_values or values
    record = _records(session).get((eas[0].get('load') or {}).get('module_id')) or {}
    name, _ = _day(str(occ.get('date')), today)
    return {
        # The lead exercise's line; each exercise's own is in `_parts`.
        'date': str(occ.get('date'))[:10], 'dayText': name, 'text': named[0][1] if named else '',
        '_parts': parts,
        'values': {k: v for k, v in (lead_values or {}).items() if v is not None},
        'status': status, 'isDeload': bool(record.get('deload', session.get('is_deload'))),
        'sessionKey': occ.get('key') if occ.get('current') else None,
        '_step': record.get('forecast_step'), '_current': bool(occ.get('current')),
    }


# ── Suggestions ───────────────────────────────────────────────────────────────

_CHANGE = {
    'reps_per_round': ('{n} more a round', '{n} fewer a round'),
    'rounds': ('{n} more rounds', '{n} fewer rounds'),
    'sets': ('{n} more sets', '{n} fewer sets'),
    'reps': ('{n} more reps a set', '{n} fewer reps a set'),
    'weight': ('{n} kg heavier', '{n} kg lighter'),
    'time': ('{n} min longer', '{n} min shorter'),
    'hold': ('{n} s longer', '{n} s shorter'),
    'distance': ('{n} km further', '{n} km shorter'),
}


def _next_step(today_values: dict, show: list[str], history: list[dict], today: str) -> str | None:
    last = next((h for h in reversed(history) if not h['isDeload']), history[-1] if history else None)
    if not last:
        return None
    name, _ = _day(last['date'], today)
    changes, interval = [], None
    for k in show:
        a, b = today_values.get(k), last['values'].get(k)
        if a is None or b is None or a == b:
            continue
        if k == 'interval':
            interval = f'Rounds now run {_interval_words(a)}'
        elif k in _CHANGE:
            changes.append(_CHANGE[k][0 if a > b else 1].format(n=_n(abs(a - b))))
    if not changes:
        return f'{interval}; the rest is the same as {name}.' if interval else f'The same as {name}.'
    ups = [today_values[k] > last['values'][k] for k in show
           if k in _CHANGE and today_values.get(k) is not None and last['values'].get(k) is not None
           and today_values[k] != last['values'][k]]
    if any(ups) and not all(ups):
        # One number up and another down is a new stage, not a step: the two
        # sessions side by side say it; a sum of differences says nothing.
        quiet = [k for k in show if k != 'interval']
        was, now = _show_text(last['values'], quiet), _show_text(today_values, quiet)
        if was and now:
            return f'A new stage: {now}. {name[0].upper()}{name[1:]} was {was}.' + (f' {interval}.' if interval else '')
    sentence = ', '.join(changes[:-1]) + (' and ' if len(changes) > 1 else '') + changes[-1]
    return f'{sentence[0].upper()}{sentence[1:]} than {name}.' + (f' {interval}.' if interval else '')


def _next_load(lead: dict, today_values: dict, history: list[dict], today: str) -> str | None:
    load = lead.get('load') or {}
    if not load.get('lift'):
        return None
    kg = today_values.get('weight')
    if load.get('work_up') and kg is None:
        return 'No weight yet: work up to a heavy set today and log it.'
    if not history or kg is None:
        return None
    last = history[-1]
    name, poss = _day(last['date'], today)
    was = last['values'].get('weight')
    if last['status'] == 'made' and was is not None:
        return f'Made {_n(was)} kg {name if name == "yesterday" else "on " + name} — {_n(kg)} kg today.'
    if last['status'] == 'missed' and was is not None:
        return (f'Missed at {_n(was)} kg {name if name == "yesterday" else "on " + name} — the same weight again.'
                if kg >= was else
                f'Missed at {_n(was)} kg {name if name == "yesterday" else "on " + name} — back to {_n(kg)} kg today.')
    if last['status'] in ('unconfirmed', 'logged') and last['_current']:
        return f"{poss[0].upper()}{poss[1:]} result is not logged; today's {_n(kg)} kg assumes the lift was made."
    return None


def _suggestion(kind: str, entry: dict, lead: dict, today_values: dict, history: list[dict],
                all_history: list[dict], cycle: dict | None, standard: dict | None, today: str) -> str | None:
    if kind == 'confirm_pending':
        if not (lead.get('load') or {}).get('conditional'):
            return None
        open_ = [h for h in all_history if h['_current'] and not h['isDeload']
                 and h['status'] in ('unconfirmed', 'logged')]
        if not open_:
            return None
        _, poss = _day(open_[0]['date'], today)
        return (f"{poss[0].upper()}{poss[1:]} session is not confirmed as clean, and today's numbers assume it "
                f'was. Confirm it first: a rebuilt program picks up from the last clean session.')
    if kind == 'next_step':
        return _next_step(today_values, entry['show'], history, today)
    if kind == 'cycle_end':
        if cycle and cycle['step'] == cycle['of']:
            return 'The last step of this cycle. The next one starts over with a heavier load.'
        return None
    if kind == 'next_load':
        return _next_load(lead, today_values, history, today)
    if kind == 'beat_last':
        scored = [h for h in history if h['status'] == 'logged']
        if not scored:
            return None
        name, _ = _day(scored[-1]['date'], today)
        return f"{scored[-1]['text']} {name if name == 'yesterday' else 'on ' + name} — the number to beat."
    if kind == 'standard_target':
        if not standard or not (standard.get('best') or standard.get('target')):
            return None
        target = standard.get('target')
        if standard.get('best') and target:
            return f"Your best is {standard['best']}; {target}."
        return f"Your best is {standard['best']}." if standard.get('best') else f'{target[0].upper()}{target[1:]}.'
    if kind == 'repeat_last':
        if not history:
            return None
        name, _ = _day(history[-1]['date'], today)
        return f"Last time, {name}: {history[-1]['text']}."
    return None


# ── The document ──────────────────────────────────────────────────────────────

def build(session: dict, *, date: str, spec: dict | None = None, history: list[dict] | None = None,
          key: str | None = None, uid: str | None = None, modules: dict | None = None,
          standards: dict | None = None) -> dict:
    """The briefing for one planned session.

    `history`: occurrences `{date, session, log, matched, key, current}` — any
    earlier planned session of the athlete with its log; only those done before
    `date` are read. `modules`: {module id: {name, progression}} of the
    session's contract track. `standards`: {standard id: {name, best, target}}
    (src/standards.watch_standard).
    """
    spec = spec or briefing_spec.spec_for(_package(session))
    modules, standards = modules or {}, standards or {}
    package, records, pieces = _package(session), _records(session), _pieces(session)
    earlier = sorted((o for o in history or [] if str(o.get('date') or '')[:10] < date[:10] and _done(o)
                      and isinstance(o.get('session'), dict)), key=lambda o: str(o['date']))

    groups: dict[tuple, dict] = {}
    for ea in _assignments(session):
        if not _carries_module(ea, records):
            continue
        entry = briefing_spec.entry_for(spec, _facts(ea, session))
        load = ea.get('load') or {}
        if entry['same_as'] == 'module' and load.get('module_id'):
            mid = load['module_id']
            identity = ('module', mid, (records.get(mid) or {}).get('variant'))
            title = (modules.get(mid) or {}).get('name') or (session.get('archetype') or {}).get('name')
        elif entry['same_as'] == 'archetype' and pieces:
            piece = _piece_of(ea, pieces)
            if piece is None:
                continue
            identity = ('archetype', piece, None)
            title = next((p.get('name') for p in pieces if p['id'] == piece), None)
        else:
            identity = ('exercise', _eid(ea), None)
            title = (ea.get('exercise') or {}).get('name')
        group = groups.setdefault(identity, {'entry': entry, 'title': title or _eid(ea), 'eas': []})
        group['eas'].append(ea)

    items, pending = [], {}
    for identity, group in list(groups.items())[:_MAX_ITEMS]:
        kind, ident, _variant = identity
        entry, eas = group['entry'], group['eas']
        show, lead = entry['show'], eas[0]
        today_values = _values(lead, session)
        lines = [{'exerciseId': _eid(ea), 'name': (ea.get('exercise') or {}).get('name') or _eid(ea),
                  'text': _text(ea, _values(ea, session), show)} for ea in eas]
        all_history = []
        for occ in earlier:
            theirs = _same(identity, occ, package)
            if theirs:
                all_history.append(_occurrence(kind, ident, occ, theirs, show, date))
        history_rows = all_history[-entry['history']:] if entry['history'] else []

        cycle = None
        if entry['cycle'] and kind == 'module':
            step = (records.get(ident) or {}).get('forecast_step')
            position = training_contract.cycle_position((modules.get(ident) or {}).get('progression'), step or 0) \
                if step is not None else None
            if position:
                cycle = dict(position, text=f"Step {position['step']} of {position['of']}" + (
                    f" · stage {position['stage']} of {position['stages']}" if position['stages'] > 1 else ''))

        standard = next((standards[s] for s in (_standard_id(ea) for ea in eas) if s and s in standards), None)
        suggestion = None
        for s_kind in entry['suggest']:
            text = _suggestion(s_kind, entry, lead, today_values, all_history, all_history, cycle, standard, date)
            if text:
                suggestion = {'kind': s_kind, 'text': text}
                break
        if kind == 'module' and 'confirm_pending' in entry['suggest'] and (lead.get('load') or {}).get('conditional'):
            for h in all_history:
                if h['_current'] and h['sessionKey'] and not h['isDeload'] and h['status'] in ('unconfirmed', 'logged'):
                    pending.setdefault(h['sessionKey'], {
                        'sessionKey': h['sessionKey'], 'date': h['date'],
                        'text': f"{h['dayText'][0].upper()}{h['dayText'][1:]}: done as written?"})

        chart = entry['chart'] or next((k for k in show if k in _METRICS and (
            today_values.get(k) is not None or any(h['values'].get(k) is not None for h in all_history))), None)
        # Exercise by exercise: today's line and that exercise's own earlier ones.
        exercises = []
        for ea, ln in zip(eas, lines):
            values = _values(ea, session)
            exercises.append({
                'exerciseId': ln['exerciseId'], 'name': ln['name'],
                'today': {'text': ln['text'], 'values': {k: v for k, v in values.items() if v is not None}},
                'history': [{'date': h['date'], 'dayText': h['dayText'], 'status': h['status'],
                             'isDeload': h['isDeload'], 'sessionKey': h['sessionKey'],
                             **h['_parts'][ln['exerciseId']]}
                            for h in history_rows if ln['exerciseId'] in h['_parts']],
            })
        item = {
            'id': f"{kind}:{ident}", 'entry': entry['id'], 'kind': kind, 'title': group['title'],
            'exercises': exercises,
            'exerciseIds': [_eid(ea) for ea in eas],
            'today': {'text': _joined([(ln['name'], ln['text']) for ln in lines]),
                      'values': {k: v for k, v in today_values.items() if v is not None},
                      'lines': lines, 'conditional': bool((lead.get('load') or {}).get('conditional'))},
            'history': [_public(h) for h in history_rows],
            'last': _public(all_history[-1]) if all_history else None,
            'times': len(all_history),
        }
        if chart:
            item['metric'] = {'id': chart, 'label': _METRICS[chart][0], 'unit': _METRICS[chart][1]}
        if cycle:
            item['cycle'] = cycle
        if suggestion:
            item['suggestion'] = suggestion
        if standard:
            item['standard'] = {k: standard[k] for k in ('id', 'name', 'best', 'target') if standard.get(k)}
        if entry['notes']:
            item['notes'] = entry['notes']
        items.append(item)

    arch = session.get('archetype') or {}
    return {
        'session': {
            'key': key, 'uid': uid, 'date': date[:10], 'name': arch.get('name'),
            'modality': session.get('modality'), 'minutes': arch.get('duration_estimate_minutes'),
            'isDeload': bool(session.get('is_deload')), 'isTest': bool(session.get('test')),
            'packageId': package,
        },
        'spec': spec.get('source'),
        'headline': f"{items[0]['title']} · {items[0]['today']['text']}" if items and items[0]['today']['text']
        else (items[0]['title'] if items else None),
        'items': items,
        'pending': sorted(pending.values(), key=lambda p: p['date']),
    }


def _public(row: dict) -> dict:
    return {k: v for k, v in row.items() if not k.startswith('_')}
