"""Main program generator — orchestrates all modules."""
from __future__ import annotations

from . import loader
from .scheduler import schedule_week, select_framework
from .selector import populate_session, select_archetype
from .progression import calculate_load
from .validator import validate
from .output import format_program


# Movement patterns → recovery/mobility patterns that address them
_COMPLEMENTARY_PATTERNS: dict[str, list[str]] = {
    'squat':            ['hip_flexion', 'knee_extension'],
    'hip_hinge':        ['hip_flexion', 'hip_hinge'],
    'horizontal_push':  ['horizontal_pull', 'rotation'],
    'vertical_push':    ['horizontal_pull', 'rotation'],
    'horizontal_pull':  ['horizontal_push', 'rotation'],
    'vertical_pull':    ['vertical_push', 'rotation'],
    'loaded_carry':     ['rotation', 'hip_flexion'],
    'locomotion':       ['hip_flexion', 'knee_extension'],
    'ballistic':        ['hip_flexion', 'knee_extension'],
    'olympic_lift':     ['hip_flexion', 'rotation'],
    'isometric':        ['rotation', 'hip_flexion'],
}


def _select_complementary(
    session_exercises: list,
    all_exercises: dict,
    n: int = 3,
) -> list[dict]:
    """Select n mobility/rehab exercises that address patterns stressed in this session."""
    # Collect movement patterns used in this session
    used_patterns: set[str] = set()
    for ea in session_exercises:
        ex = ea.get('exercise') or {}
        used_patterns.update(ex.get('movement_patterns', []))

    if not used_patterns:
        return []

    # Map to recovery-relevant patterns
    recovery_targets: set[str] = set()
    for p in used_patterns:
        recovery_targets.update(_COMPLEMENTARY_PATTERNS.get(p, []))

    if not recovery_targets:
        return []

    # Score mobility/rehab exercises by overlap with recovery targets
    candidates: list[tuple[int, dict]] = []
    for ex in all_exercises.values():
        if ex.get('category') not in ('mobility', 'rehab'):
            continue
        overlap = len(set(ex.get('movement_patterns', [])) & recovery_targets)
        if overlap > 0:
            candidates.append((overlap, ex))

    candidates.sort(key=lambda x: -x[0])
    return [ex for _, ex in candidates[:n]]


def _has_archetype(modality: str, archetypes: list, constraints: dict, phase: str,
                   relax_equipment: bool = False) -> bool:
    """Return True if at least one archetype exists for this modality/phase/equipment.

    Mirrors the filter logic in select_archetype so that _resolve_session's pass
    decisions stay consistent with what select_archetype will actually find.
    When relax_equipment=True, skips the equipment hard filter — used for the commons
    fallback pass so bodyweight/equipment-limited archetypes are still found.
    """
    available = set(constraints.get('equipment', []))
    session_time = constraints.get('session_time_minutes', 90)
    training_level = constraints.get('training_level', 'intermediate')
    for arch in archetypes:
        if arch.get('modality') != modality:
            continue
        applicable = arch.get('applicable_phases', [])
        if applicable and phase not in applicable:
            continue
        # Training level — must match if the archetype restricts levels
        levels = arch.get('training_levels', [])
        if levels and training_level not in levels:
            continue
        # Duration — skip archetypes that can't fit the session budget.
        # time_limited scaling is assumed to save ~25% (dropping one warm-up/accessory slot);
        # this prevents a 75-min archetype's 60-min variant from matching a 30-min budget.
        duration = arch.get('duration_estimate_minutes', 60)
        tl = arch.get('scaling', {}).get('time_limited')
        effective_duration = int(duration * 0.75) if tl else duration
        if effective_duration > session_time:
            continue
        if relax_equipment:
            return True  # Phase/level/duration match is sufficient when equipment filter is relaxed
        required = set(arch.get('required_equipment', [])) - {'open_space'}
        if required.issubset(available) or arch.get('scaling', {}).get('equipment_limited'):
            return True
    return False


def _build_phase_entries(
    phase_seq: list, start_phase: str, start_wip: int, num_weeks: int
) -> list[dict]:
    """Expand phase_sequence into per-week entries starting at start_phase/start_wip."""
    if not phase_seq:
        return [
            {'phase': start_phase, 'week_in_phase': start_wip + i, 'week_in_program': i + 1}
            for i in range(num_weeks)
        ]

    entries: list[dict] = []
    week_in_program = 1
    found = False

    for phase_entry in phase_seq:
        phase_name  = phase_entry['phase']
        phase_weeks = phase_entry.get('weeks', 4)
        phase_framework = phase_entry.get('framework_id')  # Phase-specific framework

        if not found:
            if phase_name != start_phase:
                continue
            found = True
            first_wip = start_wip
        else:
            first_wip = 1

        for wip in range(first_wip, phase_weeks + 1):
            entry = {
                'phase': phase_name,
                'week_in_phase': wip,
                'week_in_program': week_in_program,
            }
            if phase_framework:
                entry['framework_id'] = phase_framework
            entries.append(entry)
            week_in_program += 1
            if len(entries) >= num_weeks:
                return entries

    # start_phase not found (manual override) — fall back to flat list
    if not entries:
        return [
            {'phase': start_phase, 'week_in_phase': start_wip + i, 'week_in_program': i + 1}
            for i in range(num_weeks)
        ]

    # Phase sequence exhausted before num_weeks — pad with last phase
    last = phase_seq[-1]['phase']
    extra_wip = 1
    while len(entries) < num_weeks:
        entries.append({'phase': last, 'week_in_phase': extra_wip, 'week_in_program': week_in_program})
        week_in_program += 1
        extra_wip += 1

    return entries


def _resolve_session(sessions: list, archetypes: list, all_archetypes: list,
                     constraints: dict, phase: str) -> list:
    """
    Replace sessions whose modality has no archetype for the current phase
    with the best available substitute.

    Three-pass strategy:
      Pass 1: primary-sources archetypes, normal equipment filter (current behaviour).
      Pass 2: full archetype pool (commons fallback), equipment filter relaxed — keeps the
              same modality but uses a bodyweight/equipment-limited alternative.
              Marks session with '_commons_fallback: True'.
      Pass 3: cross-modality substitution from primary-sources archetypes only.
              Fallback order: aerobic_base → durability → mobility.
    If no pass resolves, the session is passed through (produces null archetype output).
    """
    _FALLBACKS = ('aerobic_base', 'durability', 'mobility')
    resolved = []
    for session in sessions:
        modality = session['modality']

        # Pass 1: primary-sources archetypes, normal equipment filter
        if _has_archetype(modality, archetypes, constraints, phase):
            resolved.append(session)
            continue

        # Pass 2: commons fallback — same modality, full pool, relaxed equipment
        if _has_archetype(modality, all_archetypes, constraints, phase, relax_equipment=True):
            resolved.append({**session, '_commons_fallback': True})
            continue

        # Pass 3: cross-modality substitution (primary-sources only)
        substituted = False
        for fallback in _FALLBACKS:
            if fallback == modality:
                continue
            if _has_archetype(fallback, archetypes, constraints, phase):
                resolved.append({**session, 'modality': fallback, '_cross_modality': True})
                substituted = True
                break
        if not substituted:
            resolved.append(session)  # pass through; archetype will be None
    return resolved


_GEN_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def generate(
    goal_id: str | None,
    constraints: dict,
    num_weeks: int = 4,
    output_format: str = 'markdown',
    phase_schedule: list[dict] | None = None,
    extra_injury_flags: dict | None = None,
    goal_dict: dict | None = None,
    include_trace: bool = False,
) -> str | dict:
    """
    Generate a training program.

    Args:
        goal_id:        ID from data/goals/ (e.g. 'alpine_climbing', 'general_gpp')
        constraints:    Dict matching constraints.schema.json
        num_weeks:      Weeks to generate (default 4); ignored when phase_schedule provided
        output_format:  'markdown' (default) or 'dict'
        phase_schedule: Optional list of {phase, week_in_phase, week_in_program} dicts.
                        When provided, generates exactly these weeks spanning phases.
        goal_dict:      Pre-built goal dict (e.g. blended goal); skips load_goal when provided.

    Returns:
        Formatted markdown string, or raw dict if output_format='dict'.
    """
    # --- Load data -----------------------------------------------------------
    goal = goal_dict if goal_dict is not None else loader.load_goal(goal_id)
    data = loader.load_all_data()
    all_archetypes = data['archetypes']   # Unfiltered pool — retained for commons fallback
    archetypes = data['archetypes']
    exercises  = data['exercises']
    modalities = data['modalities']
    injury_flags_data = data['injury_flags']
    if extra_injury_flags:
        injury_flags_data = {**injury_flags_data, **extra_injury_flags}

    # Filter archetypes by primary_sources (philosophy packages).
    # An archetype matches if its _package is in primary_sources, OR if any
    # primary_source name appears (case-insensitive) in its sources list
    # (e.g. ruck_session lives in horsemen_gpp but lists "Uphill Athlete" as a source).
    primary_sources = set(goal.get('primary_sources', []))
    if primary_sources:
        # Normalise to lowercase+no-underscores for fuzzy matching
        # so 'uphill_athlete' matches 'Uphill Athlete' in sources arrays
        def _norm(s: str) -> str:
            return s.lower().replace('_', ' ')

        primary_norm = {_norm(ps) for ps in primary_sources}

        def _arch_matches(arch: dict) -> bool:
            if arch.get('_package') in primary_sources:
                return True
            for src in arch.get('sources', []):
                src_norm = _norm(src)
                if any(pn in src_norm for pn in primary_norm):
                    return True
            return False

        archetypes = [arch for arch in archetypes if _arch_matches(arch)]

    # --- Validate feasibility ------------------------------------------------
    validation = validate(goal, constraints, archetypes, modalities, injury_flags_data)
    if not validation.feasible:
        return format_program({'weeks': []}, goal, constraints, validation)

    # --- Build week entries --------------------------------------------------
    if phase_schedule:
        entries = phase_schedule
    else:
        phase_seq = goal.get('phase_sequence', [])
        # Default start phase: first in the sequence (not hardcoded 'base'),
        # so sequential philosophies like Uphill Athlete start at transition.
        first_phase = phase_seq[0]['phase'] if phase_seq else 'base'
        base_phase = constraints.get('training_phase', first_phase)
        start_week = constraints.get('periodization_week', 1)
        entries = _build_phase_entries(
            phase_seq, base_phase, start_week, num_weeks
        )

    program = {'weeks': []}
    recent_arch_ids: list[str] = []
    recent_ex_ids:   list[str] = []
    all_compromises: list[str] = []  # Collect compromises from all weeks

    # Progression model for each modality (static, load from modalities data)
    prog_model_for = {
        mod_id: mod.get('progression_model', 'linear_load')
        for mod_id, mod in modalities.items()
    }

    generation_trace: dict | None = {
        'weeks': [],
        'primary_sources': goal.get('primary_sources', []),
        'philosophy_mode': 'synthetic_goal' if goal.get('is_synthetic') else 'explicit_goal',
    } if include_trace else None

    for entry in entries:
        phase          = entry['phase']
        week_in_phase  = entry['week_in_phase']
        week_in_program = entry.get('week_in_program', week_in_phase)
        phase_framework_id = entry.get('framework_id')  # Phase-specific framework override

        # 1. Build the modality→day schedule
        sched_result = schedule_week(goal, constraints, data, phase, week_in_phase,
                                     phase_framework_id=phase_framework_id,
                                     collect_trace=include_trace)
        week_schedule = sched_result['schedule']
        is_deload     = sched_result['is_deload']
        framework     = sched_result['framework']

        # Collect compromises from this week (only unique ones)
        week_compromises = sched_result.get('compromises', [])
        for compromise in week_compromises:
            if compromise not in all_compromises:
                all_compromises.append(compromise)

        week_trace: dict | None = None
        if include_trace:
            week_trace = {
                'week_number': week_in_program,
                'week_in_phase': week_in_phase,
                'phase': phase,
                'is_deload': is_deload,
                'scheduler': sched_result.get('scheduler_trace', {}),
                'sessions': {},
            }

        # 2. Populate each session with archetype + exercises + loads
        populated_schedule: dict[int, list] = {}

        for day in sorted(week_schedule.keys()):
            populated_sessions = []
            day_name = _GEN_DAY_NAMES[day - 1] if 1 <= day <= 7 else f'Day {day}'
            day_session_traces: list[dict] = []

            # Check for mobility archetype hint from smart pairing
            day_cfg = constraints.get('day_configs', {}).get(day, {})
            mobility_hint = day_cfg.get('mobility_archetype_hint')
            day_session_types = day_cfg.get('session_types')

            for session in _resolve_session(week_schedule[day], archetypes, all_archetypes, constraints, phase):
                # Determine if this session should use the mobility hint
                preferred_arch = None
                if session['modality'] == 'mobility' and mobility_hint:
                    preferred_arch = mobility_hint

                # Commons fallback: use full archetype pool with relaxed equipment
                is_commons_fallback = session.pop('_commons_fallback', False)
                is_cross_modality = session.pop('_cross_modality', False)
                session_archetypes = all_archetypes if is_commons_fallback else archetypes

                # Record compromise message for commons fallback (once per unique substitution)
                if is_commons_fallback:
                    orig_modality = session['modality'].replace('_', ' ')
                    msg = f"{orig_modality} substituted with bodyweight/equipment-limited alternative (no matching gym equipment)"
                    if msg not in all_compromises:
                        all_compromises.append(msg)

                # Select archetype + exercises
                populated = populate_session(
                    session, goal, constraints, exercises, session_archetypes,
                    injury_flags_data, phase, week_in_phase,
                    recent_arch_ids, recent_ex_ids,
                    collect_trace=include_trace,
                    exercises_by_package=data.get('exercises_by_package'),
                    preferred_archetype_id=preferred_arch,
                    day_session_types=day_session_types,
                    relax_equipment=is_commons_fallback,
                )

                session_trace: dict | None = None
                if include_trace:
                    session_trace = populated.pop('session_trace', {})
                    session_trace['progression'] = []

                # Detect slots that could not be filled and surface a compromise message.
                # This fires only when all selection passes failed (rare — equipment + package gap).
                for ea in populated.get('exercises', []):
                    if ea.get('exercise') is None and not ea.get('injury_skip'):
                        arch_name = (populated.get('archetype') or {}).get('name', session['modality'])
                        slot_role = ea.get('slot_role', 'slot')
                        slot_cat = (ea.get('slot') or {}).get('exercise_filter', {}).get('category', '')
                        equip = constraints.get('equipment', [])
                        if slot_cat and not any(slot_cat in e for e in equip):
                            msg = (f"{arch_name}: '{slot_role}' slot requires {slot_cat} exercises "
                                   f"— add {slot_cat} to your equipment profile to fill this slot.")
                        else:
                            msg = (f"{arch_name}: '{slot_role}' slot skipped — no matching exercises "
                                   f"found for current equipment and training level.")
                        if msg not in all_compromises:
                            all_compromises.append(msg)

                # Calculate load for each exercise slot
                mod_id = session['modality']
                prog = prog_model_for.get(mod_id, 'linear_load')

                for ea in populated.get('exercises', []):
                    if ea.get('exercise') is None:
                        continue
                    load = calculate_load(
                        ea['exercise'],
                        ea['slot'],
                        prog,
                        week_in_phase,
                        phase,
                        constraints.get('training_level', 'intermediate'),
                        is_deload,
                        session_time_minutes=constraints.get('session_time_minutes', 75),
                    )
                    ea['load'] = load

                    if include_trace and session_trace is not None:
                        session_trace['progression'].append({
                            'exercise_id': ea['exercise']['id'],
                            'exercise_name': ea['exercise'].get('name', ''),
                            'slot_role': ea.get('slot_role', ''),
                            'slot_type': ea['slot'].get('slot_type', ''),
                            'model': prog,
                            'week': week_in_phase,
                            'phase': phase,
                            'level': constraints.get('training_level', 'intermediate'),
                            'is_deload': is_deload,
                            'output': dict(load),
                        })

                    # Track exercise variety
                    recent_ex_ids.append(ea['exercise']['id'])
                    if len(recent_ex_ids) > 40:
                        recent_ex_ids.pop(0)

                if populated.get('archetype'):
                    recent_arch_ids.append(populated['archetype']['id'])
                    if len(recent_arch_ids) > 14:
                        recent_arch_ids.pop(0)

                # Complementary recovery work — mobility/rehab exercises targeting stressed patterns
                comp = _select_complementary(populated.get('exercises', []), exercises)
                if comp:
                    populated['complementary_work'] = [
                        {
                            'exercise': ex,
                            'prescription': {
                                'sets': 2,
                                'duration_sec': 60,
                                'note': 'Hold or flow through full range — quality over speed',
                            },
                        }
                        for ex in comp
                    ]

                populated_sessions.append(populated)
                if include_trace and session_trace is not None:
                    day_session_traces.append(session_trace)

            populated_schedule[day] = populated_sessions
            if include_trace and week_trace is not None:
                week_trace['sessions'][day_name] = day_session_traces

        program['weeks'].append({
            'week_number':    week_in_program,
            'week_in_phase':  week_in_phase,
            'phase':          phase,
            'is_deload':      is_deload,
            'schedule':       populated_schedule,
            'framework':      framework['id'],
        })
        if include_trace and generation_trace is not None and week_trace is not None:
            generation_trace['weeks'].append(week_trace)

    # Add compromises to program
    program['compromises'] = all_compromises

    if output_format == 'dict':
        if include_trace and generation_trace is not None:
            program['generation_trace'] = generation_trace
        return program

    return format_program(program, goal, constraints, validation)
