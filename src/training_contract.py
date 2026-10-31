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
from typing import NamedTuple
import math
import os

from . import levels as _levels, provenance, recovery_regions
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
        if module.get('variants'):
            # A module whose sessions alternate (Starting Strength's A and B):
            # the rotation names a variant per exposure. `blocks` becomes every
            # variant's blocks once each, for what reads a module whole (the
            # catalog-coverage tool, the optional-module blocker).
            by_id = {v['id']: v for v in module['variants']}
            rotations = [module.get('rotation')] if not module.get('periods') else \
                [p.get('rotation') or module.get('rotation') for p in module['periods']]
            if any(not r or set(r) - by_id.keys() for r in rotations):
                raise ContractError(f"{module['id']}: its rotation must name its variants.")
            seen, merged = set(), []
            for v in module['variants']:
                for b in v['blocks']:
                    if (b['role'], b['exercise_id']) not in seen:
                        seen.add((b['role'], b['exercise_id']))
                        merged.append(b)
            module['blocks'] = merged
        p = module['progression']
        if p['model'] == 'load_per_exposure':
            missing = {b['exercise_id'] for b in module['blocks'] if b.get('loaded')} - set(p.get('lifts') or {})
            if missing:
                raise ContractError(f"{module['id']}: no increments declared for {sorted(missing)}.")
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
    from . import equipment, implements
    implement = implements.merged(document, contract)
    if implement and implement.get('equipment') not in equipment.ids():
        raise ContractError(f"{package}/{track}: its implement {implement.get('equipment')!r} is not in the equipment list.")
    if not implement and any(b.get('loaded') for m in contract['modules'] if m['progression']['model'] != 'load_per_exposure'
                             for b in m['blocks']):
        raise ContractError(f'{package}/{track}: a loaded block chosen by weight needs the implement it uses '
                            '(`implement: {equipment, count}`).')
    return {**deepcopy(contract), 'version': document['version'], 'package': package, 'track_id': track,
            **({'implement': implement} if implement else {})}


def period_of(module: dict, week_number: int | None) -> dict | None:
    """The period a program week falls in, for a module whose weeks repeat in
    a cycle (BJJ's StrengthLog block: six weeks of strength, a deload week,
    five of power, then again); None for a module without periods."""
    periods = module.get('periods')
    if not periods or week_number is None:
        return None
    left = (week_number - 1) % sum(p['weeks'] for p in periods)
    for p in periods:
        if left < p['weeks']:
            return p
        left -= p['weeks']


def in_phase(module: dict, phase_id: str | None) -> dict | None:
    """The module as it runs in a phase, or None where it does not run: a
    module may name its `phases` (Uphill's General Strength runs in
    Transition, its muscular endurance in Specific) and its weekly exposures
    per phase (`exposures_by_phase`), and the module whose day it sits beside
    in a phase (`adjacent_to_by_phase`: Uphill's back-to-back long days)."""
    if module.get('phases') and phase_id not in module['phases']:
        return None
    n = (module.get('exposures_by_phase') or {}).get(phase_id)
    out = {**module, 'exposures_per_week': n} if n is not None else module
    beside = (module.get('adjacent_to_by_phase') or {}).get(phase_id)
    return {**out, 'adjacent_to': beside} if beside else out


def module_week(module: dict, week_in_program: int, week_in_phase: int) -> int:
    """The week a module counts its periods by: its phase's week when it runs
    in named phases (the General Strength laps of Transition's weeks), else
    the program's."""
    return week_in_phase if module.get('phases') else week_in_program


def at_step(module: dict, step: int, week_number: int | None = None, offset: int = 0) -> dict:
    """The module as it runs at an exposure: a module with variants takes the
    one its rotation names (A, B, A, B … — so a week is A-B-A, the next B-A-B),
    the rotation of the week's period when it has periods. A deload advances
    no exposure, so its sessions take the next variants by `offset`, their
    order in the week. A deload period that names its own rotation runs those
    workouts as written (`written_deload`): StrengthLog's deload week has its
    own exercises, sets and reps, cut by nothing. A rotation that `holds`
    stays on its last variant once it gets there (the tenth workout of
    Uphill's muscular-endurance progression)."""
    period = period_of(module, week_number)
    if (period or {}).get('note'):
        # What the period asks of every block (Persist's Bridge week: RPE 6–7).
        module = {**module, 'period_note': period['note']}
    rotation = (period or {}).get('rotation') or module.get('rotation')
    if not module.get('variants') or not rotation:
        return module
    index = step + offset
    vid = rotation[min(index, len(rotation) - 1) if module.get('rotation_holds') else index % len(rotation)]
    variant = next(v for v in module['variants'] if v['id'] == vid)
    return {**module, 'blocks': variant['blocks'], 'variant': vid,
            'name': variant.get('name', module['name']),
            'archetype_id': variant.get('archetype_id', module['archetype_id']),
            'written_deload': bool(period and period.get('deload') and period.get('rotation'))}


# ── Weekly volume (Uphill) ───────────────────────────────────────────────────
#
# The week's aerobic minutes build `ramp_pct` a week for `build_weeks` weeks,
# then a recovery week runs at `recovery_pct` of the hardest of them; the
# next block starts one step above the last. A module takes its `share` of
# the week per session — the long day half (`share: 0.5`), the easy days what
# the others leave (`share: rest`) — on the block marked `volume`. The minutes
# follow the calendar, never confirmations, and a session longer than the
# athlete's longest day is capped there, and the program says so.

def _volume_exponent(week: int, build_weeks: int) -> int:
    """How many ramp steps a build week stands above week 1."""
    recoveries = (week - 1) // (build_weeks + 1)
    return (week - 1 - recoveries) - (build_weeks - 1) * recoveries


def ramp_level(progression: dict, level: str, week: int) -> float:
    """The build-week minutes the ramp stands at in `week`: its own in a build
    week, the last build week's in a recovery week (the start before week 1)."""
    build = progression['build_weeks']
    last = week
    while last >= 1 and last % (build + 1) == 0:
        last -= 1
    return progression['start_minutes'][level] * (1 + progression['ramp_pct'] / 100) ** (
        _volume_exponent(last, build) if last >= 1 else 0)


def weekly_minutes(progression: dict, level: str, week: int, deload: bool,
                   phase_id: str | None = None, week_in_phase: int = 1, held: float | None = None) -> float:
    """The week's aerobic minutes: the ramp for a build week; a recovery week
    (or any deload) at `recovery_pct` of the last build week before it. In a
    phase outside `ramp_phases` the minutes hold where the ramp stopped
    (`held`, else the week before the phase) — Uphill's Specific: intensity
    rises, volume does not — and a deload there is a share of that."""
    recovery = progression['recovery_pct'] / 100
    ramping = progression.get('ramp_phases')
    if ramping and phase_id not in ramping:
        base = held if held is not None else ramp_level(progression, level, week - week_in_phase)
        return base * (recovery if deload else 1)
    if not deload:
        return progression['start_minutes'][level] * (1 + progression['ramp_pct'] / 100) ** \
            _volume_exponent(week, progression['build_weeks'])
    return ramp_level(progression, level, week - 1) * recovery


def volume_share(module: dict, week_modules: list) -> float:
    """A session's share of the week's volume; `rest` is what the week's other
    volume modules leave, over this module's sessions."""
    share = module['progression']['share']
    if share != 'rest':
        return share
    taken = sum(m['progression']['share'] * m['exposures_per_week'] for m in week_modules
                if m['progression']['model'] == 'weekly_volume' and m['progression']['share'] != 'rest')
    return max(0.0, 1 - taken) / module['exposures_per_week']


def hold_volume(held: dict, modules: list, level: str, week: int, phase_id: str | None) -> None:
    """Where each volume module's ramp stands after a week of a ramping phase,
    which a later phase outside `ramp_phases` holds at."""
    for m in modules:
        p = m['progression']
        if p['model'] == 'weekly_volume' and (not p.get('ramp_phases') or phase_id in p['ramp_phases']):
            held[m['id']] = ramp_level(p, level, week)


def with_volume(module: dict, level: str, week: int, deload: bool, longest: float, week_modules: list,
                phase_id: str | None = None, week_in_phase: int = 1, held: dict | None = None) -> dict:
    """The module with its volume block's minutes for the week (capped at the
    athlete's longest day, `volume_capped` saying from what), and the pack
    its `pack_pct` names for the week. A deload's minutes are the recovery
    week's, so nothing cuts them again (`written_deload`)."""
    p = module['progression']
    if p['model'] != 'weekly_volume':
        return module
    minutes = max(1, round(weekly_minutes(p, level, week, deload, phase_id, week_in_phase,
                                          (held or {}).get(module['id']))
                           * volume_share(module, week_modules)))
    fixed = sum(math.ceil(b.get('duration_sec', 0) / 60) for b in module['blocks'] if not b.get('volume'))
    room = max(1, int(longest - fixed))
    pack = None
    for start, pct in p.get('pack_pct') or []:
        if week >= start:
            pack = pct
    blocks = []
    for b in module['blocks']:
        if b.get('volume'):
            b = {**b, 'duration_sec': min(minutes, room) * 60}
            if pack is not None:
                note = 'No pack yet.' if not pack else f'Pack: {pack:g} % of your bodyweight.'
                b['notes'] = f"{b.get('notes', '')} {note}".strip()
        blocks.append(b)
    return {**module, 'blocks': blocks, 'written_deload': deload,
            'volume_capped': minutes if minutes > room else None}


# ── Load per confirmed exposure (Starting Strength) ──────────────────────────
#
# Each lift carries {next_kg, kg, exposures, failures, resets, stalled}:
# `next_kg` is what its next progressing exposure prescribes, `kg` the last
# weight made (the basis of a percentage block: the Texas Method's Monday is
# about 90 % of the five-rep max). A made exposure adds the lift's increment —
# the first `first_exposures` at the larger step, a step smaller after each
# reset; a miss repeats the weight; `stall.failures` misses in a row reset it
# by `stall.reset_pct`, and a lift that stalls again after `stall.resets`
# resets has finished its novice progression and holds (Alter, "The Reset").
# Each reset may change how the lift runs (`with_stall`): a light day in the
# week (`stall.light_day`), then a set scheme (`stall.scheme`, 5×3).
# A lift with no weight yet is worked up to on the day and recorded.

def _advancing(block: dict) -> bool:
    """A loaded block at full weight carries its lift forward; a percentage
    block (the Texas Method's volume and light days) reads it."""
    return bool(block.get('loaded')) and block.get('advances', block.get('pct', 1) == 1)


def _round_kg(kg: float, step: float) -> float:
    return round(round(kg / step) * step, 2)


def lift_increment(module: dict, lift: str, exposures: int, resets: int) -> float:
    """The kg a lift adds after its `exposures`-th made exposure."""
    spec = (module['progression'].get('lifts') or {}).get(lift) or {}
    steps = spec.get('increments_kg') or [0]
    first = spec.get('first_exposures')
    index = (1 if first is not None and exposures >= first else 0) + resets
    return steps[min(index, len(steps) - 1)]


def apply_lift_outcome(module: dict, lift: str, record: dict, made: bool, kg: float) -> None:
    """One confirmed exposure of a lift, made or missed at `kg`."""
    p = module['progression']
    step = p.get('round_kg', 1.25)
    record.setdefault('exposures', 0)
    record.setdefault('failures', 0)
    record.setdefault('resets', 0)
    if made:
        record['kg'] = kg
        record['exposures'] += 1
        record['failures'] = 0
        record['next_kg'] = kg if record.get('stalled') else _round_kg(
            kg + lift_increment(module, lift, record['exposures'], record['resets']), step)
        return
    record['failures'] += 1
    record['next_kg'] = kg
    stall = p.get('stall')
    if stall and record['failures'] >= stall['failures']:
        record['failures'] = 0
        if record['resets'] >= stall.get('resets', 1):
            record['stalled'] = True
        else:
            record['resets'] += 1
            record['next_kg'] = _round_kg(kg * (1 - stall['reset_pct'] / 100), step)


def with_stall(module: dict, state: dict, step: int, position: int, light_steps=()) -> dict:
    """The module as its lifts' resets run it at the week's `position`-th
    exposure (Alter, "The Reset"): from `stall.scheme.after_resets` resets a
    named lift runs the scheme's sets and reps (5×3); from
    `stall.light_day.after_resets` the week's `exposure`-th session lifts it
    light — a share of the last weight made, not advancing it. The module
    carries the light lift (`light_day`) and the program's earlier light
    exposures (`light_steps`), which lift_forecast steps over."""
    stall = module['progression'].get('stall') or {}
    scheme, day = stall.get('scheme'), stall.get('light_day')
    if not (scheme or day):
        return module

    def resets(lift: str) -> int:
        return ((state.get('lifts') or {}).get(lift) or {}).get('resets', 0)

    blocks, light = [], None
    for b in module['blocks']:
        lift = b.get('exercise_id')
        if _advancing(b) and scheme and lift in scheme['lifts'] and resets(lift) >= scheme['after_resets']:
            b = {**b, 'sets': scheme['sets'], 'reps': scheme['reps']}
        if (_advancing(b) and day and lift == day['lift'] and position == day['exposure']
                and resets(lift) >= day['after_resets']):
            b = {**b, 'sets': day['sets'], 'reps': day['reps'], 'pct': day['pct'], 'advances': False,
                 'duration_sec': b['duration_sec'] * day['sets'] // b['sets'],
                 'notes': day.get('note') or b.get('notes', '')}
            light = lift
        blocks.append(b)
    return {**module, 'blocks': blocks, 'light_day': light, 'light_steps': frozenset(light_steps)}


def lift_forecast(module: dict, state: dict, step: int) -> dict:
    """Every lift as it stands at `step`, forecast from the confirmed state on
    the assumption that each exposure between is made (the program says so:
    `conditional`); a light day's lift stays where it was."""
    lifts = deepcopy(state.get('lifts') or {})
    light = ((module['progression'].get('stall') or {}).get('light_day') or {}).get('lift')
    for s in range(state.get('completed', 0), step):
        for b in at_step(module, s)['blocks']:
            if not _advancing(b) or (s in module.get('light_steps', ()) and b['exercise_id'] == light):
                continue
            record = lifts.setdefault(b['exercise_id'], {})
            if record.get('next_kg') is None:
                record['exposures'] = record.get('exposures', 0) + 1
                continue
            apply_lift_outcome(module, b['exercise_id'], record, True, record['next_kg'])
    return lifts


def _lift_outcome(outcome: dict, prescribed: dict) -> tuple[bool | None, float | None]:
    """(made, kg) from a logged exercise: the one-tap answer's `made`, else the
    logged sets — every prescribed set completed at its reps — else unknown."""
    if not isinstance(outcome, dict):
        return None, None
    sets = [s for s in outcome.get('sets') or [] if isinstance(s, dict)]
    weights = [s['weightKg'] for s in sets if isinstance(s.get('weightKg'), (int, float))
               and not isinstance(s.get('weightKg'), bool) and math.isfinite(s['weightKg']) and s['weightKg'] > 0]
    kg = outcome.get('weightKg')
    if isinstance(kg, bool) or not isinstance(kg, (int, float)) or not math.isfinite(kg) or kg <= 0:
        kg = max(weights) if weights else prescribed.get('kg')
    if isinstance(outcome.get('made'), bool):
        return outcome['made'], kg
    if not sets:
        return None, kg
    reps = prescribed.get('reps')
    done = [s for s in sets if s.get('completed') is True
            and (not isinstance(reps, int) or not isinstance(s.get('repsActual'), int) or s['repsActual'] >= reps)]
    return len(done) >= (prescribed.get('sets') or 1), kg


def seed_lifts(current: dict, logs: dict, module: dict) -> dict:
    """Each lift's state from the athlete's last logged working sets in a
    program that ran before this contract (Starting Strength's linear
    progression before 2026-10-20): the weight goes up from what was last
    lifted, or repeats it if the sets were not all made."""
    out: dict = {}
    lifts = set((module['progression'].get('lifts') or {}))
    day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    for week in current.get('weeks') or []:
        schedule = week.get('schedule') or {}
        for day in sorted(schedule, key=lambda d: d if isinstance(d, int) else day_order.index(d) + 1):
            name = day_order[day - 1] if isinstance(day, int) else day
            for si, session in enumerate(schedule[day]):
                key = f"{week['week_number']}-{name}-{si}"
                log = logs.get(key) or (logs.get(f"{week['week_number']}-{name}") if si == 0 else {}) or {}
                for ea in session.get('exercises') or []:
                    eid = (ea.get('exercise') or {}).get('id')
                    if eid not in lifts:
                        continue
                    load = ea.get('load') or {}
                    made, kg = _lift_outcome((log.get('exercises') or {}).get(eid) or {},
                                             {'kg': None, 'sets': load.get('sets'), 'reps': load.get('reps')})
                    if made is None or kg is None:
                        continue
                    record = out.setdefault(eid, {})
                    apply_lift_outcome(module, eid, record, made, kg)
    return out


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
    specs = {m['id']: m for m in contract['modules']}
    day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    for week in current.get('weeks') or []:
        schedule = week.get('schedule') or {}
        for day in sorted(schedule, key=lambda d: d if isinstance(d, int) else day_order.index(d) + 1):
            name = day_order[day - 1] if isinstance(day, int) else day
            for si, session in enumerate(schedule[day]):
                if session.get('test'):
                    continue
                key = f"{week['week_number']}-{name}-{si}"
                log = logs.get(key) or (logs.get(f"{week['week_number']}-{name}") if si == 0 else {}) or {}
                if not log.get('completedAt'):
                    continue
                for module in session.get('modules') or []:
                    # A deload advances nothing; each module record says
                    # whether it deloaded (older programs: the session does).
                    if module.get('deload', session.get('is_deload')):
                        continue
                    mid = module['id']
                    record = state.setdefault(mid, {'completed': 0})
                    if module.get('forecast_step') != record.get('completed', 0):
                        continue
                    spec = specs.get(mid) or {}
                    if spec.get('progression', {}).get('model') == 'load_per_exposure':
                        # Attendance moves the rotation (A, then B); each lift
                        # moves on its own outcome — a missed squat does not
                        # hold back the press. A lift with no outcome holds.
                        record['completed'] += 1
                        for eid, prescribed in (module.get('lifts') or {}).items():
                            made, kg = _lift_outcome((log.get('exercises') or {}).get(eid) or {}, prescribed)
                            if made is None or kg is None:
                                continue
                            lift = record.setdefault('lifts', {}).setdefault(prescribed.get('lift', eid), {})
                            apply_lift_outcome(spec, prescribed.get('lift', eid), lift, made, kg)
                        continue
                    if spec.get('variants') and not module['exercise_ids']:
                        # Workouts that alternate with nothing to earn (BJJ's
                        # StrengthLog sessions, weights the athlete's own):
                        # attending moves the rotation on.
                        record['completed'] += 1
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


def confirmation_outcomes(session: dict, clean: bool, rpe: int | None,
                          logged: dict | None = None, lifts: dict | None = None) -> dict:
    """What "done as written" logs for a session's modules: each progressing
    exercise's prescribed rounds or seconds (the module record's
    `requirements`), whether it was clean, and the RPE — merged into whatever
    was logged for it already (sets, a bell), which wins where it says more.

    A loaded lift (Starting Strength) logs `made` and the weight instead:
    `lifts` — {exercise id: {made, weightKg}} — names the ones that went
    otherwise than written (a missed squat, a heavier press) and every lift it
    does not name was made; without it, `clean` says for all of them. Its sets
    are written at that weight unless sets were logged already.

    The athlete's one-tap answer after a session: a watch-recorded or linked
    workout logs no per-exercise outcome, so without it no exposure was ever
    confirmed and every regenerate started each cycle again (2026-10-20)."""
    logged = logged or {}
    named = lifts is not None
    lifts = lifts or {}
    out: dict = {}
    for record in session.get('modules') or []:
        for eid, prescribed in (record.get('lifts') or {}).items():
            entry = dict(logged.get(eid) or {})
            given = lifts.get(eid) or {}
            made = given['made'] if isinstance(given.get('made'), bool) else (named or bool(clean))
            kg = given.get('weightKg', entry.get('weightKg', prescribed.get('kg')))
            entry['made'] = made
            if kg is not None:
                entry['weightKg'] = kg
            if not entry.get('sets'):
                reps = prescribed.get('reps')
                entry['sets'] = [{'setIndex': i, 'weightKg': kg, 'completed': made,
                                  **({'repsActual': reps} if made and isinstance(reps, int) else {})}
                                 for i in range(prescribed.get('sets') or 1)]
            entry['clean'] = bool(clean)
            if rpe is not None:
                entry['rpe'] = rpe
            out[eid] = entry
        for eid, req in (record.get('requirements') or {}).items():
            if eid in (record.get('lifts') or {}):
                continue
            entry = dict(logged.get(eid) or {})
            if req.get('duration_sec'):
                entry.setdefault('durationSec', req['duration_sec'])
            else:
                entry['rounds'] = max(entry.get('rounds') or 0, req.get('rounds') or 1)
            entry['clean'] = bool(clean)
            if rpe is not None:
                entry['rpe'] = rpe
            out[eid] = entry
    return out


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


def _inventory(module: dict, constraints: dict) -> list | None:
    """The weights the athlete owns of the module's implement
    (`<equipment>_weights_kg`), or None when they did not say."""
    from . import implements
    eq = (module.get('implement') or {}).get('equipment')
    return constraints.get(implements.weights_key(eq)) if eq else None


def _bell(module: dict, constraints: dict, state: dict) -> float | None:
    """The module's weight of its implement (a bell, for Wildman), checked
    against what the athlete owns."""
    from . import implements
    eq = (module.get('implement') or {}).get('equipment')
    one = implements.noun(eq)[0] if eq else 'implement'
    inventory = _inventory(module, constraints)
    if inventory is not None and (not isinstance(inventory, list) or not inventory or any(isinstance(w, bool) or not isinstance(w, (int, float))
                                                     or not math.isfinite(w) or w <= 0 for w in inventory)):
        raise ContractError(f'{implements.weights_key(eq)} must contain positive {one} weights.')
    weight = state.get('weight_kg')
    if weight is not None and (isinstance(weight, bool) or not isinstance(weight, (int, float))
                               or not math.isfinite(weight) or weight <= 0):
        raise ContractError('A module weight must be a positive number.')
    if weight is not None and inventory is not None and weight not in inventory:
        raise ContractError(f"{module['id']}: the selected {one} is not in the available inventory.")
    # An equipment item says nothing about owned sizes. Never invent a
    # fractional weight or infer a safe working load from an athlete's level.
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


def _injured(ex: dict, constraints: dict, blocked: tuple | None) -> bool:
    """Whether the athlete's injuries (or avoided movements) alone rule the
    exercise out, whatever the equipment."""
    return blocked is not None and _ruled_out(ex, {**constraints, 'equipment': list(ex.get('equipment') or [])}, blocked)


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


def module_deload(module: dict, week_number: int, forced: bool, week_deload: bool) -> bool:
    """Whether a module deloads this program week. A module with `periods`
    deloads in its deload period in place of the framework's cadence (BJJ's
    strength in StrengthLog's seventh week, while the mat carries on); fatigue
    or a deload phase (`forced`) deloads every module."""
    if forced:
        return True
    period = period_of(module, week_number)
    return bool(period.get('deload')) if period is not None else week_deload


def _cuts(module: dict, deload: bool) -> bool:
    """Whether a deload cuts the module's blocks to their `deload_keep` share;
    a deload period's own workouts run as written."""
    return deload and not module.get('written_deload')


def _assignment(block: dict, module: dict, exercises: dict, constraints: dict,
                state: dict, step: int, deload: bool, blocked: tuple | None = None,
                advise: bool = True) -> dict:
    eid = _choose(block, module, exercises, constraints, blocked)
    ex = exercises[eid]
    if not _equipment_ok(ex, set(constraints.get('equipment') or [])):
        have = set(constraints.get('equipment') or [])
        missing = [item for item in ex.get('equipment') or [] if item not in have]
        raise ContractError(f"{module['id']}: {ex.get('name', eid)} needs {', '.join(missing) or 'equipment'}, "
                            'which is not in your equipment.')
    slot = {'role': f"{module['id']}_{block['role']}", 'slot_type': block['slot_type'],
            'notes': block.get('notes', ''), 'exercise_filter': {'exercise_ids': [eid]}}
    if 'standard' in block:
        slot['standard'] = block['standard']
    if block.get('switch_at_sec'):
        # The scored protocol's hand switch (the watch cue), carried with the test.
        slot['switch_at_sec'] = block['switch_at_sec']
    cut = _cuts(module, deload)
    if block['slot_type'] in ('sets_reps', 'static_hold'):
        # Strength and holds: at a prescribed effort the athlete chooses the
        # load that meets the RPE and records it (RPE autoregulation); a block
        # may instead say how the load is chosen (`load_note`). A deload keeps
        # its share of the sets. The block's minutes include its rests.
        sets = block['sets']
        if cut:
            sets = max(1, math.floor(sets * _keep(block, module)))
        rest = block.get('rest_sec', 60)
        if block['slot_type'] == 'sets_reps':
            # Chin-ups "to failure, each set" (Rippetoe) are sets of `max`; a
            # range or a distance is written as the source writes it ("6-8", "20 m").
            load = {'sets': sets, 'reps': 'max' if block.get('to_failure') else block['reps'], 'rest_sec': rest}
            per_set = block['duration_sec'] / block['sets']
        else:
            load = {'sets': sets, 'hold_seconds': block['hold_sec'], 'rest_sec': rest}
            per_set = block['hold_sec'] + rest
        if block.get('load_note'):
            load['load_note'] = block['load_note']
        elif block.get('rpe_target') is not None:
            load['target_rpe'] = block['rpe_target']
            load['load_note'] = f"Choose the load you finish at RPE {block['rpe_target']:g}, and record it."
        seconds = math.ceil(sets * per_set / 60) * 60
        load['duration_minutes'] = seconds // 60
    elif block['slot_type'] == 'emom':
        rounds, reps, interval, cue = _stage(module['progression'], step, _interval_budget(module, constraints))
        if cut:
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
        if cut and not block.get('standard'):
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
    by_load = module['progression']['model'] == 'load_per_exposure'
    weight = None if by_load else _bell(module, constraints, state)
    if by_load and block.get('loaded'):
        load.update(_lift_load(block, module, exercises, state, step))
    elif block.get('loaded'):
        if weight is not None:
            load['weight_kg'] = weight
        from . import implements
        implement = module.get('implement') or {}
        one, many = implements.noun(implement['equipment']) if implement.get('equipment') else ('implement', 'implements')
        count = implement.get('count', 1)
        load['load_note'] = ((f'Use {implements.number(count)} matching {many}; selected weight is per {one}. '
                              'Finish repetitions cleanly, then rest.'
                              if count > 1 else
                              f'Use the selected single {one}; finish repetitions with clean mechanics, then rest.')
                             if weight is not None else
                             f'Choose a {one} you can control throughout. Record its weight before increasing load.')
    if block['slot_type'] == 'emom' and load.get('focus'):
        # The stage's cue leads the note both clients show (start/stop).
        load['load_note'] = f"{load['focus']} {load.get('load_note') or ''}".strip()
    load.update(prescription_version=1, progression_model=module['progression']['model'],
                module_id=module['id'], forecast_step=step,
                advances_module=_advancing(block) if by_load else _progresses(block),
                conditional=step != state.get('completed', 0), elapsed_sec=seconds)
    if module.get('period_note') and not block.get('standard'):
        load['load_note'] = f"{module['period_note']} {load.get('load_note') or ''}".strip()
    if advise and module.get('advice') and load['advances_module']:
        # The method's recommendation, left to the athlete: said where the
        # block is read (the module's first advancing block of the session,
        # once), never acted on by the cursor.
        load['load_note'] = f"{load.get('load_note') or ''} {module['advice']}".strip()
    return {'slot_role': slot['role'], 'slot_type': slot['slot_type'], 'slot': slot,
            'exercise': ex, 'load': load, **({'standard': block['standard']} if block.get('standard') else {})}


def _lift_load(block: dict, module: dict, exercises: dict, state: dict, step: int) -> dict:
    """A loaded block's weight by the lift's forecast: the next weight for a
    progressing block, a share of the last one made for a percentage block,
    a work-up on the day when the lift has no weight yet."""
    lift = block['exercise_id']
    record = lift_forecast(module, state, step).get(lift) or {}
    increment = lift_increment(module, lift, record.get('exposures', 0) + 1, record.get('resets', 0))
    name = (exercises.get(lift) or {}).get('name', lift)
    step_kg = module['progression'].get('round_kg', 1.25)
    out: dict = {'lift': lift}
    if _advancing(block):
        kg = record.get('next_kg')
        out['increment_kg'] = increment
        if kg is not None:
            out['weight_kg'] = kg
            out['load_note'] = (f"{kg:g} kg." if record.get('stalled')
                                else f"{kg:g} kg. Make every rep and next time it is {increment:g} kg more.")
        elif not record.get('exposures'):
            out['work_up'] = True
            reps = block.get('reps') or 5
            out['load_note'] = (f"Work up from the empty bar in sets of {reps}, in small jumps. "
                                + ("The weight that feels heavy but keeps your form is today's: do the rest of "
                                   'the sets there, and record it.' if (block.get('sets') or 1) > 1 else
                                   "The heaviest set you make with good form is today's: record it."))
        else:
            # What the last made exposure added, not what this one will.
            added = lift_increment(module, lift, record['exposures'], record.get('resets', 0))
            out['load_note'] = (f"{added:g} kg more than your last {name} "
                                f"{block.get('sets') or 1}×{block.get('reps')}.")
    else:
        pct = block.get('pct', 1)
        basis = record.get('kg') if record.get('kg') is not None else record.get('next_kg')
        if basis is not None:
            out['weight_kg'] = _round_kg(basis * pct, step_kg)
            out['load_note'] = f"{pct:.0%} of your current {name}."
        else:
            out['load_note'] = f"About {pct:.0%} of your five-rep max; record the weight."
    if record.get('stalled'):
        out['stalled'] = True
        out['load_note'] += (' This lift stalled again after a reset: its novice progression is over, and '
                             'the Texas Method carries it on.')
    return out


def _progresses(block: dict) -> bool:
    """A loaded block (the bell) or one declared to progress without a bell
    (an easy run's minutes) carries the module's progression."""
    return bool(block.get('loaded') or block.get('progresses'))


def _module_rows(module, exercises, constraints, state, step, deload, blocked=None, left_out=None):
    """A module's assignments. A block the package marks `optional` that none of
    its options fits (a dead hang under a shoulder-instability flag) is left out
    and named in `left_out`; an essential one still refuses."""
    rows = []
    advised = False
    for block in module['blocks']:
        if _cuts(module, deload) and not block.get('standard') and _keep(block, module) == 0:
            continue
        if block.get('optional') and all(
                eid in exercises and _ruled_out(exercises[eid], constraints, blocked) for eid in block_options(block)):
            if left_out is not None:
                left_out.append(f"{module['name']}: {exercises.get(block['exercise_id'], {}).get('name', block['exercise_id'])} "
                                'left out — no option fits the equipment or injuries')
            continue
        if module.get('drop_when_injured') and all(
                eid in exercises and _injured(exercises[eid], constraints, blocked) for eid in block_options(block)):
            # The athlete's call (BJJ): a lift the injury rules out goes, the
            # rest of the workout stays; missing equipment still refuses.
            if left_out is not None:
                left_out.append(f"{module['name']}: {exercises.get(block['exercise_id'], {}).get('name', block['exercise_id'])} "
                                'left out — your injury rules it out')
            continue
        row = _assignment(block, module, exercises, constraints, state, step, deload, blocked, advise=not advised)
        advised = advised or bool(row['load'].get('advances_module'))
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


def _spacing(candidate: dict, regions: dict | None = None,
             others: dict | None = None) -> tuple[int, int, int, int]:
    """How well a placement alternates and spreads its work, higher is better:
    fewest same-modality days back to back (two gym sessions, a run of
    classes), then fewest same-modality neighbours among the training days,
    the week wrapping into the next (swing, swing, press, press reads worse
    than swing, press, swing, press), then the fewest body regions loaded
    heavily on days a day or two apart (`regions`: module id -> heavy regions,
    src/recovery_regions.py; a day apart counts twice), then the widest gap
    between each module's own sessions (Wildman: "Kettlebell Swings on Monday
    & Thursday, Clean & Press on Wednesday & Saturday"). In a composition,
    `others` is {day: heavy regions} of the other tracks' work, and loading a
    region beside (or on) a day they load it counts against the placement too."""
    days = sorted(candidate)
    kind = {d: frozenset(m['modality'] for m in candidate[d]) for d in days}
    pairs = list(zip(days, days[1:] + days[:1])) if len(days) > 1 else []
    adjacent = sum(1 for a, b in pairs if (b - a) % 7 == 1 and kind[a] == kind[b])
    neighbours = sum(1 for a, b in pairs if kind[a] == kind[b])
    on: dict[str, list[int]] = {}
    for d in days:
        for m in candidate[d]:
            on.setdefault(m['id'], []).append(d)
    spread = sum(min((b - a) % 7 or 7 for a, b in zip(ds, ds[1:] + ds[:1])) for ds in on.values())
    load = {d: frozenset().union(*((regions or {}).get(m['id'], frozenset()) for m in candidate[d])) for d in days}
    regional = sum((3 - gap) * len(load[a] & load[b]) for i, a in enumerate(days) for b in days[i + 1:]
                   for gap in [min(b - a, 7 + a - b)] if gap <= 2)
    regional += sum((3 - gap) * len(load[a] & theirs) for a in days for b, theirs in (others or {}).items()
                    for gap in [min(abs(b - a), 7 - abs(b - a))] if gap <= 2)
    return -adjacent, -neighbours, -regional, spread


def _placements(modules: list, durations: dict, pool: list[int], cap: float, day_caps: dict | None = None):
    """Every placement of the essential modules that keeps their exposures,
    spacing and each day's budget (`day_caps`, within the session cap: a long
    day goes where the athlete has the time), in preference order; it never
    substitutes a modality."""
    result = {d: [] for d in pool}
    totals = {d: 0 for d in pool}
    limit = {d: min(cap, (day_caps or {}).get(d, cap)) for d in pool}

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
            if any(totals[d] + durations[m['id']] > limit[d] for d in days):
                continue
            beside = {d for d, ms in result.items() if any(x['id'] == m.get('adjacent_to') for x in ms)}
            if beside and not all(d - 1 in beside or d + 1 in beside for d in days):
                # Placed after the module it sits beside (the contract's order).
                continue
            for d in days:
                result[d].append(m); totals[d] += durations[m['id']]
            yield from assign(index + 1)
            for d in days:
                result[d].pop(); totals[d] -= durations[m['id']]
    yield from assign(0)


def _week_span(weeks: list[int]) -> str:
    """"week 3", "weeks 1–2", "weeks 1–2 and 5"."""
    runs: list[list[int]] = []
    for w in sorted(set(weeks)):
        if runs and w == runs[-1][-1] + 1:
            runs[-1].append(w)
        else:
            runs.append([w])
    parts = [f"{r[0]}–{r[-1]}" if len(r) > 1 else str(r[0]) for r in runs]
    text = parts[0] if len(parts) == 1 else ', '.join(parts[:-1]) + ' and ' + parts[-1]
    return ('week ' if len(runs) == 1 and len(runs[0]) == 1 else 'weeks ') + text


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
    mat sessions grow with the week; 0 leaves a module out), and the
    implement the track's loaded blocks use (`implement`: a pair of bells for
    Wildman's double-bell track). The compiler and the verifier read the same
    list."""
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
        if contract.get('implement'):
            m = {**m, 'implement': contract['implement']}
        out.append(m)
    return out


def _level_refusal(contract: dict, level: str) -> str:
    """Why a level is refused, naming the package's track written for it if
    there is one (an intermediate on Starting Strength's novice progression
    is sent to the Texas Method), else the levels its tracks are written for."""
    from . import loader
    phil = loader.load_philosophy(contract['package'])
    names = {t['id']: t.get('name', t['id']) for t in phil.get('tracks') or []}
    this = names.get(contract['track_id'], contract['track_id'])
    document = _document(os.path.join(loader._PACKAGES_DIR, contract['package'], 'training_contract.yaml'))
    fits = [tid for tid, t in (document.get('tracks') or {}).items() if level in (t.get('training_levels') or [])]
    levels = contract['training_levels']
    who = levels[0] if len(levels) == 1 else f"{', '.join(levels[:-1])} and {levels[-1]}"
    if fits:
        return f"{this} is written for {who} athletes; at {level}, {names.get(fits[0], fits[0])} is the track for you."
    written = sorted({lv for t in (document.get('tracks') or {}).values() for lv in t.get('training_levels') or []},
                     key=_levels.rank)
    return (f"{this} is written for {who} athletes, and no track of this "
            f"program is written for {level} (they cover {', '.join(written)}).")


def start(contract: dict, entries: list, constraints: dict, data: dict, policy,
          frameworks: dict) -> 'ContractRun':
    """The contract ready to compile week by week: `week(entry)` places and
    emits one week (appending it to `program`), `finish()` closes the program.
    A composition (src/composition.py) passes each week the `day_room` its other
    tracks leave on each day and their work (`others`); alone, neither."""
    from .scheduler import _build_day_pool
    if len(policy.owner_packages) > 1:
        raise ContractError('Module contracts currently support one methodology at a time; a blend needs an explicit composition contract.')
    level = constraints.get('training_level', 'intermediate')
    if level not in contract['training_levels']:
        raise ContractError(_level_refusal(contract, level))
    implement = contract.get('implement') or {}
    if implement.get('count', 1) > 1:
        from . import implements
        need, key = implement['count'], implements.count_key(implement['equipment'])
        count = constraints.get(key, 0)
        if isinstance(count, bool) or not isinstance(count, int) or count < need:
            raise ContractError(f'This track requires {implements.number(need)} matching '
                                f"{implements.plural_label(implement['equipment'])}; confirm {key} of at least {need}.")
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
    # Each module's heavily loaded regions, read from its archetype, so the
    # placement keeps two leg-heavy programs off neighbouring days when it can.
    archetype_of = {a['id']: a for a in data['archetypes'] if a.get('_package') == contract['package']}
    module_regions = {m['id']: recovery_regions.heavy(recovery_regions.archetype_load(
        archetype_of[m['archetype_id']], data['exercises'], data['modalities'])) for m in modules}
    supplied = constraints.get('module_progression_state') or {}
    if not isinstance(supplied, dict):
        raise ContractError('Module progression state must be an object keyed by module id.')
    state = deepcopy(supplied)
    for m in modules:
        value = state.setdefault(m['id'], {'completed': 0})
        if not isinstance(value, dict) or isinstance(value.get('completed', 0), bool) or not isinstance(value.get('completed', 0), int) or value.get('completed', 0) < 0:
            raise ContractError('Module completed exposures must be nonnegative integers.')
    # The weight the athlete last made on a lift (the builder's optional
    # starting weights: a novice's last work sets, an intermediate's five-rep
    # max), for a lift that has none yet: the next session adds to it.
    # Without one, the lift's first session works up to a weight.
    starting = constraints.get('starting_loads_kg') or {}
    if not isinstance(starting, dict) or any(isinstance(v, bool) or not isinstance(v, (int, float))
                                             or not math.isfinite(v) or v <= 0 for v in starting.values()):
        raise ContractError('starting_loads_kg must map exercise ids to positive weights.')
    for m in modules:
        if m['progression']['model'] != 'load_per_exposure':
            continue
        for lift in m['progression'].get('lifts') or {}:
            record = state[m['id']].setdefault('lifts', {}).setdefault(lift, {})
            if record.get('next_kg') is None and starting.get(lift) is not None:
                kg = _round_kg(starting[lift], m['progression'].get('round_kg', 1.25))
                record.update(kg=kg, next_kg=_round_kg(kg + lift_increment(m, lift, 0, 0),
                                                       m['progression'].get('round_kg', 1.25)))
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
    # Each module's minutes in the last week nothing deloaded.
    build_minutes: dict[str, float] = {}
    # Optional work left short: (module, placed, of, reason) -> its weeks.
    shortfalls: dict[tuple, list[int]] = {}
    # Each module's light exposures so far (with_stall), which its forecast steps over.
    light_steps: dict[str, set] = {m['id']: set() for m in modules}
    all_modules = modules
    # The longest day the athlete has: a volume session is capped there.
    longest = min(cap, max((constraints.get('day_configs', {}).get(d) or {}).get('minutes', cap) for d in pool))
    program['training_contract']['longest_minutes'] = longest
    capped_said: set = set()
    held: dict = {}

    def week(entry: dict, day_room: dict | None = None, others: dict | None = None,
             essential_days=None, search: int = 500) -> dict:
        """Place and emit one week of the contract; `day_room` caps each day's
        minutes below its own budget, `others` is {day: heavy regions} of the
        work already there, which this week's placement steers clear of, and
        `essential_days` (when given) the only days its essential work may
        take — optional work may still go wherever there is room. `search` is
        how many placements are looked at."""
        nonlocal previous
        fw = frameworks[entry['framework_id']]
        # The modules this phase runs (`phases`), with its exposures.
        modules = [w for w in (in_phase(m, entry.get('phase_id')) for m in all_modules) if w]
        essential = [m for m in modules if not m.get('optional')]
        hold_volume(held, modules, level, entry['week_in_program'], entry.get('phase_id'))
        weeks_of = {m['id']: module_week(m, entry['week_in_program'], entry['week_in_phase']) for m in modules}
        frequency = (fw.get('deload_protocol') or {}).get('frequency_weeks')
        forced = (constraints.get('fatigue_state') == 'overreached'
                  or entry.get('phase_id') in contract.get('deload_phases', []))
        # The week's deload is the framework's; a module with periods
        # deloads in its own deload period instead (module_deload).
        deload = forced or bool(frequency and entry['week_in_program'] % frequency == 0)
        deloads = {m['id']: module_deload(m, weeks_of[m['id']], forced, deload) for m in modules}
        # The phase's `exclude_exercises` rule a movement out as an injury
        # does: a declared alternative or an optional block's absence applies.
        week_blocked = (blocked_ids | set(entry.get('exclude_exercises') or []), blocked_patterns)

        def resolve(m, step, offset=0, position=1, seen=()):
            """The module as it runs at this exposure of this week."""
            return with_volume(with_stall(at_step(m, step, weeks_of[m['id']], offset), state[m['id']], step,
                                          position, seen),
                               level, entry['week_in_program'], deloads[m['id']], longest, modules,
                               entry.get('phase_id'), entry['week_in_phase'], held)

        # The week's longest exposure: a cycle's last step, or the longer of
        # alternating variants (Workout A runs longer than B).
        estimates = {m['id']: max(sum(r['load']['elapsed_sec'] for r in _module_rows(
                        resolve(m, cursor[m['id']] + k, 0, k + 1 if m.get('variants') else m['exposures_per_week']),
                        data['exercises_by_package'][contract['package']],
                        constraints, state[m['id']], cursor[m['id']] + k, deloads[m['id']], week_blocked))
                        for k in ((range(m['exposures_per_week']) if m.get('variants')
                                   else [m['exposures_per_week'] - 1]))) / 60
                     for m in modules}
        # Optional work is offered by the last build week's minutes: a deload
        # frees time, and it never adds a session the build weeks had no room
        # for (BJJ's conditioning used to appear in the deload week alone).
        if not any(deloads.values()):
            build_minutes.update(estimates)
        build_estimates = {mid: max(minutes, build_minutes.get(mid, 0)) if deloads[mid] else minutes
                           for mid, minutes in estimates.items()}
        for m in modules:
            if not m.get('optional') and estimates[m['id']] > cap:
                # Say which and by how much, not that "the budget cannot fit".
                raise ContractError(f"{m['name']} needs {estimates[m['id']]:g} minutes a session; "
                                    f"{cap:g} are available.")
        from . import standard_tests
        tests = standard_tests.tests_for_week(entry)
        if tests and not contract.get('test_module'):
            raise ContractError('The phase declares a test but its contract names no test module.')
        if len(tests) > 1:
            raise ContractError('Multiple tests in one contract week are not supported.')
        pending_test = tests[0] if tests and constraints.get('fatigue_state') != 'overreached' else None
        test_last = bool(pending_test and pending_test.get('day') == 'last')
        day_caps = {d: (constraints.get('day_configs', {}).get(d) or {}).get('minutes', cap) for d in pool}
        if day_room is not None:
            day_caps = {d: min(day_caps[d], day_room.get(d, day_caps[d])) for d in pool}
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
            room = {d: min(cap, day_caps.get(d, cap)) - sum(build_estimates[x['id']] for x in candidate.get(d, []))
                    for d in pool}
            fit = {}
            for m in optional:
                # Free days first; a module that may share a day (Wildman's
                # programs stack into one session) then takes a day with the
                # minutes left beside the essential work.
                days = [d for d in pool if d < limit and clear_of_last_week(m['id'], d, m.get('min_spacing_days', 2))
                        and (d not in candidate or m.get('may_share_day'))
                        and not {x['id'] for x in candidate.get(d, [])} & set(m.get('never_with') or [])]
                days.sort(key=lambda d: (d in candidate, -room[d], d))
                fit[m['id']] = _place_optional(m, build_estimates[m['id']], days, room)
                for d in fit[m['id']]:
                    room[d] -= build_estimates[m['id']]
            return fit, closes

        # The placement that closes a test week with its test and fits the most
        # optional work, then alternates and spaces the work best; the search
        # is small (a week, a few modules).
        best = None
        essential_caps = day_caps if essential_days is None else \
            {d: (day_caps[d] if d in essential_days else 0) for d in pool}
        for i, candidate in enumerate(_placements(essential, estimates, pool, cap, essential_caps)):
            if not spaced(candidate):
                continue
            fit, closes = optional_fit(candidate)
            # Optional work never costs an essential session its own day.
            stacked = sum(len(ms) - 1 for ms in candidate.values())
            # In a composition, a day another track trains on (or keeps for
            # itself) is avoided before a day of this track's own is shared.
            shared = sum(1 for d in candidate if d in (others or {}))
            key = (closes, -shared, -stacked, sum(len(v) for v in fit.values()),
                   *_spacing(candidate, module_regions, others))
            if best is None or key > best[0]:
                best = (key, candidate, fit)
            if i >= search:
                break
        if best is None:
            error = ContractError('Required module frequency, recovery spacing and session budget cannot all fit. Increase available time or days.')
            # What the week asked for, module by module, which a composition
            # weighs against the track's share of the athlete's minutes.
            error.week_minutes = sum(estimates[m['id']] * m['exposures_per_week'] for m in essential)
            error.module_minutes = {m['id']: estimates[m['id']] for m in essential}
            error.volume_minutes = sum(estimates[m['id']] * m['exposures_per_week'] for m in essential
                                       if m['progression']['model'] == 'weekly_volume')
            raise error
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
        position: dict[str, int] = {}
        for day, day_modules in sorted(placed.items()):
            # Also honour per-day budgets, not just the overall session limit.
            day_cap = day_caps[day]
            assignments, records, session_test = [], [], None
            # A test day is a test session for every module on it: none deloads
            # or advances, as `verify` and `confirmed_state` read the session.
            test_today = bool(pending_test and day == test_day
                              and any(m['id'] == contract.get('test_module') for m in day_modules))
            resolved = []
            for m in day_modules:
                position[m['id']] = position.get(m['id'], 0) + 1
                # A deload holds the cursor, so the week's sessions alternate by their order.
                offset = position[m['id']] - 1 if deloads[m['id']] else 0
                m = resolve(m, cursor[m['id']], offset, position[m['id']], light_steps[m['id']])
                if m.get('volume_capped') and m['id'] not in capped_said:
                    capped_said.add(m['id'])
                    program['compromises'].append(
                        f"{m['name']}: the method's {m['volume_capped']} minutes in week {entry['week_in_program']} "
                        f"(its share of the week's aerobic time) are capped at your longest day, {longest:g} minutes.")
                if m.get('light_day'):
                    light_steps[m['id']].add(cursor[m['id']])
                resolved.append(m)
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
                                    state[m['id']], cursor[m['id']], deloads[m['id']] and not test_today,
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
                                'deload': deloads[m['id']] and not test_today,
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
                                                      if r.get('exercise') and r['slot_type'] == 'time_domain' and m['progression']['model'] == 'timed_cycle'), 0),
                                **({'variant': m['variant']} if m.get('variant') else {}),
                                **({'light_day': m['light_day']} if m.get('light_day') else {}),
                                # What each progressing lift was prescribed, so
                                # confirmed_state reads made or missed against it.
                                **({'lifts': {r['exercise']['id']: {
                                    'lift': r['load']['lift'], 'kg': r['load'].get('weight_kg'),
                                    'sets': r['load'].get('sets'), 'reps': r['load'].get('reps')}
                                    for r in rows if r.get('exercise') and r['load'].get('lift')
                                    and r['load'].get('advances_module')}}
                                   if m['progression']['model'] == 'load_per_exposure' else {})})
                if not deloads[m['id']] and not test_today:
                    cursor[m['id']] += 1
            elapsed = sum(e['load']['elapsed_sec'] for e in assignments) // 60
            if elapsed > min(cap, day_cap):
                raise ContractError(f'Day {day}: required modules need {elapsed:g} minutes; available time is {min(cap, day_cap):g}.')
            first = resolved[0]
            arch = {'id': session_test['archetype'] if session_test else first['archetype_id'],
                    'name': test_arch['name'] if session_test else ' + '.join(m['name'] for m in resolved),
                    '_package': contract['package'], 'modality': first['modality'],
                    'duration_estimate_minutes': elapsed, 'slots': [a['slot'] for a in assignments],
                    'notes': contract['notes'], 'training_levels': contract['training_levels']}
            session = {'modality': first['modality'], 'archetype': arch,
                       'is_deload': any(deloads[m['id']] for m in resolved),
                       'exercises': assignments, 'modules': records,
                       'provenance': provenance.origin(arch, policy, kind='archetype')}
            if session_test:
                session['test'] = session_test
            schedule[day] = [session]
        program['weeks'].append({'week_number': entry['week_in_program'], 'week_in_phase': entry['week_in_phase'],
                                 'phase': entry['phase'], 'phase_id': entry.get('phase_id'),
                                 'phase_name': entry.get('phase_name'), 'track_id': contract['track_id'],
                                 # Every module deloading (Persist's Bridge week) is a deload
                                 # week too; one module's own (BJJ's strength) is not.
                                 'framework': fw['id'], 'schedule': schedule,
                                 'is_deload': deload or bool(deloads and all(deloads.values())),
                                 **({'modules_skipped': skipped} if skipped else {})})
        for item in skipped:
            shortfalls.setdefault((item['name'], item['placed'], item['of'], item['reason']), []).append(
                entry['week_in_program'])
        if tests and constraints.get('fatigue_state') == 'overreached':
            program['weeks'][-1]['tests_skipped'] = [{'archetypes': t['archetypes'], 'reason': 'overreached'} for t in tests]
        elif pending_test:
            raise ContractError('The required test could not be placed in its module.')
        return program['weeks'][-1]

    def finish(include_trace: bool = False) -> dict:
        # One line a shortfall, with its weeks unless it is every week: "0 of 2"
        # before the snatch joins and "1 of 2" after read as one claim otherwise.
        for (name, placed, of, reason), weeks in shortfalls.items():
            when = '' if len(weeks) == len(program['weeks']) else f" in {_week_span(weeks)}"
            program['compromises'].append(f"{name}: {placed} of {of} weekly sessions{when} — {reason}.")
        verify(program, contract, constraints)
        if include_trace:
            program['generation_trace'] = _trace(program, contract, constraints)
        return program

    return ContractRun(week=week, finish=finish, program=program, state=state, pool=pool)


class ContractRun(NamedTuple):
    week: object
    finish: object
    program: dict
    state: dict
    pool: list


def generate(contract: dict, entries: list, constraints: dict, data: dict, policy,
             frameworks: dict, include_trace: bool = False) -> dict:
    """Compile the contract directly to the normal generator result shape."""
    run = start(contract, entries, constraints, data, policy, frameworks)
    for entry in entries:
        run.week(entry)
    return run.finish(include_trace)


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
            'archetype': {'selected_id': s['archetype']['id'], 'filter_counts': {}, 'candidates': [],
                          'selection_reason': 'training_contract'},
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
    every = {m['id']: m for m in active_modules(contract, constraints)}
    level = constraints.get('training_level', 'intermediate')
    longest = (program.get('training_contract') or {}).get('longest_minutes', constraints['session_time_minutes'])
    if longest > constraints['session_time_minutes']:
        raise ContractError('A volume session is budgeted past the session limit.')
    last_day = {}
    cursors = {mid: (program.get('module_state', {}).get(mid) or {}).get('completed', 0) for mid in every}
    light_seen: dict[str, set] = {mid: set() for mid in every}
    held: dict = {}
    for wi, week in enumerate(program['weeks']):
        # The modules the week's phase runs, with its exposures (`phases`).
        expected = {mid: w for mid, w in ((mid, in_phase(m, week.get('phase_id'))) for mid, m in every.items()) if w}
        week_list = list(expected.values())
        hold_volume(held, week_list, level, week['week_number'], week.get('phase_id'))
        counts = {mid: 0 for mid in expected}
        forced = (constraints.get('fatigue_state') == 'overreached'
                  or week.get('phase_id') in contract.get('deload_phases', []))
        for day, sessions in sorted(week['schedule'].items()):
            for session in sessions:
                elapsed = sum(e['load']['elapsed_sec'] for e in session['exercises']) / 60
                if elapsed > constraints['session_time_minutes'] or elapsed != session['archetype']['duration_estimate_minutes']:
                    raise ContractError('Session workload and duration budget disagree.')
                for record in session['modules']:
                    mid = record['id']
                    if mid not in expected:
                        raise ContractError('A session uses a module outside its track or phase.')
                    counts[mid] += 1
                    if record['forecast_step'] != cursors[mid]:
                        raise ContractError('A module cursor was advanced without its exposure sequence.')
                    mweek = module_week(expected[mid], week['week_number'], week.get('week_in_phase', week['week_number']))
                    deload = module_deload(expected[mid], mweek, forced, week['is_deload'])
                    if record.get('deload') != (deload and not session.get('test')):
                        raise ContractError("A module's deload is not its cadence's.")
                    if not deload and not session.get('test'):
                        cursors[mid] += 1
                    absolute = wi * 7 + day
                    if mid in last_day and absolute - last_day[mid] < expected[mid]['min_spacing_days']:
                        raise ContractError('Required recovery spacing was lost.')
                    last_day[mid] = absolute
                    actual = [e['exercise']['id'] for e in session['exercises'] if e['load']['module_id'] == mid and e.get('exercise')]
                    lift_state = (program.get('module_state') or {}).get(mid) or {}
                    module_now = with_volume(with_stall(at_step(expected[mid], record['forecast_step'], mweek,
                                                                counts[mid] - 1 if deload else 0),
                                                        lift_state, record['forecast_step'], counts[mid], light_seen[mid]),
                                             level, week['week_number'], deload, longest, week_list,
                                             week.get('phase_id'), week.get('week_in_phase', 1), held)
                    dropping = _cuts(module_now, deload) and not session.get('test')
                    if module_now.get('variant') != record.get('variant'):
                        raise ContractError('A module ran a variant out of its rotation.')
                    if module_now.get('light_day') != record.get('light_day'):
                        raise ContractError("A lift's light day is not where its resets put it.")
                    if module_now.get('light_day'):
                        light_seen[mid].add(record['forecast_step'])
                    blocks = [b for b in module_now['blocks']
                              if not (dropping and not b.get('standard') and _keep(b, expected[mid]) == 0)]
                    if expected[mid].get('drop_when_injured') and (constraints.get('injury_flags')
                                                                   or constraints.get('avoid_movements')):
                        # A lift the injury rules out may be missing (_module_rows).
                        blocks = [{**b, 'optional': True} for b in blocks]
                    if not _sequence_matches(actual, blocks):
                        raise ContractError('A module lost its fixed movement sequence.')
                    if expected[mid]['progression']['model'] == 'load_per_exposure':
                        # Every weight is the lift's forecast from the confirmed state.
                        for b in blocks:
                            if not b.get('loaded'):
                                continue
                            row = next((e for e in session['exercises'] if e['slot_role'] == f"{mid}_{b['role']}"), None)
                            want = _lift_load(b, module_now, {}, lift_state, record['forecast_step'])
                            if row is not None and row['load'].get('weight_kg') != want.get('weight_kg'):
                                raise ContractError('A lift is not prescribed the weight its confirmed progression gives.')
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
                        inventory = _inventory(expected[mid], constraints)
                        if load.get('weight_kg') is not None and inventory is not None and load['weight_kg'] not in inventory:
                            from . import implements
                            eq = (expected[mid].get('implement') or {}).get('equipment')
                            one = implements.noun(eq)[0] if eq else 'implement'
                            raise ContractError(f'A prescription uses a {one} outside the available inventory.')
                        if load['progression_model'] != spec['model']:
                            raise ContractError('A prescription lost its resolved progression policy.')
                        if spec['model'] == 'weekly_volume' and ea.get('exercise'):
                            # The week's minutes are its share of the ramp, capped at the longest day.
                            block = next((b for b in blocks if ea['slot_role'] == f"{mid}_{b['role']}"), {})
                            if block.get('volume') and load['elapsed_sec'] != math.ceil(block['duration_sec'] / 60) * 60:
                                raise ContractError("A volume session's minutes are not its share of the week's ramp.")
                        if spec['model'] == 'timed_cycle' and ea.get('exercise') and ea['slot_type'] == 'time_domain':
                            seconds = (session['test']['protocol_sec'][ea['exercise']['id']] if ea.get('standard') else
                                       min(spec['duration_max_sec'], spec['duration_start_sec'] + record['forecast_step'] * spec['duration_step_sec']))
                            if dropping:
                                block = next((b for b in blocks if ea['slot_role'] in (b['role'], f"{mid}_{b['role']}")), {})
                                seconds = max(60, int(seconds * _keep(block, expected[mid])))
                            seconds = math.ceil(seconds / 60) * 60
                            if load['elapsed_sec'] != seconds or load['duration_minutes'] * 60 != seconds:
                                raise ContractError('An event duration does not follow its declared progression or test protocol.')
                        if ea['slot_type'] == 'emom':
                            rounds, reps, interval, _cue = _stage(spec, record['forecast_step'],
                                                                  _interval_budget(expected[mid], constraints))
                            if dropping:
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
        from .fidelity import claim_violations
        broken = claim_violations(weeks, checks)
        if broken:
            raise ContractError(f"The phase's defining claim is broken: {broken[0][2]}.")
        previous_work = None
        minutes = []
        for week in weeks:
            sessions = [s for ss in week['schedule'].values() for s in ss]
            arches = {m['archetype_id'] for s in sessions for m in s['modules']}
            if arches & set(checks.get('archetypes_forbidden') or []):
                raise ContractError('A phase-forbidden session was generated.')
            if checks.get('max_zone') is not None:
                # Timed work carries the zone ceiling; sets and holds prescribe
                # a load or an effort, never a heart rate (src/analytics/hr_plan.py).
                bounds = [ea['load'].get('zone_upper') for s in sessions for ea in s['exercises']
                          if ea['slot_type'] == 'time_domain' and not ea.get('meta')]
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
