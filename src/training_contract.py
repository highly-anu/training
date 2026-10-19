"""Executable, opt-in methodology contracts.

Modules retain their identity, spacing, prescription and confirmed progression
across calendar phases. Future exposures are explicitly conditional forecasts;
only recorded, clean work advances confirmed state. No prose is executable.
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


def load_contract(package: str, track: str) -> dict | None:
    from . import loader
    import os
    path = os.path.join(loader._PACKAGES_DIR, package, 'training_contract.yaml')
    if not os.path.exists(path):
        return None
    from jsonschema import Draft7Validator
    from yaml import YAMLError
    try:
        document = loader._load_yaml(path)
    except (OSError, YAMLError) as exc:
        raise ContractError(f'The training contract could not be read: {exc}') from exc
    schema = loader._load_yaml(os.path.join(loader._DATA_DIR, '..', 'docs', 'schemas', 'training_contract.schema.json'))
    errors = sorted(Draft7Validator(schema).iter_errors(document), key=lambda e: str(e.path))
    if errors:
        raise ContractError(f'Invalid training contract: {errors[0].message}')
    contract = (document.get('tracks') or {}).get(track)
    if contract is None:
        raise ContractError(f'{package}/{track} has no executable training contract.')
    ids = [m['id'] for m in contract['modules']]
    if len(set(ids)) != len(ids):
        raise ContractError('Training module ids must be unique within a track.')
    for module in contract['modules']:
        p = module['progression']
        if p['model'] == 'density_cycle' and (p['reps_start'] > p['reps_max'] or p['rounds'] != sorted(set(p['rounds']))):
            raise ContractError('Density cycles require increasing rounds and a valid repetition range.')
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
    reps = list(range(spec['reps_start'], spec['reps_max'] + 1, spec['reps_step']))
    rounds = spec['rounds']
    index = min(step, len(reps) * len(rounds) - 1)
    return rounds[index // len(reps)], reps[index % len(reps)]


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


def _assignment(block: dict, module: dict, exercises: dict, constraints: dict,
                state: dict, step: int, deload: bool) -> dict:
    eid = block['exercise_id']
    if eid not in exercises:
        raise ContractError(f"{module['id']}: {eid} is absent from the declared exercise catalog.")
    ex = exercises[eid]
    if not _equipment_ok(ex, set(constraints.get('equipment') or [])):
        raise ContractError(f"{module['id']}: equipment for {eid} is unavailable.")
    slot = {'role': f"{module['id']}_{block['role']}", 'slot_type': block['slot_type'],
            'notes': block.get('notes', ''), 'exercise_filter': {'exercise_ids': [eid]}}
    if 'standard' in block:
        slot['standard'] = block['standard']
    if block['slot_type'] == 'emom':
        rounds, reps = _cycle(module['progression'], step)
        if deload:
            rounds = max(1, math.floor(rounds * module.get('deload_keep', 1)))
        load = {'target_rounds': rounds, 'reps_per_round': reps, 'work_sec': 60,
                'rest_sec': 0, 'time_minutes': rounds, 'format': 'EMOM',
                'duration_minutes': rounds}
        seconds = rounds * 60
    else:
        seconds = block['duration_sec']
        if block.get('loaded') and not block.get('standard') and module['progression']['model'] == 'timed_cycle':
            p = module['progression']
            seconds = min(p['duration_max_sec'], p['duration_start_sec'] + step * p['duration_step_sec'])
        if deload and not block.get('standard'):
            seconds = max(60, int(seconds * module.get('deload_keep', 1)))
        # Existing phone/watch clients use integral-minute timed blocks. Round
        # the actual work up, then budget that work; never just round its label.
        seconds = math.ceil(seconds / 60) * 60
        load = {'duration_minutes': seconds // 60}
        if block.get('target_rpm') is not None:
            load['target_rpm'] = block['target_rpm']
        if block['slot_type'] == 'skill_practice':
            load['focus'] = 'Controlled technique; stop before movement quality deteriorates.'
    slot['rest_sec'] = 0  # inter-event recovery is an explicit timed block below
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
    load.update(prescription_version=1, progression_model=module['progression']['model'],
                module_id=module['id'], forecast_step=step,
                advances_module=bool(block.get('loaded')),
                conditional=step != state.get('completed', 0), elapsed_sec=seconds)
    return {'slot_role': slot['role'], 'slot_type': slot['slot_type'], 'slot': slot,
            'exercise': ex, 'load': load, **({'standard': block['standard']} if block.get('standard') else {})}


def _module_rows(module, exercises, constraints, state, step, deload):
    rows = []
    for block in module['blocks']:
        row = _assignment(block, module, exercises, constraints, state, step, deload)
        rows.append(row)
        if block.get('rest_after_sec'):
            rest = block['rest_after_sec']
            role = f"{module['id']}_{block['role']}_recovery"
            rows.append({'slot_role': role, 'slot_type': 'time_domain', 'exercise': None, 'meta': True,
                         'slot': {'role': role, 'slot_type': 'time_domain', 'skip_exercise': True,
                                  'notes': 'Recover before the next event.'},
                         'load': {**{k: row['load'][k] for k in ('prescription_version', 'progression_model', 'module_id', 'forecast_step', 'conditional')},
                                  'duration_minutes': rest // 60, 'elapsed_sec': rest,
                                  'advances_module': False, 'focus': 'Recovery before the next event.'}})
    return rows


def _place(modules: list, durations: dict, pool: list[int], cap: float) -> dict:
    """Backtracking keeps essential exposures; it never substitutes a modality."""
    result = {d: [] for d in pool}
    totals = {d: 0 for d in pool}
    def assign(index):
        if index == len(modules):
            return True
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
            if assign(index + 1):
                return True
            for d in days:
                result[d].pop(); totals[d] -= durations[m['id']]
        return False
    if not assign(0):
        raise ContractError('Required module frequency, recovery spacing and session budget cannot all fit. Increase available time or days.')
    return {d: ms for d, ms in result.items() if ms}


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
    modules = [m for m in contract['modules'] if level in m['training_levels']]
    if contract.get('requires_kettlebell_pair'):
        modules = [{**m, 'bell_count': 2} for m in modules]
    if not modules:
        raise ContractError('No training modules are defined for this level.')
    if constraints.get('fatigue_state', 'normal') not in ('normal', 'overreached', 'fresh', 'accumulated'):
        raise ContractError('Unsupported fatigue state.')
    if constraints.get('allow_split_sessions'):
        raise ContractError('This contract already composes its required modules; automatic accessory sessions are unsupported.')
    learned = set(constraints.get('mastered_exercises') or []) | set(contract.get('level_seeds', {}).get(level, []))
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
    cap = constraints.get('session_time_minutes', 60)
    days = constraints.get('days_per_week', 4)
    first_fw = frameworks[entries[0]['framework_id']]
    pool = _build_day_pool(days, sorted(constraints.get('preferred_days') or []),
                           sorted(constraints.get('forced_rest_days') or []),
                           framework_id=first_fw['id'], phase=entries[0]['phase'],
                           week_in_phase=1, framework=first_fw)
    program = {'weeks': [], 'compromises': [], 'module_state': state,
               'training_contract': {'id': f"{contract['package']}/{contract['track_id']}@{contract['version']}",
                                     'version': contract['version'], 'status': 'fulfilled',
                                     'forecast': 'Future exposures assume successful clean completion; regenerate after logging outcomes.'}}
    for entry in entries:
        fw = frameworks[entry['framework_id']]
        frequency = (fw.get('deload_protocol') or {}).get('frequency_weeks')
        deload = (constraints.get('fatigue_state') == 'overreached'
                  or entry.get('phase_id') in contract.get('deload_phases', [])
                  or bool(frequency and entry['week_in_program'] % frequency == 0))
        estimates = {m['id']: sum(r['load']['elapsed_sec'] for r in _module_rows(
                        m, data['exercises_by_package'][contract['package']], constraints, state[m['id']],
                        cursor[m['id']] + m['exposures_per_week'] - 1, deload)) / 60 for m in modules}
        placed = _place(modules, estimates, pool, cap)
        from . import standard_tests
        tests = standard_tests.tests_for_week(entry)
        if tests and not contract.get('test_module'):
            raise ContractError('The phase declares a test but its contract names no test module.')
        if len(tests) > 1:
            raise ContractError('Multiple tests in one contract week are not supported.')
        pending_test = tests[0] if tests and constraints.get('fatigue_state') != 'overreached' else None
        test_days = [d for d, ms in placed.items() if any(m['id'] == contract.get('test_module') for m in ms)]
        test_day = (max(test_days) if pending_test and pending_test.get('day') == 'last' else min(test_days)) if test_days else None
        schedule = {}
        for day, day_modules in sorted(placed.items()):
            # Also honour per-day budgets, not just the overall session limit.
            day_cap = (constraints.get('day_configs', {}).get(day) or {}).get('minutes', cap)
            assignments, records, session_test = [], [], None
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
                                         standard=standard_tests.standard_ref(sl), rest_after_sec=sl.get('rest_sec', 0))
                    session_test = {'archetype': aid, 'standards': standard_tests.standards_of(test_arch),
                                    'phase_id': entry.get('phase_id'), 'week_in_phase': entry['week_in_phase'],
                                    'in_place_of': m['modality'],
                                    'instead_of': {'archetype': m['archetype_id'], 'minutes': estimates[m['id']], 'buckets': {}}}
                    pending_test = None
                rows = _module_rows(m, data['exercises_by_package'][contract['package']], constraints,
                                    state[m['id']], cursor[m['id']], deload and session_test is None)
                for ea in rows:
                    ex = ea.get('exercise')
                    if not ex:
                        continue
                    if ex['id'] in blocked_ids or set(ex.get('movement_patterns') or []) & blocked_patterns or set(ex.get('contraindicated_with') or []) & set(constraints.get('injury_flags') or []):
                        raise ContractError(f"{m['id']}: an essential movement conflicts with an active injury restriction.")
                    if ex['id'] in (entry.get('exclude_exercises') or []):
                        raise ContractError(f"{m['id']}: an essential movement is excluded by this phase.")
                assignments.extend(rows)
                rounds = next((r['load'].get('target_rounds') for r in rows if r['load'].get('target_rounds')), 1)
                records.append({'id': m['id'], 'forecast_step': cursor[m['id']],
                                'archetype_id': m['archetype_id'],
                                'exercise_ids': [b['exercise_id'] for b in m['blocks'] if b.get('loaded')],
                                'rounds': rounds, 'max_rpe': m['max_rpe'],
                                'requirements': {r['exercise']['id']: {
                                    'rounds': r['load'].get('target_rounds', 1),
                                    'duration_sec': 0 if r['slot_type'] == 'emom' else r['load']['elapsed_sec']}
                                    for r in rows if r.get('exercise') and r['load'].get('advances_module')},
                                'duration_sec': next((r['load']['elapsed_sec'] for r in rows
                                                      if r.get('exercise') and r['slot_type'] == 'time_domain' and m['progression']['model'] == 'timed_cycle'), 0)})
                if not deload and session_test is None:
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
                                 'framework': fw['id'], 'is_deload': deload, 'schedule': schedule})
        if tests and constraints.get('fatigue_state') == 'overreached':
            program['weeks'][-1]['tests_skipped'] = [{'archetypes': t['archetypes'], 'reason': 'overreached'} for t in tests]
        elif pending_test:
            raise ContractError('The required test could not be placed in its module.')
    verify(program, contract, constraints)
    if include_trace:
        names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        program['generation_trace'] = {'primary_sources': [contract['package']], 'philosophy_mode': 'training_contract',
            'weeks': [{'week_number': w['week_number'], 'week_in_phase': w['week_in_phase'], 'phase': w['phase'],
                       'is_deload': w['is_deload'], 'scheduler': {'contract': program['training_contract']['id']},
                       'sessions': {names[d - 1]: [{'modality': s['modality'], 'archetype': {'selected_id': s['archetype']['id']},
                           'slots': [], 'progression': [{'exercise_id': (ea.get('exercise') or {}).get('id'), 'slot_role': ea['slot_role'],
                               'model': ea['load']['progression_model'], 'output': ea['load']} for ea in s['exercises']]} for s in ss]
                           for d, ss in w['schedule'].items()}} for w in program['weeks']]}
    return program


def verify(program: dict, contract: dict, constraints: dict) -> None:
    """Independent output acceptance checks; never trust the session label."""
    expected = {m['id']: m for m in contract['modules'] if constraints.get('training_level', 'intermediate') in m['training_levels']}
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
                    if actual != [b['exercise_id'] for b in expected[mid]['blocks']]:
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
                    if rests != {f"{mid}_{b['role']}_recovery": b['rest_after_sec']
                                 for b in expected[mid]['blocks'] if b.get('rest_after_sec')}:
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
                            seconds = (spec['duration_max_sec'] if ea.get('standard') else
                                       min(spec['duration_max_sec'], spec['duration_start_sec'] + record['forecast_step'] * spec['duration_step_sec']))
                            if week['is_deload'] and not session.get('test'):
                                seconds = max(60, int(seconds * expected[mid].get('deload_keep', 1)))
                            seconds = math.ceil(seconds / 60) * 60
                            if load['elapsed_sec'] != seconds or load['duration_minutes'] * 60 != seconds:
                                raise ContractError('An event duration does not follow its declared progression or test protocol.')
                        if ea['slot_type'] == 'emom':
                            reps = list(range(spec['reps_start'], spec['reps_max'] + 1, spec['reps_step']))
                            position = min(record['forecast_step'], len(reps) * len(spec['rounds']) - 1)
                            rounds = spec['rounds'][position // len(reps)]
                            if week['is_deload']:
                                rounds = max(1, math.floor(rounds * expected[mid].get('deload_keep', 1)))
                            if load.get('target_rounds') != rounds or load.get('reps_per_round') != reps[position % len(reps)]:
                                raise ContractError('A prescription does not follow its declared progression cycle.')
                            if load['elapsed_sec'] != rounds * 60 or load.get('work_sec') != 60:
                                raise ContractError('A minute-based module lost its interval structure.')
        if any(counts[mid] != m['exposures_per_week'] for mid, m in expected.items()):
            raise ContractError('An essential weekly module exposure is missing.')


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
