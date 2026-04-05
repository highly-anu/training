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


def select_framework(goal: dict, constraints: dict,
                     _trace: dict | None = None) -> dict:
    """Select the best framework for the given goal and constraints.

    If _trace dict is provided it will be populated with framework selection details.
    """
    # Explicit override from the API request (set by api.py from body.framework_id)
    forced = constraints.get('forced_framework')
    fw_sel = goal.get('framework_selection', {})
    default_id = fw_sel.get('default_framework', 'concurrent_training')

    if _trace is not None:
        _trace['forced_override'] = forced
        _trace['default_id'] = default_id
        _trace['alternatives_checked'] = []

    if forced:
        try:
            fw = loader.load_framework(forced)
            if _trace is not None:
                _trace['selected_id'] = fw['id']
                _trace['selection_reason'] = 'forced_override'
            return fw
        except FileNotFoundError:
            pass  # fall through to normal selection

    selected_id = default_id

    # First matching alternative condition wins
    for alt in fw_sel.get('alternatives', []):
        cond = alt.get('condition', '')
        matched = _eval_condition(cond, constraints)
        if _trace is not None:
            _trace['alternatives_checked'].append({
                'framework_id': alt['framework_id'],
                'condition': cond,
                'matched': matched,
            })
        if matched:
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

    days_fallback = None
    if not (min_days <= days <= max_days):
        # Try alternatives that fit the days constraint
        for alt in fw_sel.get('alternatives', []):
            try:
                candidate = loader.load_framework(alt['framework_id'])
                c = candidate.get('applicable_when', {})
                if c.get('days_per_week_min', 1) <= days <= c.get('days_per_week_max', 7):
                    days_fallback = candidate['id']
                    fw = candidate
                    break
            except FileNotFoundError:
                continue

    if _trace is not None:
        _trace['selected_id'] = fw['id']
        _trace['days_constraint'] = {
            'athlete_days': days,
            'framework_min': min_days,
            'framework_max': max_days,
            'days_fallback': days_fallback,
        }
        _trace['selection_reason'] = (
            'forced_override' if forced
            else ('days_fallback' if days_fallback else
                  ('alternative_condition' if selected_id != default_id else 'default'))
        )

    return fw


# ---------------------------------------------------------------------------
# Session allocation
# ---------------------------------------------------------------------------

def _proportional_round(raw: dict, target: int) -> dict:
    """Round fractional session counts preserving total (largest-remainder method)."""
    floors = {k: math.floor(v) for k, v in raw.items()}
    deficit = target - sum(floors.values())
    # Round fractional parts to 9 dp to avoid floating-point comparison artifacts
    # (e.g. 2.4 - floor(2.4) = 0.3999... which would incorrectly rank below 0.4)
    by_remainder = sorted(raw.items(), key=lambda x: round(x[1] - math.floor(x[1]), 9), reverse=True)
    result = dict(floors)
    for i, (k, _) in enumerate(by_remainder):
        if i >= deficit:
            break
        result[k] += 1
    return result


def allocate_sessions(priorities: dict, days_per_week: int, framework: dict) -> dict:
    """Convert priority vector + framework to session counts per modality.

    Goal priorities are always the primary driver.  When the framework defines
    sessions_per_week, it guides the *ratio* among overlapping modalities, but
    modalities the goal does not prioritise are excluded and the freed slots
    flow to goal-priority modalities not covered by the framework.
    """
    fw_sessions = framework.get('sessions_per_week', {})

    if fw_sessions:
        # Only keep framework modalities the goal actually prioritises
        active_fw = {mod: cnt for mod, cnt in fw_sessions.items()
                     if priorities.get(mod, 0) > 0}
        active_total = sum(active_fw.values())

        if not active_fw or active_total == 0:
            # No overlap — fall back to pure goal priorities
            raw = {mod: weight * days_per_week
                   for mod, weight in priorities.items() if weight > 0}
        else:
            total_prio = sum(w for w in priorities.values() if w > 0) or 1
            fw_covered_prio = sum(priorities.get(m, 0) for m in active_fw)
            goal_only_prio = total_prio - fw_covered_prio

            # Slots allocated to fw-covered modalities (proportional to their priority share)
            fw_slots = days_per_week * (fw_covered_prio / total_prio)
            # Slots for goal modalities absent from the framework
            goal_only_slots = days_per_week * (goal_only_prio / total_prio)

            # Framework modalities: keep their relative ratio within fw_slots
            raw = {mod: (cnt / active_total) * fw_slots for mod, cnt in active_fw.items()}

            # Goal-only modalities: split goal_only_slots by their relative priority
            goal_only = {mod: w for mod, w in priorities.items()
                         if w > 0 and mod not in fw_sessions}
            if goal_only:
                goal_only_total = sum(goal_only.values()) or 1
                for mod, w in goal_only.items():
                    raw[mod] = (w / goal_only_total) * goal_only_slots
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


def _select_cadence(framework_id: str, days: int, phase: str, week_in_phase: int,
                    framework: dict | None = None) -> List[int]:
    """Return the day-of-week pattern for this framework/volume/phase/week combo."""
    yaml_options = (framework or {}).get('cadence_options', {})
    options = yaml_options.get(days) or _CADENCE_OPTIONS.get(framework_id, {}).get(days)
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
                    week_in_phase: int = 1,
                    framework: dict | None = None) -> List[int]:
    """Compute the ordered list of days that will receive sessions.

    Uses framework-specific cadence patterns with week-to-week rotation.
    forced_workout days are always included; forced_rest days are always excluded.
    """
    effective = max(days_per_week, len(forced_workout))
    desired = set(_select_cadence(framework_id, effective, phase, week_in_phase, framework))

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


def _add_split_sessions(raw: Dict[int, List[str]], modalities: dict,
                        constraints: dict) -> None:
    """Append a secondary mobility/skill session to primary training days.

    Mutates *raw* in place. Only adds a secondary session when:
    - the day already has exactly one primary session
    - the secondary modality is compatible with the existing session
    - the day's available time has at least 20 min of headroom after the primary
    """
    # Days 6-7 are Sat/Sun; everything else is weekday (Mon-Fri)
    weekday_time = constraints.get('weekday_session_minutes') or constraints.get('session_time_minutes', 75)
    weekend_time = constraints.get('weekend_session_minutes') or constraints.get('session_time_minutes', 75)
    secondary_min_time = 20  # minimum spare minutes required to add a secondary session

    secondary_days = constraints.get('secondary_days') or []
    day_configs = constraints.get('day_configs') or {}

    # Add secondary sessions to active training days
    for day in sorted(raw.keys()):
        # If specific secondary_days are given, only process those
        if secondary_days and day not in secondary_days:
            continue

        existing = raw[day]
        if len(existing) != 1:
            continue  # only add to single-session days
        if existing[0] in ('mobility', 'movement_skill'):
            continue  # already a mobility-only day — do not stack another

        day_cfg = day_configs.get(day) or day_configs.get(str(day))
        if day_cfg:
            available_time = day_cfg.get('minutes', 0)
        else:
            available_time = weekend_time if day >= 6 else weekday_time

        # Primary session rough estimate: assume 60 min if we can't determine exactly
        if available_time - 60 < secondary_min_time:
            continue

        for secondary in ('mobility', 'movement_skill'):
            sec_data = modalities.get(secondary, {})
            if _session_compatible(day, secondary, sec_data, {day: existing}, modalities):
                raw[day] = existing + [secondary]
                break

    # Add mobility-only sessions to rest days that the user marked for mobility
    for day in secondary_days:
        if day in raw:
            continue  # already has a training session (handled above)
        raw[day] = ['mobility']


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def schedule_week(goal: dict, constraints: dict, data: dict,
                  phase: str, week_number: int,
                  collect_trace: bool = False) -> dict:
    """
    Build a weekly schedule.

    Returns:
        {
          'schedule': {day_int: [{'modality': str, 'is_deload': bool}]},
          'framework': dict,
          'is_deload': bool,
          'allocation': {modality: count},
          'scheduler_trace': dict  (only when collect_trace=True)
        }
    """
    priorities = get_phase_priorities(goal, phase)

    fw_trace: dict | None = {} if collect_trace else None
    framework = select_framework(goal, constraints, _trace=fw_trace)

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
        framework=framework,
    )

    allocation = allocate_sessions(priorities, len(pool), framework)

    deload_freq = framework.get('deload_protocol', {}).get('frequency_weeks', 4)
    is_deload = (week_number % deload_freq == 0)
    if constraints.get('fatigue_state') == 'overreached':
        is_deload = True

    raw = assign_to_days(allocation, data['modalities'], len(pool), pool)

    if constraints.get('allow_split_sessions'):
        _add_split_sessions(raw, data['modalities'], constraints)

    schedule = {}
    for day in sorted(raw.keys()):
        ordered = _order_day(raw[day], data['modalities'])
        schedule[day] = [{'modality': m, 'is_deload': is_deload} for m in ordered]

    result = {
        'schedule': schedule,
        'framework': framework,
        'is_deload': is_deload,
        'allocation': allocation,
    }

    if collect_trace:
        # Build raw allocation for trace (before rounding)
        fw_sessions = framework.get('sessions_per_week', {})
        active_fw = {mod: cnt for mod, cnt in fw_sessions.items()
                     if priorities.get(mod, 0) > 0}
        active_total = sum(active_fw.values()) or 1
        total_prio = sum(w for w in priorities.values() if w > 0) or 1
        fw_covered_prio = sum(priorities.get(m, 0) for m in active_fw)
        goal_only_prio = total_prio - fw_covered_prio

        if active_fw:
            fw_slots = len(pool) * (fw_covered_prio / total_prio)
            goal_only_slots = len(pool) * (goal_only_prio / total_prio)
            raw_alloc = {mod: (cnt / active_total) * fw_slots for mod, cnt in active_fw.items()}
            goal_only = {mod: w for mod, w in priorities.items()
                         if w > 0 and mod not in fw_sessions}
            if goal_only:
                go_total = sum(goal_only.values()) or 1
                for mod, w in goal_only.items():
                    raw_alloc[mod] = (w / go_total) * goal_only_slots
        else:
            raw_alloc = {mod: w * len(pool) for mod, w in priorities.items() if w > 0}

        # Modality placement order (sorted by recovery cost desc — same as assign_to_days)
        modality_order = [
            m for m, _ in sorted(
                allocation.items(),
                key=lambda kv: _RECOVERY_COST_RANK.get(
                    data['modalities'].get(kv[0], {}).get('recovery_cost', 'low'), 1
                ),
                reverse=True,
            )
        ]

        # Day-name mapping for assignments display
        _DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        day_assignments: dict[str, list[str]] = {}
        for day_int in sorted(raw.keys()):
            if raw[day_int]:
                day_name = _DAY_NAMES[day_int - 1] if 1 <= day_int <= 7 else str(day_int)
                day_assignments[day_name] = list(raw[day_int])

        result['scheduler_trace'] = {
            'framework_selection': fw_trace,
            'allocation': {
                'phase_priorities': dict(priorities),
                'raw': {k: round(v, 3) for k, v in raw_alloc.items()},
                'final': dict(allocation),
            },
            'day_assignment': {
                'modality_order': modality_order,
                'day_pool': pool,
                'assignments': day_assignments,
            },
            'is_deload': is_deload,
            'deload_freq_weeks': deload_freq,
        }

    return result
