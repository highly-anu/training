"""The athlete's results on the standards, read the same way by every screen.

A result is one dated value on a standard (`performance_logs`,
src/standards_store.py). The level, the next level and the text a value prints
as are worked out here, once: the web and the phone each used to compute the
level from the thresholds themselves, and disagreed — the phone had no "below
entry" and printed 1.25×BW as "1.3".

Current is the latest result (a retest after a layoff is honest even when it
is worse); best is the best result ever. A result counts for the athlete's day
(`loggedOn`), not its UTC timestamp's. Results belong to the athlete, not to a
program: each is placed in the block whose activation covers its day.

Pure: no Flask, no DB.
"""
from __future__ import annotations

from datetime import date, datetime

from src.analytics import benchmarks_data as bd

# Epley, as src/analytics/primitives/load.py estimates a 1RM from a set.
_EPLEY = 0.0333

SOURCES = ('manual', 'session', 'garmin', 'apple_watch', 'workout')


class InputError(ValueError):
    """What the athlete sent cannot be a result; the message says why, in words."""


def _iso_day(raw) -> str | None:
    try:
        return date.fromisoformat(str(raw)[:10]).isoformat()
    except (TypeError, ValueError):
        return None


def day_of(entry: dict, tz: str | None = None) -> str | None:
    """The athlete's day a result counts for: `loggedOn`, else its timestamp's
    day where the athlete was (a row from before migrations/011), else UTC."""
    if entry.get('loggedOn'):
        return _iso_day(entry['loggedOn'])
    raw = entry.get('date') or entry.get('loggedAt') or entry.get('logged_at')
    if raw and tz and len(str(raw)) > 10:
        try:
            from src.fit_import import local_date
            return local_date(datetime.fromisoformat(str(raw).replace('Z', '+00:00')), tz=tz)
        except (TypeError, ValueError):
            pass
    return _iso_day(raw)


def point(b: dict, value: float, day: str | None, sex: str) -> dict:
    """One value placed on a standard's ladder, with its words."""
    lv = bd.level_of(b, value, sex)
    nxt = lv['next']
    return {
        'value': value, 'valueText': bd.format_value(b, value), 'date': day,
        'level': lv['level'], 'levelIndex': lv['index'],
        'next': nxt, 'nextText': bd.format_value(b, bd.thresholds(b, sex).get(nxt)) if nxt else None,
        'gap': lv['gap'], 'gapText': bd.format_value(b, lv['gap']) if lv['gap'] is not None else None,
    }


def input_text(inp: dict | None) -> str | None:
    """What was lifted, for a ×BW result logged as a load: "140 kg × 2 at 82 kg"."""
    if not isinstance(inp, dict) or inp.get('kg') is None:
        return None
    reps = int(inp.get('reps') or 1)
    text = f"{bd.number_text(float(inp['kg']), 1)} kg" + (f' × {reps}' if reps > 1 else '')
    if inp.get('bodyweightKg'):
        text += f" at {bd.number_text(float(inp['bodyweightKg']), 1)} kg"
    return text + (' · est.' if inp.get('est') else '')


def entries(raw: list | None, tz: str | None = None) -> list[dict]:
    """A standard's stored results, each with its day, oldest first; rows
    without a numeric value or a day are left out."""
    out = []
    for e in raw or []:
        v = e.get('value')
        day = day_of(e, tz)
        if isinstance(v, bool) or not isinstance(v, (int, float)) or day is None:
            continue
        out.append({'id': e.get('id'), 'value': float(v), 'date': day,
                    'source': e.get('source') or 'manual', 'note': e.get('note'),
                    'input': e.get('input'), 'sessionUid': e.get('sessionUid'),
                    'workoutId': e.get('workoutId')})
    out.sort(key=lambda e: (e['date'], e['id'] or 0))
    return out


def bodyweight_at(logs: dict, day: str, tz: str | None = None) -> float | None:
    """The latest bodyweight on or before `day` — what a ×BW result is read against."""
    hist = [e for e in entries(logs.get(bd.BODYWEIGHT_ID), tz) if e['date'] <= day]
    return hist[-1]['value'] if hist else None


def resolve_input(b: dict | None, body: dict, logs: dict, day: str, tz: str | None = None) -> tuple[float, dict]:
    """(value in the standard's unit, the input to keep) from what was sent.

    A ×BW standard may be logged as the load lifted — `kg` and `reps` — and is
    divided by the bodyweight on or before that day (`bodyweightKg` in the body
    wins); more than one rep is an Epley estimate, flagged. Anything else is
    `text` ("4:58") or `value`, read by `parse_input`. Raises InputError.
    """
    if body.get('kg') is not None:
        if not b or b.get('metric_type') != 'bw_ratio':
            raise InputError('a load in kg is only for a ×BW standard')
        kg, reps = _positive(body.get('kg'), 'kg'), body.get('reps', 1)
        if isinstance(reps, bool) or not isinstance(reps, (int, float)) or int(reps) != reps or not 1 <= reps <= 30:
            raise InputError('reps must be a whole number from 1 to 30')
        reps = int(reps)
        bw = _positive(body['bodyweightKg'], 'bodyweightKg') if body.get('bodyweightKg') is not None \
            else bodyweight_at(logs, day, tz)
        if not bw:
            raise InputError('a ×BW result needs a bodyweight on or before that day — log one first')
        est = kg if reps == 1 else kg * (1 + _EPLEY * reps)
        inp = {'kg': kg, 'reps': reps, 'bodyweightKg': bw, 'est': reps > 1}
        if body.get('bodyweightKg') is not None:
            inp['bodyweightGiven'] = True
        return round(est / bw, 3), inp
    raw = body.get('value') if body.get('value') is not None else body.get('text')
    if raw is None:
        raise InputError('a value is required')
    value = bd.parse_input(b, raw)
    if value is None:
        raise InputError('value must be a positive number (or m:ss for a time)')
    return value, ({'text': str(raw)} if isinstance(raw, str) else {})


def _positive(v, name: str) -> float:
    if isinstance(v, bool):
        raise InputError(f'{name} must be a number')
    try:
        f = float(v)
    except (TypeError, ValueError):
        raise InputError(f'{name} must be a number') from None
    if not f > 0 or f != f or f == float('inf'):
        raise InputError(f'{name} must be a positive number')
    return f


# ── blocks ───────────────────────────────────────────────────────────────────

def blocks_from_activations(activations: list[dict], philosophy_names: dict | None = None) -> list[dict]:
    """[{id, name, from, to}] from program_history.list_activations, oldest
    first; `to` is the block's own last day (effective_to is exclusive)."""
    from datetime import timedelta
    names = philosophy_names or {}
    out = []
    for a in sorted(activations or [], key=lambda a: (str(a.get('effectiveFrom')), a.get('activationId') or 0)):
        start = _iso_day(a.get('effectiveFrom'))
        end_excl = _iso_day(a.get('effectiveTo'))
        if not start:
            continue
        ids = [i for i in (a.get('sourceGoalIds') or []) if i != '_blended']
        name = ' + '.join(names.get(i, i.replace('_', ' ').title()) for i in ids) or a.get('goalName') or 'Program'
        out.append({'id': a.get('activationId'), 'versionId': a.get('versionId'), 'name': name, 'from': start,
                    'to': (date.fromisoformat(end_excl) - timedelta(days=1)).isoformat() if end_excl else None})
    return out


def block_on(blocks: list[dict], day: str | None, session_uid: str | None = None) -> dict | None:
    """The block a result belongs to: its test session's, else the one in force that day."""
    if not day:
        return None
    if session_uid:
        vid = session_uid.split(':', 1)[0]
        own = [b for b in blocks if b.get('versionId') == vid]
        hits = [b for b in own if b['from'] <= day and (b['to'] is None or day <= b['to'])]
        if hits or own:
            b = (hits or own)[-1]
            return {'id': b['id'], 'name': b['name']}
    hits = [b for b in blocks if b['from'] <= day and (b['to'] is None or day <= b['to'])]
    return {'id': hits[-1]['id'], 'name': hits[-1]['name']} if hits else None


# ── the athlete's results ────────────────────────────────────────────────────

def _entry_out(b: dict | None, e: dict, sex: str, blocks: list[dict]) -> dict:
    p = point(b, e['value'], e['date'], sex) if b else {'valueText': bd.format_value(None, e['value'])}
    return {
        'id': e['id'], 'value': e['value'], 'date': e['date'], 'valueText': p['valueText'],
        'level': p.get('level'), 'levelIndex': p.get('levelIndex', 0),
        'source': e['source'], 'note': e['note'], 'inputText': input_text(e['input']),
        'sessionUid': e['sessionUid'], 'workoutId': e['workoutId'],
        'block': block_on(blocks, e['date'], e['sessionUid']),
    }


def summarise(benchmarks, logs: dict, sex: str = 'male', tz: str | None = None,
              blocks: list[dict] | None = None) -> dict:
    """{standards: {id: {current, best, count, entries}}, bodyweight, blocks}.

    `logs` is standards_store.list_results' shape. Only standards with at least
    one result appear; ids no standard has any more are left out rather than
    guessed at. Bodyweight carries its own entries, so it can be corrected too.
    """
    sex = sex if sex in ('male', 'female') else 'male'
    blocks = blocks or []
    out: dict[str, dict] = {}
    for b in benchmarks:
        es = entries(logs.get(b['id']), tz)
        if not es:
            continue
        better = min if b['lower_is_better'] else max
        best = better(es, key=lambda e: e['value'])
        latest = es[-1]
        out[b['id']] = {
            'current': point(b, latest['value'], latest['date'], sex),
            'best': point(b, best['value'], best['date'], sex),
            'count': len(es),
            'entries': [_entry_out(b, e, sex, blocks) for e in es],
        }
    bw = entries(logs.get(bd.BODYWEIGHT_ID), tz)
    return {
        'sex': sex,
        'standards': out,
        # The program timeline, so a history chart can shade each block.
        'blocks': [{'id': b['id'], 'name': b['name'], 'from': b['from'], 'to': b['to']} for b in blocks],
        'bodyweight': ({'value': bw[-1]['value'], 'valueText': bd.format_value(None, bw[-1]['value']),
                        'date': bw[-1]['date'], 'entries': [_entry_out(None, e, sex, blocks) for e in bw]}
                       if bw else None),
    }


def digest_key(logs: dict) -> list:
    """What a cached analytics document must key on: every value and day, not
    the number of entries (an edit keeps the count and changes the answer)."""
    return sorted((k, e.get('id'), e.get('value'), str(e.get('loggedOn') or e.get('date')))
                  for k, v in logs.items() for e in v or [])
