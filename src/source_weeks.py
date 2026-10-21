"""The source's own weeks: data/packages/<id>/source_weeks.yaml.

A package's record (fidelity.yaml) says what its sources state; its source
weeks are what they *show* — an example week, a progression table — written
down as data (docs/schemas/source_weeks.schema.json) and generated under the
profile the source assumes. The scorecard's S5 asks every one to reproduce:
the same days, sessions and exercises (structure), and the same numbers
where the source gives them (sets, reps, loads, rounds …). A field the entry
leaves out is the source's silence and is never compared.

    - id: novice_ab
      rule: R1                       # the rule it pins (fidelity.yaml)
      track: linear_progression
      profile: {days_per_week: 3, session_time_minutes: 90, training_level: novice,
                equipment: [barbell, rack, plates, bench, pull_up_bar]}
      weeks:                         # from the first week the entry covers
        - days:                      # training days in order; a `rest` entry
            - archetype: 3x5_linear  #   makes the week positional, Monday first
              exercises: [{id: back_squat, sets: 3, reps: 5}, …]
      series:                        # one field over successive sessions
        - {exercise: back_squat, field: weight_kg, values: [65, 70, 75]}

A session's keys: `archetype`, `category`, `modality` (each compared when
given) and `exercises` — the work exercises in order, each an id or
`{id, <load field>: value …}`. Number fields are read from the assignment's
`load` (its prescription), falling back to the assignment itself.

Pure apart from generation: `check(pkg)` loads, generates and compares.
"""
from __future__ import annotations

import math
import os

import yaml

from src import goals, loader, provenance
from src.generator import generate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILE = 'source_weeks.yaml'
_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
_SESSION_KEYS = ('archetype', 'category', 'modality')


def load(pkg: str) -> list[dict]:
    path = os.path.join(ROOT, 'data', 'packages', pkg, FILE)
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8') as fh:
        return yaml.safe_load(fh) or []


# ── Generating what the source assumes ───────────────────────────────────────

def constraints_for(entry: dict, contract: dict | None) -> dict:
    """The entry's profile over the defaults a fidelity profile has; a
    contract athlete qualifies (two bells, the level's mastery)."""
    from tools.check_fidelity import contract_entry
    from tools.check_styles import ALL_EQUIPMENT
    c = {'days_per_week': 3, 'session_time_minutes': 60, 'training_level': 'intermediate',
         'equipment': list(ALL_EQUIPMENT), 'injury_flags': [], 'fatigue_state': 'normal',
         'periodization_week': 1}
    c.update(entry.get('profile') or {})
    if c['equipment'] == 'all':
        c['equipment'] = list(ALL_EQUIPMENT)
    return contract_entry(c, contract)


def weeks_needed(entry: dict) -> int:
    first = int(entry.get('from_week') or 1)
    return int(entry.get('num_weeks') or (first - 1 + len(entry.get('weeks') or [])) or 1)


def program_for(pkg: str, entry: dict) -> dict | None:
    frameworks = list(loader.load_all_frameworks().values())
    level = (entry.get('profile') or {}).get('training_level')
    goal = goals.philosophy_to_goal(pkg, frameworks, track_id=entry.get('track'), level=level)
    policy = provenance.resolve_source_policy(goal)
    constraints = constraints_for(entry, goal.get('training_contract'))
    return generate(goal_id=goal['id'], goal_dict=goal, constraints=constraints,
                    num_weeks=weeks_needed(entry), output_format='dict', policy=policy)


# ── Comparing ────────────────────────────────────────────────────────────────

def _day_num(day) -> int:
    if isinstance(day, int):
        return day
    if isinstance(day, str) and day.isdigit():
        return int(day)
    return _DAY_NAMES.index(day) + 1 if day in _DAY_NAMES else 0


def _days(week: dict) -> dict[int, list]:
    return {_day_num(d): ss for d, ss in (week.get('schedule') or {}).items() if ss}


def _work(session: dict) -> list:
    return [ea for ea in session.get('exercises') or [] if not ea.get('meta') and ea.get('exercise')]


def _field(ea: dict, name: str):
    load = ea.get('load') or {}
    return load[name] if name in load else ea.get(name)


def _same(a, b) -> bool:
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        return abs(a - b) < 1e-6
    return a == b


def _session_value(s: dict, key: str):
    if key == 'archetype':
        return (s.get('archetype') or {}).get('id')
    return s.get(key)


def _expected(name: str, value, round_kg: float | None):
    """A source's kilograms, on the plates the contract loads (`round_kg`)."""
    if round_kg and name.endswith('_kg') and isinstance(value, (int, float)):
        return math.floor(value / round_kg + 0.5) * round_kg
    return value


def _numbers(ea: dict, e: dict, where: str, round_kg) -> list[str]:
    out = []
    for name, value in e.items():
        want = _expected(name, value, round_kg)
        if name != 'id' and not _same(_field(ea, name), want):
            out.append(f"{where} {e['id']}: {name} {_field(ea, name)!r}, the source {value!r}"
                       + (f" (≈{want!r} on {round_kg} kg plates)" if want != value else ''))
    return out


def compare_session(got: dict, want: dict, where: str, round_kg: float | None = None) -> tuple[list[str], list[str]]:
    """(structure mismatches, number mismatches) for one session: `exercises`
    is the whole list in order, `includes` some of them in any order."""
    structure, numbers = [], []
    for key in _SESSION_KEYS:
        if key in want and _session_value(got, key) != want[key]:
            structure.append(f"{where}: {key} {_session_value(got, key)!r}, the source {want[key]!r}")
    work = _work(got)
    if 'exercises' in want:
        wanted = [e if isinstance(e, dict) else {'id': e} for e in want['exercises']]
        ids = [ea['exercise']['id'] for ea in work]
        if ids != [e['id'] for e in wanted]:
            structure.append(f"{where}: exercises {ids}, the source {[e['id'] for e in wanted]}")
        else:
            for ea, e in zip(work, wanted):
                numbers += _numbers(ea, e, where, round_kg)
    for e in [e if isinstance(e, dict) else {'id': e} for e in want.get('includes') or []]:
        ea = next((x for x in work if x['exercise']['id'] == e['id']), None)
        if ea is None:
            structure.append(f"{where}: no {e['id']}, which the source has")
        else:
            numbers += _numbers(ea, e, where, round_kg)
    return structure, numbers


def _sessions_of(day) -> list:
    if day == 'rest' or day is None:
        return []
    return day if isinstance(day, list) else [day]


def compare(program: dict | None, entry: dict) -> tuple[list[str], list[str]]:
    """(structure mismatches, number mismatches) between a generated program
    and one source-week entry."""
    eid = entry['id']
    if not program or not program.get('weeks') or program.get('validation_errors'):
        return [f"{eid}: the profile is refused ({(program or {}).get('validation_errors') or 'no weeks'})"], []
    structure, numbers = [], []
    first = int(entry.get('from_week') or 1) - 1
    weeks = program['weeks']
    for i, want in enumerate(entry.get('weeks') or []):
        wi = first + i
        if wi >= len(weeks):
            structure.append(f"{eid}: week {wi + 1} was not generated")
            continue
        got = _days(weeks[wi])
        if want.get('modalities'):
            counts: dict = {}
            for ss in got.values():
                for s in ss:
                    if not s.get('test'):
                        counts[s.get('modality')] = counts.get(s.get('modality'), 0) + 1
            for mod, n in want['modalities'].items():
                if counts.get(mod, 0) != n:
                    structure.append(f"{eid} week {wi + 1}: {counts.get(mod, 0)} {mod} session(s), the source {n}")
        if 'days' not in want:
            continue
        days = want.get('days') or []
        if 'rest' in days:
            pairs = [(n + 1, got.get(n + 1, []), _sessions_of(d)) for n, d in enumerate(days)]
            extra = sorted(set(got) - set(range(1, len(days) + 1)))
            if extra:
                structure.append(f"{eid} week {wi + 1}: sessions on day(s) {extra} the source rests")
        else:
            ordered = [got[d] for d in sorted(got)]
            if len(ordered) != len(days):
                structure.append(f"{eid} week {wi + 1}: {len(ordered)} training days, the source {len(days)}")
            pairs = [(n + 1, ordered[n] if n < len(ordered) else [], _sessions_of(d)) for n, d in enumerate(days)]
        for day, got_ss, want_ss in pairs:
            where = f"{eid} week {wi + 1} day {day}"
            if len(got_ss) != len(want_ss):
                structure.append(f"{where}: {len(got_ss)} session(s), the source {len(want_ss)}")
                continue
            for k, (g, w) in enumerate(zip(got_ss, want_ss)):
                st, nu = compare_session(g, w, where + (f" session {k + 1}" if len(want_ss) > 1 else ''),
                                         entry.get('round_kg'))
                structure += st
                numbers += nu
    for s in entry.get('series') or []:
        got = [_field(ea, s['field']) for w in weeks for d in sorted(_days(w)) for sess in _days(w)[d]
               for ea in _work(sess) if ea['exercise']['id'] == s['exercise']][:len(s['values'])]
        where = f"{eid} series {s['exercise']}.{s['field']}"
        want = [_expected(s['field'], v, entry.get('round_kg')) for v in s['values']]
        if len(got) < len(want):
            structure.append(f"{where}: {len(got)} sessions carry it, the source {len(want)}")
        elif not all(_same(a, b) for a, b in zip(got, want)):
            numbers.append(f"{where}: {got}, the source {s['values']}")
    return structure, numbers


def check(pkg: str) -> tuple[int, list[str], list[str]]:
    """(entries, structure mismatches, number mismatches) for a package."""
    entries = load(pkg)
    structure, numbers = [], []
    for entry in entries:
        st, nu = compare(program_for(pkg, entry), entry)
        structure += st
        numbers += nu
    return len(entries), structure, numbers
