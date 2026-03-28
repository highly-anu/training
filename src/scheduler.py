"""Assign modalities to training days for a single week."""
from __future__ import annotations
import math
from typing import Dict, List

from . import loader

_RECOVERY_COST_RANK = {'high': 3, 'medium': 2, 'low': 1}
_POSITION_ORDER = {'first': 0, 'main': 1, 'accessory': 2, 'finisher': 3, 'cooldown': 4}


# ---------------------------------------------------------------------------
# Phase priorities
# ---------------------------------------------------------------------------

def get_phase_priorities(goal: dict, phase: str) -> dict:
    """Return the priority vector for the given phase, applying any override."""
    for entry in goal.get('phase_sequence', []):
        if entry['phase'] == phase and 'priority_override' in entry:
            return dict(entry['priority_override'])
    return dict(goal.get('priorities', {}))


# ---------------------------------------------------------------------------
# Framework selection
# ---------------------------------------------------------------------------

def _eval_condition(condition: str, constraints: dict) -> bool:
    """Evaluate a simple condition string like 'days_per_week <= 3'."""
    for op in ('<=', '>=', '==', '<', '>'):
        if op in condition:
            left, _, right = condition.partition(op)
            field = left.strip()
            value = right.strip()
            if field in constraints:
                try:
                    athlete_val = constraints[field]
                    cmp_val = type(athlete_val)(value)
                    if op == '<=': return athlete_val <= cmp_val
                    if op == '>=': return athlete_val >= cmp_val
                    if op == '==': return athlete_val == cmp_val
                    if op == '<':  return athlete_val < cmp_val
                    if op == '>':  return athlete_val > cmp_val
                except (ValueError, TypeError):
                    pass
    return False


def select_framework(goal: dict, constraints: dict) -> dict:
    """Select the best framework for the given goal and constraints."""
    # Explicit override from the API request (set by api.py from body.framework_id)
    forced = constraints.get('forced_framework')
    if forced:
        try:
            return loader.load_framework(forced)
        except FileNotFoundError:
            pass  # fall through to normal selection

    fw_sel = goal.get('framework_selection', {})
    default_id = fw_sel.get('default_framework', 'concurrent_training')
    selected_id = default_id

    # First matching alternative condition wins
    for alt in fw_sel.get('alternatives', []):
        if _eval_condition(alt.get('condition', ''), constraints):
            selected_id = alt['framework_id']
            break

    try:
        fw = loader.load_framework(selected_id)
    except FileNotFoundError:
        fw = loader.load_framework(default_id)

    # Validate days_per_week against framework limits
    applicable = fw.get('applicable_when', {})
    min_days = applicable.get('days_per_week_min', 1)
    max_days = applicable.get('days_per_week_max', 7)
    days = constraints.get('days_per_week', 5)

    if not (min_days <= days <= max_days):
        # Try alternatives that fit the days constraint
        for alt in fw_sel.get('alternatives', []):
            try:
                candidate = loader.load_framework(alt['framework_id'])
                c = candidate.get('applicable_when', {})
                if c.get('days_per_week_min', 1) <= days <= c.get('days_per_week_max', 7):
                    fw = candidate
                    break
            except FileNotFoundError:
                continue

    return fw


# ---------------------------------------------------------------------------
# Session allocation
# ---------------------------------------------------------------------------

def _proportional_round(raw: dict, target: int) -> dict:
    """Round fractional session counts preserving total (largest-remainder method)."""
    floors = {k: math.floor(v) for k, v in raw.items()}
    deficit = target - sum(floors.values())
    # Sort by fractional part descending to assign extra sessions
    by_remainder = sorted(raw.items(), key=lambda x: x[1] - math.floor(x[1]), reverse=True)
    result = dict(floors)
    for i, (k, _) in enumerate(by_remainder):
        if i >= deficit:
            break
        result[k] += 1
    return result


def allocate_sessions(priorities: dict, days_per_week: int, framework: dict) -> dict:
    """Convert priority vector + framework to session counts per modality."""
    fw_sessions = framework.get('sessions_per_week', {})

    if fw_sessions:
        fw_total = sum(fw_sessions.values())
        if fw_total == 0:
            return {}
        scale = days_per_week / fw_total
        raw = {mod: count * scale for mod, count in fw_sessions.items()}
    else:
        raw = {mod: weight * days_per_week
               for mod, weight in priorities.items() if weight > 0}

    allocation = _proportional_round(raw, days_per_week)
    return {k: v for k, v in allocation.items() if v > 0}


# ---------------------------------------------------------------------------
# Day assignment
# ---------------------------------------------------------------------------

def _recovery_cost_rank(mod_id: str, modalities: dict) -> int:
    return _RECOVERY_COST_RANK.get(
        modalities.get(mod_id, {}).get('recovery_cost', 'low'), 1
    )


def _recovery_safe(day: int, modality: str, mod_data: dict,
                   schedule: dict, modalities: dict) -> bool:
    """Return True if placing modality on day respects recovery windows."""
    recovery_needed = mod_data.get('recovery_hours_min', 24)
    my_cost = _RECOVERY_COST_RANK.get(mod_data.get('recovery_cost', 'low'), 1)

    for prev_day in range(max(1, day - 3), day):
        hours = (day - prev_day) * 24
        for prev_mod in schedule.get(prev_day, []):
            # Same modality: enforce its recovery window
            if prev_mod == modality and hours < recovery_needed:
                return False
            # Two high-cost modalities: minimum 48 h gap
            pm_cost = _recovery_cost_rank(prev_mod, modalities)
            if my_cost == 3 and pm_cost == 3 and hours < 48:
                return False
    return True


def _session_compatible(day: int, new_mod: str, mod_data: dict,
                        schedule: dict, modalities: dict) -> bool:
    """Return True if new_mod can share a day with already-assigned modalities."""
    existing = schedule.get(day, [])
    if not existing:
        return True
    incompatible_with_new = set(mod_data.get('incompatible_in_session_with', []))
    for ex_mod in existing:
        if ex_mod in incompatible_with_new:
            return False
        ex_incompatible = set(modalities.get(ex_mod, {}).get('incompatible_in_session_with', []))
        if new_mod in ex_incompatible:
            return False
    return True


def _score_days(days: list, schedule: dict, modality: str,
                mod_data: dict, modalities: dict) -> list:
    """Return days sorted by placement desirability (best first)."""
    my_cost = _RECOVERY_COST_RANK.get(mod_data.get('recovery_cost', 'low'), 1)
    scored = []
    for day in days:
        gap_score = 0
        for prev_day in range(max(1, day - 4), day):
            hours = (day - prev_day) * 24
            for prev_mod in schedule.get(prev_day, []):
                if prev_mod == modality:
                    needed = mod_data.get('recovery_hours_min', 24)
                    gap_score -= max(0, needed - hours)
                pm_cost = _recovery_cost_rank(prev_mod, modalities)
                if my_cost == 3 and pm_cost == 3:
                    gap_score -= max(0, 48 - hours)
        session_load_penalty = len(schedule.get(day, [])) * 12
        scored.append((gap_score - session_load_penalty, day))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [day for _, day in scored]


# Evenly-spaced default training days — fallback when no framework cadence is defined.
_DEFAULT_SPREAD: Dict[int, List[int]] = {
    2: [1, 5],
    3: [1, 4, 7],
    4: [1, 3, 5, 7],
    5: [1, 2, 4, 6, 7],
    6: [1, 2, 3, 5, 6, 7],
    7: [1, 2, 3, 4, 5, 6, 7],
}

# Framework-specific cadence patterns (1=Mon … 7=Sun).
# Multiple options per (framework, N) rotate week-to-week via week_in_phase % len(options).
# First option in each list is most spread-out — used for taper/deload/rehab phases.
_CADENCE_OPTIONS: Dict[str, Dict[int, List[List[int]]]] = {
    'linear_progression': {
        # Classic alternating rest — Mon/Wed/Fri and shifted variants
        2: [[1, 4], [2, 5], [1, 5]],
        3: [[1, 3, 5], [2, 4, 6], [1, 3, 6]],
        4: [[1, 2, 4, 6], [1, 3, 4, 6], [2, 3, 5, 7]],
    },
    'concurrent_training': {
        # Index 0 = most spread-out (used for taper/deload); others are 2-on-1-off variants
        3: [[1, 4, 7], [1, 3, 6], [2, 4, 7]],
        4: [[1, 3, 5, 7], [1, 2, 4, 6], [2, 3, 5, 7]],
        5: [[1, 2, 4, 6, 7], [1, 2, 4, 5, 7], [1, 3, 4, 6, 7]],
        6: [[1, 2, 3, 5, 6, 7], [1, 2, 4, 5, 6, 7]],
    },
    'gpp_circuits': {
        3: [[1, 3, 5], [2, 4, 6], [1, 4, 6]],
        4: [[1, 2, 4, 6], [1, 3, 5, 6], [2, 3, 5, 7]],
        5: [[1, 2, 3, 5, 7], [1, 2, 4, 5, 7], [1, 3, 4, 6, 7]],
    },
    'polarized_80_20': {
        # Uphill Athlete: large recovery gaps between hard sessions
        3: [[1, 4, 7], [2, 5, 7], [1, 3, 6]],
        4: [[1, 3, 5, 7], [1, 2, 5, 7], [2, 4, 6, 7]],
        5: [[1, 2, 4, 6, 7], [1, 3, 4, 6, 7], [1, 2, 3, 5, 7]],
        6: [[1, 2, 3, 5, 6, 7], [1, 2, 4, 5, 6, 7]],
    },
    'high_frequency_skill': {
        # Clusters of consecutive days for daily practice
        4: [[1, 2, 3, 5], [2, 3, 4, 6], [1, 2, 4, 5]],
        5: [[1, 2, 3, 4, 6], [1, 2, 3, 5, 7], [2, 3, 4, 5, 7]],
        6: [[1, 2, 3, 4, 5, 7], [2, 3, 4, 5, 6, 7]],
    },
    'block_periodization': {
        3: [[1, 3, 5], [1, 3, 6], [2, 4, 6]],
        4: [[1, 2, 4, 6], [1, 3, 5, 7], [2, 3, 5, 7]],
        5: [[1, 2, 3, 5, 7], [1, 2, 4, 5, 7], [1, 3, 4, 6, 7]],
    },
    'rpe_autoregulation': {
        3: [[1, 3, 5], [2, 4, 6], [1, 4, 7]],
        4: [[1, 2, 4, 6], [1, 3, 5, 7], [2, 3, 5, 7]],
        5: [[1, 2, 4, 5, 7], [1, 2, 3, 6, 7], [1, 3, 4, 6, 7]],
    },
    # emom_amrap, kb_pentathlon → fall back to _DEFAULT_SPREAD
}

# Phases that prefer the most evenly-distributed pattern (maximum recovery between sessions)
_SPREAD_PHASES = {'taper', 'deload', 'rehab'}


def _spread_pick(candidates: List[int], n: int) -> List[int]:
    """Pick n items from candidates, evenly spaced across the list."""
    if n <= 0 or not candidates:
        return []
    if n >= len(candidates):
        return list(candidates)
    if n == 1:
        return [candidates[len(candidates) // 2]]
    return [candidates[round(i * (len(candidates) - 1) / (n - 1))] for i in range(n)]


def _select_cadence(framework_id: str, days: int, phase: str, week_in_phase: int) -> List[int]:
    """Return the day-of-week pattern for this framework/volume/phase/week combo."""
    options = _CADENCE_OPTIONS.get(framework_id, {}).get(days)
    if not options:
        return _DEFAULT_SPREAD.get(days, list(range(1, days + 1)))
    if phase in _SPREAD_PHASES:
        return options[0]                          # most spread-out in recovery phases
    return options[week_in_phase % len(options)]   # rotate week-to-week otherwise


def _build_day_pool(days_per_week: int,
                    forced_workout: List[int],
                    forced_rest: List[int],
                    framework_id: str = '',
                    phase: str = 'base',
                    week_in_phase: int = 1) -> List[int]:
    """Compute the ordered list of days that will receive sessions.

    Uses framework-specific cadence patterns with week-to-week rotation.
    forced_workout days are always included; forced_rest days are always excluded.
    """
    effective = max(days_per_week, len(forced_workout))
    desired = set(_select_cadence(framework_id, effective, phase, week_in_phase))

    # Enforce user pins
    desired = (desired | set(forced_workout)) - set(forced_rest)

    pool = list(desired)
    if len(pool) > effective:
        # Trim — keep forced_workout days; drop excess auto days
        priority = list(forced_workout) + [d for d in sorted(pool) if d not in forced_workout]
        pool = sorted(priority[:effective])
    elif len(pool) < effective:
        available = [d for d in range(1, 8) if d not in pool and d not in forced_rest]
        pool = sorted(pool + _spread_pick(available, effective - len(pool)))
    else:
        pool = sorted(pool)
    return pool


def assign_to_days(allocation: dict, modalities: dict,
                   days_per_week: int,
                   day_pool: List[int] | None = None) -> Dict[int, List[str]]:
    """Place modalities on specific days with recovery-awareness.

    day_pool: pre-computed ordered day numbers (1=Mon … 7=Sun).
    The returned dict always has keys 1–7 so the calendar shows rest days.
    """
    schedule: Dict[int, List[str]] = {d: [] for d in range(1, 8)}
    if day_pool is not None:
        days = day_pool
    else:
        days = _DEFAULT_SPREAD.get(days_per_week, list(range(1, days_per_week + 1)))

    # Place high-cost modalities first — hardest to schedule
    sorted_mods = sorted(
        allocation.items(),
        key=lambda kv: _recovery_cost_rank(kv[0], modalities),
        reverse=True,
    )

    for modality, count in sorted_mods:
        mod_data = modalities.get(modality, {})
        placed = 0
        ordered_days = _score_days(days, schedule, modality, mod_data, modalities)

        for day in ordered_days:
            if placed >= count:
                break
            if (_recovery_safe(day, modality, mod_data, schedule, modalities) and
                    _session_compatible(day, modality, mod_data, schedule, modalities)):
                schedule[day].append(modality)
                placed += 1

        # Fallback: place on least-loaded days ignoring soft recovery constraints
        if placed < count:
            for day in sorted(days, key=lambda d: len(schedule[d])):
                if placed >= count:
                    break
                if modality not in schedule[day]:
                    schedule[day].append(modality)
                    placed += 1

    return schedule


def _order_day(modality_list: list, modalities: dict) -> list:
    """Sort modalities within a day by session_position."""
    return sorted(
        modality_list,
        key=lambda m: _POSITION_ORDER.get(
            modalities.get(m, {}).get('session_position', 'main'), 1
        ),
    )


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def schedule_week(goal: dict, constraints: dict, data: dict,
                  phase: str, week_number: int) -> dict:
    """
    Build a weekly schedule.

    Returns:
        {
          'schedule': {day_int: [{'modality': str, 'is_deload': bool}]},
          'framework': dict,
          'is_deload': bool,
          'allocation': {modality: count},
        }
    """
    priorities = get_phase_priorities(goal, phase)
    framework = select_framework(goal, constraints)

    forced_workout: List[int] = sorted(
        d for d in (constraints.get('preferred_days') or []) if 1 <= d <= 7
    )
    forced_rest: List[int] = sorted(
        d for d in (constraints.get('forced_rest_days') or []) if 1 <= d <= 7
    )
    effective_days = max(constraints['days_per_week'], len(forced_workout))
    pool = _build_day_pool(
        effective_days, forced_workout, forced_rest,
        framework_id=framework.get('id', ''),
        phase=phase,
        week_in_phase=week_number,
    )

    allocation = allocate_sessions(priorities, len(pool), framework)

    deload_freq = framework.get('deload_protocol', {}).get('frequency_weeks', 4)
    is_deload = (week_number % deload_freq == 0)
    if constraints.get('fatigue_state') == 'overreached':
        is_deload = True

    raw = assign_to_days(allocation, data['modalities'], len(pool), pool)

    schedule = {}
    for day in sorted(raw.keys()):
        ordered = _order_day(raw[day], data['modalities'])
        schedule[day] = [{'modality': m, 'is_deload': is_deload} for m in ordered]

    return {
        'schedule': schedule,
        'framework': framework,
        'is_deload': is_deload,
        'allocation': allocation,
    }
