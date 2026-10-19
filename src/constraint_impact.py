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

A training contract (src/training_contract.py) refuses what it cannot run as
written instead of degrading it, and asks the athlete to confirm mastery or a
pair of matching bells; that is the fourth constraint, `proficiency`. A
refused request is answered with the single constraint that, lifted alone,
lets it generate (`explain_refusal`), tried alongside the framework's ideal
days and minutes.

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

DIMENSIONS = ('equipment', 'injury', 'level', 'proficiency')
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


def contract_requirements(goal: dict, level: str | None = None) -> dict:
    """What a training contract asks an athlete at `level` to confirm: every
    movement a module requires mastery of that the contract does not already
    seed for the level (General Practice counts an intermediate's clean and
    press as known), and a pair of matching bells."""
    contract = (goal or {}).get('training_contract')
    if not contract:
        return {}
    seeded = set((contract.get('level_seeds') or {}).get(level) or [])
    # Only the modules this level runs: a novice on General Practice is never
    # asked for the intermediate clean-and-press module's skills.
    modules = [m for m in contract.get('modules') or []
               if level is None or level in (m.get('training_levels') or [level])]
    out: dict = {'mastered_exercises': sorted({e for m in modules
                                               for e in m.get('requires_mastery') or []} - seeded)}
    if contract.get('requires_kettlebell_pair'):
        out['kettlebell_count'] = 2
    return out


def reference_constraints(constraints: dict, lib: dict, framework: dict | None,
                          override: dict | None = None, requirements: dict | None = None) -> dict:
    """The athlete's constraints with nothing in the way.

    Equipment is everything the allowed packages' exercises and archetypes ask
    for, on top of what the athlete has, with no bell inventory to pick from;
    a contract's `requirements` are confirmed. Days, minutes, fatigue, track
    and start phase stay the athlete's, since they decide the schedule rather
    than what fills it. `override` may pin `equipment` or `training_level`.
    """
    override, requirements = override or {}, requirements or {}
    equipment = set(constraints.get('equipment') or [])
    for ex in (lib.get('exercises') or {}).values():
        equipment.update(ex.get('equipment') or [])
    for arch in lib.get('archetypes') or []:
        equipment.update(arch.get('required_equipment') or [])
    equipment.discard('none')
    written_for = ((framework or {}).get('applicable_when') or {}).get('training_level')
    out = {
        **constraints,
        'equipment': sorted(override.get('equipment') or equipment),
        'injury_flags': [],
        'training_level': override.get('training_level')
        or reference_level(constraints.get('training_level', 'intermediate'), written_for),
    }
    out.pop('kettlebell_weights_kg', None)
    if requirements.get('mastered_exercises'):
        out['mastered_exercises'] = sorted(set(constraints.get('mastered_exercises') or [])
                                           | set(requirements['mastered_exercises']))
    if requirements.get('kettlebell_count'):
        out['kettlebell_count'] = max(constraints.get('kettlebell_count') or 1, requirements['kettlebell_count'])
    return out


def _proficiency_short(constraints: dict, reference: dict) -> bool:
    return bool(set(reference.get('mastered_exercises') or []) - set(constraints.get('mastered_exercises') or [])
                or (reference.get('kettlebell_count') or 1) > (constraints.get('kettlebell_count') or 1))


def relaxations(constraints: dict, reference: dict) -> dict[str, dict]:
    """One run per constraint the athlete has: their constraints with only that
    one as the reference has it. A constraint that changes nothing is not run."""
    out: dict[str, dict] = {}
    if (set(reference['equipment']) - set(constraints.get('equipment') or [])
            or constraints.get('kettlebell_weights_kg')):
        lifted = {**constraints, 'equipment': reference['equipment']}
        lifted.pop('kettlebell_weights_kg', None)
        out['equipment'] = lifted
    if constraints.get('injury_flags'):
        out['injury'] = {**constraints, 'injury_flags': []}
    if constraints.get('training_level') != reference['training_level']:
        out['level'] = {**constraints, 'training_level': reference['training_level']}
    if _proficiency_short(constraints, reference):
        out['proficiency'] = {**constraints,
                              **{k: reference[k] for k in ('mastered_exercises', 'kettlebell_count') if k in reference}}
    return out


def schedule_probe(constraints: dict, framework: dict | None) -> dict | None:
    """The athlete's constraints at the framework's ideal days and minutes, if
    they ask for fewer — tried only for a refused request."""
    exp = (framework or {}).get('expectations') or {}
    days = max(constraints.get('days_per_week') or 0, exp.get('ideal_days_per_week') or 0)
    minutes = max(constraints.get('session_time_minutes') or 0, exp.get('ideal_session_minutes') or 0)
    if (days, minutes) == (constraints.get('days_per_week'), constraints.get('session_time_minutes')):
        return None
    # A weekly schedule would be turned back into the athlete's days by the
    # generator, so the probe drops it and what it derives.
    probe = {k: v for k, v in constraints.items()
             if k not in ('weekly_schedule', 'day_configs', 'preferred_days', 'forced_rest_days')}
    return {**probe, 'days_per_week': days, 'session_time_minutes': minutes}


def describe_lifts(constraints: dict, runs: dict[str, dict], exercises: dict, injury_flags: dict) -> dict[str, str]:
    """What each run changed, in words: "add barbell, rack", "confirm mastery
    of Jerk", "4 days, 60 min"."""
    def name(eid):
        return (exercises.get(eid) or {}).get('name', eid)
    out = {}
    for dim, c in runs.items():
        if dim == 'equipment':
            added = sorted(set(c['equipment']) - set(constraints.get('equipment') or []) - _NOT_EQUIPMENT)
            parts = [f"add {', '.join(added)}"] if added else []
            if constraints.get('kettlebell_weights_kg'):
                parts.append('any bell weight')
            out[dim] = '; '.join(parts) or 'all equipment'
        elif dim == 'injury':
            out[dim] = 'without ' + ', '.join((injury_flags.get(f) or {}).get('name', f)
                                              for f in constraints.get('injury_flags') or [])
        elif dim == 'level':
            out[dim] = f"at {c['training_level']}"
        elif dim == 'proficiency':
            missing = sorted(set(c.get('mastered_exercises') or []) - set(constraints.get('mastered_exercises') or []))
            parts = [f"confirm mastery of {', '.join(name(e) for e in missing)}"] if missing else []
            if (c.get('kettlebell_count') or 1) > (constraints.get('kettlebell_count') or 1):
                parts.append(f"{c['kettlebell_count']} matching bells")
            out[dim] = '; '.join(parts)
        elif dim == 'schedule':
            out[dim] = f"{c['days_per_week']} days, {c['session_time_minutes']} min"
    return out


def explain_refusal(refused: dict, generated: dict[str, bool], lifts: dict[str, str],
                    reference: dict) -> dict:
    """A request the generator refused, and what alone would let it generate.

    `generated` says, per run tried ('reference', each dimension, 'schedule'),
    whether it produced weeks.
    """
    unblocked = [{'cause': dim, 'text': lifts.get(dim, dim)}
                 for dim in (*DIMENSIONS, 'schedule') if generated.get(dim)]
    if not unblocked and generated.get('reference'):
        # A novice with one bell on the double-bell track needs the level and
        # the pair: no one of them alone, all of them together.
        unblocked = [{'cause': 'combined',
                      'text': '; '.join(lifts[d] for d in DIMENSIONS if d in lifts)}]
    return {
        'feasible': False,
        'refused': {'detail': refused.get('detail'), 'validation': refused.get('validation')},
        'reference': {k: reference.get(k) for k in ('equipment', 'training_level', 'injury_flags',
                                                     'mastered_exercises', 'kettlebell_count') if k in reference},
        'lifted': [dim for dim in (*DIMENSIONS, 'schedule') if dim in generated],
        'lifts': lifts,
        'unblocked_by': unblocked,
        'reference_generates': bool(generated.get('reference')),
    }


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
        if (ex.get('id') in (self.ref.get('mastered_exercises') or [])
                and ex.get('id') not in (self.c.get('mastered_exercises') or [])):
            out.append({'cause': 'proficiency', 'needs': [], 'text': f"{name} needs confirmed mastery"})
        unlocked = (self.unlocked.get(ex.get('_package'), set().union(*self.unlocked.values()))
                    if isinstance(self.unlocked, dict) else self.unlocked)
        if unlocked is not None and ex.get('id') not in unlocked:
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
    athlete's level, or a dict of them per package, as the selector unlocks per
    archetype package) lets an exercise say it is level-locked.
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
            restore.update(list(dict.fromkeys(needs)))  # once per change, however many slots need it

    # A change counts as a knock-on only after a direct one: before the first,
    # nothing has moved the rotation yet, so a difference is the constraint's own.
    direct_seen = False
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
                        'level': f"are not unlocked at {constraints.get('training_level')}",
                        'proficiency': 'need confirmed mastery'}[cause]
                why.append({'cause': cause, 'text': f"{len(per_slot)} of {filled} of its exercises {what}"})
                if cause == 'equipment':
                    needs += [e for n in per_slot for e in n]
            causes = (shape or ['combined']) + [c for c in DIMENSIONS if c in blocked and c not in shape]
            knock_on = direct_seen and kind == 'archetype' and explain.archetype_open(r)
            if knock_on:
                why = [{'cause': 'knock_on', 'text': f"{_arch(r).get('name')} is open to the athlete: "
                                                     'an earlier change moved the rotation'}]
            entry.update(change=kind, causes=causes, why=why, knock_on=knock_on,
                         alternatives=_session_alternatives(lifted, key, r, a),
                         reference_slots=ref_slots, actual_slots=_slot_list(a))
            count(causes, 'knock_on' if knock_on else 'sessions', needs)
            direct_seen = direct_seen or not knock_on
            changes.append(entry)
            continue

        slot_changes = []
        for i, (r_ea, a_ea) in enumerate(zip(_exercises(r), _exercises(a))):
            if _fill(r_ea) == _fill(a_ea):
                continue
            was, now = _exercise_view(r_ea), _exercise_view(a_ea)
            causes = _restores_slot(lifted, key, r, i) or ['combined']
            found = explain.blockers(r_ea) if was is not None else []
            knock_on = direct_seen and was is not None and not found
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
            direct_seen = direct_seen or not knock_on
        if slot_changes:
            entry.update(change='slots', slots=slot_changes,
                         knock_on=all(sc['knock_on'] for sc in slot_changes))
            changes.append(entry)

    return {
        'reference': {k: reference_constraints.get(k) for k in (
            'equipment', 'training_level', 'injury_flags', 'mastered_exercises', 'kettlebell_count')
            if k in reference_constraints},
        'lifted': [dim for dim in DIMENSIONS if dim in relaxed],
        'sessions': {'total': len(act), 'changed': len(changes),
                     'direct': sum(1 for c in changes if not c['knock_on'])},
        'totals': {cause: dict(c) for cause, c in totals.items()},
        'restore': {'equipment': [{'id': e, 'changes': n} for e, n in restore.most_common()]},
        'changes': changes,
    }
