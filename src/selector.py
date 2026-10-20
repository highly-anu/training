"""Select archetypes and exercises for each session."""
from __future__ import annotations
import os as _os
import yaml as _yaml
from typing import Optional
from src.progression import zone_band as _zone_band
from . import blockers, phases, provenance, standard_tests

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
    # Basic movement literacy, not a progression to be earned. Every beginner
    # program teaches bracing and hinging in the first session — granting a novice
    # the empty set meant a novice unlocked nothing in Starting Strength, the
    # method written for novices. Exercise-ID prerequisites (pull_up, front_squat,
    # power_clean) stay gated below: those are genuine progressions.
    'novice': {
        'bracing_mechanics', 'bracing', 'hip_hinge', 'hip_hinge_pattern',
        'squat_pattern', 'push_pattern', 'pull_pattern', 'open_space',
    },
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


_LEVEL_ORDER = ['novice', 'intermediate', 'advanced', 'elite']


def _level_known(training_level: str, level_seeds: dict | None = None) -> set:
    """The concepts and exercise ids assumed known at a level: the built-in
    concepts plus every package seed at that level or below."""
    known = set(_LEVEL_CONCEPTS.get(training_level, set()))
    if level_seeds:
        # Seeds cascade upward: what a novice knows, an advanced athlete knows.
        cutoff = _LEVEL_ORDER.index(training_level) if training_level in _LEVEL_ORDER else 0
        for seeds in level_seeds.values():
            for level in _LEVEL_ORDER[:cutoff + 1]:
                known |= set(seeds.get(level, ()))
    return known


def _get_unlocked(training_level: str, exercises: dict, level_seeds: dict | None = None,
                  also_known: set | None = None) -> set:
    """Return set of exercise IDs accessible at this training level.

    level_seeds: {package_id: {level: set}} from loader.load_level_seeds, already
    narrowed to the packages this goal may use. A package seeds the concepts its
    own athletes are assumed to arrive with — Starting Strength teaches a novice
    to brace and hinge in the first session, and without that seed every one of
    its 13 exercises stayed locked for the novices it is written for.

    also_known: exercise ids the athlete has earned on top of the level — the
    analytics' "movements earned" passes what has been practised, to ask what
    that practice opens.
    """
    if training_level == 'elite':
        return set(exercises.keys())

    known = _level_known(training_level, level_seeds) | set(also_known or ())

    # Resolve prerequisite chains to a fixed point. A requirement is satisfied
    # when it is a known concept OR an exercise that is itself unlocked, so a
    # chain like atg_split_squat -> bulgarian_split_squat_light resolves on its
    # own. Previously only one hop was checked, which is why _LEVEL_CONCEPTS had
    # to seed carries "directly to avoid multi-hop prerequisite chain limitation".
    unlocked: set = set()
    pending = dict(exercises)
    while True:
        newly = {
            ex_id for ex_id, ex in pending.items()
            if all(r in known or r in unlocked for r in (ex.get('requires') or []))
        }
        if not newly:
            break
        unlocked |= newly
        for ex_id in newly:
            pending.pop(ex_id, None)
    return unlocked


# ---------------------------------------------------------------------------
# Filter helpers
# ---------------------------------------------------------------------------

def _equipment_ok(ex: dict, available: set) -> bool:
    required = set(ex.get('equipment', [])) - {'open_space', 'none'}
    return required.issubset(available)


def _matches_slot_filter(ex: dict, ex_filter: dict, excluded_patterns: set) -> bool:
    """Check category, movement_pattern, and injury exclusion."""
    if 'bilateral' in ex_filter and ex.get('bilateral') != ex_filter['bilateral']:
        return False
    if ex_filter.get('equipment_required') and not set(ex_filter['equipment_required']).issubset(ex.get('equipment') or []):
        return False
    # Category filter
    req_cat = ex_filter.get('category')
    if req_cat and ex.get('category') != req_cat:
        return False

    # Explicit id list — a slot whose events are fixed by rules (a pentathlon's five)
    req_ids = ex_filter.get('exercise_ids')
    if req_ids and ex.get('id') not in req_ids:
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


def _blocked_categories_for_equipment(available_equip: set) -> set:
    """Return exercise categories that are unlikely to have any matches given available equipment.

    This is a fast proxy — used for archetype scoring, not for hard filtering.
    """
    blocked: set[str] = set()
    if not available_equip.intersection({'barbell', 'rack', 'plates'}):
        blocked.add('barbell')
    if 'kettlebell' not in available_equip:
        blocked.add('kettlebell')
    if 'sandbag' not in available_equip:
        blocked.add('sandbag')
    if 'dumbbells' not in available_equip:
        blocked.add('dumbbells')
    if not available_equip.intersection({'ruck_pack', 'weight_vest'}):
        blocked.add('carries')
    return blocked


# Slot intensities that mark a loaded main lift, as opposed to a warm-up, an
# accessory or a carry. A slot that names a %1RM is one too.
MAIN_LIFT_INTENSITIES = frozenset({'heavy', 'max', 'max_effort'})


def is_main_lift_slot(slot: dict) -> bool:
    """A sets x reps slot carrying the week's heavy lift.

    The generator keeps such a slot on one exercise for a whole phase (unless
    the phase says `rotate_main_lifts`), because its load progresses from
    session to session; rotating front squat, box squat and back squat
    through it reset the progression every time.
    """
    if slot.get('slot_type', 'sets_reps') != 'sets_reps':
        return False
    return (slot.get('intensity') or '') in MAIN_LIFT_INTENSITIES \
        or bool(slot.get('intensity_pct_1rm'))


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
    preferred_archetype_id: str | None = None,
    day_session_types: list | None = None,
    relax_equipment: bool = False,
) -> Optional[dict]:
    """Pick the best archetype for a session slot.

    When return_trace=True returns (archetype, trace_dict) instead of just archetype.
    When preferred_archetype_id is provided, that archetype gets a strong scoring bonus.
    """
    available_equip = set(constraints.get('equipment', []))
    session_time = constraints.get('session_time_minutes', 75)
    training_level = constraints.get('training_level', 'intermediate')
    recent_list = list(recent_ids or [])
    recent = set(recent_list)
    # Where each archetype sits in its package (load order) and when it was
    # last used: ties go to the one used longest ago, then to the first one
    # authored. The tiebreak used to be the id, reversed, so the
    # alphabetically last archetype won every tie: a Starting Strength novice
    # ran HLM from week 2.
    order = {a.get('id'): i for i, a in enumerate(archetypes)}
    last_used = {aid: i for i, aid in enumerate(recent_list)}

    n_modality = 0
    n_phase = 0
    n_level = 0
    n_equip = 0

    candidates = []
    too_long = []  # passed every filter but the session-time one
    for arch in archetypes:
        if arch.get('modality') != modality:
            continue
        # A test is placed by its phase (philosophy.yaml `tests:`), never picked;
        # a named workout only by its day category (src/week_template.py).
        if standard_tests.is_test_only(arch) or arch.get('pool_only'):
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
                if not relax_equipment:
                    continue  # no scaling and not relaxed — skip
        n_equip += 1

        # Duration filter
        duration = arch.get('duration_estimate_minutes', 60)
        if is_deload:
            deload_sc = arch.get('scaling', {}).get('deload', {})
            duration = deload_sc.get('duration_estimate_minutes', int(duration * 0.7))
        # Hard cap: on short days, exclude archetypes that clearly can't fit
        if day_session_types and 'short' in day_session_types and 'long' not in day_session_types:
            if duration > 50:  # 40m budget + 25% tolerance
                if not arch.get('scaling', {}).get('time_limited'):
                    too_long.append((duration, arch))
                    continue
        elif duration > session_time:
            if not arch.get('scaling', {}).get('time_limited'):
                too_long.append((duration, arch))
                continue  # no time-limited scaling — skip

        candidates.append(arch)

    # Nothing fits the session time: keep the modality with its shortest
    # archetype (populate_session caps the session at the athlete's time)
    # rather than return nothing. Returning nothing made the generator swap
    # the modality for aerobic base, so a 45-minute athlete lost Horsemen's
    # max strength and Uphill's muscular endurance outright.
    if not candidates and too_long:
        shortest = min(d for d, _ in too_long)
        candidates = [a for d, a in too_long if d == shortest]

    _excl = excl_patterns or set()

    def _score_arch(arch: dict) -> tuple:
        score = 0
        # Strong preference for complementary mobility archetype
        if preferred_archetype_id and arch['id'] == preferred_archetype_id:
            score += 10  # Higher than equipment bonus to take precedence
        # Prefer archetypes whose equipment is fully satisfied over equipment_limited fallbacks.
        # Bonus must exceed the max recency penalty (-3) so a recently-used fully-equipped
        # archetype always beats an equipment-limited one.
        required = set(arch.get('required_equipment', [])) - {'open_space'}
        if required.issubset(available_equip):
            score += 6
        if arch['id'] in recent:
            score -= 3
        # Duration fit: reward archetypes that match the day's slot type
        if day_session_types:
            arch_dur = arch.get('duration_estimate_minutes', 60)
            if 'long' in day_session_types and arch_dur >= 60:
                score += 3
            elif 'short' in day_session_types and 'long' not in day_session_types and arch_dur <= 45:
                score += 3
            elif 'long' in day_session_types and arch_dur <= 45:
                score -= 2  # Short archetype on long day is suboptimal
        # Penalise archetypes with a high injury-skip rate: prefer alternatives
        # that can actually be executed with the athlete's active injury constraints.
        if _excl:
            slots = [s for s in arch.get('slots', []) if not s.get('skip_exercise')]
            if slots:
                skipped = sum(1 for s in slots if _slot_injury_blocked(s, _excl))
                skip_rate = skipped / len(slots)
                score -= round(skip_rate * 8)
        # Penalise archetypes whose exercise slots require equipment the athlete doesn't have.
        # Uses -8 per blocked slot (not rate-based) so a blocked main-strength slot is always
        # decisive: a bodyweight-only alternative will beat a partially-filled barbell session.
        blocked_cats = _blocked_categories_for_equipment(available_equip)
        if blocked_cats:
            all_slots = [s for s in arch.get('slots', []) if not s.get('skip_exercise') and not s.get('is_meta')]
            equip_blocked = sum(
                1 for s in all_slots
                if s.get('exercise_filter', {}).get('category') in blocked_cats
            )
            score -= equip_blocked * 10
        return (score, -last_used.get(arch['id'], -1), -order.get(arch['id'], 0))

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
        source_bonus = 0  # the free-text sources bonus is gone; kept for the trace's shape
        recency_penalty = 0
        injury_penalty = 0
        required = set(arch.get('required_equipment', [])) - {'open_space'}
        if required.issubset(available_equip):
            equip_bonus = 6
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
    primary_sources: set | None = None,
    policy=None,
    modality: str | None = None,
) -> Optional[dict]:
    """Pick the best exercise for an archetype slot.

    When return_trace=True returns (exercise, trace_dict) instead of just exercise.
    primary_sources: set of philosophy package IDs to filter exercises by (e.g. {'starting_strength'})
    policy: provenance.SourcePolicy. Under a strict policy the global fallback below
        is disabled, so an unfillable slot is reported instead of silently borrowing.
    """
    available_equip = set(constraints.get('equipment', []))
    recent = recent_ex_ids or []
    session_used = set(session_used_ids or [])
    ex_filter = slot.get('exercise_filter', {})
    primary_sources = primary_sources or set()
    excludes_max = phases.kind_flag(phase, 'excludes_max_effort')

    n_pool = 0
    n_package = 0
    n_equip = 0
    n_filter = 0

    def _build_candidates(restrict_to_primary: bool) -> list:
        """Collect candidate exercises, optionally restricted to primary_sources packages."""
        nonlocal n_pool, n_package, n_equip, n_filter
        cands = []
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
            # A test's own exercise (a "2000m Row Time Trial") is prescribed
            # only by a slot that names it, never picked for a circuit's row.
            # A named workout's movement likewise (exercise `named_only`).
            if (ex.get('test_only') or ex.get('named_only')) and ex_id not in (ex_filter.get('exercise_ids') or []):
                continue
            n_pool += 1

            # Philosophy package filter. Read _packages (every package that declares
            # this id), not _package (first declarer) — otherwise an exercise the
            # philosophy genuinely owns is rejected because another package happens
            # to declare the same id earlier in glob order.
            if restrict_to_primary and primary_sources:
                if policy is not None:
                    if not provenance.allows_exercise(ex, policy, modality):
                        continue
                else:
                    ex_packages = ex.get('_packages') or (
                        [ex['_package']] if ex.get('_package') else []
                    )
                    if ex_packages and not set(ex_packages) & primary_sources:
                        continue
            n_package += 1

            # Equipment
            if not _equipment_ok(ex, available_equip):
                continue
            n_equip += 1

            # Slot filter
            if not _matches_slot_filter(ex, ex_filter, excl_patterns):
                continue
            n_filter += 1

            # Taper kinds: no max-effort exercises
            if excludes_max and ex.get('effort') == 'max':
                continue

            slot_intensity = ex_filter.get('intensity') or slot.get('intensity', '')
            slot_type = slot.get('slot_type', '')

            # AMRAP / for_time / circuit slots: skill and mobility exercises are poor fits
            if slot_type in ('amrap', 'amrap_movement', 'for_time') and ex.get('category') in ('skill', 'mobility', 'rehab'):
                continue

            # Zone1-2 aerobic time_domain slots: only low-effort exercises
            if (slot_intensity in ('zone1', 'zone2')
                    and slot_type == 'time_domain'
                    and ex_filter.get('category') == 'aerobic'
                    and ex.get('effort') not in ('low', None, '')):
                continue

            cands.append(ex)
        return cands

    # Pass 1: primary-sources exercises only
    candidates = _build_candidates(restrict_to_primary=True)

    # Pass 2: if the philosophy's own packages have no exercise for this slot, widen.
    # Historically this reached the entire cross-package index with no warning, which
    # is how a Starting Strength program ended up prescribing ATG mobility work. Under
    # a strict policy we stay inside the allowed packages and let the slot go unfilled,
    # so the gap is reported rather than hidden.
    borrowed_fallback = False
    if not candidates and primary_sources and not (policy is not None and policy.strict):
        n_pool = n_package = n_equip = n_filter = 0  # reset counters for accurate trace
        candidates = _build_candidates(restrict_to_primary=False)
        borrowed_fallback = bool(candidates)

    # Ties go to the exercise authored first in its package, not to the
    # alphabetically last id (which put front squat ahead of back squat).
    order = {eid: i for i, eid in enumerate(exercises)}

    def _score_ex(ex: dict) -> tuple:
        recency_penalty = sum(2 for eid in recent if eid == ex['id'])
        # A slot that names its exercises (a pentathlon's five events) rotates
        # through them on recency alone; the ladder bonus would starve the
        # events that unlock nothing.
        forward_bonus = 0.5 if ex.get('unlocks') and not ex_filter.get('exercise_ids') else 0
        # Prefer exercises that have defined movement patterns over joint drills / stub entries
        pattern_bonus = 0.5 if ex.get('movement_patterns') else 0
        if ex_filter.get('ordered') and ex_filter.get('exercise_ids'):
            # The written movement first, the source's declared substitutes
            # after it (a rope climb, or 10 pull-ups without a rope).
            return (-ex_filter['exercise_ids'].index(ex['id']),)
        if ex_filter.get('exercise_ids'):
            # …and among equals the one used longest ago goes first (recent is
            # oldest → newest), so every event comes round.
            last = max((i for i, eid in enumerate(recent) if eid == ex['id']), default=-1)
            return (-recency_penalty + pattern_bonus, -last, -order.get(ex['id'], 0))
        return (-recency_penalty + forward_bonus + pattern_bonus, -order.get(ex['id'], 0))

    if not candidates:
        if not return_trace:
            return None
        return None, {
            'selected_id': None,
            'injury_blocked': _slot_injury_blocked(slot, excl_patterns),
            'filter_counts': {
                'in_pool': n_pool, 'after_package': n_package,
                'after_equip': n_equip, 'after_filter': n_filter, 'final': 0,
            },
            'candidates': [],
        }

    candidates.sort(key=_score_ex, reverse=True)

    # Prefer exercises not already used in this session (two-pass: fresh first, fallback to any)
    # A workout written out in full (an ordered slot) repeats a movement on
    # purpose — Mirror's KB press right, then left — so it takes the written one.
    fresh = [ex for ex in candidates if ex['id'] not in session_used]
    selected = candidates[0] if ex_filter.get('ordered') else (fresh if fresh else candidates)[0]

    if not return_trace:
        return selected

    # Limit candidate list to top 10 for trace (can be large otherwise)
    top_candidates = candidates[:10]
    trace = {
        'selected_id': selected['id'],
        'injury_blocked': False,
        'filter_counts': {
            'in_pool': n_pool, 'after_package': n_package,
            'after_equip': n_equip, 'after_filter': n_filter, 'final': len(candidates),
        },
        'candidates': [
            {
                'id': ex['id'],
                'name': ex.get('name', ex['id']),
                'package': ex.get('_package', ''),
                'packages': ex.get('_packages', []),
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


def _slot_unfillable_in_policy(slot: dict, exercises: dict, policy, modality: str | None) -> bool:
    """True when no exercise in the policy's packages could ever match this slot.

    Ignores equipment and training level on purpose: those are athlete
    constraints, while this answers whether the philosophy owns the movement
    at all. Used to label an unfilled slot as a package coverage gap.
    """
    ex_filter = slot.get('exercise_filter', {})
    for ex in exercises.values():
        if not provenance.allows_exercise(ex, policy, modality):
            continue
        if _matches_slot_filter(ex, ex_filter, set()):
            return False
    return True


def _explain_unfilled(slot, constraints, exercises, unlocked, excl_ids, injury_flags_data,
                      phase, primary_sources, policy, modality,
                      phase_excluded=frozenset(),
                      known=frozenset()) -> tuple[str | None, dict | None, str | None, dict | None]:
    """Why a slot found no exercise, and the injury flag's substitute if one fits.

    Returns (reason, substitute, instead_of, blocked_by), cheapest test first:

    - 'coverage': no exercise in the allowed packages matches the slot at all;
    - 'injury': it fills once the athlete's flags are lifted;
    - 'equipment': it fills with every piece of equipment;
    - 'level': it fills with every exercise unlocked;
    - 'phase': it fills only with the phase's `exclude_exercises` back in
      (the method has not reached the lift; not the athlete's level);
    - None: nothing explains it.

    The substitute comes from a flag's `modified_exercises`: an entry whose
    `instead_of` fits the slot and whose `use` the athlete could be given
    anyway: unlocked at their level and not left out by the phase, within
    their equipment and the program's packages, not excluded or
    contraindicated by any flag, and clear of every other flag's excluded
    patterns (the flag that names it vouches only for its own).

    `blocked_by` names the constraint concretely, read from the exercise the
    lifted run would give: `{cause, exercise}` plus the equipment it `needs`,
    the injury `flags` that rule it out, or the `requires` the level has not
    reached; an injury substitute carries the flag it came `via`.
    """
    common = dict(primary_sources=primary_sources, policy=policy, modality=modality)
    if policy is not None and policy.strict and _slot_unfillable_in_policy(slot, exercises, policy, modality):
        return 'coverage', None, None, {'cause': 'coverage'}
    flags = list(constraints.get('injury_flags') or [])
    if flags:
        no_flags = {**constraints, 'injury_flags': []}
        everything = unlocked | (set(excl_ids) & set(exercises))
        found = select_exercise(slot, no_flags, exercises, everything, set(), set(), [], phase, **common)
        if found:
            hits = [fid for fid, _ in blockers.flag_hits(found, flags, injury_flags_data)]
            blocked = {'cause': 'injury', 'exercise': found['id'], 'flags': hits or flags}
            available = set(constraints.get('equipment', []))
            ex_filter = slot.get('exercise_filter') or {}
            for flag_id in flags:
                others = {pat for fid in flags if fid != flag_id
                          for pat in (injury_flags_data.get(fid) or {}).get('excluded_movement_patterns') or []}
                for mod in (injury_flags_data.get(flag_id) or {}).get('modified_exercises') or []:
                    was, use = exercises.get(mod.get('instead_of')), exercises.get(mod.get('use'))
                    if not was or not use or use['id'] in excl_ids or use['id'] not in unlocked:
                        continue
                    if not _matches_slot_filter(was, ex_filter, set()):
                        continue
                    if not _equipment_ok(use, available) or set(use.get('movement_patterns') or []) & others:
                        continue
                    if set(use.get('contraindicated_with') or []) & set(flags):
                        continue
                    if policy is not None and not provenance.allows_exercise(use, policy, modality):
                        continue
                    return 'injury', use, was['id'], {**blocked, 'exercise': was['id'], 'via': flag_id}
            return 'injury', None, None, blocked
    all_equipment = {e for ex in exercises.values() for e in ex.get('equipment', [])}
    found = select_exercise(slot, {**constraints, 'equipment': sorted(all_equipment)}, exercises,
                            unlocked, set(), excl_ids, [], phase, **common)
    if found:
        return 'equipment', None, None, {
            'cause': 'equipment', 'exercise': found['id'],
            'needs': blockers.missing_equipment(found.get('equipment'), constraints.get('equipment'))}
    every_level = set(exercises) - set(excl_ids)
    found = select_exercise(slot, constraints, exercises, every_level - set(phase_excluded),
                            set(), excl_ids, [], phase, **common)
    if found:
        # A requirement is met by an unlocked exercise or by a concept the
        # level knows (`known`, as _get_unlocked resolves them); only the rest
        # is missing — "needs bracing" for a novice who arrives bracing was wrong.
        return 'level', None, None, {
            'cause': 'level', 'exercise': found['id'], 'level': constraints.get('training_level'),
            'requires': [r for r in found.get('requires') or [] if r not in unlocked and r not in known]}
    if phase_excluded:
        found = select_exercise(slot, constraints, exercises, every_level,
                                set(), excl_ids, [], phase, **common)
        if found:
            return 'phase', None, None, {'cause': 'phase', 'exercise': found['id']}
    return None, None, None, None


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
    preferred_archetype_id: str | None = None,
    day_session_types: list | None = None,
    relax_equipment: bool = False,
    policy=None,
    level_seeds: dict | None = None,
    exclude_exercise_ids: set | frozenset | None = None,
    pinned_lifts: dict | None = None,
    deload_keep: float | None = None,
    unfilled_cache: dict | None = None,
) -> dict:
    """Populate a session with an archetype and exercises.

    `exclude_exercise_ids` are the week's phase `exclude_exercises`: lifts the
    method has not reached yet in this phase (Wildman's foundations stop
    before the snatch and the jerk).

    `pinned_lifts` is the phase's memory of its main lifts, keyed
    (archetype id, slot index) and owned by the caller: a main-lift slot
    (`is_main_lift_slot`) reuses the exercise it got first in the phase while
    that exercise still passes every filter, and records it otherwise. None
    turns pinning off (a phase that rotates its lifts, a single-session
    regenerate). A pinned lift already in the session is not reused, and a
    fresh pick steers clear of the other slots' pins, so a session never
    prescribes one lift twice.

    `unfilled_cache` (also caller-owned, per phase) remembers why a slot came
    up empty, keyed (archetype id, slot index, phase kind): the athlete's
    constraints do not change within a program, so a gap that repeats every
    week is explained once.

    When collect_trace=True the result dict includes a 'session_trace' key with
    archetype selection and per-slot exercise selection trace data.

    When forced_archetype is provided, archetype selection is skipped and the
    given archetype dict is used directly (used by the single-session replace endpoint).

    When preferred_archetype_id is provided, that archetype gets strong preference
    (used for complementary mobility pairing).
    """
    modality = session['modality']
    is_deload = session.get('is_deload', False)

    excl_patterns, excl_ids = _injury_exclusions(constraints, injury_flags_data)
    training_level = constraints.get('training_level', 'intermediate')
    unlocked = _get_unlocked(training_level, exercises, level_seeds) - excl_ids
    known_seeds = level_seeds   # the seeds `unlocked` was resolved with (narrowed per package below)
    if exclude_exercise_ids:
        unlocked -= set(exclude_exercise_ids)
    primary_sources = set(goal.get('primary_sources', []))
    if policy is None:
        policy = provenance.resolve_source_policy(goal)

    # Select archetype
    if forced_archetype is not None:
        arch = forced_archetype
        # Placed, not chosen (a test, a week template's named workout): the
        # trace keeps the shape the Dev Lab reads, with nothing to compare.
        arch_trace: dict = {'selected_id': arch.get('id'), 'filter_counts': {}, 'candidates': [],
                            'selection_reason': session.get('category') or 'forced'}
    elif collect_trace:
        arch_result = select_archetype(
            modality, constraints, phase, is_deload,
            goal, archetypes, recent_arch_ids,
            excl_patterns=excl_patterns,
            return_trace=True,
            preferred_archetype_id=preferred_archetype_id,
            day_session_types=day_session_types,
            relax_equipment=relax_equipment,
        )
        arch, arch_trace = arch_result if isinstance(arch_result, tuple) else (arch_result, {})
    else:
        arch = select_archetype(
            modality, constraints, phase, is_deload,
            goal, archetypes, recent_arch_ids,
            excl_patterns=excl_patterns,
            preferred_archetype_id=preferred_archetype_id,
            day_session_types=day_session_types,
            relax_equipment=relax_equipment,
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

    # A session uses only exercises declared in its archetype's exercises.yaml.
    # Merging the global pool here allowed cross-package picks in blends and
    # permissive fallback paths, even when the package had no matching exercise.
    arch_package = arch.get('_package')
    if arch_package and exercises_by_package is not None:
        # Keep explicitly permitted borrowed exercises; package membership alone
        # must not erase a declared borrowing contract (Uphill's barbell work).
        own = exercises_by_package.get(arch_package, {})
        session_policy = (provenance.SourcePolicy(owner_packages=frozenset({arch_package}),
                          borrows=policy.borrows, strict=policy.strict) if policy is not None else None)
        borrowed = {eid: ex for eid, ex in exercises.items() if session_policy is not None
                    and provenance.allows_exercise(ex, session_policy, modality)}
        exercises = {**borrowed, **own}
        package_seeds = {arch_package: (level_seeds or {}).get(arch_package, {})}
        known_seeds = package_seeds
        unlocked = _get_unlocked(training_level, exercises, package_seeds) - excl_ids
        unlocked -= set(exclude_exercise_ids or ())

    # Populate slots
    used_ex_ids = list(recent_ex_ids or [])
    session_used_ids: list[str] = []  # tracks only current-session picks for intra-session dedup
    exercise_assignments = []
    slot_traces: list[dict] = []

    for i, slot in enumerate(arch.get('slots', [])):
        slot_role = slot.get('role', f'slot_{i}')
        slot_type = slot.get('slot_type', 'sets_reps')

        # Meta/structural slots don't get individual exercise assignments.
        # They still carry a prescription, though: a BJJ drilling round is
        # "25 minutes at moderate intensity" whether or not an exercise resolves
        # for it. Emitting an empty load left these blocks with no duration for
        # any client to time, which is why a bjj_class session showed up on the
        # watch as four unusable rows.
        if slot.get('skip_exercise'):
            meta_load = {}
            if 'duration_minutes' in slot:
                meta_load['duration_minutes'] = slot['duration_minutes']
            elif 'duration_sec' in slot:
                meta_load['duration_minutes'] = max(1, round(slot['duration_sec'] / 60))
            if slot.get('sets'):
                meta_load['sets'] = slot['sets']
            intensity = slot.get('intensity')
            if intensity:
                lo, hi, label = _zone_band(intensity)
                meta_load['intensity'] = intensity
                if lo is not None:
                    meta_load['zone_target'] = label
                    meta_load['zone_lower'] = lo
                    meta_load['zone_upper'] = hi
            exercise_assignments.append({
                'slot_index': i,
                'slot_role': slot_role,
                'slot_type': slot_type,
                'exercise': None,
                'slot': slot,
                'load': meta_load,
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

        pin_key = (arch.get('id'), i)
        pinned_id = None
        reserved: list[str] = []
        if pinned_lifts is not None and is_main_lift_slot(slot):
            pinned_id = pinned_lifts.get(pin_key)
            if pinned_id in session_used_ids:
                pinned_id = None
        if pinned_lifts is not None:
            reserved = [eid for (aid, idx), eid in pinned_lifts.items()
                        if aid == arch.get('id') and idx != i]
        fresh_used = session_used_ids + reserved
        ex = None
        ex_trace: dict = {}
        if pinned_id:
            # Same filters, narrowed to the pinned lift; None falls through to
            # a fresh pick (an injury or the taper ruled it out).
            pinned_slot = {**slot, 'exercise_filter': {**(slot.get('exercise_filter') or {}),
                                                       'exercise_ids': [pinned_id]}}
            ex = select_exercise(
                pinned_slot, constraints, exercises, unlocked,
                excl_patterns, excl_ids, [], phase,
                primary_sources=primary_sources, policy=policy, modality=modality,
            )
            if ex is not None and collect_trace:
                ex_trace = {'selected_id': ex['id'], 'injury_blocked': False, 'pinned': True,
                            'filter_counts': {}, 'candidates': []}
        if ex is None and collect_trace:
            ex_result = select_exercise(
                slot, constraints, exercises, unlocked,
                excl_patterns, excl_ids, used_ex_ids, phase,
                session_used_ids=fresh_used,
                return_trace=True,
                primary_sources=primary_sources,
                policy=policy,
                modality=modality,
            )
            ex, ex_trace = ex_result if isinstance(ex_result, tuple) else (ex_result, {})
        elif ex is None:
            ex = select_exercise(
                slot, constraints, exercises, unlocked,
                excl_patterns, excl_ids, used_ex_ids, phase,
                session_used_ids=fresh_used,
                primary_sources=primary_sources,
                policy=policy,
                modality=modality,
            )

        substituted_for = None
        reason = None
        blocked_by = None
        if ex is None:
            cache_key = (arch.get('id'), i, phase)
            if unfilled_cache is not None and cache_key in unfilled_cache:
                reason, sub_id, instead_of, blocked_by = unfilled_cache[cache_key]
                sub = exercises.get(sub_id) if sub_id else None
            else:
                reason, sub, instead_of, blocked_by = _explain_unfilled(
                    slot, constraints, exercises, unlocked, excl_ids, injury_flags_data,
                    phase, primary_sources, policy, modality,
                    phase_excluded=frozenset(exclude_exercise_ids or ()),
                    known=_level_known(training_level, known_seeds))
                if unfilled_cache is not None:
                    unfilled_cache[cache_key] = (reason, sub['id'] if sub else None, instead_of, blocked_by)
            if sub is not None and sub['id'] not in session_used_ids:
                ex, substituted_for = sub, instead_of

        if ex is None:
            injury_blocked = _slot_injury_blocked(slot, excl_patterns) or reason == 'injury'
            # Distinguish "the philosophy owns nothing for this slot" from
            # "equipment/level ruled everything out" — the first is a package
            # coverage gap to author, the second is an athlete constraint.
            # Every empty slot says which; one used to be left empty with no
            # reason whenever equipment or an excluded exercise emptied it.
            coverage_gap = reason == 'coverage' and not injury_blocked
            gap_reason = ('NO_EXERCISE_IN_ALLOWED_PACKAGES' if coverage_gap
                          else 'EQUIPMENT_UNAVAILABLE' if reason == 'equipment'
                          else 'LEVEL_LOCKED' if reason == 'level'
                          else 'PHASE_EXCLUDED' if reason == 'phase' else None)
            exercise_assignments.append({
                'slot_index': i,
                'slot_role': slot_role,
                'slot_type': slot_type,
                'exercise': None,
                'slot': slot,
                'injury_skip': injury_blocked,
                'coverage_gap': coverage_gap,
                'equipment_gap': reason == 'equipment' and not injury_blocked,
                'gap_reason': gap_reason,
                **({'blocked_by': dict(blocked_by)} if blocked_by else {}),
                'error': (
                    "skipped — excluded by injury flag" if injury_blocked
                    else "No exercise fits the available equipment" if reason == 'equipment'
                    else "No exercise unlocked at this training level" if reason == 'level'
                    else "Not part of this phase yet" if reason == 'phase'
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
            if pinned_lifts is not None and is_main_lift_slot(slot):
                pinned_lifts.setdefault(pin_key, ex['id'])
            used_ex_ids.append(ex['id'])
            session_used_ids.append(ex['id'])
            assignment = {
                'slot_index': i,
                'slot_role': slot_role,
                'slot_type': slot_type,
                'exercise': ex,
                'slot': slot,
            }
            # The standard this slot measures, outside `slot` so it survives
            # api._clean_exercise_assignment and storage.
            ref = standard_tests.standard_ref(slot)
            if ref:
                assignment['standard'] = ref
            if substituted_for:
                assignment['substituted_for'] = substituted_for
                if blocked_by and blocked_by.get('via'):
                    assignment['substituted_by_flag'] = blocked_by['via']
            exercise_assignments.append(assignment)
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
    if standard_tests.is_test(arch):
        pass                      # a test runs as written, whatever the week
    elif is_deload:
        deload_sc = arch.get('scaling', {}).get('deload', {})
        keep = deload_keep if deload_keep is not None else 0.7
        effective_duration = deload_sc.get('duration_estimate_minutes', int(effective_duration * keep))
    session_time = constraints.get('session_time_minutes', 9999)
    if effective_duration > session_time and not standard_tests.is_test(arch):
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
