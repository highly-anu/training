"""Tests of the standards: which sessions measure a standard, and when a phase runs one.

A package marks an archetype as a test (`test:`), points each scored slot at a
commons standard (`standard: <id>` or `{id, result}`), and its philosophy's
phases say when they test (`tests:` — a week in the phase, or every N). The
generator puts the test in place of one session of the week (src/generator.py),
prescribed exactly as written: a test is a protocol, not a training load, so no
weekly ramp, level, phase multiplier or deload scaling touches its scored slots
(a 2 km row test would otherwise be prescribed as 1.5 km). Nothing here names
a philosophy; the link is data.

Pure: no Flask, no DB.
"""
from __future__ import annotations

from src.progression import paced_rpm, watch_cues, zone_band

# What a logged result can be, which standard metrics it fits, and the slot
# types it is the natural reading of. The validator, the protocol and (phase 5)
# the suggestion hook read this one table.
RESULTS: dict[str, dict] = {
    'duration': {'metrics': {'time_minutes', 'time_seconds', 'time_sec'},
                 'slot_types': {'for_time', 'rounds_for_time', 'distance'}},
    'rounds':   {'metrics': {'score'}, 'slot_types': {'amrap'}},
    'reps':     {'metrics': {'reps'}, 'slot_types': {'time_domain', 'amrap', 'sets_reps', 'amrap_movement'}},
    'hold':     {'metrics': {'time_seconds', 'time_sec', 'time_minutes'}, 'slot_types': {'static_hold', 'skill_practice'}},
    'load':     {'metrics': {'bw_ratio'}, 'slot_types': {'sets_reps'}},
    'distance': {'metrics': {'metres'}, 'slot_types': {'time_domain'}},
}


def default_result(slot_type: str | None, metric_type: str | None) -> str | None:
    """The one result kind a slot type and a standard's metric agree on, or None."""
    fits = [k for k, r in RESULTS.items()
            if (slot_type in r['slot_types']) and (metric_type is None or metric_type in r['metrics'])]
    return fits[0] if len(fits) == 1 else None


def standard_ref(slot: dict | None, metric_type: str | None = None) -> dict | None:
    """A slot's `standard`, normalised to {id, result}; None when it has none."""
    raw = (slot or {}).get('standard')
    if not raw:
        return None
    sid, result = (raw, None) if isinstance(raw, str) else (raw.get('id'), raw.get('result'))
    if not sid:
        return None
    if result is None and metric_type is None:
        from src.analytics import benchmarks_data
        metric_type = (benchmarks_data.by_id().get(sid) or {}).get('metric_type')
    return {'id': sid, 'result': result or default_result((slot or {}).get('slot_type'), metric_type)}


def is_test(arch: dict | None) -> bool:
    return bool((arch or {}).get('test') is not None and (arch or {}).get('test') is not False)


def is_test_only(arch: dict | None) -> bool:
    """A test archetype ordinary selection must not pick (only a phase places it)."""
    return is_test(arch) and not ((arch or {}).get('test') or {}).get('selectable')


def standards_of(arch: dict | None) -> list[str]:
    """The standards an archetype's slots measure, in slot order."""
    out: list[str] = []
    for slot in (arch or {}).get('slots') or []:
        ref = standard_ref(slot)
        if ref and ref['id'] not in out:
            out.append(ref['id'])
    return out


# ── when a phase tests ───────────────────────────────────────────────────────

def _fires(test: dict, pos: int, weeks: int) -> bool:
    if test.get('every'):
        n = int(test['every'])
        start = int(test.get('start') or n)
        return pos >= start and (pos - start) % n == 0
    week = test.get('week', 'last')
    if week == 'first':
        return pos == 1
    if week == 'last':
        return pos == weeks
    try:
        return pos == int(week)
    except (TypeError, ValueError):
        return False


def tests_for_week(entry: dict) -> list[dict]:
    """The tests one generator week entry runs (`phases.week_entry` carries the
    phase's `tests`, `phase_weeks` and `repeatable`).

    Positions are weeks in the phase. A repeatable phase run past its length
    repeats its test points every cycle; a phase run past its end otherwise
    tests nothing more. Each result says which archetypes to try, in order —
    a rotation starts at this occurrence's turn — and how to place it.
    """
    tests = entry.get('tests') or []
    if not tests:
        return []
    weeks = max(1, int(entry.get('phase_weeks') or 1))
    wip = max(1, int(entry.get('week_in_phase') or 1))
    if wip > weeks and not entry.get('repeatable'):
        return []
    cycle, pos = divmod(wip - 1, weeks)
    pos += 1
    out = []
    for t in tests:
        if not _fires(t, pos, weeks):
            continue
        rotation = list(t.get('archetypes') or ([t['archetype']] if t.get('archetype') else []))
        if not rotation:
            continue
        # This occurrence's turn: earlier firings in this cycle and every cycle before.
        per_cycle = sum(1 for p in range(1, weeks + 1) if _fires(t, p, weeks))
        k = cycle * per_cycle + sum(1 for p in range(1, pos) if _fires(t, p, weeks))
        turn = k % len(rotation)
        in_place = t.get('in_place_of')
        out.append({
            'archetypes': rotation[turn:] + rotation[:turn],
            'in_place_of': [in_place] if isinstance(in_place, str) else list(in_place or []),
            'day': t.get('day') or ('last' if t.get('week', 'last') == 'last' and not t.get('every') else 'first'),
            'on_deload': t.get('on_deload', 'keep'),
        })
    return out


# ── the protocol ─────────────────────────────────────────────────────────────

def protocol_load(exercise: dict, slot: dict) -> dict:
    """A standard slot's prescription, exactly as the test is written.

    `test: True` tells every reader it is a test, `effort: max` that the score
    is the point; nothing is scaled by week, level, phase or deload.
    """
    st = slot.get('slot_type', 'sets_reps')
    out: dict = {}
    if st == 'time_domain':
        minutes = slot.get('duration_minutes') or max(1, round((slot.get('duration_sec') or 600) / 60))
        out = {'duration_minutes': minutes}
    elif st in ('for_time', 'rounds_for_time', 'distance') and slot.get('distance_m'):
        m = slot['distance_m']
        out = {'distance_km': round(m / 1000, 3)} if m >= 1000 else {'distance_m': m}
        if slot.get('time_cap_sec'):
            out['time_minutes'] = max(1, round(slot['time_cap_sec'] / 60))
    elif st in ('for_time', 'rounds_for_time'):
        out = {'time_minutes': max(1, round((slot.get('time_cap_sec') or slot.get('duration_sec') or 1200) / 60)),
               'format': 'FOR_TIME'}
        if slot.get('rounds'):
            out['target_rounds'] = slot['rounds']
    elif st == 'amrap':
        out = {'time_minutes': max(1, round((slot.get('duration_sec') or 1200) / 60)), 'format': 'AMRAP'}
    elif st == 'amrap_movement':
        out = {'reps_per_round': slot.get('reps_per_round', 10)}
    elif st == 'static_hold':
        out = {'sets': slot.get('sets', 1)}
        if slot.get('hold_seconds') or slot.get('duration_sec'):
            out['hold_seconds'] = slot.get('hold_seconds') or slot.get('duration_sec')
    else:
        out = {'sets': slot.get('sets', 1), 'reps': slot.get('reps', 1)}
    if slot.get('pack_load_kg') is not None:
        out['pack_load_kg'] = slot['pack_load_kg']
    intensity = slot.get('intensity')
    if intensity:
        lo, hi, label = zone_band(intensity)
        if lo is not None:
            out.update({'zone_target': label, 'zone_lower': lo, 'zone_upper': hi})
    rpm = paced_rpm(exercise, slot)
    if rpm is not None:
        out['target_rpm'] = rpm
    out.update(watch_cues(slot))
    out['test'] = True
    out['effort'] = 'max'
    return out
