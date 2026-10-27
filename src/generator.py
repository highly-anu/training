"""Main program generator — orchestrates all modules."""
from __future__ import annotations

from . import blockers, loader, phases, provenance, recovery_regions, standard_tests, week_template
from .scheduler import schedule_week, select_framework
from .selector import populate_session, select_archetype
from .progression import calculate_load
from .validator import validate
from .output import format_program
from typing import NamedTuple


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
    """True if `select_archetype` would find an archetype for this modality.

    It asks the selector itself. A copy of its filters used to live here, with
    a different default session time (90 against 75), its own time-limited
    discount and no short-day cap, so this pass could say yes where selection
    then found nothing, or say no and relax the equipment for no reason.
    """
    return select_archetype(modality, constraints, phase, False, {}, archetypes,
                            relax_equipment=relax_equipment) is not None


def _build_phase_entries(
    phase_seq: list, start_phase: str | None, start_wip: int, num_weeks: int,
    first_week_number: int = 1,
) -> list[dict]:
    """Expand phase_sequence into per-week entries starting at start_phase/start_wip.

    `start_phase` is a `phase_id` from the sequence (resolve a request with
    `phases.resolve_start_phase`); None starts at the first phase. Every entry
    carries its phase's framework, including the padding past the end of the
    sequence — padding used to drop it and run the goal's default framework.

    `first_week_number` is the `week_in_program` of the first entry. A partial
    regenerate passes the kept head's length + 1 so its tail continues the
    numbering; until it did, every partial regenerate numbered its tail from
    1 again and a program read 1, 1, 2, 3.
    """
    first = max(1, int(first_week_number or 1))
    if not phase_seq:
        raise phases.PhaseResolutionError('The goal has no phase sequence.')

    start_id = start_phase or phase_seq[0].get('phase_id')
    start_idx = next(
        (i for i, e in enumerate(phase_seq) if e.get('phase_id') == start_id), None)
    if start_idx is None:
        raise phases.PhaseResolutionError(
            f"Phase '{start_phase}' is not in this track: "
            f"{[e.get('phase_id') for e in phase_seq]}"
        )

    entries: list[dict] = []
    week_in_program = first
    for idx in range(start_idx, len(phase_seq)):
        phase_entry = phase_seq[idx]
        phase_weeks = int(phase_entry.get('weeks') or 1)
        first_wip = max(1, int(start_wip or 1)) if idx == start_idx else 1
        for wip in range(first_wip, phase_weeks + 1):
            entries.append(phases.week_entry(phase_entry, wip, week_in_program))
            week_in_program += 1
            if len(entries) >= num_weeks:
                return entries

    # Sequence exhausted before num_weeks — continue the last phase, counting on
    # from its last emitted week so deload cadence and loads keep running.
    last = phase_seq[-1]
    if entries and entries[-1].get('phase_id') == last.get('phase_id'):
        extra_wip = entries[-1]['week_in_phase'] + 1
    else:
        extra_wip = max(1, int(start_wip or 1)) if start_idx == len(phase_seq) - 1 else 1
    while len(entries) < num_weeks:
        entries.append(phases.week_entry(last, extra_wip, week_in_program))
        week_in_program += 1
        extra_wip += 1

    return entries


def _resolve_session(sessions: list, archetypes: list, fallback_archetypes: list,
                     constraints: dict, phase: str) -> list:
    """
    Replace sessions whose modality has no archetype for the current phase
    with the best available substitute.

    Three-pass strategy:
      Pass 1: primary-sources archetypes, normal equipment filter (current behaviour).
      Pass 2: fallback_archetypes, equipment filter relaxed — same modality, but a
              bodyweight/equipment-limited alternative. Marks '_commons_fallback'.
              NOTE: data/commons/ holds no archetypes, so this is NOT a commons pool:
              it is the policy-allowed packages when strict, else the whole library.
      Pass 3: cross-modality substitution from primary-sources archetypes only.
              Fallback order: aerobic_base → durability → mobility. Marks
              '_substituted_for' with the modality it replaced, so the session,
              the compromises and the coverage report can say so — it used to
              change the modality and leave no trace.
    If no pass resolves, the session is passed through (produces null archetype output).
    """
    _FALLBACKS = ('aerobic_base', 'durability', 'mobility')
    resolved = []
    for session in sessions:
        modality = session['modality']
        if session.get('_forced_archetype'):
            # A template day's named workout, picked as written (week_template).
            resolved.append(session)
            continue

        # Pass 1: primary-sources archetypes, normal equipment filter
        if _has_archetype(modality, archetypes, constraints, phase):
            resolved.append(session)
            continue

        # Pass 2: same modality from the fallback pool, equipment filter relaxed
        if _has_archetype(modality, fallback_archetypes, constraints, phase, relax_equipment=True):
            resolved.append({**session, '_commons_fallback': True})
            continue

        # Pass 3: cross-modality substitution (primary-sources only)
        substituted = False
        for fallback in _FALLBACKS:
            if fallback == modality:
                continue
            if _has_archetype(fallback, archetypes, constraints, phase):
                resolved.append({**session, 'modality': fallback, '_substituted_for': modality})
                substituted = True
                break
        if not substituted:
            resolved.append(session)  # pass through; archetype will be None
    return resolved


def _fits_as_written(arch: dict, constraints: dict, phase: str, populate) -> bool:
    """Whether the athlete can do a named workout as written: their level, the
    phase, every piece of its equipment (open space is assumed) and every
    movement fillable (an injury or a phase exclusion can rule one out)."""
    level = constraints.get('training_level', 'intermediate')
    if arch.get('training_levels') and level not in arch['training_levels']:
        return False
    if arch.get('applicable_phases') and phase not in arch['applicable_phases']:
        return False
    have = set(constraints.get('equipment') or []) | {'open_space'}
    if not set(arch.get('required_equipment') or []) <= have:
        return False
    populated = populate(arch)
    return bool(populated.get('archetype')) and all(
        ea.get('exercise') is not None or ea.get('meta') or (ea.get('slot') or {}).get('skip_exercise')
        for ea in populated.get('exercises', []))


_GEN_DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']


def _test_slot(resolved_by_day: dict, modalities: list, day_pref: str, taken: set):
    """(day, index, session) of the session a test replaces: the first (or
    last) of the week in the first of `modalities` that has one. A session
    that is already a stand-in (another modality's substitute, a relaxed-
    equipment fallback) or already taken by another test is not a candidate."""
    days = sorted(resolved_by_day)
    if day_pref == 'last':
        days = list(reversed(days))
    for mod in modalities:
        for day in days:
            sessions = list(enumerate(resolved_by_day[day]))
            if day_pref == 'last':
                sessions.reverse()
            for idx, sess in sessions:
                if mod not in (sess.get('modality'), sess.get('category')) or (day, idx) in taken:
                    continue
                if sess.get('_substituted_for') or sess.get('_commons_fallback'):
                    continue
                return day, idx, sess
    return None


def _stand_in(session: dict) -> dict:
    """The session a test replaced: its archetype, planned minutes and minutes
    per intensity bucket (src/fidelity.py's reading), so a test counts as the
    work it stands in for wherever the plan's volume and intensity are read."""
    from src import fidelity
    arch = session.get('archetype') or {}
    return {
        'archetype': arch.get('id'), 'name': arch.get('name'), 'modality': session.get('modality'),
        'minutes': round(fidelity.session_minutes(session), 1),
        'buckets': {b: round(m, 1) for b, m in fidelity.session_buckets(session).items() if m},
    }


def _plan_week_tests(entry: dict, resolved_by_day: dict, archetypes: list, constraints: dict,
                     is_deload: bool, populate) -> tuple[dict, list]:
    """The week's tests (src/standard_tests.tests_for_week), each put in place
    of one session — {(day, index): {session, populated}} — and the ones the
    athlete cannot do, with why.

    A test goes in only when the athlete can do it as written: their level,
    their equipment (a test is never equipment-scaled: the score would not
    compare), a session of the modality to replace, the time (a test past
    1.1× the session limit needs a long day), and every scored slot filled
    (an injury can rule a movement out). The rotation's next archetype is tried
    before the test is skipped; a skipped test leaves the week as scheduled.
    """
    specs = standard_tests.tests_for_week(entry)
    if not specs:
        return {}, []
    by_id = {a.get('id'): a for a in archetypes}
    level = constraints.get('training_level', 'intermediate')
    equipment = set(constraints.get('equipment') or [])
    day_configs = constraints.get('day_configs') or {}
    cap = constraints.get('session_time_minutes')
    placed: dict = {}
    skipped: list = []
    taken: set = set()
    for spec in specs:
        record = {'archetypes': spec['archetypes'], 'phase_id': entry.get('phase_id'),
                  'week_in_phase': entry.get('week_in_phase')}
        if constraints.get('fatigue_state') == 'overreached':
            skipped.append({**record, 'reason': 'overreached'})
            continue
        if is_deload and spec['on_deload'] == 'skip':
            skipped.append({**record, 'reason': 'deload'})
            continue
        reason = None
        for aid in spec['archetypes']:
            arch = by_id.get(aid)
            if not arch or not standard_tests.is_test(arch):
                reason = reason or 'archetype_unavailable'
                continue
            if arch.get('training_levels') and level not in arch['training_levels']:
                reason = 'level'
                continue
            if not (set(arch.get('required_equipment') or []) - {'open_space'}) <= equipment:
                reason = 'equipment_gap'
                continue
            found = _test_slot(resolved_by_day, spec['in_place_of'] or [arch.get('modality')], spec['day'], taken)
            if found is None:
                reason = 'no_session_of_modality'
                continue
            day, idx, session = found
            types = (day_configs.get(day) or {}).get('session_types') or []
            # The tolerance tools/check_fidelity.py allows a session (1.1×).
            if cap and (arch.get('duration_estimate_minutes') or 0) > cap * 1.1 and 'long' not in types:
                reason = 'session_too_short'
                continue
            # A templated day keeps its category (the day the test stands in
            # for); the replaced day's pieces and warm-up are not the test's.
            test_session = {k: v for k, v in session.items()
                            if not k.startswith('_') and k not in ('pieces', 'warm_up', 'light', 'category_name')}
            test_session['modality'] = arch.get('modality')
            populated = populate(test_session, arch)
            # The scored piece is every slot with a standard and the movements
            # inside it (Helen's swings and pull-ups): all of it, or no test.
            eas = populated.get('exercises', [])
            scored_roles = {ea.get('slot_role') for ea in eas if standard_tests.standard_ref(ea.get('slot'))}
            piece = [ea for ea in eas if ea.get('slot_role') in scored_roles
                     or (ea.get('slot') or {}).get('parent_slot_role') in scored_roles]
            if not scored_roles or any(ea.get('exercise') is None and not ea.get('meta') for ea in piece):
                gap = next((ea for ea in piece if ea.get('exercise') is None and not ea.get('meta')), {})
                reason = ('injury_skip' if any(ea.get('injury_skip') for ea in piece)
                          else gap.get('gap_reason') or 'equipment_gap')
                continue
            populated['test'] = {
                'archetype': aid, 'standards': standard_tests.standards_of(arch),
                'phase_id': entry.get('phase_id'), 'week_in_phase': entry.get('week_in_phase'),
                'in_place_of': session.get('modality'),
            }
            placed[(day, idx)] = {'session': test_session, 'populated': populated}
            taken.add((day, idx))
            reason = None
            break
        if reason:
            skipped.append({**record, 'reason': reason})
    return placed, skipped




def _build_coverage_report(program: dict, policy) -> dict:
    """What the philosophy could not cover, and what it borrowed to cover it.

    Sibling of `compromises`. Compromises explain a substitution in prose; this
    is the structured record of where the package fell short, so the UI can show
    it and tools/check_provenance.py can assert on it.
    """
    unfilled_sessions: list[dict] = []
    unfilled_slots: list[dict] = []
    borrowed_sessions: list[dict] = []
    substituted_sessions: list[dict] = []
    placed_tests: list[dict] = []
    skipped_tests: list[dict] = []
    seen_slots: set = set()

    for week in program.get('weeks', []):
        # The engine's weeks carry `week_number` and integer day keys; the
        # report used to read `week` (always None) and pass the integer on,
        # where the clients' types expect a number and a day name.
        week_no = week.get('week_number', week.get('week'))
        for t in week.get('tests_skipped') or []:
            skipped_tests.append({'week': week_no, **t})
        for day_key, sessions in (week.get('schedule') or {}).items():
            day_name = (_GEN_DAY_NAMES[day_key - 1] if isinstance(day_key, int) and 1 <= day_key <= 7
                        else day_key)
            for session in sessions:
                arch = session.get('archetype')
                if session.get('test'):
                    placed_tests.append({'week': week_no, 'day': day_name, **session['test']})
                if session.get('substituted_for'):
                    substituted_sessions.append({
                        'week': week_no, 'day': day_name,
                        'modality': session.get('modality'),
                        'substituted_for': session['substituted_for'],
                        'archetype': (arch or {}).get('id'),
                        'reason': {'level': 'NO_ARCHETYPE_FOR_LEVEL', 'phase': 'NO_ARCHETYPE_FOR_PHASE'}.get(
                            session.get('substitution_cause'), 'NO_ARCHETYPE_FOR_PHASE_OR_LEVEL'),
                    })
                if not arch:
                    unfilled_sessions.append({
                        'week': week_no, 'day': day_name,
                        'modality': session.get('modality'),
                        'reason': 'NO_ARCHETYPE_IN_ALLOWED_PACKAGES',
                    })
                    continue

                tag = provenance.origin(arch, policy, kind='archetype')
                if tag and tag.get('borrowed'):
                    borrowed_sessions.append({
                        'week': week_no, 'day': day_name,
                        'archetype': arch.get('id'),
                        'from_package': tag.get('package'),
                        'label': tag.get('label'),
                        'reason': tag.get('reason'),
                    })

                for ea in session.get('exercises', []):
                    if not ea.get('coverage_gap'):
                        continue
                    key = (arch.get('id'), ea.get('slot_role'))
                    if key in seen_slots:
                        continue
                    seen_slots.add(key)
                    unfilled_slots.append({
                        'archetype': arch.get('id'),
                        'slot_role': ea.get('slot_role'),
                        'reason': ea.get('gap_reason'),
                    })

    return {
        'philosophy': sorted(policy.owner_packages)[0] if policy.owner_packages else None,
        'strict': policy.strict,
        'unfilled_sessions': unfilled_sessions,
        'unfilled_slots': unfilled_slots,
        'borrowed_sessions': borrowed_sessions,
        'substituted_sessions': substituted_sessions,
        'placed_tests': placed_tests,
        'skipped_tests': skipped_tests,
    }


def generate(
    goal_id: str | None,
    constraints: dict,
    num_weeks: int = 4,
    output_format: str = 'markdown',
    phase_schedule: list[dict] | None = None,
    extra_injury_flags: dict | None = None,
    goal_dict: dict | None = None,
    include_trace: bool = False,
    policy: 'provenance.SourcePolicy | None' = None,
    start_week_number: int | None = None,
) -> str | dict:
    """
    Generate a training program.

    Args:
        goal_id:        Identifier for logging/trace only; goal_dict supplies the content.
        constraints:    Dict matching constraints.schema.json
        num_weeks:      Weeks to generate (default 4); ignored when phase_schedule provided
        start_week_number: `week_number` of the first generated week (default 1).
                        A partial regenerate passes the kept head's length + 1.
                        Ignored with phase_schedule, which carries absolute weeks.
        output_format:  'markdown' (default) or 'dict'
        phase_schedule: Optional list of {phase, week_in_phase, week_in_program} dicts.
                        When provided, generates exactly these weeks spanning phases.
        goal_dict:      The goal to generate for. Required — see src/goals.py.
        policy:         Package SourcePolicy; derived from the goal when omitted.
                        Pass the one api.py validated against so the two paths
                        can never check different libraries.

    Returns:
        Formatted markdown string, or raw dict if output_format='dict'.
    """
    # --- Load data -----------------------------------------------------------
    # goal_dict is always supplied by api.py and the tools; loader.load_goal was
    # removed with the data/goals/ directory in the vertical migration, so calling
    # it here raised AttributeError rather than reporting a missing goal.
    if goal_dict is None:
        raise ValueError(
            f"generate() needs goal_dict. Goals are no longer loaded by id "
            f"(got goal_id={goal_id!r}); build one with src.goals.philosophy_to_goal."
        )
    goal = goal_dict
    data = loader.load_all_data()

    # Narrow the library to the packages this goal may draw from. Archetypes used
    # to be matched by a substring search over their free-text `sources:` prose,
    # which let any package claiming "Gym Jones" in its bibliography into a Gym
    # Jones program; ownership is `_package`, not attribution.
    if policy is None:
        policy = provenance.resolve_source_policy(goal)
    lib = provenance.scope(data, policy)

    archetypes = lib['archetypes']
    exercises  = lib['exercises']
    modalities = lib['modalities']
    injury_flags_data = lib['injury_flags']
    if extra_injury_flags:
        injury_flags_data = {**injury_flags_data, **extra_injury_flags}

    # --- Validate feasibility ------------------------------------------------
    validation = validate(goal, constraints, archetypes, modalities, injury_flags_data)
    if not validation.feasible:
        # Honour output_format here too — callers asking for a dict were getting
        # a markdown string back on this path.
        if output_format == 'dict':
            return {'weeks': [], 'compromises': [],
                    'coverage_report': _build_coverage_report({}, policy),
                    'validation_errors': list(validation.errors)}
        return format_program({'weeks': []}, goal, constraints, validation)

    # --- Build week entries --------------------------------------------------
    if phase_schedule:
        entries = phase_schedule
    else:
        phase_seq = goal.get('phase_sequence', [])
        # Default start: the track's first phase (never a hard-coded 'base'),
        # so Uphill Athlete starts at transition.
        start_phase = phases.resolve_start_phase(
            phase_seq, constraints.get('start_phase'), constraints.get('training_phase'))
        start_week = constraints.get('periodization_week', 1)
        entries = _build_phase_entries(
            phase_seq, start_phase, start_week, num_weeks,
            first_week_number=start_week_number or 1,
        )

    track_id = (goal.get('track') or {}).get('id')
    if goal.get('training_contract'):
        from . import training_contract
        try:
            program = training_contract.generate(goal['training_contract'], entries, constraints,
                                                 {**data, 'injury_flags': injury_flags_data}, policy,
                                                 loader.load_all_frameworks(), include_trace)
            training_contract.verify_phase_rules(program, goal)
        except training_contract.ContractError as exc:
            return {'weeks': [], 'compromises': [], 'validation_errors': [
                {'code': 'TRAINING_CONTRACT_UNFULFILLED', 'message': str(exc)}],
                'training_contract': {'status': 'unfulfilled'}}
        program['coverage_report'] = _build_coverage_report(program, policy)
        if output_format == 'dict':
            return program
        return format_program(program, goal, constraints, validation)
    run = start(goal, constraints, data, lib, policy, injury_flags_data, include_trace)
    run.prime(entries)
    for week_index, entry in enumerate(entries):
        run.week(week_index, entry)
    return run.finish(entries, output_format, validation)


class ProgramRun(NamedTuple):
    prime: object
    week: object
    note_regions: object
    finish: object
    program: dict


def start(goal: dict, constraints: dict, data: dict, lib: dict, policy, injury_flags_data: dict,
          include_trace: bool = False) -> ProgramRun:
    """The goal ready to generate week by week (what `generate` loops over):
    `prime(entries)` replays a templated track's elapsed weeks, `week(index,
    entry)` builds one week and appends it to `program`, `finish(entries,
    output_format, validation)` closes the program. A composition
    (src/composition.py) passes a week its own `plan_constraints` (the days and
    minutes the other tracks leave) and has `note_regions` record what the
    other tracks load each day."""
    archetypes = lib['archetypes']
    exercises  = lib['exercises']
    modalities = lib['modalities']
    # Pool used when the philosophy's own archetypes cannot cover a scheduled
    # modality. Under a strict policy that stays inside the allowed packages and
    # the session is reported as a coverage gap; otherwise it is the whole
    # library, which is the legacy permissive behaviour.
    fallback_archetypes = archetypes if policy.strict else lib['all_archetypes']
    # Each archetype's heavily loaded regions, for the picker's regional rule.
    arch_regions = {a['id']: recovery_regions.heavy(recovery_regions.archetype_load(a, lib['all_exercises'], modalities))
                    for a in fallback_archetypes}
    track_id = (goal.get('track') or {}).get('id')
    program = {'weeks': []}
    # A templated phase's rotation through each category's workouts, and
    # whether each workout fits the athlete as written (per phase).
    template_rotation: dict = {}
    template_fits: dict = {}
    template_recent: list = []
    archetypes_by_id = {a['id']: a for a in archetypes}

    def _template_fits(entry: dict):
        """Whether the athlete can do a named workout as written in this
        week's phase, in so many minutes (cached per phase)."""
        _phase, _week = entry['phase'], entry['week_in_phase']
        _excluded = frozenset(entry.get('exclude_exercises') or ())
        _key = entry.get('phase_id') or _phase

        def fits(arch: dict, minutes: float) -> bool:
            if (arch.get('duration_estimate_minutes') or 0) > minutes:
                return False
            key = (arch['id'], _key)
            if key not in template_fits:
                template_fits[key] = _fits_as_written(
                    arch, constraints, _phase,
                    lambda a: populate_session(
                        {'modality': a.get('modality')}, goal, constraints, exercises, archetypes,
                        injury_flags_data, _phase, _week, [], [], forced_archetype=a,
                        exercises_by_package=lib.get('exercises_by_package'), policy=policy,
                        level_seeds=lib.get('level_seeds'), exclude_exercise_ids=_excluded,
                        pinned_lifts=None, unfilled_cache={}))
            return template_fits[key]
        return fits


    def prime(entries: list) -> None:
        """Replay the weeks before a mid-track regenerate's first."""
        if entries and entries[0].get('week_template'):
            # A regenerate from mid-track carries on where the track stands: the
            # weeks before it are planned again (cheaply: fits are cached) so each
            # pool's rotation and the last week's picks are what they were.
            all_frameworks = loader.load_all_frameworks()
            for prior in week_template.prior_entries(goal.get('phase_sequence') or [], entries[0]):
                fw = all_frameworks.get(prior.get('framework_id')) or {}
                if fw.get('categories'):
                    week_template.plan_week(prior, fw, constraints, archetypes_by_id, template_rotation,
                                            _template_fits(prior), template_recent)
    recent_arch_ids: list[str] = []
    recent_ex_ids:   list[str] = []
    # Each phase's main lifts, (archetype id, slot index) -> exercise id; reset
    # when the phase changes, because a new phase may move to a new lift.
    pinned_lifts: dict = {}
    unfilled_cache: dict = {}  # why a slot came up empty, explained once per phase
    pinned_phase = None
    # Last week's {day: [modality]}: its end counts against this week's start.
    prev_week_modalities: dict | None = None
    all_compromises: list[str] = []  # Collect compromises from all weeks
    # Day of the program (week index x 7 + day) -> the regions its sessions
    # loaded heavily, so the picker knows what yesterday asked of the body.
    region_days: dict[int, frozenset] = {}

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


    def week(week_index: int, entry: dict, plan_constraints: dict | None = None) -> dict:
        """Build one week; `plan_constraints` (a composition's) decide its days
        and minutes in place of the athlete's whole week."""
        nonlocal pinned_lifts, unfilled_cache, pinned_phase, prev_week_modalities
        phase          = entry['phase']
        week_in_phase  = entry['week_in_phase']
        week_in_program = entry.get('week_in_program', week_in_phase)
        phase_framework_id = entry.get('framework_id')  # Phase-specific framework override
        phase_excluded = frozenset(entry.get('exclude_exercises') or ())
        phase_key = entry.get('phase_id') or phase
        if phase_key != pinned_phase:
            pinned_lifts, unfilled_cache, pinned_phase = {}, {}, phase_key
        week_pins = None if entry.get('rotate_main_lifts') else pinned_lifts

        # 1. Build the modality→day schedule
        sched_result = schedule_week(goal, constraints, data, phase, week_in_phase,
                                     phase_framework_id=phase_framework_id,
                                     collect_trace=include_trace, prev_week=prev_week_modalities)
        week_schedule = sched_result['schedule']
        is_deload     = sched_result['is_deload']
        framework     = sched_result['framework']
        deload_keep   = (framework.get('deload_protocol') or {}).get('volume_reduction_pct')

        # Collect compromises from this week (only unique ones)
        week_compromises = sched_result.get('compromises', [])
        template_left_out: dict = {}
        if entry.get('week_template') and framework.get('categories'):
            # The source's own week, day by day: each day the next named
            # workout of its category the athlete can do as written.
            week_schedule, week_compromises = week_template.plan_week(
                entry, framework, plan_constraints or constraints, archetypes_by_id, template_rotation,
                _template_fits(entry), template_recent, template_left_out)
        for compromise in week_compromises:
            if compromise not in all_compromises:
                all_compromises.append(compromise)
        prev_week_modalities = {d: [s['modality'] for s in ss if s.get('modality')]
                                for d, ss in week_schedule.items()}

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
            if entry.get('week_template') and framework.get('categories'):
                # The source's week decided the days, not the modality schedule.
                week_trace['scheduler'] = {
                    'week_template': entry['week_template'], 'is_deload': is_deload,
                    'framework_selection': {'selected_id': framework['id'],
                                            'selection_reason': 'week_template'}}

        # 2. Populate each session with archetype + exercises + loads
        populated_schedule: dict[int, list] = {}

        # Resolve every day first (pure), so the week's tests can be put in
        # place of the sessions they replace before anything is populated.
        resolved_by_day = {day: _resolve_session(week_schedule[day], archetypes, fallback_archetypes,
                                                 constraints, phase)
                           for day in sorted(week_schedule.keys())}

        def _populate_test(test_session: dict, arch: dict) -> dict:
            return populate_session(
                test_session, goal, constraints, exercises, archetypes,
                injury_flags_data, phase, week_in_phase,
                recent_arch_ids, recent_ex_ids,
                forced_archetype=arch,
                exercises_by_package=lib.get('exercises_by_package'),
                policy=policy, level_seeds=lib.get('level_seeds'),
                exclude_exercise_ids=phase_excluded,
                pinned_lifts=None, deload_keep=deload_keep, unfilled_cache={},
            )

        # A templated day nothing fitted may still take the phase's test (the
        # PT test on a hard job-specific day the athlete's injury emptied).
        categories = framework.get('categories') or {}
        for day, cat in template_left_out.items():
            resolved_by_day[day] = [{'modality': categories[cat]['modality'], 'category': cat, '_placeholder': True}]
        placed_tests, skipped_tests = _plan_week_tests(entry, resolved_by_day, archetypes,
                                                       plan_constraints or constraints, is_deload, _populate_test)
        for day in template_left_out:
            if (day, 0) not in placed_tests:
                del resolved_by_day[day]
        week_schedule = {d: v for d, v in week_schedule.items()} | {d: [] for d in template_left_out
                                                                     if d in resolved_by_day}

        for day in sorted(week_schedule.keys()):
            populated_sessions = []
            day_name = _GEN_DAY_NAMES[day - 1] if 1 <= day <= 7 else f'Day {day}'
            day_session_traces: list[dict] = []

            # A split day's mobility session prefers an archetype that declares
            # it `complements` the day's primary modality (scheduler pairing).
            day_cfg = constraints.get('day_configs', {}).get(day, {})
            complements = day_cfg.get('mobility_complements')
            # Every one that does; the selector filters them (level, equipment,
            # phase) before the preference applies.
            mobility_hint = frozenset(a['id'] for a in archetypes if a.get('modality') == 'mobility'
                                      and complements in (a.get('complements') or [])) if complements else None
            day_session_types = day_cfg.get('session_types')

            program_day = week_index * 7 + day
            recent_regions = [((program_day - d) * 24, regions) for d, regions in region_days.items()
                              if 0 < program_day - d <= 2 and regions]
            for idx, session in enumerate(resolved_by_day[day]):
                test = placed_tests.get((day, idx))
                # Determine if this session should use the mobility hint
                preferred_arch = None
                if session['modality'] == 'mobility' and mobility_hint:
                    preferred_arch = mobility_hint

                forced = session.pop('_forced_archetype', None)
                # Commons fallback: use full archetype pool with relaxed equipment
                is_commons_fallback = session.pop('_commons_fallback', False)
                substituted_for = session.pop('_substituted_for', None)
                session_archetypes = fallback_archetypes if is_commons_fallback else archetypes

                # Record compromise message for commons fallback (once per unique substitution)
                if is_commons_fallback:
                    orig_modality = session['modality'].replace('_', ' ')
                    msg = f"{orig_modality} substituted with bodyweight/equipment-limited alternative (no matching gym equipment)"
                    if msg not in all_compromises:
                        all_compromises.append(msg)

                # Select archetype + exercises. A test was populated when it was
                # placed; the session it stands in for is still selected, so the
                # rest of the program rotates exactly as it would have without
                # the test (its picks feed the recency lists below).
                # A placeholder day (nothing fitted; the test took it) stands
                # in for no session.
                rotation_source = {'exercises': []} if session.pop('_placeholder', False) else populate_session(
                    session, goal, constraints, exercises, session_archetypes,
                    injury_flags_data, phase, week_in_phase,
                    recent_arch_ids, recent_ex_ids,
                    collect_trace=include_trace,
                    forced_archetype=forced,
                    exercises_by_package=lib.get('exercises_by_package'),
                    preferred_archetype_id=preferred_arch,
                    day_session_types=day_session_types,
                    relax_equipment=is_commons_fallback,
                    policy=policy,
                    level_seeds=lib.get('level_seeds'),
                    exclude_exercise_ids=phase_excluded,
                    pinned_lifts=None if forced else week_pins,
                    deload_keep=deload_keep,
                    unfilled_cache=unfilled_cache,
                    recent_regions=recent_regions,
                    arch_regions=arch_regions,
                )
                populated = test['populated'] if test is not None else rotation_source

                session_trace: dict | None = None
                if include_trace:
                    session_trace = rotation_source.pop('session_trace', {}) if test is None \
                        else populated.pop('session_trace', {})
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
                # The week's framework may prescribe a modality its own way
                # (Filly's strength work as RPE targets); else the modality's.
                from .training_contract import resolve_model
                prog = resolve_model(framework, mod_id, modalities)

                # The session a test stands in for, prescribed as it would have
                # been: what the week would have trained, recorded on the test
                # so the plan's minutes and intensity read it as that session.
                if test is not None:
                    for ea in rotation_source.get('exercises', []):
                        if ea.get('exercise') is not None:
                            ea['load'] = calculate_load(
                                ea['exercise'], ea['slot'], prog, week_in_phase, phase,
                                constraints.get('training_level', 'intermediate'), is_deload,
                                session_time_minutes=constraints.get('session_time_minutes', 75),
                                deload_keep=deload_keep)
                    populated['test']['instead_of'] = _stand_in(rotation_source)

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
                        deload_keep=deload_keep,
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

                    # Track exercise variety (from the session a test stands in for)
                    if test is None:
                        recent_ex_ids.append(ea['exercise']['id'])
                        if len(recent_ex_ids) > 40:
                            recent_ex_ids.pop(0)
                if test is not None:
                    for ea in rotation_source.get('exercises', []):
                        if ea.get('exercise') is not None:
                            recent_ex_ids.append(ea['exercise']['id'])
                            if len(recent_ex_ids) > 40:
                                recent_ex_ids.pop(0)

                # A session scheduled as another modality because the package
                # has no archetype for this one in this phase at this level
                # (_resolve_session pass 3). Say so on the session, once in the
                # compromises, and in the coverage report.
                # Picked with the equipment filter relaxed (pass 2): the
                # archetype's equipment the athlete lacks, so the session can
                # say it runs scaled instead of only the compromise line.
                if is_commons_fallback and test is None:
                    lacking = blockers.missing_equipment(
                        (populated.get('archetype') or {}).get('required_equipment'),
                        constraints.get('equipment'))
                    if lacking:
                        populated['equipment_scaled'] = lacking

                if substituted_for:
                    populated['substituted_for'] = substituted_for
                    level = constraints.get('training_level', 'intermediate')
                    # Name the cause: no archetype written for this level at
                    # all, or none for this phase (an archetype naming no
                    # levels is open to all of them).
                    own = [a for a in archetypes if a.get('modality') == substituted_for]
                    level_gap = bool(own) and all(a.get('training_levels') and level not in a['training_levels']
                                                  for a in own)
                    populated['substitution_cause'] = 'level' if level_gap else 'phase'
                    why = f"for a {level} athlete" if level_gap else f"for the {phase} phase"
                    msg = (f"No {substituted_for.replace('_', ' ')} session in {policy.describe()} {why} — "
                           f"scheduled as {session['modality'].replace('_', ' ')} instead.")
                    if msg not in all_compromises:
                        all_compromises.append(msg)

                if rotation_source.get('archetype'):
                    recent_arch_ids.append(rotation_source['archetype']['id'])
                    if len(recent_arch_ids) > 14:
                        recent_arch_ids.pop(0)

                # Tag which package this session actually came from, so a borrowed
                # session can be labelled instead of silently passing as the
                # philosophy's own.
                if populated.get('archetype'):
                    tag = provenance.origin(populated['archetype'], policy, kind='archetype')
                    if tag:
                        populated['provenance'] = tag

                # Complementary recovery work — mobility/rehab exercises targeting stressed patterns
                session_package = (populated.get('archetype') or {}).get('_package')
                recovery_exercises = data['exercises_by_package'].get(session_package, {})
                # A named workout is the day as the source writes it: no extras.
                comp = None if forced else _select_complementary(populated.get('exercises', []), recovery_exercises)
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
            region_days[program_day] = region_days.get(program_day, frozenset()).union(
                *(recovery_regions.heavy(recovery_regions.session_load(s, modalities)) for s in populated_sessions))
            if include_trace and week_trace is not None:
                week_trace['sessions'][day_name] = day_session_traces

        week_out = {
            'week_number':    week_in_program,
            'week_in_phase':  week_in_phase,
            'phase':          phase,
            'is_deload':      is_deload,
            'schedule':       populated_schedule,
            'framework':      framework['id'],
        }
        if entry.get('phase_id'):
            week_out['phase_id'] = entry['phase_id']
        if entry.get('phase_name'):
            week_out['phase_name'] = entry['phase_name']
        if track_id:
            week_out['track_id'] = track_id
        if skipped_tests:
            week_out['tests_skipped'] = skipped_tests
        program['weeks'].append(week_out)
        if include_trace and generation_trace is not None and week_trace is not None:
            generation_trace['weeks'].append(week_trace)
        return week_out

    def note_regions(week_index: int, day: int, regions: frozenset) -> None:
        """What another track's session loads on a day, for the picker's regional rule."""
        key = week_index * 7 + day
        region_days[key] = region_days.get(key, frozenset()) | regions

    def finish(entries: list, output_format: str = 'dict', validation=None):
        # Add compromises to program
        program['compromises'] = all_compromises
        if entries and all(e.get('week_template') for e in entries) and \
                not any(w['schedule'] for w in program['weeks']):
            # Nothing of the source fits as written (Horsemen has no novice path;
            # an athlete without its gear gets none of its workouts): say so
            # rather than hand back weeks of rest.
            level = constraints.get('training_level', 'intermediate')
            return {'weeks': [], 'compromises': all_compromises,
                    'coverage_report': _build_coverage_report({}, policy),
                    'validation_errors': [{
                        'code': 'TEMPLATE_UNFILLED',
                        'message': (f"None of this track's named workouts can be done as written by a {level} "
                                    'athlete with this equipment and these injuries.'),
                        'suggested_fix': 'The source is written for experienced athletes with a full gym; '
                                         'check the training level and equipment.'}]}
        program['coverage_report'] = _build_coverage_report(program, policy)

        if output_format == 'dict':
            if include_trace and generation_trace is not None:
                program['generation_trace'] = generation_trace
            return program

        return format_program(program, goal, constraints, validation)

    return ProgramRun(prime=prime, week=week, note_regions=note_regions, finish=finish, program=program)
