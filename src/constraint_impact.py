"""What the athlete's constraints change in a program, and which one changes it.

The Dev Lab's Impact view (POST /api/dev/constraint-impact). Besides the
athlete's own program, the API generates a *reference* with nothing in the
way — every piece of equipment the program's packages use, no injury flags,
the level the start phase's framework is written for — and one run per
constraint with only that one lifted. Lined up session by session, the
reference and the athlete's program say what was planned instead of what; a
change that goes away when one constraint alone is lifted is that
constraint's doing, and one that needs more than one lifted is 'combined'.

Before this a constrained program said only that it was constrained: a
Starting Strength run with no equipment warned "will use equipment-limited
scaling" while every slot came out empty, and an intermediate on the novice
phase ran HLM and 5×5 instead of the 3×5 sessions with nothing to show it.

Generation is deterministic, so the runs differ only by what was lifted —
but one change moves the exercise rotation (recency) for every week after
it. A change whose reference session or exercise is itself open to the
athlete is marked `knock_on`: a constraint changed something earlier, not
this. Without the mark an Uphill program with a knee flag read 72 of 72
sessions changed.

Pure over generated programs (the API's shape: weeks → schedule → day name →
sessions); api.py runs the generations.
"""
from __future__ import annotations

from collections import Counter

DIMENSIONS = ('equipment', 'injury', 'level')
LEVELS = ('novice', 'intermediate', 'advanced', 'elite')
DAY_ORDER = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')
_NOT_EQUIPMENT = {'none', 'open_space'}


# ── The runs ──────────────────────────────────────────────────────────────────

def reference_level(level: str, written_for: list | None) -> str:
    """The athlete's level if the framework is written for it, else the listed
    level nearest to it (a tie goes to the lower one)."""
    if not written_for or level in written_for:
        return level
    rank = LEVELS.index(level) if level in LEVELS else 1

    def distance(lvl: str) -> tuple:
        r = LEVELS.index(lvl) if lvl in LEVELS else 1
        return abs(r - rank), r
    return min(written_for, key=distance)


def reference_constraints(constraints: dict, lib: dict, framework: dict | None,
                          override: dict | None = None) -> dict:
    """The athlete's constraints with nothing in the way.

    Equipment is everything the allowed packages' exercises and archetypes ask
    for, on top of what the athlete has; days, minutes, fatigue, track and
    start phase stay the athlete's, since they decide the schedule rather than
    what fills it. `override` may pin `equipment` or `training_level`.
    """
    override = override or {}
    equipment = set(constraints.get('equipment') or [])
    for ex in (lib.get('exercises') or {}).values():
        equipment.update(ex.get('equipment') or [])
    for arch in lib.get('archetypes') or []:
        equipment.update(arch.get('required_equipment') or [])
    equipment.discard('none')
    written_for = ((framework or {}).get('applicable_when') or {}).get('training_level')
    return {
        **constraints,
        'equipment': sorted(override.get('equipment') or equipment),
        'injury_flags': [],
        'training_level': override.get('training_level')
        or reference_level(constraints.get('training_level', 'intermediate'), written_for),
    }


def relaxations(constraints: dict, reference: dict) -> dict[str, dict]:
    """One run per constraint the athlete has: their constraints with only that
    one as the reference has it. A constraint that changes nothing is not run."""
    out: dict[str, dict] = {}
    if set(reference['equipment']) - set(constraints.get('equipment') or []):
        out['equipment'] = {**constraints, 'equipment': reference['equipment']}
    if constraints.get('injury_flags'):
        out['injury'] = {**constraints, 'injury_flags': []}
    if constraints.get('training_level') != reference['training_level']:
        out['level'] = {**constraints, 'training_level': reference['training_level']}
    return out


# ── Lining sessions up ────────────────────────────────────────────────────────

def sessions_of(program: dict) -> dict[tuple, dict]:
    """(week index, day name, session index) → session. The array index, not
    `week_number`, which a partial regenerate can repeat."""
    out: dict[tuple, dict] = {}
    for wi, week in enumerate(program.get('weeks') or []):
        for day, sessions in (week.get('schedule') or {}).items():
            for si, session in enumerate(sessions or []):
                out[(wi, day, si)] = session
    return out


def _order(key: tuple) -> tuple:
    wi, day, si = key
    return wi, DAY_ORDER.index(day) if day in DAY_ORDER else 7, si


def _arch(session: dict | None) -> dict:
    return (session or {}).get('archetype') or {}


def _shape(session: dict | None) -> tuple:
    return (session or {}).get('modality'), _arch(session).get('id')


def _gap(ea: dict) -> str | None:
    if ea.get('injury_skip'):
        return 'INJURY_EXCLUDED'
    return ea.get('gap_reason')


def _fill(ea: dict | None) -> tuple:
    ea = ea or {}
    return (ea.get('exercise') or {}).get('id'), _gap(ea)


def _exercises(session: dict | None) -> list[dict]:
    return list((session or {}).get('exercises') or [])


def _session_view(session: dict | None) -> dict | None:
    if session is None:
        return None
    arch = _arch(session)
    return {
        'modality': session.get('modality'),
        'archetype': {'id': arch.get('id'), 'name': arch.get('name')} if arch else None,
        'test': bool(session.get('test')),
        'substituted_for': session.get('substituted_for'),
    }


def _exercise_view(ea: dict | None) -> dict | None:
    ex = (ea or {}).get('exercise')
    return {'id': ex.get('id'), 'name': ex.get('name', ex.get('id'))} if ex else None


def _slot_list(session: dict | None) -> list[dict]:
    return [{'role': ea.get('slot_role'), 'exercise': _exercise_view(ea), 'gap_reason': _gap(ea)}
            for ea in _exercises(session)]


# ── Why ───────────────────────────────────────────────────────────────────────

def _missing(required, available) -> list[str]:
    return sorted(set(required or []) - set(available or []) - _NOT_EQUIPMENT)


def _blocking_flags(ex: dict, flags: list, flag_data: dict) -> list[str]:
    names = []
    patterns = set(ex.get('movement_patterns') or [])
    for fid in flags:
        flag = flag_data.get(fid) or {}
        hit = sorted(patterns & set(flag.get('excluded_movement_patterns') or []))
        if ex.get('id') in (flag.get('excluded_exercises') or []) or fid in (ex.get('contraindicated_with') or []):
            names.append(flag.get('name', fid))
        elif hit:
            names.append(f"{flag.get('name', fid)} ({', '.join(hit)})")
    return names


class _Explainer:
    """Plain words for why a constraint changed a session or a slot."""

    def __init__(self, constraints, reference, exercises, archetypes, injury_flags, unlocked):
        self.c, self.ref = constraints, reference
        self.exercises, self.archetypes, self.flags = exercises, archetypes, injury_flags
        self.unlocked = unlocked

    def archetype_open(self, ref_session: dict) -> bool:
        """The reference's session is one the athlete could be given as is."""
        arch = self.archetypes.get(_arch(ref_session).get('id')) or _arch(ref_session)
        levels = arch.get('training_levels') or []
        return ((not levels or self.c.get('training_level') in levels)
                and not _missing(arch.get('required_equipment'), self.c.get('equipment'))
                and not any(self.blockers(ea) for ea in _exercises(ref_session)))

    def archetype(self, cause: str, ref_session: dict) -> tuple[str, list[str]]:
        arch = self.archetypes.get(_arch(ref_session).get('id')) or _arch(ref_session)
        name = arch.get('name', arch.get('id'))
        if cause == 'equipment':
            need = _missing(arch.get('required_equipment'), self.c.get('equipment'))
            if need:
                return f"{name} needs {', '.join(need)}", need
        if cause == 'level':
            levels = arch.get('training_levels') or []
            if levels and self.c.get('training_level') not in levels:
                return f"{name} is written for {', '.join(levels)}", []
            return f"at {self.ref['training_level']} the reference runs {name}", []
        if cause == 'injury':
            patterns = {s.get('exercise_filter', {}).get('movement_pattern')
                        for s in arch.get('slots') or []}
            hit = [(self.flags.get(f) or {}).get('name', f) for f in self.c.get('injury_flags') or []
                   if patterns & set((self.flags.get(f) or {}).get('excluded_movement_patterns') or [])]
            if hit:
                return f"{', '.join(hit)} blocks slots of {name}", []
        return f"lifting {cause} alone restores {name}", []

    def _exercise(self, ref_ea: dict) -> tuple[dict, str]:
        # The program's copy is the one the generator used — a package's own
        # definition of a shared id can ask for other equipment (Filly's dips
        # take a belt) — and the library fills what the program strips.
        embedded = (ref_ea or {}).get('exercise') or {}
        ex = {**(self.exercises.get(embedded.get('id')) or {}), **embedded}
        return ex, ex.get('name', ex.get('id', '?'))

    def blockers(self, ref_ea: dict) -> list[dict]:
        """What in the athlete's constraints rules out the reference's exercise
        itself — read from the exercise, not from a run, so it holds for a slot
        whose session changed archetype too."""
        ex, name = self._exercise(ref_ea)
        if not ex:
            return []
        out = []
        need = _missing(ex.get('equipment'), self.c.get('equipment'))
        if need:
            out.append({'cause': 'equipment', 'text': f"{name} needs {', '.join(need)}", 'needs': need})
        hit = _blocking_flags(ex, self.c.get('injury_flags') or [], self.flags)
        if hit:
            out.append({'cause': 'injury', 'text': f"{name} is blocked by {', '.join(hit)}", 'needs': []})
        if self.unlocked is not None and ex.get('id') not in self.unlocked:
            out.append({'cause': 'level', 'needs': [],
                        'text': f"{name} is not unlocked at {self.c.get('training_level')}"})
        return out

    def slot(self, cause: str, ref_ea: dict) -> tuple[str, list[str]]:
        ex, name = self._exercise(ref_ea)
        if cause == 'equipment':
            need = _missing(ex.get('equipment'), self.c.get('equipment'))
            if need:
                return f"{name} needs {', '.join(need)}", need
        if cause == 'injury':
            hit = _blocking_flags(ex, self.c.get('injury_flags') or [], self.flags)
            if hit:
                return f"{name} is blocked by {', '.join(hit)}", []
        if cause == 'level':
            return f"at {self.ref['training_level']} the reference picks {name}", []
        return f"lifting {cause} alone restores {name}", []


# ── The comparison ────────────────────────────────────────────────────────────

def _restores_session(relaxed: dict[str, dict], key: tuple, ref_session: dict | None) -> list[str]:
    return [dim for dim in DIMENSIONS if dim in relaxed
            and _shape(relaxed[dim].get(key)) == _shape(ref_session)]


def _restores_slot(relaxed: dict[str, dict], key: tuple, ref_session: dict, index: int) -> list[str]:
    out = []
    want = _fill(_exercises(ref_session)[index])
    for dim in DIMENSIONS:
        if dim not in relaxed:
            continue
        session = relaxed[dim].get(key)
        if _shape(session) != _shape(ref_session):
            continue
        slots = _exercises(session)
        if index < len(slots) and _fill(slots[index]) == want:
            out.append(dim)
    return out


def _session_alternatives(relaxed: dict[str, dict], key: tuple, ref: dict | None,
                          act: dict | None) -> list[dict]:
    """What a constraint lifted alone puts here when it is neither the
    athlete's session nor the reference's."""
    out = []
    for dim in DIMENSIONS:
        session = relaxed.get(dim, {}).get(key)
        if session is not None and _shape(session) not in (_shape(ref), _shape(act)):
            out.append({'cause': dim, **_session_view(session)})
    return out


def _slot_alternatives(relaxed: dict[str, dict], key: tuple, ref: dict, index: int,
                       was: dict | None, now: dict | None) -> list[dict]:
    """The exercise a constraint lifted alone puts in the slot when it is
    neither the athlete's nor the reference's — no barbell empties a carry
    slot, but a sandbag would have filled it."""
    taken = {(was or {}).get('id'), (now or {}).get('id')}
    out = []
    for dim in DIMENSIONS:
        session = relaxed.get(dim, {}).get(key)
        if _shape(session) != _shape(ref):
            continue
        slots = _exercises(session)
        alt = _exercise_view(slots[index]) if index < len(slots) else None
        if alt and alt['id'] not in taken:
            out.append({'cause': dim, 'exercise': alt})
    return out


def analyse(actual: dict, reference: dict, relaxed: dict[str, dict], *,
            constraints: dict, reference_constraints: dict,
            exercises: dict, archetypes: dict, injury_flags: dict,
            unlocked: set | None = None) -> dict:
    """Every session the constraints changed, what it would have been, and why.

    `actual`, `reference` and each `relaxed[dimension]` are generated programs;
    `archetypes` is keyed by id. Changes are listed in calendar order. A
    session whose modality or archetype changed lists both slot lists; one
    that kept its archetype lists the slots that changed. Each change names its
    `causes` — the constraints that, lifted alone, restore it — or
    `['combined']`, and `knock_on` when the reference's own session or
    exercise was open to the athlete. `unlocked` (the exercise ids open at the
    athlete's level) lets an exercise say it is level-locked.
    """
    explain = _Explainer(constraints, reference_constraints, exercises, archetypes, injury_flags,
                         unlocked)
    act, ref = sessions_of(actual), sessions_of(reference)
    lifted = {dim: sessions_of(p) for dim, p in relaxed.items()}
    week_numbers = [w.get('week_number') for w in actual.get('weeks') or []]

    changes: list[dict] = []
    totals: dict[str, Counter] = {}
    restore: Counter = Counter()

    def count(causes: list[str], what: str, needs: list[str]) -> None:
        for cause in causes:
            totals.setdefault(cause, Counter())[what] += 1
        if 'equipment' in causes:
            restore.update(needs)

    for key in sorted(set(act) | set(ref), key=_order):
        a, r = act.get(key), ref.get(key)
        wi, day, si = key
        entry = {
            'week_index': wi,
            'week_number': week_numbers[wi] if wi < len(week_numbers) else wi + 1,
            'day': day, 'session_index': si,
            'reference': _session_view(r), 'actual': _session_view(a),
        }
        if r is None or a is None or _shape(a) != _shape(r):
            # Two questions: what put another session here (the runs answer:
            # whichever constraint, lifted alone, brings the reference's back),
            # and would the reference's own exercises survive the athlete's
            # constraints (each exercise answers). Starting Strength with no
            # equipment at intermediate is both: the level swaps 3x5 for HLM,
            # and no barbell would have emptied the 3x5 anyway.
            shape = _restores_session(lifted, key, r)
            kind = ('added' if r is None else 'removed' if a is None
                    else 'modality' if a.get('modality') != r.get('modality') else 'archetype')
            why, needs = [], []
            for cause in shape:
                text, need = (explain.archetype(cause, r) if r is not None
                              else (f'lifting {cause} alone takes it out again', []))
                why.append({'cause': cause, 'text': text})
                needs += need
            if not shape:
                why.append({'cause': 'combined', 'text': 'no one constraint lifted alone brings it back'})
            ref_slots = _slot_list(r)
            blocked: dict[str, list] = {}
            for view, r_ea in zip(ref_slots, _exercises(r)):
                found = explain.blockers(r_ea)
                if found:
                    view['blocked_by'] = [{'cause': b['cause'], 'text': b['text']} for b in found]
                for b in found:
                    blocked.setdefault(b['cause'], []).append(b['needs'])
            filled = sum(1 for v in ref_slots if v['exercise'])
            for cause, per_slot in blocked.items():
                need = sorted({e for n in per_slot for e in n})
                what = {'equipment': f"need {', '.join(need)}",
                        'injury': 'are blocked by an injury flag',
                        'level': f"are not unlocked at {constraints.get('training_level')}"}[cause]
                why.append({'cause': cause, 'text': f"{len(per_slot)} of {filled} of its exercises {what}"})
                if cause == 'equipment':
                    needs += [e for n in per_slot for e in n]
            causes = (shape or ['combined']) + [c for c in DIMENSIONS if c in blocked and c not in shape]
            knock_on = kind == 'archetype' and explain.archetype_open(r)
            if knock_on:
                why = [{'cause': 'knock_on', 'text': f"{_arch(r).get('name')} is open to the athlete: "
                                                     'an earlier change moved the rotation'}]
            entry.update(change=kind, causes=causes, why=why, knock_on=knock_on,
                         alternatives=_session_alternatives(lifted, key, r, a),
                         reference_slots=ref_slots, actual_slots=_slot_list(a))
            count(causes, 'knock_on' if knock_on else 'sessions', needs)
            changes.append(entry)
            continue

        slot_changes = []
        for i, (r_ea, a_ea) in enumerate(zip(_exercises(r), _exercises(a))):
            if _fill(r_ea) == _fill(a_ea):
                continue
            was, now = _exercise_view(r_ea), _exercise_view(a_ea)
            causes = _restores_slot(lifted, key, r, i) or ['combined']
            found = explain.blockers(r_ea) if was is not None else []
            knock_on = was is not None and not found
            why, needs = [], []
            for cause in causes:
                if cause != 'combined' and was is not None:
                    text, need = explain.slot(cause, r_ea)
                    why.append({'cause': cause, 'text': text})
                    needs += need
            if knock_on:
                why = [{'cause': 'knock_on', 'text': f"{was['name']} is open to the athlete: "
                                                     'an earlier change moved the rotation'}]
            elif causes == ['combined']:
                # Usually two constraints each rule the exercise out (no
                # barbell and a knee flag): say both.
                why += [{'cause': b['cause'], 'text': b['text']} for b in found]
                needs += [e for b in found for e in b['needs']]
                if not found:
                    why.append({'cause': 'combined', 'text': 'no one constraint lifted alone restores it'})
            slot_changes.append({
                'index': i, 'role': a_ea.get('slot_role') or r_ea.get('slot_role'),
                'kind': 'emptied' if now is None else 'filled' if was is None else 'swapped',
                'from': was, 'to': now, 'gap_reason': _gap(a_ea),
                'substituted_for': a_ea.get('substituted_for'),
                'causes': causes, 'why': why, 'knock_on': knock_on,
                'alternatives': _slot_alternatives(lifted, key, r, i, was, now),
            })
            count(causes, 'knock_on' if knock_on else 'slots', needs)
        if slot_changes:
            entry.update(change='slots', slots=slot_changes,
                         knock_on=all(sc['knock_on'] for sc in slot_changes))
            changes.append(entry)

    return {
        'reference': {
            'equipment': reference_constraints['equipment'],
            'training_level': reference_constraints['training_level'],
            'injury_flags': [],
        },
        'lifted': [dim for dim in DIMENSIONS if dim in relaxed],
        'sessions': {'total': len(act), 'changed': len(changes),
                     'direct': sum(1 for c in changes if not c['knock_on'])},
        'totals': {cause: dict(c) for cause, c in totals.items()},
        'restore': {'equipment': [{'id': e, 'changes': n} for e, n in restore.most_common()]},
        'changes': changes,
    }
