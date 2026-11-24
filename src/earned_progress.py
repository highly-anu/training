"""Progress a slot earns: one step for each session made, none for a miss.

A slot's own `progress` normally follows the calendar (progression.
written_progress). With `earned: true` it follows the log: every exposure of
the slot in a program is prescribed at the steps earned so far — a session
logged as made earns one, a session missed (logged short, or a day gone by
with no log) earns none and the next one repeats it, and the sessions still
ahead are forecast as made. A weight logged other than the one prescribed
becomes where the steps carry on from. A light day (a deload week's, a day
marked light) is done at its share and neither earns nor counts.

`replan` walks a program's weeks as the API stores them and rewrites the
`load` of each earned slot's exposures; nothing else about the program
changes, and loads are outside the version skeleton, so no version is minted
(as POST /programs/adjust). It runs when a program is generated (a forecast)
and when a session is logged (api._save_session_log).

Pure over its inputs. docs/roadmap.md item 24.5; test_earned_progress.py.
"""
from __future__ import annotations

from datetime import date

from .progression import calculate_load
from .training_contract import _lift_outcome
from .workout_matcher import session_calendar_date

DAY_ORDER = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def _earned(slot: dict) -> bool:
    return bool((slot.get('progress') or {}).get('earned'))


def _slots(session: dict) -> dict:
    arch = session.get('archetype') if isinstance(session.get('archetype'), dict) else {}
    return {s.get('role'): s for s in arch.get('slots') or [] if isinstance(s, dict)}


def has_earned(weeks: list) -> bool:
    """Whether any session of the program has a slot that earns its steps."""
    return any(_earned(slot) for week in weeks or [] for sessions in (week.get('schedule') or {}).values()
               for session in sessions or [] if isinstance(session, dict) for slot in _slots(session).values())


def _key(session: dict, role: str) -> tuple:
    """The slot's identity across the program: its own session and role,
    whether the session stands alone or is the second piece of a day
    (`<archetype id>__<role>`, week_template.compose)."""
    if '__' in role and not role.startswith('warm_up__'):
        piece, bare = role.split('__', 1)
        return piece, bare
    return (session.get('archetype') or {}).get('id'), role


def _made(ex_log, load: dict) -> tuple[bool | None, float | None]:
    """(made, kg) of a logged exercise against its prescription; (None, None)
    when the log says nothing of it."""
    if not isinstance(ex_log, dict) or not ex_log:
        return None, None
    made, kg = _lift_outcome(ex_log, {'kg': load.get('weight_kg'), 'sets': load.get('sets'), 'reps': load.get('reps')})
    if made is None and any(ex_log.get(k) is not None for k in ('rounds', 'durationSec', 'distanceKm')):
        made = True     # an outcome that is not sets: done is made
    return made, kg


def replan(weeks: list, logs: dict | None, start_date: str | None = None, today: date | None = None,
           state: dict | None = None, first_week_index: int = 0) -> tuple[int, dict]:
    """Rewrite the loads of every earned slot in `weeks` (the API's shape:
    `schedule` by day name), in place. → (how many loads changed, the state
    after the last week: {slot key: {steps, offset_kg}}).

    `logs` are the session logs by their program-relative key. `start_date`
    and `today` say which unlogged sessions are behind the athlete (missed:
    no step) and which are ahead (forecast as made); without them every
    unlogged session is ahead. `state` carries on from earlier weeks (a
    regenerated tail), `first_week_index` being where `weeks` starts in the
    program."""
    logs = logs or {}
    state = {k: dict(v) for k, v in (state or {}).items()}
    changed = 0
    for wi, week in enumerate(weeks or []):
        schedule = week.get('schedule') or {}
        for day in sorted(schedule, key=lambda d: DAY_ORDER.index(d) if d in DAY_ORDER else 7):
            for si, session in enumerate(schedule[day] or []):
                if not isinstance(session, dict):
                    continue
                slots = _slots(session)
                if not any(_earned(s) for s in slots.values()):
                    continue
                key = f"{week.get('week_number')}-{day}-{si}"
                log = logs.get(key) or (logs.get(f"{week.get('week_number')}-{day}") if si == 0 else None)
                behind = False
                if log is None and start_date and today:
                    try:
                        behind = date.fromisoformat(session_calendar_date(start_date, first_week_index + wi, day)) < today
                    except (TypeError, ValueError):
                        behind = False
                light = bool(session.get('light')) or bool(week.get('is_deload'))
                for ea in session.get('exercises') or []:
                    slot = slots.get(ea.get('slot_role'))
                    if not slot or not _earned(slot) or not isinstance(ea.get('exercise'), dict):
                        continue
                    st = state.setdefault(_key(session, slot['role']), {'steps': 0, 'offset_kg': 0.0})
                    view = dict(slot)
                    if st['offset_kg'] and slot.get('start_kg') is not None:
                        view['start_kg'] = max(0.0, float(slot['start_kg']) + st['offset_kg'])
                    load = calculate_load(ea['exercise'], view, 'as_written', 1, week.get('phase') or 'build',
                                          'intermediate', False, earned_steps=st['steps'])
                    load.pop('load_note', None)      # kept beside the load by the API (_clean_exercise_assignment)
                    if load != ea.get('load'):
                        ea['load'] = load
                        changed += 1
                    if light:
                        continue
                    made, kg = (None, None) if log is None else _made((log.get('exercises') or {}).get(ea['exercise'].get('id')), load)
                    if log is None:
                        made = not behind
                    elif made is None:
                        made = False                  # the session was logged without it
                    if not made:
                        continue
                    st['steps'] += 1
                    rule = slot.get('progress') or {}
                    written = load.get('weight_kg')
                    if kg is not None and written is not None and not rule.get('top_reps') and abs(kg - written) >= 0.25:
                        st['offset_kg'] = round(st['offset_kg'] + kg - written, 2)
    return changed, state
