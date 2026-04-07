"""Main program generator — orchestrates all modules."""
from __future__ import annotations

from . import loader
from .scheduler import schedule_week, select_framework
from .selector import populate_session, select_archetype
from .progression import calculate_load
from .validator import validate
from .output import format_program


def _has_archetype(modality: str, archetypes: list, constraints: dict, phase: str) -> bool:
    """Return True if at least one archetype exists for this modality/phase/equipment."""
    available = set(constraints.get('equipment', []))
    for arch in archetypes:
        if arch.get('modality') != modality:
            continue
        applicable = arch.get('applicable_phases', [])
        if applicable and phase not in applicable:
            continue
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

        if not found:
            if phase_name != start_phase:
                continue
            found = True
            first_wip = start_wip
        else:
            first_wip = 1

        for wip in range(first_wip, phase_weeks + 1):
            entries.append({
                'phase': phase_name,
                'week_in_phase': wip,
                'week_in_program': week_in_program,
            })
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


def _resolve_session(sessions: list, archetypes: list,
                     constraints: dict, phase: str) -> list:
    """
    Replace sessions whose modality has no archetype for the current phase
    with the first available fallback modality that does.

    Fallback order: aerobic_base → durability → mobility.
    If no fallback resolves, the session is passed through unchanged (will
    produce an empty session in output, preferable to a silent wrong substitution).
    """
    _FALLBACKS = ('aerobic_base', 'durability', 'mobility')
    resolved = []
    for session in sessions:
        modality = session['modality']
        if not _has_archetype(modality, archetypes, constraints, phase):
            substituted = False
            for fallback in _FALLBACKS:
                if fallback == modality:
                    continue  # skip if same as the failing modality
                if _has_archetype(fallback, archetypes, constraints, phase):
                    resolved.append({**session, 'modality': fallback})
                    substituted = True
                    break
            if not substituted:
                resolved.append(session)  # pass through; archetype will be None
        else:
            resolved.append(session)
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
    archetypes = data['archetypes']
    exercises  = data['exercises']
    modalities = data['modalities']
    injury_flags_data = data['injury_flags']
    if extra_injury_flags:
        injury_flags_data = {**injury_flags_data, **extra_injury_flags}

    # --- Validate feasibility ------------------------------------------------
    validation = validate(goal, constraints, archetypes, modalities, injury_flags_data)
    if not validation.feasible:
        return format_program({'weeks': []}, goal, constraints, validation)

    # --- Build week entries --------------------------------------------------
    if phase_schedule:
        entries = phase_schedule
    else:
        base_phase = constraints.get('training_phase', 'base')
        start_week = constraints.get('periodization_week', 1)
        entries = _build_phase_entries(
            goal.get('phase_sequence', []), base_phase, start_week, num_weeks
        )

    program = {'weeks': []}
    recent_arch_ids: list[str] = []
    recent_ex_ids:   list[str] = []

    # Progression model for each modality (static, load from modalities data)
    prog_model_for = {
        mod_id: mod.get('progression_model', 'linear_load')
        for mod_id, mod in modalities.items()
    }

    generation_trace: dict | None = {'weeks': []} if include_trace else None

    for entry in entries:
        phase          = entry['phase']
        week_in_phase  = entry['week_in_phase']
        week_in_program = entry.get('week_in_program', week_in_phase)

        # 1. Build the modality→day schedule
        sched_result = schedule_week(goal, constraints, data, phase, week_in_phase,
                                     collect_trace=include_trace)
        week_schedule = sched_result['schedule']
        is_deload     = sched_result['is_deload']
        framework     = sched_result['framework']

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

            for session in _resolve_session(week_schedule[day], archetypes, constraints, phase):
                # Select archetype + exercises
                populated = populate_session(
                    session, goal, constraints, exercises, archetypes,
                    injury_flags_data, phase, week_in_phase,
                    recent_arch_ids, recent_ex_ids,
                    collect_trace=include_trace,
                    exercises_by_package=data.get('exercises_by_package'),
                )

                session_trace: dict | None = None
                if include_trace:
                    session_trace = populated.pop('session_trace', {})
                    session_trace['progression'] = []

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

    if output_format == 'dict':
        if include_trace and generation_trace is not None:
            program['generation_trace'] = generation_trace
        return program

    return format_program(program, goal, constraints, validation)
