"""Select archetypes and exercises for each session."""
from __future__ import annotations
import os as _os
import yaml as _yaml
from typing import Optional

# ---------------------------------------------------------------------------
# Movement pattern aliases — loaded from data/movement_patterns.yaml
# Archetype slots use shorthand; exercises use schema IDs.
# Each entry is (mode, patterns):
#   'or'       — exercise needs ANY of the patterns (collective alias)
#   'and'      — exercise needs ALL of the patterns (compound movement)
#   'category' — match by exercise category instead of movement_patterns
# ---------------------------------------------------------------------------
_mp_path = _os.path.join(_os.path.dirname(__file__), '..', 'data', 'commons', 'movement_patterns.yaml')
_PATTERN_ALIASES: dict[str, tuple] = {
    k: (v['mode'], v['patterns'])
    for k, v in _yaml.safe_load(open(_mp_path))['aliases'].items()
}

# ---------------------------------------------------------------------------
# Training-level prerequisite seeding
# ---------------------------------------------------------------------------
_LEVEL_CONCEPTS: dict[str, set] = {
    'novice': set(),
    'intermediate': {
        'hip_hinge', 'bracing_mechanics', 'bracing', 'squat_pattern',
        'push_pattern', 'pull_pattern', 'hanging', 'shoulder_stability',
        # Exercise IDs assumed known at intermediate
        'deadlift', 'back_squat', 'front_squat', 'strict_press', 'bench_press',
        'pull_up', 'pull_up_strict', 'dip_strict',
        'kb_swing_two_hand', 'kb_clean', 'kb_goblet_squat',
        # Carries — seeded directly to avoid multi-hop prerequisite chain limitation
        'farmer_carry_kb', 'rack_carry_kb', 'overhead_carry_kb',
        'run_easy', 'open_space',
    },
    'advanced': {
        'hip_hinge', 'bracing_mechanics', 'bracing', 'squat_pattern',
        'push_pattern', 'pull_pattern', 'hanging',
        'deadlift', 'back_squat', 'front_squat', 'strict_press', 'bench_press',
        'pull_up', 'pull_up_strict', 'dip_strict', 'muscle_up',
        'power_clean', 'hang_power_clean',
        'kb_swing_two_hand', 'kb_swing_single_arm', 'kb_clean', 'kb_snatch',
        'handstand_hold', 'handstand_push_up',
        'run_easy', 'run_tempo', 'open_space',
    },
}


def _get_unlocked(training_level: str, exercises: dict) -> set:
    """Return set of exercise IDs accessible at this training level."""
    if training_level == 'elite':
        return set(exercises.keys())

    known = _LEVEL_CONCEPTS.get(training_level, set())
    unlocked = set()
    for ex_id, ex in exercises.items():
        requires = ex.get('requires', [])
        if not requires:
            unlocked.add(ex_id)
        elif all(r in known for r in requires):
            unlocked.add(ex_id)
    return unlocked


# ---------------------------------------------------------------------------
# Filter helpers
# ---------------------------------------------------------------------------

def _equipment_ok(ex: dict, available: set) -> bool:
    required = set(ex.get('equipment', [])) - {'open_space', 'none'}
    return required.issubset(available)


def _matches_slot_filter(ex: dict, ex_filter: dict, excluded_patterns: set) -> bool:
    """Check category, movement_pattern, and injury exclusion."""
    # Category filter
    req_cat = ex_filter.get('category')
    if req_cat and ex.get('category') != req_cat:
        return False

    # Movement-pattern filter (uses aliases with or/and/category modes)
    req_pattern = ex_filter.get('movement_pattern')
    if req_pattern:
        alias = _PATTERN_ALIASES.get(req_pattern)
        ex_patterns = set(ex.get('movement_patterns', []))

        if alias is None:
            # Unknown alias — direct match
            if req_pattern not in ex_patterns:
                return False
        else:
            mode, patterns = alias
            if mode == 'or':
                if not ex_patterns.intersection(patterns):
                    return False
            elif mode == 'and':
                if not all(p in ex_patterns for p in patterns):
                    return False
            elif mode == 'category':
                # Match by category field instead of movement pattern
                if ex.get('category') not in patterns:
                    return False

    # Explicit slot-level pattern exclusion (e.g. exclude_movement_pattern: ballistic)
    excl_slot_pattern = ex_filter.get('exclude_movement_pattern')
    if excl_slot_pattern:
        if excl_slot_pattern in set(ex.get('movement_patterns', [])):
            return False

    # Injury exclusion via movement patterns
    if excluded_patterns:
        ex_patterns = set(ex.get('movement_patterns', []))
        if ex_patterns.intersection(excluded_patterns):
            return False

    return True


def _injury_exclusions(constraints: dict, injury_flags_data: dict) -> tuple[set, set]:
    """Return (excluded_movement_patterns, excluded_exercise_ids)."""
    excl_patterns: set = set()
    excl_ids: set = set()
    for flag_id in constraints.get('injury_flags', []):
        flag = injury_flags_data.get(flag_id, {})
        excl_patterns.update(flag.get('excluded_movement_patterns', []))
        excl_ids.update(flag.get('excluded_exercises', []))
    return excl_patterns, excl_ids


def _slot_injury_blocked(slot: dict, excl_patterns: set) -> bool:
    """Return True if a slot's required movement pattern is fully excluded by injury flags."""
    if not excl_patterns:
        return False
    slot_pattern = slot.get('exercise_filter', {}).get('movement_pattern')
    if not slot_pattern:
        return False
    alias = _PATTERN_ALIASES.get(slot_pattern)
    if alias is not None:
        mode, patterns = alias
        if mode == 'and' and any(p in excl_patterns for p in patterns):
            return True
        if mode == 'or' and all(p in excl_patterns for p in patterns):
            return True
    elif slot_pattern in excl_patterns:
        return True
    return False


# ---------------------------------------------------------------------------
# Archetype selection
# ---------------------------------------------------------------------------

def select_archetype(
    modality: str,
    constraints: dict,
    phase: str,
    is_deload: bool,
    goal: dict,
    archetypes: list,
    recent_ids: list | None = None,
    excl_patterns: set | None = None,
    return_trace: bool = False,
) -> Optional[dict]:
    """Pick the best archetype for a session slot.

    When return_trace=True returns (archetype, trace_dict) instead of just archetype.
    """
    available_equip = set(constraints.get('equipment', []))
    session_time = constraints.get('session_time_minutes', 75)
    training_level = constraints.get('training_level', 'intermediate')
    recent = set(recent_ids or [])
    primary_sources = set(goal.get('primary_sources', []))

    n_modality = 0
    n_phase = 0
    n_level = 0
    n_equip = 0

    candidates = []
    for arch in archetypes:
        if arch.get('modality') != modality:
            continue
        n_modality += 1

        # Phase filter
        applicable = arch.get('applicable_phases', [])
        if applicable and phase not in applicable:
            continue
        n_phase += 1

        # Training level filter (e.g. novice-only archetypes not shown to intermediate+)
        applicable_levels = arch.get('training_levels', [])
        if applicable_levels and training_level not in applicable_levels:
            continue
        n_level += 1

        # Equipment filter
        required = set(arch.get('required_equipment', [])) - {'open_space'}
        if not required.issubset(available_equip):
            if not arch.get('scaling', {}).get('equipment_limited'):
                continue  # no scaling — skip
        n_equip += 1

        # Duration filter
        duration = arch.get('duration_estimate_minutes', 60)
        if is_deload:
            deload_sc = arch.get('scaling', {}).get('deload', {})
            duration = deload_sc.get('duration_estimate_minutes', int(duration * 0.7))
        if duration > session_time:
            if not arch.get('scaling', {}).get('time_limited'):
                continue  # no time-limited scaling — skip

        candidates.append(arch)

    _excl = excl_patterns or set()

    def _score_arch(arch: dict) -> tuple:
        score = 0
        # Prefer archetypes whose equipment is fully satisfied over equipment_limited fallbacks.
        # Bonus must exceed the max recency penalty (-3) so a recently-used fully-equipped
        # archetype always beats an equipment-limited one.
        required = set(arch.get('required_equipment', [])) - {'open_space'}
        if required.issubset(available_equip):
            score += 6
        for src in arch.get('sources', []):
            src_lower = src.lower()
            for ps in primary_sources:
                key = ps.replace('_gpp', '').replace('_', ' ').lower()
                if key in src_lower:
                    score += 2
                    break
        if arch['id'] in recent:
            score -= 3
        # Penalise archetypes with a high injury-skip rate: prefer alternatives
        # that can actually be executed with the athlete's active injury constraints.
        if _excl:
            slots = [s for s in arch.get('slots', []) if not s.get('skip_exercise')]
            if slots:
                skipped = sum(1 for s in slots if _slot_injury_blocked(s, _excl))
                skip_rate = skipped / len(slots)
                score -= round(skip_rate * 8)
        return (score, arch['id'])  # id as stable tiebreaker

    if not candidates:
        if not return_trace:
            return None
        return None, {
            'selected_id': None,
            'filter_counts': {
                'by_modality': n_modality, 'by_phase': n_phase,
                'by_level': n_level, 'by_equipment': n_equip,
                'by_duration': 0, 'final': 0,
            },
            'candidates': [],
        }

    candidates.sort(key=_score_arch, reverse=True)
    selected = candidates[0]

    if not return_trace:
        return selected

    def _breakdown(arch: dict) -> dict:
        equip_bonus = 0
        source_bonus = 0
        recency_penalty = 0
        injury_penalty = 0
        required = set(arch.get('required_equipment', [])) - {'open_space'}
        if required.issubset(available_equip):
            equip_bonus = 6
        for src in arch.get('sources', []):
            src_lower = src.lower()
            for ps in primary_sources:
                key = ps.replace('_gpp', '').replace('_', ' ').lower()
                if key in src_lower:
                    source_bonus += 2
                    break
        if arch['id'] in recent:
            recency_penalty = -3
        if _excl:
            slots = [s for s in arch.get('slots', []) if not s.get('skip_exercise')]
            if slots:
                skipped = sum(1 for s in slots if _slot_injury_blocked(s, _excl))
                injury_penalty = -round((skipped / len(slots)) * 8)
        return {
            'equipment': equip_bonus,
            'source': source_bonus,
            'recency': recency_penalty,
            'injury_penalty': injury_penalty,
            'total': equip_bonus + source_bonus + recency_penalty + injury_penalty,
        }

    trace = {
        'selected_id': selected['id'],
        'filter_counts': {
            'by_modality': n_modality, 'by_phase': n_phase,
            'by_level': n_level, 'by_equipment': n_equip,
            'by_duration': len(candidates), 'final': len(candidates),
        },
        'candidates': [
            {
                'id': arch['id'],
                'name': arch.get('name', arch['id']),
                'score': _score_arch(arch)[0],
                'breakdown': _breakdown(arch),
            }
            for arch in candidates
        ],
    }
    return selected, trace


# ---------------------------------------------------------------------------
# Exercise selection
# ---------------------------------------------------------------------------

def select_exercise(
    slot: dict,
    constraints: dict,
    exercises: dict,
    unlocked_ids: set,
    excl_patterns: set,
    excl_ids: set,
    recent_ex_ids: list | None = None,
    phase: str = 'base',
    session_used_ids: list | None = None,
    return_trace: bool = False,
) -> Optional[dict]:
    """Pick the best exercise for an archetype slot.

    When return_trace=True returns (exercise, trace_dict) instead of just exercise.
    """
    available_equip = set(constraints.get('equipment', []))
    recent = recent_ex_ids or []
    session_used = set(session_used_ids or [])
    ex_filter = slot.get('exercise_filter', {})

    n_pool = 0
    n_equip = 0
    n_filter = 0

    candidates = []
    for ex_id in unlocked_ids:
        if ex_id in excl_ids:
            continue
        ex = exercises.get(ex_id)
        if ex is None:
            continue

        # Contraindication check
        if set(ex.get('contraindicated_with', [])).intersection(
                set(constraints.get('injury_flags', []))):
            continue
        n_pool += 1

        # Equipment
        if not _equipment_ok(ex, available_equip):
            continue
        n_equip += 1

        # Slot filter
        if not _matches_slot_filter(ex, ex_filter, excl_patterns):
            continue
        n_filter += 1

        # Taper: no max-effort exercises
        if phase == 'taper' and ex.get('effort') == 'max':
            continue

        slot_intensity = ex_filter.get('intensity') or slot.get('intensity', '')
        slot_type = slot.get('slot_type', '')

        # AMRAP / for_time / circuit slots: skill and mobility exercises are poor fits
        # (these slots need compound, repeatable movements under fatigue)
        if slot_type in ('amrap', 'amrap_movement', 'for_time') and ex.get('category') in ('skill', 'mobility', 'rehab'):
            continue

        # Zone1-2 aerobic time_domain slots: only low-effort exercises
        # (prevents tempo runs / threshold exercises appearing in easy aerobic slots)
        # Does NOT apply to distance/carry slots — ruck_carry is medium effort but zone2 pace
        if (slot_intensity in ('zone1', 'zone2')
                and slot_type == 'time_domain'
                and ex_filter.get('category') == 'aerobic'
                and ex.get('effort') not in ('low', None, '')):
            continue

        candidates.append(ex)

    def _score_ex(ex: dict) -> tuple:
        recency_penalty = sum(2 for eid in recent if eid == ex['id'])
        forward_bonus = 0.5 if ex.get('unlocks') else 0
        # Prefer exercises that have defined movement patterns over joint drills / stub entries
        pattern_bonus = 0.5 if ex.get('movement_patterns') else 0
        return (-recency_penalty + forward_bonus + pattern_bonus, ex['id'])

    if not candidates:
        if not return_trace:
            return None
        return None, {
            'selected_id': None,
            'injury_blocked': _slot_injury_blocked(slot, excl_patterns),
            'filter_counts': {
                'in_pool': n_pool, 'after_equip': n_equip,
                'after_filter': n_filter, 'final': 0,
            },
            'candidates': [],
        }

    candidates.sort(key=_score_ex, reverse=True)

    # Prefer exercises not already used in this session (two-pass: fresh first, fallback to any)
    fresh = [ex for ex in candidates if ex['id'] not in session_used]
    selected = (fresh if fresh else candidates)[0]

    if not return_trace:
        return selected

    # Limit candidate list to top 10 for trace (can be large otherwise)
    top_candidates = candidates[:10]
    trace = {
        'selected_id': selected['id'],
        'injury_blocked': False,
        'filter_counts': {
            'in_pool': n_pool, 'after_equip': n_equip,
            'after_filter': n_filter, 'final': len(candidates),
        },
        'candidates': [
            {
                'id': ex['id'],
                'name': ex.get('name', ex['id']),
                'score': round(_score_ex(ex)[0], 2),
                'breakdown': {
                    'recency_penalty': -sum(2 for eid in recent if eid == ex['id']),
                    'unlocks_bonus': 0.5 if ex.get('unlocks') else 0,
                    'pattern_bonus': 0.5 if ex.get('movement_patterns') else 0,
                },
            }
            for ex in top_candidates
        ],
    }
    return selected, trace


# ---------------------------------------------------------------------------
# Session population
# ---------------------------------------------------------------------------

def populate_session(
    session: dict,
    goal: dict,
    constraints: dict,
    exercises: dict,
    archetypes: list,
    injury_flags_data: dict,
    phase: str,
    week_number: int,
    recent_arch_ids: list | None = None,
    recent_ex_ids: list | None = None,
    collect_trace: bool = False,
    forced_archetype: dict | None = None,
    exercises_by_package: dict | None = None,
) -> dict:
    """Populate a session with an archetype and exercises.

    When collect_trace=True the result dict includes a 'session_trace' key with
    archetype selection and per-slot exercise selection trace data.

    When forced_archetype is provided, archetype selection is skipped and the
    given archetype dict is used directly (used by the single-session replace endpoint).
    """
    modality = session['modality']
    is_deload = session.get('is_deload', False)

    excl_patterns, excl_ids = _injury_exclusions(constraints, injury_flags_data)
    training_level = constraints.get('training_level', 'intermediate')
    unlocked = _get_unlocked(training_level, exercises) - excl_ids

    # Select archetype
    if forced_archetype is not None:
        arch = forced_archetype
        arch_trace: dict = {}
    elif collect_trace:
        arch_result = select_archetype(
            modality, constraints, phase, is_deload,
            goal, archetypes, recent_arch_ids,
            excl_patterns=excl_patterns,
            return_trace=True,
        )
        arch, arch_trace = arch_result if isinstance(arch_result, tuple) else (arch_result, {})
    else:
        arch = select_archetype(
            modality, constraints, phase, is_deload,
            goal, archetypes, recent_arch_ids,
            excl_patterns=excl_patterns,
        )

    if arch is None:
        result = {**session, 'archetype': None, 'exercises': [],
                  'error': f'No archetype found for {modality}'}
        if collect_trace:
            result['session_trace'] = {
                'modality': modality,
                'archetype': arch_trace if collect_trace else {},
                'slots': [],
            }
        return result

    # Overlay package-specific exercise definitions (prescription fields, etc.)
    arch_package = arch.get('_package')
    if arch_package and exercises_by_package and arch_package in exercises_by_package:
        pkg_exs = exercises_by_package[arch_package]
        exercises = {
            **exercises,
            **{
                ex_id: {**exercises[ex_id], **pkg_ex} if ex_id in exercises else pkg_ex
                for ex_id, pkg_ex in pkg_exs.items()
            },
        }

    # Populate slots
    used_ex_ids = list(recent_ex_ids or [])
    session_used_ids: list[str] = []  # tracks only current-session picks for intra-session dedup
    exercise_assignments = []
    slot_traces: list[dict] = []

    for i, slot in enumerate(arch.get('slots', [])):
        slot_role = slot.get('role', f'slot_{i}')
        slot_type = slot.get('slot_type', 'sets_reps')

        # Meta/structural slots don't get individual exercise assignments
        if slot.get('skip_exercise'):
            exercise_assignments.append({
                'slot_index': i,
                'slot_role': slot_role,
                'slot_type': slot_type,
                'exercise': None,
                'slot': slot,
                'meta': True,
            })
            if collect_trace:
                slot_traces.append({
                    'slot_index': i, 'slot_role': slot_role,
                    'slot_type': slot_type, 'meta': True,
                    'movement_pattern': None, 'selected_id': None,
                    'injury_blocked': False, 'filter_counts': {},
                    'candidates': [],
                })
            continue

        if collect_trace:
            ex_result = select_exercise(
                slot, constraints, exercises, unlocked,
                excl_patterns, excl_ids, used_ex_ids, phase,
                session_used_ids=session_used_ids,
                return_trace=True,
            )
            ex, ex_trace = ex_result if isinstance(ex_result, tuple) else (ex_result, {})
        else:
            ex = select_exercise(
                slot, constraints, exercises, unlocked,
                excl_patterns, excl_ids, used_ex_ids, phase,
                session_used_ids=session_used_ids,
            )

        if ex is None:
            injury_blocked = _slot_injury_blocked(slot, excl_patterns)
            exercise_assignments.append({
                'slot_index': i,
                'slot_role': slot_role,
                'slot_type': slot_type,
                'exercise': None,
                'slot': slot,
                'injury_skip': injury_blocked,
                'error': (
                    f"skipped — {slot.get('exercise_filter', {}).get('movement_pattern')} excluded by injury flag"
                    if injury_blocked
                    else f"No exercise for slot '{slot.get('role')}'"
                ),
            })
            if collect_trace:
                slot_traces.append({
                    'slot_index': i, 'slot_role': slot_role, 'slot_type': slot_type,
                    'meta': False,
                    'movement_pattern': slot.get('exercise_filter', {}).get('movement_pattern'),
                    **(ex_trace if ex_trace else {
                        'selected_id': None, 'injury_blocked': injury_blocked,
                        'filter_counts': {}, 'candidates': [],
                    }),
                })
        else:
            used_ex_ids.append(ex['id'])
            session_used_ids.append(ex['id'])
            exercise_assignments.append({
                'slot_index': i,
                'slot_role': slot_role,
                'slot_type': slot_type,
                'exercise': ex,
                'slot': slot,
            })
            if collect_trace:
                slot_traces.append({
                    'slot_index': i, 'slot_role': slot_role, 'slot_type': slot_type,
                    'meta': False,
                    'movement_pattern': slot.get('exercise_filter', {}).get('movement_pattern'),
                    **(ex_trace if ex_trace else {
                        'selected_id': ex['id'], 'injury_blocked': False,
                        'filter_counts': {}, 'candidates': [],
                    }),
                })

    # Compute the effective duration (deload-scaled and time-capped) and store it on
    # the archetype so output.py and the frontend render the correct session length.
    effective_duration = arch.get('duration_estimate_minutes', 60)
    if is_deload:
        deload_sc = arch.get('scaling', {}).get('deload', {})
        effective_duration = deload_sc.get('duration_estimate_minutes', int(effective_duration * 0.7))
    session_time = constraints.get('session_time_minutes', 9999)
    if effective_duration > session_time:
        effective_duration = session_time
    if effective_duration != arch.get('duration_estimate_minutes'):
        arch = {**arch, 'duration_estimate_minutes': effective_duration}

    result = {**session, 'archetype': arch, 'exercises': exercise_assignments}
    if collect_trace:
        result['session_trace'] = {
            'modality': modality,
            'archetype': arch_trace,
            'slots': slot_traces,
        }
    return result
