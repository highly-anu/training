"""Executable, opt-in methodology contracts.

Modules retain their identity, spacing, prescription and confirmed progression
across calendar phases. Future exposures are explicitly conditional forecasts;
only recorded, clean work advances confirmed state. No prose is executable.

A module is essential unless it says `optional: true`: supplementary work the
method lets the athlete skip (Pentathlon Prep's easy runs). An optional module
takes only days no essential module uses, and when there is no such day, or an
injury or the equipment rules its movement out, the week says it was left out
instead of the request being refused.
"""
from __future__ import annotations

from copy import deepcopy
from itertools import combinations
import math

from . import provenance
from .selector import _equipment_ok, _injury_exclusions


class ContractError(ValueError):
    """The requested program cannot fulfil an essential methodology rule."""


def resolve_model(framework: dict, modality: str, modalities: dict) -> str:
    """Explicit overrides win; opted-in frameworks own their progression."""
    return ((framework.get('progression_overrides') or {}).get(modality)
            or (framework.get('progression_model') if framework.get('prescription_policy') == 'framework' else None)
            or (modalities.get(modality) or {}).get('progression_model', 'linear_load'))


_DOCUMENTS: dict = {}


def _document(path: str) -> dict:
    """The validated contract file, read once per change: `/philosophies` asks
    for every track's contract on each request."""
    from . import loader
    import os
    from jsonschema import Draft7Validator
    from yaml import YAMLError
    mtime = os.path.getmtime(path)
    cached = _DOCUMENTS.get(path)
    if cached and cached[0] == mtime:
        return cached[1]
    try:
        document = loader._load_yaml(path)
    except (OSError, YAMLError) as exc:
        raise ContractError(f'The training contract could not be read: {exc}') from exc
    schema = loader._load_yaml(os.path.join(loader._DATA_DIR, '..', 'docs', 'schemas', 'training_contract.schema.json'))
    errors = sorted(Draft7Validator(schema).iter_errors(document), key=lambda e: str(e.path))
    if errors:
        raise ContractError(f'Invalid training contract: {errors[0].message}')
    _DOCUMENTS[path] = (mtime, document)
    return document


def load_contract(package: str, track: str) -> dict | None:
    from . import loader
    import os
    path = os.path.join(loader._PACKAGES_DIR, package, 'training_contract.yaml')
    if not os.path.exists(path):
        return None
    document = _document(path)
    contract = (document.get('tracks') or {}).get(track)
    if contract is None:
        raise ContractError(f'{package}/{track} has no executable training contract.')
    ids = [m['id'] for m in contract['modules']]
    if len(set(ids)) != len(ids):
        raise ContractError('Training module ids must be unique within a track.')
    for module in contract['modules']:
        p = module['progression']
        if p['model'] == 'density_cycle':
            stages = list(zip(p['rounds'], p.get('interval_sec') or [60] * len(p['rounds'])))
            staged = bool(p.get('interval_sec'))
            if p['reps_start'] > p['reps_max'] or (staged and len(set(stages)) != len(stages)) \
                    or (not staged and p['rounds'] != sorted(set(p['rounds']))) \
                    or len(p.get('interval_sec') or p['rounds']) != len(p['rounds']) \
                    or len(p.get('cues') or p['rounds']) != len(p['rounds']):
                raise ContractError('Density cycles require increasing rounds (or distinct stages) and a valid repetition range.')
        if p['model'] == 'timed_cycle' and p['duration_start_sec'] > p['duration_max_sec']:
            raise ContractError('Timed cycles must start at or below their duration ceiling.')
        if any(b['slot_type'] == 'emom' for b in module['blocks']) and p['model'] != 'density_cycle':
            raise ContractError('EMOM contract blocks require a density_cycle prescription.')
    return {**deepcopy(contract), 'version': document['version'], 'package': package, 'track_id': track}


def confirmed_state(current: dict, logs: dict, contract: dict) -> dict:
    """Consume successful exposures once, in prescription order, never by date alone.

    CompletedAt by itself proves attendance, not clean work. An unsuccessful,
    missing or out-of-order exposure cannot advance the module. State is scoped
    to a contract version and track; an unrelated program is never imported.
    """
    identity = f"{contract['package']}/{contract['track_id']}@{contract['version']}"
    if (current.get('training_contract') or {}).get('id') != identity:
        return {}
    state = deepcopy(current.get('module_state') or {})
    day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    for week in current.get('weeks') or []:
        schedule = week.get('schedule') or {}
        for day in sorted(schedule, key=lambda d: d if isinstance(d, int) else day_order.index(d) + 1):
            name = day_order[day - 1] if isinstance(day, int) else day
            for si, session in enumerate(schedule[day]):
                if session.get('is_deload') or session.get('test'):
                    continue
                key = f"{week['week_number']}-{name}-{si}"
                log = logs.get(key) or (logs.get(f"{week['week_number']}-{name}") if si == 0 else {}) or {}
                if not log.get('completedAt'):
                    continue
                for module in session.get('modules') or []:
                    mid = module['id']
                    record = state.setdefault(mid, {'completed': 0})
                    if module.get('forecast_step') != record.get('completed', 0):
                        continue
                    outcomes = [log.get('exercises', {}).get(eid, {}) for eid in module['exercise_ids']]
                    if not outcomes or not all(isinstance(o, dict) and o.get('clean') is True and not isinstance(o.get('rpe'), bool) and isinstance(o.get('rpe'), (int, float))
                                               and 0 < o['rpe'] <= module['max_rpe'] for o in outcomes):
                        continue
                    if any(o.get(k) is not None and (isinstance(o[k], bool) or not isinstance(o[k], (int, float)) or not math.isfinite(o[k]))
                           for o in outcomes for k in ('durationSec', 'rounds')):
                        continue
                    requirements = module.get('requirements') or {eid: {
                        'duration_sec': module.get('duration_sec', 0), 'rounds': module['rounds']}
                        for eid in module['exercise_ids']}
                    if not all((o.get('durationSec') or 0) >= requirements[eid].get('duration_sec', 0)
                               if requirements[eid].get('duration_sec') else
                               (o.get('rounds') or len(o.get('sets') or [])) >= requirements[eid]['rounds']
                               for eid, o in zip(module['exercise_ids'], outcomes)):
                        continue
                    logged_weights = [o.get('weightKg') for o in outcomes if o.get('weightKg') is not None]
                    if any(isinstance(w, bool) or not isinstance(w, (int, float)) or not math.isfinite(w) or w <= 0 for w in logged_weights):
                        continue
                    weights = set(logged_weights)
                    if weights:
                        if len(weights) != 1 or any(isinstance(w, bool) or not isinstance(w, (int, float)) or not math.isfinite(w) or w <= 0 for w in weights):
                            continue
                        weight = next(iter(weights))
                        if record.get('weight_kg') is not None and record['weight_kg'] != weight:
                            continue  # a different bell is a new cycle, not earned continuation
                        record['weight_kg'] = weight
                    record['completed'] += 1
    return state


def _cycle(spec: dict, step: int) -> tuple[int, int]:
    """Density first, then volume; exhaustion holds until a new cycle is chosen."""
    rounds, reps, _interval, _cue = _stage(spec, step)
    return rounds, reps


def _stage(spec: dict, step: int, budget_sec: float | None = None) -> tuple[int, int, int, str | None]:
    """(rounds, reps, interval seconds, cue) at a step. A cycle runs the reps
    from start to max at each stage in turn — Wildman's swing program: 6 to 20
    a minute over 10 minutes, then over 20, then start/stop over ten and
    twenty 90-second rounds — and holds at the last until a new cycle (a
    heavier bell) is chosen."""
    reps = list(range(spec['reps_start'], spec['reps_max'] + 1, spec['reps_step']))
    rounds = spec['rounds']
    intervals = spec.get('interval_sec') or [60] * len(rounds)
    cues = spec.get('cues') or [None] * len(rounds)
    index = min(step, len(reps) * len(rounds) - 1)
    stage = index // len(reps)
    if budget_sec is not None and rounds[stage] * intervals[stage] > budget_sec:
        # Pressed for time, the shorter version of the stage: the longest
        # earlier stage that fits, at the same interval first (Wildman: "if
        # pressed for time ... do the short version", Approach 3 for 4).
        fitting = [k for k in range(stage, -1, -1) if rounds[k] * intervals[k] <= budget_sec]
        if fitting:
            stage = max(fitting, key=lambda k: (intervals[k] == intervals[stage], rounds[k] * intervals[k], k))
    return rounds[stage], reps[index % len(reps)], intervals[stage], cues[stage]


def _interval_budget(module: dict, constraints: dict) -> float:
    """The seconds a module's interval block may take: the session's minutes
    less its other blocks'."""
    other = sum(b.get('duration_sec', 0) + b.get('rest_after_sec', 0)
                for b in module['blocks'] if b['slot_type'] != 'emom')
    return constraints.get('session_time_minutes', 60) * 60 - other


def _bell(module: dict, constraints: dict, state: dict) -> float | None:
    inventory = constraints.get('kettlebell_weights_kg')
    if inventory is not None and (not isinstance(inventory, list) or not inventory or any(isinstance(w, bool) or not isinstance(w, (int, float))
                                                     or not math.isfinite(w) or w <= 0 for w in inventory)):
        raise ContractError('kettlebell_weights_kg must contain positive bell weights.')
    weight = state.get('weight_kg')
    if weight is not None and (isinstance(weight, bool) or not isinstance(weight, (int, float))
                               or not math.isfinite(weight) or weight <= 0):
        raise ContractError('A module weight must be a positive number.')
    if weight is not None and inventory is not None and weight not in inventory:
        raise ContractError(f"{module['id']}: the selected bell is not in the available inventory.")
    # A category such as 'kettlebell' says nothing about owned sizes. Never invent
    # a fractional bell or infer a safe working load from an athlete's level.
    return weight


def block_options(block: dict) -> list[str]:
    """The block's exercise and, in the package's order, the substitutes it
    declares: what the method accepts in its place, never a silent fallback."""
    return [block['exercise_id'], *(block.get('alternatives') or [])]


def _ruled_out(ex: dict, constraints: dict, blocked: tuple | None) -> bool:
    if not _equipment_ok(ex, set(constraints.get('equipment') or [])):
        return True
    if blocked is None:
        return False
    ids, patterns = blocked
    return (ex['id'] in ids or bool(set(ex.get('movement_patterns') or []) & patterns)
            or bool(set(ex.get('contraindicated_with') or []) & set(constraints.get('injury_flags') or [])))


def _choose(block: dict, module: dict, exercises: dict, constraints: dict, blocked: tuple | None) -> str:
    """The first declared option the athlete can do. With none, a block that
    declares alternatives refuses naming them all; a single-exercise block
    returns its exercise, so the equipment or injury check names it."""
    for eid in block_options(block):
        if eid not in exercises:
            raise ContractError(f"{module['id']}: {eid} is absent from the declared exercise catalog.")
        if not _ruled_out(exercises[eid], constraints, blocked):
            return eid
    if len(block_options(block)) > 1:
        names = ', '.join(exercises[e].get('name', e) for e in block_options(block))
        raise ContractError(f"{module['id']}: none of {names} fits the equipment or injuries.")
    return block['exercise_id']


def _keep(block: dict, module: dict) -> float:
    """The share a deload keeps of this block; 0 drops it (BJJ drops live rolling)."""
    return block.get('deload_keep', module.get('deload_keep', 1))


def _assignment(block: dict, module: dict, exercises: dict, constraints: dict,
                state: dict, step: int, deload: bool, blocked: tuple | None = None) -> dict:
    eid = _choose(block, module, exercises, constraints, blocked)
    ex = exercises[eid]
    if not _equipment_ok(ex, set(constraints.get('equipment') or [])):
        raise ContractError(f"{module['id']}: equipment for {eid} is unavailable.")
    slot = {'role': f"{module['id']}_{block['role']}", 'slot_type': block['slot_type'],
            'notes': block.get('notes', ''), 'exercise_filter': {'exercise_ids': [eid]}}
    if 'standard' in block:
        slot['standard'] = block['standard']
    if block.get('switch_at_sec'):
        # The scored protocol's hand switch (the watch cue), carried with the test.
        slot['switch_at_sec'] = block['switch_at_sec']
    if block['slot_type'] in ('sets_reps', 'static_hold'):
        # Strength and holds at a prescribed effort: the athlete chooses the
        # load that meets the RPE and records it (RPE autoregulation); a deload
        # keeps its share of the sets. The block's minutes include its rests.
        sets = block['sets']
        if deload:
            sets = max(1, math.floor(sets * _keep(block, module)))
        rest = block.get('rest_sec', 60)
        if block['slot_type'] == 'sets_reps':
            load = {'sets': sets, 'reps': block['reps'], 'rest_sec': rest}
            per_set = block['duration_sec'] / block['sets']
        else:
            load = {'sets': sets, 'hold_seconds': block['hold_sec'], 'rest_sec': rest}
            per_set = block['hold_sec'] + rest
        if block.get('rpe_target') is not None:
            load['target_rpe'] = block['rpe_target']
            load['load_note'] = f"Choose the load you finish at RPE {block['rpe_target']:g}, and record it."
        seconds = math.ceil(sets * per_set / 60) * 60
        load['duration_minutes'] = seconds // 60
    elif block['slot_type'] == 'emom':
        rounds, reps, interval, cue = _stage(module['progression'], step, _interval_budget(module, constraints))
        if deload:
            rounds = max(1, math.floor(rounds * _keep(block, module)))
        # Whole minutes, as every timed block (ten 90-second rounds are 15).
        seconds = math.ceil(rounds * interval / 60) * 60
        load = {'target_rounds': rounds, 'reps_per_round': reps, 'work_sec': interval,
                'rest_sec': 0, 'time_minutes': seconds // 60,
                'format': 'EMOM' if interval == 60 else f'EVERY {interval} S',
                'duration_minutes': seconds // 60}
        if cue:
            load['focus'] = cue
    else:
        seconds = block['duration_sec']
        if _progresses(block) and not block.get('standard') and module['progression']['model'] == 'timed_cycle':
            p = module['progression']
            seconds = min(p['duration_max_sec'], p['duration_start_sec'] + step * p['duration_step_sec'])
        if deload and not block.get('standard'):
            seconds = max(60, int(seconds * _keep(block, module)))
        # Existing phone/watch clients use integral-minute timed blocks. Round
        # the actual work up, then budget that work; never just round its label.
        seconds = math.ceil(seconds / 60) * 60
        load = {'duration_minutes': seconds // 60}
        if block.get('target_rpm') is not None:
            load['target_rpm'] = block['target_rpm']
        if block['slot_type'] == 'skill_practice':
            load['focus'] = 'Controlled technique; stop before movement quality deteriorates.'
    if block.get('intensity'):
        # A prescribed zone, as the selector writes one, so heart rate counts
        # for this block in the analytics (src/analytics/hr_plan.py).
        from .progression import zone_band
        slot['intensity'] = load['intensity'] = block['intensity']
        lo, hi, label = zone_band(block['intensity'])
        if lo is not None:
            load.update(zone_target=label, zone_lower=lo, zone_upper=hi)
    # Inter-event recovery is an explicit timed block below; a strength block's
    # rest between sets is inside its own minutes.
    slot['rest_sec'] = block.get('rest_sec', 60) if block['slot_type'] in ('sets_reps', 'static_hold') else 0
    if block.get('standard'):
        from .standard_tests import protocol_load
        slot['role'] = block['role']
        slot['duration_minutes'] = seconds / 60
        load.update(protocol_load(ex, slot))
    weight = _bell(module, constraints, state)
    if block.get('loaded'):
        if weight is not None:
            load['weight_kg'] = weight
        load['load_note'] = (('Use two matching bells; selected weight is per bell. Finish repetitions cleanly, then rest.'
                              if module.get('bell_count') == 2 else
                              'Use the selected single bell; finish repetitions with clean mechanics, then rest.')
                             if weight is not None else
                             'Choose a bell you can control throughout. Record its weight before increasing load.')
    if block['slot_type'] == 'emom' and load.get('focus'):
        # The stage's cue leads the note both clients show (start/stop).
        load['load_note'] = f"{load['focus']} {load.get('load_note') or ''}".strip()
    load.update(prescription_version=1, progression_model=module['progression']['model'],
                module_id=module['id'], forecast_step=step,
                advances_module=_progresses(block),
                conditional=step != state.get('completed', 0), elapsed_sec=seconds)
    return {'slot_role': slot['role'], 'slot_type': slot['slot_type'], 'slot': slot,
            'exercise': ex, 'load': load, **({'standard': block['standard']} if block.get('standard') else {})}


def _progresses(block: dict) -> bool:
    """A loaded block (the bell) or one declared to progress without a bell
    (an easy run's minutes) carries the module's progression."""
    return bool(block.get('loaded') or block.get('progresses'))


def _module_rows(module, exercises, constraints, state, step, deload, blocked=None, left_out=None):
    """A module's assignments. A block the package marks `optional` that none of
    its options fits (a dead hang under a shoulder-instability flag) is left out
    and named in `left_out`; an essential one still refuses."""
    rows = []
    for block in module['blocks']:
        if deload and not block.get('standard') and _keep(block, module) == 0:
            continue
        if block.get('optional') and all(
                eid in exercises and _ruled_out(exercises[eid], constraints, blocked) for eid in block_options(block)):
            if left_out is not None:
                left_out.append(f"{module['name']}: {exercises.get(block['exercise_id'], {}).get('name', block['exercise_id'])} "
                                'left out — no option fits the equipment or injuries')
            continue
        row = _assignment(block, module, exercises, constraints, state, step, deload, blocked)
        rows.append(row)
        if block.get('rest_after_sec'):
            # Whole minutes, as every timed block: the session's minutes are
            # their sum, which `verify` compares exactly.
            rest = math.ceil(block['rest_after_sec'] / 60) * 60
            role = f"{module['id']}_{block['role']}_recovery"
            rows.append({'slot_role': role, 'slot_type': 'time_domain', 'exercise': None, 'meta': True,
                         'slot': {'role': role, 'slot_type': 'time_domain', 'skip_exercise': True,
                                  'notes': 'Recover before the next event.'},
                         'load': {**{k: row['load'][k] for k in ('prescription_version', 'progression_model', 'module_id', 'forecast_step', 'conditional')},
                                  'duration_minutes': rest // 60, 'elapsed_sec': rest,
                                  'advances_module': False, 'focus': 'Recovery before the next event.'}})
    return rows


def _placements(modules: list, durations: dict, pool: list[int], cap: float):
    """Every placement of the essential modules that keeps their exposures,
    spacing and budget, in preference order; it never substitutes a modality."""
    result = {d: [] for d in pool}
    totals = {d: 0 for d in pool}

    def assign(index):
        if index == len(modules):
            yield {d: list(ms) for d, ms in result.items() if ms}
            return
        m = modules[index]
        choices = list(combinations(pool, m['exposures_per_week']))
        choices.sort(key=lambda days: (sum(totals[d] for d in days), days))
        for days in choices:
            gaps = [b - a for a, b in zip(days, days[1:])] + [7 + days[0] - days[-1]]
            if min(gaps) < m.get('min_spacing_days', 2):
                continue
            if any(totals[d] + durations[m['id']] > cap for d in days):
                continue
            for d in days:
                result[d].append(m); totals[d] += durations[m['id']]
            yield from assign(index + 1)
            for d in days:
                result[d].pop(); totals[d] -= durations[m['id']]
    yield from assign(0)


def _place_optional(module: dict, minutes: float, free: list[int], room: dict) -> list[int]:
    """As many of an optional module's exposures as fit on the given days
    (`room`: each day's minutes left), keeping its recovery spacing; possibly
    none. Days earlier in `free` are preferred."""
    for k in range(min(module['exposures_per_week'], len(free)), 0, -1):
        for days in combinations(free, k):
            ordered = sorted(days)
            gaps = [b - a for a, b in zip(ordered, ordered[1:])] + [7 + ordered[0] - ordered[-1]]
            if min(gaps) < module.get('min_spacing_days', 2):
                continue
            if any(minutes > room.get(d, 0) for d in days):
                continue
            return ordered
    return []


def _optional_blocker(module: dict, exercises: dict, constraints: dict, state: dict,
                      blocked_ids: set, blocked_patterns: set) -> str | None:
    """Why an optional module cannot run for this athlete at all, if it cannot."""
    try:
        rows = _module_rows(module, exercises, constraints, state, 0, False, (blocked_ids, blocked_patterns))
    except ContractError as exc:
        return str(exc)
    for row in rows:
        ex = row.get('exercise')
        if ex and _ruled_out(ex, constraints, (blocked_ids, blocked_patterns)):
            return f"{ex.get('name', ex['id'])} conflicts with an active injury restriction"
    return None


def active_modules(contract: dict, constraints: dict) -> list[dict]:
    """The modules this athlete runs: those written for their level, each with
    its weekly exposures for the days they train (`exposures_by_days` — BJJ's
    mat sessions grow with the week; 0 leaves a module out), and the bell pair
    a track asks for. The compiler and the verifier read the same list."""
    level = constraints.get('training_level', 'intermediate')
    days = constraints.get('days_per_week', 4)
    learned = set(constraints.get('mastered_exercises') or []) | set((contract.get('level_seeds') or {}).get(level, []))
    out = []
    for m in contract['modules']:
        if level not in m['training_levels']:
            continue
        if m.get('when_mastered') and set(m.get('requires_mastery') or []) - learned:
            continue  # joins the week once its movements are confirmed
        by_days = m.get('exposures_by_days')
        if by_days:
            counts = {int(k): v for k, v in by_days.items()}
            if days < min(counts):
                raise ContractError(f"{m['name']} needs at least {min(counts)} training days a week.")
            n = counts[max(k for k in counts if k <= days)]
            if not n:
                continue
            m = {**m, 'exposures_per_week': n}
        if contract.get('requires_kettlebell_pair'):
            m = {**m, 'bell_count': 2}
        out.append(m)
    return out


def generate(contract: dict, entries: list, constraints: dict, data: dict, policy,
             frameworks: dict, include_trace: bool = False) -> dict:
    """Compile the contract directly to the normal generator result shape."""
    from .scheduler import _build_day_pool
    if len(policy.owner_packages) > 1:
        raise ContractError('Module contracts currently support one methodology at a time; a blend needs an explicit composition contract.')
    level = constraints.get('training_level', 'intermediate')
    if level not in contract['training_levels']:
        raise ContractError(f"This track supports {contract['training_levels']}, not {level}.")
    if contract.get('requires_kettlebell_pair'):
        count = constraints.get('kettlebell_count', 0)
        if isinstance(count, bool) or not isinstance(count, int) or count < 2:
            raise ContractError('This track requires two matching kettlebells; confirm kettlebell_count of at least 2.')
    modules = active_modules(contract, constraints)
    if not modules:
        raise ContractError('No training modules are defined for this level.')
    if constraints.get('fatigue_state', 'normal') not in ('normal', 'overreached', 'fresh', 'accumulated'):
        raise ContractError('Unsupported fatigue state.')
    # `allow_split_sessions` is ignored: the contract composes its own days
    # (modules share one when they must) and adds no accessory sessions. It
    # used to refuse, so any schedule with a second session on a day — which
    # the web turns into the flag — could not generate a contract track.
    learned = set(constraints.get('mastered_exercises') or []) | set(contract.get('level_seeds', {}).get(level, []))
    waiting = [m for m in contract['modules'] if m.get('when_mastered') and level in m['training_levels']
               and set(m.get('requires_mastery') or []) - learned]
    for m in modules:
        if set(m.get('requires_mastery') or []) - learned:
            raise ContractError(f"{m['id']}: confirm mastery of {m['requires_mastery']} before using this track.")
        if m['archetype_id'] not in {a['id'] for a in data['archetypes'] if a.get('_package') == contract['package']}:
            raise ContractError(f"{m['id']}: its declared archetype is absent from the package.")
    supplied = constraints.get('module_progression_state') or {}
    if not isinstance(supplied, dict):
        raise ContractError('Module progression state must be an object keyed by module id.')
    state = deepcopy(supplied)
    for m in modules:
        value = state.setdefault(m['id'], {'completed': 0})
        if not isinstance(value, dict) or isinstance(value.get('completed', 0), bool) or not isinstance(value.get('completed', 0), int) or value.get('completed', 0) < 0:
            raise ContractError('Module completed exposures must be nonnegative integers.')
    cursor = {m['id']: state[m['id']].get('completed', 0) for m in modules}
    blocked_patterns, blocked_ids = _injury_exclusions(constraints, data['injury_flags'])
    blocked_patterns |= set(constraints.get('avoid_movements') or [])
    catalog = data['exercises_by_package'][contract['package']]
    essential = [m for m in modules if not m.get('optional')]
    optional_out = {m['id']: _optional_blocker(m, catalog, constraints, state[m['id']], blocked_ids, blocked_patterns)
                    for m in modules if m.get('optional')}
    cap = constraints.get('session_time_minutes', 60)
    days = constraints.get('days_per_week', 4)
    first_fw = frameworks[entries[0]['framework_id']]
    pool = _build_day_pool(days, sorted(constraints.get('preferred_days') or []),
                           sorted(constraints.get('forced_rest_days') or []),
                           framework_id=first_fw['id'], phase=entries[0]['phase'],
                           week_in_phase=1, framework=first_fw)
    program = {'weeks': [], 'compromises': [
                   f"{m['name']} joins the week once you confirm "
                   f"{', '.join(sorted(set(m['requires_mastery']) - learned))}." for m in waiting],
               'module_state': state,
               'training_contract': {'id': f"{contract['package']}/{contract['track_id']}@{contract['version']}",
                                     'version': contract['version'], 'status': 'fulfilled',
                                     'forecast': 'Future exposures assume successful clean completion; regenerate after logging outcomes.'}}
    # Each module's last day the week before: a week placed differently (a
    # test week closes with its test) must keep the spacing across the boundary.
    previous: dict[str, int] = {}
    for entry in entries:
        fw = frameworks[entry['framework_id']]
        frequency = (fw.get('deload_protocol') or {}).get('frequency_weeks')
        deload = (constraints.get('fatigue_state') == 'overreached'
                  or entry.get('phase_id') in contract.get('deload_phases', [])
                  or bool(frequency and entry['week_in_program'] % frequency == 0))
        # The phase's `exclude_exercises` rule a movement out as an injury
        # does: a declared alternative or an optional block's absence applies.
        week_blocked = (blocked_ids | set(entry.get('exclude_exercises') or []), blocked_patterns)
        estimates = {m['id']: sum(r['load']['elapsed_sec'] for r in _module_rows(
                        m, data['exercises_by_package'][contract['package']], constraints, state[m['id']],
                        cursor[m['id']] + m['exposures_per_week'] - 1, deload, week_blocked)) / 60
                     for m in modules}
        from . import standard_tests
        tests = standard_tests.tests_for_week(entry)
        if tests and not contract.get('test_module'):
            raise ContractError('The phase declares a test but its contract names no test module.')
        if len(tests) > 1:
            raise ContractError('Multiple tests in one contract week are not supported.')
        pending_test = tests[0] if tests and constraints.get('fatigue_state') != 'overreached' else None
        test_last = bool(pending_test and pending_test.get('day') == 'last')
        day_caps = {d: (constraints.get('day_configs', {}).get(d) or {}).get('minutes', cap) for d in pool}
        optional = [m for m in modules if m.get('optional') and not optional_out[m['id']]]

        def clear_of_last_week(mid: str, day: int, spacing: int) -> bool:
            return mid not in previous or 7 + day - previous[mid] >= spacing

        def spaced(candidate: dict) -> bool:
            first = {}
            for d, ms in candidate.items():
                for m in ms:
                    first[m['id']] = min(first.get(m['id'], 8), d)
            spacing = {m['id']: m.get('min_spacing_days', 2) for m in modules}
            return all(clear_of_last_week(mid, d, spacing[mid]) for mid, d in first.items())

        # The module a test stands in for closes every week, not only a test
        # week, so a test week differs from its twin by the test alone (the
        # standard_tests rule) and the test is the last session of its week.
        close_with_test_module = bool(contract.get('test_module')) and (test_last or not pending_test)

        def optional_fit(candidate: dict) -> tuple[dict, bool]:
            """Optional days on this placement, and whether the test module closes the
            week; nothing optional goes after it, in a test week or its twin."""
            test_days = [d for d, ms in candidate.items() if any(m['id'] == contract.get('test_module') for m in ms)]
            closes = not close_with_test_module or (bool(test_days) and max(test_days) == max(candidate))
            limit = max(test_days) if close_with_test_module and test_days else 8
            room = {d: min(cap, day_caps.get(d, cap)) - sum(estimates[x['id']] for x in candidate.get(d, []))
                    for d in pool}
            fit = {}
            for m in optional:
                # Free days first; a module that may share a day (Wildman's
                # programs stack into one session) then takes a day with the
                # minutes left beside the essential work.
                days = [d for d in pool if d < limit and clear_of_last_week(m['id'], d, m.get('min_spacing_days', 2))
                        and (d not in candidate or m.get('may_share_day'))]
                days.sort(key=lambda d: (d in candidate, -room[d], d))
                fit[m['id']] = _place_optional(m, estimates[m['id']], days, room)
                for d in fit[m['id']]:
                    room[d] -= estimates[m['id']]
            return fit, closes

        # The first placement that closes a test week with its test and fits
        # the most optional work; the search is small (a week, a few modules).
        best = None
        for i, candidate in enumerate(_placements(essential, estimates, pool, cap)):
            if not spaced(candidate):
                continue
            fit, closes = optional_fit(candidate)
            # Optional work never costs an essential session its own day.
            stacked = sum(len(ms) - 1 for ms in candidate.values())
            # Alternate kinds of work: two days of the same modality back to
            # back (two gym sessions, a run of classes) only when nothing else fits.
            kind = {d: frozenset(m['modality'] for m in ms) for d, ms in candidate.items()}
            alike = sum(1 for d in kind if kind.get(d % 7 + 1) == kind[d])
            key = (closes, -stacked, sum(len(v) for v in fit.values()), -alike)
            if best is None or key > best[0]:
                best = (key, candidate, fit)
            if key == (True, 0, sum(m['exposures_per_week'] for m in optional), 0) or i >= 500:
                break
        if best is None:
            raise ContractError('Required module frequency, recovery spacing and session budget cannot all fit. Increase available time or days.')
        _, placed, fit = best
        previous = {}
        skipped = []
        for m in modules:
            if not m.get('optional'):
                continue
            days_for = fit.get(m['id'], [])
            reason = optional_out[m['id']]
            if not reason and len(days_for) < m['exposures_per_week']:
                free = [d for d in pool if d not in placed]
                reason = ('nothing is scheduled after the event volume session' if close_with_test_module and len(free) > len(days_for)
                          else f"no time beside the week's other work in {cap:g}-minute sessions" if m.get('may_share_day')
                          else 'no free training day for it' if not free
                          else f"not enough free days {m.get('min_spacing_days', 2)} days apart")
            for d in days_for:
                placed.setdefault(d, []).append(m)
            if reason:
                skipped.append({'id': m['id'], 'name': m['name'],
                                'placed': len(days_for), 'of': m['exposures_per_week'], 'reason': reason})
        test_days = [d for d, ms in placed.items() if any(m['id'] == contract.get('test_module') for m in ms)]
        test_day = (max(test_days) if pending_test and pending_test.get('day') == 'last' else min(test_days)) if test_days else None
        for d, ms in placed.items():
            for m in ms:
                previous[m['id']] = max(previous.get(m['id'], 0), d)
        schedule = {}
        for day, day_modules in sorted(placed.items()):
            # Also honour per-day budgets, not just the overall session limit.
            day_cap = (constraints.get('day_configs', {}).get(day) or {}).get('minutes', cap)
            assignments, records, session_test = [], [], None
            # A test day is a test session for every module on it: none deloads
            # or advances, as `verify` and `confirmed_state` read the session.
            test_today = bool(pending_test and day == test_day
                              and any(m['id'] == contract.get('test_module') for m in day_modules))
            for m in day_modules:
                if pending_test and day == test_day and m['id'] == contract['test_module']:
                    aid = pending_test['archetypes'][0]
                    test_arch = next((a for a in data['archetypes'] if a['id'] == aid and a.get('_package') == contract['package']), None)
                    if not standard_tests.is_test(test_arch):
                        raise ContractError('The contract test is missing its scored protocol.')
                    scored = {sl['exercise_filter']['exercise_ids'][0]: sl for sl in test_arch['slots'] if sl.get('standard')}
                    m = deepcopy(m)
                    for block in m['blocks']:
                        if block['exercise_id'] in scored:
                            sl = scored[block['exercise_id']]
                            block.update(duration_sec=int(sl['duration_minutes'] * 60),
                                         standard=standard_tests.standard_ref(sl), rest_after_sec=sl.get('rest_sec', 0),
                                         switch_at_sec=sl.get('switch_at_sec'))
                    # The scored protocol's own minutes, which the verifier
                    # holds the test to: a weekly ceiling (Pentathlon's
                    # four-minute mini sets) is not the event's six.
                    session_test = {'archetype': aid, 'standards': standard_tests.standards_of(test_arch),
                                    'protocol_sec': {eid: int(sl['duration_minutes'] * 60) for eid, sl in scored.items()},
                                    'phase_id': entry.get('phase_id'), 'week_in_phase': entry['week_in_phase'],
                                    'in_place_of': m['modality'],
                                    'instead_of': {'archetype': m['archetype_id'], 'minutes': estimates[m['id']], 'buckets': {}}}
                    pending_test = None
                left_out: list[str] = []
                rows = _module_rows(m, data['exercises_by_package'][contract['package']], constraints,
                                    state[m['id']], cursor[m['id']], deload and not test_today,
                                    week_blocked, left_out)
                for line in left_out:
                    if line + '.' not in program['compromises']:
                        program['compromises'].append(line + '.')
                for ea in rows:
                    ex = ea.get('exercise')
                    if not ex:
                        continue
                    if _ruled_out(ex, constraints, (blocked_ids, blocked_patterns)):
                        raise ContractError(f"{m['id']}: an essential movement conflicts with an active injury restriction.")
                    if ex['id'] in (entry.get('exclude_exercises') or []):
                        raise ContractError(f"{m['id']}: an essential movement is excluded by this phase.")
                assignments.extend(rows)
                rounds = next((r['load'].get('target_rounds') for r in rows if r['load'].get('target_rounds')), 1)
                records.append({'id': m['id'], 'forecast_step': cursor[m['id']],
                                'archetype_id': m['archetype_id'],
                                # What was prescribed: a declared alternative, never a
                                # block left out, so confirmed_state reads the right logs.
                                'exercise_ids': [r['exercise']['id'] for r in rows
                                                 if r.get('exercise') and r['load'].get('advances_module')],
                                'rounds': rounds, 'max_rpe': m['max_rpe'],
                                'requirements': {r['exercise']['id']: {
                                    'rounds': r['load'].get('target_rounds', 1),
                                    'duration_sec': 0 if r['slot_type'] == 'emom' else r['load']['elapsed_sec']}
                                    for r in rows if r.get('exercise') and r['load'].get('advances_module')},
                                'duration_sec': next((r['load']['elapsed_sec'] for r in rows
                                                      if r.get('exercise') and r['slot_type'] == 'time_domain' and m['progression']['model'] == 'timed_cycle'), 0)})
                if not deload and not test_today:
                    cursor[m['id']] += 1
            elapsed = sum(e['load']['elapsed_sec'] for e in assignments) // 60
            if elapsed > min(cap, day_cap):
                raise ContractError(f'Day {day}: required modules need {elapsed:g} minutes; available time is {min(cap, day_cap):g}.')
            first = day_modules[0]
            arch = {'id': session_test['archetype'] if session_test else first['archetype_id'],
                    'name': test_arch['name'] if session_test else ' + '.join(m['name'] for m in day_modules),
                    '_package': contract['package'], 'modality': first['modality'],
                    'duration_estimate_minutes': elapsed, 'slots': [a['slot'] for a in assignments],
                    'notes': contract['notes'], 'training_levels': contract['training_levels']}
            session = {'modality': first['modality'], 'archetype': arch, 'is_deload': deload,
                       'exercises': assignments, 'modules': records,
                       'provenance': provenance.origin(arch, policy, kind='archetype')}
            if session_test:
                session['test'] = session_test
            schedule[day] = [session]
        program['weeks'].append({'week_number': entry['week_in_program'], 'week_in_phase': entry['week_in_phase'],
                                 'phase': entry['phase'], 'phase_id': entry.get('phase_id'),
                                 'phase_name': entry.get('phase_name'), 'track_id': contract['track_id'],
                                 'framework': fw['id'], 'is_deload': deload, 'schedule': schedule,
                                 **({'modules_skipped': skipped} if skipped else {})})
        for item in skipped:
            line = f"{item['name']}: {item['placed']} of {item['of']} weekly sessions — {item['reason']}."
            if line not in program['compromises']:
                program['compromises'].append(line)
        if tests and constraints.get('fatigue_state') == 'overreached':
            program['weeks'][-1]['tests_skipped'] = [{'archetypes': t['archetypes'], 'reason': 'overreached'} for t in tests]
        elif pending_test:
            raise ContractError('The required test could not be placed in its module.')
    verify(program, contract, constraints)
    if include_trace:
        program['generation_trace'] = _trace(program, contract, constraints)
    return program


def _trace(program: dict, contract: dict, constraints: dict) -> dict:
    """The generation trace in the shape the selector's has (the Dev Lab reads
    one shape; test_devlab_trace.py keeps it): the framework is the phase's,
    nothing was chosen among candidates, and every slot and progression entry
    names the module that placed it."""
    names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    contract_id = program['training_contract']['id']
    level = constraints.get('training_level', 'intermediate')

    def session(s: dict, w: dict) -> dict:
        exercises = s['exercises']
        return {
            'modality': s['modality'],
            'archetype': {'selected_id': s['archetype']['id'], 'filter_counts': {}, 'candidates': []},
            'modules': [m['id'] for m in s.get('modules') or []],
            'slots': [{'slot_index': i, 'slot_role': ea['slot_role'], 'slot_type': ea.get('slot_type'),
                       'meta': bool(ea.get('meta')), 'movement_pattern': None,
                       'selected_id': (ea.get('exercise') or {}).get('id'),
                       'injury_blocked': bool(ea.get('injury_skip')), 'filter_counts': {}, 'candidates': [],
                       'module_id': (ea.get('load') or {}).get('module_id')}
                      for i, ea in enumerate(exercises)],
            'progression': [{'exercise_id': (ea.get('exercise') or {}).get('id'),
                             'exercise_name': (ea.get('exercise') or {}).get('name'),
                             'slot_role': ea['slot_role'], 'slot_type': ea.get('slot_type'),
                             'model': ea['load']['progression_model'], 'week': w['week_number'],
                             'phase': w['phase'], 'level': level, 'is_deload': w['is_deload'],
                             'output': ea['load']}
                            for ea in exercises if ea.get('load', {}).get('progression_model')],
        }

    return {'primary_sources': [contract['package']], 'philosophy_mode': 'training_contract',
            'weeks': [{'week_number': w['week_number'], 'week_in_phase': w['week_in_phase'],
                       'phase': w['phase'], 'is_deload': w['is_deload'],
                       'scheduler': {'contract': contract_id, 'is_deload': w['is_deload'],
                                     'framework_selection': {'selected_id': w['framework'],
                                                             'selection_reason': 'training_contract'}},
                       'sessions': {names[d - 1]: [session(s, w) for s in ss]
                                    for d, ss in w['schedule'].items()}}
                      for w in program['weeks']]}


def _sequence_matches(actual: list[str], blocks: list[dict]) -> bool:
    """Each block in order by one of its options; an optional block may be absent."""
    i = 0
    for b in blocks:
        if i < len(actual) and actual[i] in block_options(b):
            i += 1
        elif not b.get('optional'):
            return False
    return i == len(actual)


def verify(program: dict, contract: dict, constraints: dict) -> None:
    """Independent output acceptance checks; never trust the session label."""
    expected = {m['id']: m for m in active_modules(contract, constraints)}
    last_day = {}
    inventory = constraints.get('kettlebell_weights_kg')
    cursors = {mid: (program.get('module_state', {}).get(mid) or {}).get('completed', 0) for mid in expected}
    for wi, week in enumerate(program['weeks']):
        counts = {mid: 0 for mid in expected}
        for day, sessions in week['schedule'].items():
            for session in sessions:
                elapsed = sum(e['load']['elapsed_sec'] for e in session['exercises']) / 60
                if elapsed > constraints['session_time_minutes'] or elapsed != session['archetype']['duration_estimate_minutes']:
                    raise ContractError('Session workload and duration budget disagree.')
                for record in session['modules']:
                    mid = record['id']
                    if mid not in expected:
                        raise ContractError('A session uses a module outside its track.')
                    counts[mid] += 1
                    if record['forecast_step'] != cursors[mid]:
                        raise ContractError('A module cursor was advanced without its exposure sequence.')
                    if not week['is_deload'] and not session.get('test'):
                        cursors[mid] += 1
                    absolute = wi * 7 + day
                    if mid in last_day and absolute - last_day[mid] < expected[mid]['min_spacing_days']:
                        raise ContractError('Required recovery spacing was lost.')
                    last_day[mid] = absolute
                    actual = [e['exercise']['id'] for e in session['exercises'] if e['load']['module_id'] == mid and e.get('exercise')]
                    dropping = week['is_deload'] and not session.get('test')
                    blocks = [b for b in expected[mid]['blocks']
                              if not (dropping and not b.get('standard') and _keep(b, expected[mid]) == 0)]
                    if not _sequence_matches(actual, blocks):
                        raise ContractError('A module lost its fixed movement sequence.')
                    requirements = {e['exercise']['id']: {
                        'rounds': e['load'].get('target_rounds', 1),
                        'duration_sec': 0 if e['slot_type'] == 'emom' else e['load']['elapsed_sec']}
                        for e in session['exercises'] if e.get('exercise')
                        and e['load']['module_id'] == mid and e['load'].get('advances_module')}
                    if record.get('requirements') != requirements:
                        raise ContractError('A module lost its per-exercise completion requirements.')
                    rests = {e['slot_role']: e['load']['elapsed_sec'] for e in session['exercises']
                             if e['load']['module_id'] == mid and e.get('meta')}
                    # A test session names its slots by the test's own roles.
                    present = {e['slot_role'] for e in session['exercises'] if e['load']['module_id'] == mid}
                    if rests != {f"{mid}_{b['role']}_recovery": math.ceil(b['rest_after_sec'] / 60) * 60
                                 for b in blocks if b.get('rest_after_sec') and present & {b['role'], f"{mid}_{b['role']}"}}:
                        raise ContractError('A module lost its required inter-event recovery.')
                    spec = expected[mid]['progression']
                    for ea in session['exercises']:
                        load = ea['load']
                        if load['module_id'] != mid:
                            continue
                        if load['forecast_step'] != record['forecast_step']:
                            raise ContractError('An assignment lost its module progression position.')
                        if load.get('weight_kg') is not None and inventory is not None and load['weight_kg'] not in inventory:
                            raise ContractError('A prescription uses a bell outside the available inventory.')
                        if load['progression_model'] != spec['model']:
                            raise ContractError('A prescription lost its resolved progression policy.')
                        if spec['model'] == 'timed_cycle' and ea.get('exercise') and ea['slot_type'] == 'time_domain':
                            seconds = (session['test']['protocol_sec'][ea['exercise']['id']] if ea.get('standard') else
                                       min(spec['duration_max_sec'], spec['duration_start_sec'] + record['forecast_step'] * spec['duration_step_sec']))
                            if week['is_deload'] and not session.get('test'):
                                block = next((b for b in blocks if ea['slot_role'] in (b['role'], f"{mid}_{b['role']}")), {})
                                seconds = max(60, int(seconds * _keep(block, expected[mid])))
                            seconds = math.ceil(seconds / 60) * 60
                            if load['elapsed_sec'] != seconds or load['duration_minutes'] * 60 != seconds:
                                raise ContractError('An event duration does not follow its declared progression or test protocol.')
                        if ea['slot_type'] == 'emom':
                            rounds, reps, interval, _cue = _stage(spec, record['forecast_step'],
                                                                  _interval_budget(expected[mid], constraints))
                            if week['is_deload']:
                                block = next((b for b in blocks if ea['slot_role'] in (b['role'], f"{mid}_{b['role']}")), {})
                                rounds = max(1, math.floor(rounds * _keep(block, expected[mid])))
                            if load.get('target_rounds') != rounds or load.get('reps_per_round') != reps:
                                raise ContractError('A prescription does not follow its declared progression cycle.')
                            if load['elapsed_sec'] != math.ceil(rounds * interval / 60) * 60 or load.get('work_sec') != interval:
                                raise ContractError('A minute-based module lost its interval structure.')
        if any(counts[mid] != m['exposures_per_week'] for mid, m in expected.items() if not m.get('optional')):
            raise ContractError('An essential weekly module exposure is missing.')
        if any(counts[mid] > m['exposures_per_week'] for mid, m in expected.items()):
            raise ContractError('A module runs more often than its weekly exposures.')


def verify_phase_rules(program: dict, goal: dict) -> None:
    """Essential declared phase checks are production acceptance criteria."""
    previous_minutes = None
    for phase in goal.get('phase_sequence') or []:
        checks = phase.get('checks') or {}
        if checks.get('intensity_split_tolerance') is not None:
            raise ContractError('This module contract does not implement heart-rate intensity split targets.')
        weeks = [w for w in program['weeks'] if w.get('phase_id') == phase['phase_id']]
        previous_work = None
        minutes = []
        for week in weeks:
            sessions = [s for ss in week['schedule'].values() for s in ss]
            arches = {m['archetype_id'] for s in sessions for m in s['modules']}
            if arches & set(checks.get('archetypes_forbidden') or []):
                raise ContractError('A phase-forbidden session was generated.')
            if checks.get('max_zone') is not None:
                bounds = [ea['load'].get('zone_upper') for s in sessions for ea in s['exercises']]
                if not bounds or any(v is None or v > checks['max_zone'] for v in bounds):
                    raise ContractError('The phase zone ceiling cannot be verified for this prescription.')
            if not week['is_deload'] and not any(s.get('test') for s in sessions):
                if set(checks.get('archetypes_required') or []) - arches:
                    raise ContractError('A required phase session is missing.')
                if set(checks.get('modalities_required') or []) - {s['modality'] for s in sessions}:
                    raise ContractError('A required phase modality is missing.')
            amount = sum(ea['load']['elapsed_sec'] for s in sessions for ea in s['exercises']) / 60
            if not week['is_deload']:
                minutes.append(amount)
                band = checks.get('volume_change_per_week')
                if band and previous_work and week['week_number'] == previous_work[0] + 1:
                    change = amount / previous_work[1] - 1
                    if not band[0] <= change <= band[1]:
                        raise ContractError('Weekly workload violates the declared ramp.')
                previous_work = (week['week_number'], amount)
        amounts = minutes or [sum(ea['load']['elapsed_sec'] for ss in w['schedule'].values() for s in ss for ea in s['exercises']) / 60 for w in weeks]
        band = checks.get('volume_vs_previous_phase')
        if band and previous_minutes and amounts:
            change = (sum(amounts) / len(amounts)) / previous_minutes - 1
            if not band[0] <= change <= band[1]:
                raise ContractError('Phase workload violates the declared change from the previous phase.')
        if amounts:
            previous_minutes = amounts[-1]
