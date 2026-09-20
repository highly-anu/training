"""Validate goal + constraints feasibility before generation."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import List

from .goals import FrameworkResolutionError
from .scheduler import select_framework


@dataclass
class ValidationResult:
    feasible: bool = True
    errors: List[dict] = field(default_factory=list)
    warnings: List[dict] = field(default_factory=list)
    info: List[dict] = field(default_factory=list)

    def add_error(self, code: str, message: str, suggested_fix: str = None):
        self.errors.append({'code': code, 'message': message, 'suggested_fix': suggested_fix})
        self.feasible = False

    def add_warning(self, code: str, message: str, suggested_fix: str = None):
        self.warnings.append({'code': code, 'message': message, 'suggested_fix': suggested_fix})

    def add_info(self, code: str, message: str):
        self.info.append({'code': code, 'message': message})


def validate(
    goal: dict,
    constraints: dict,
    archetypes: list,
    modalities: dict,
    injury_flags_data: dict,
    policy=None,
) -> ValidationResult:
    """Pre-flight feasibility.

    `archetypes` must already be scoped to the policy — pass the same list the
    generator will use, or the two check different libraries.
    """
    result = ValidationResult()
    _check_forced_framework(goal, constraints, result)
    _check_equipment(goal, constraints, archetypes, result)
    _check_days(goal, constraints, result)
    _check_session_time(goal, constraints, archetypes, result)
    _check_injury_conflicts(goal, constraints, modalities, injury_flags_data, result)
    _check_phase(goal, constraints, result)
    _check_schedule(goal, constraints, result)
    _check_coverage(goal, archetypes, policy, result)
    return result


def _check_coverage(goal, archetypes, policy, result):
    """Modalities the goal schedules that its packages own no archetype for.

    A warning, not an error: a program missing one modality is still useful, and
    injury_skip already establishes that a blank slot is information rather than
    failure. Only a goal whose top priorities are all uncoverable is infeasible.
    """
    if policy is None or not policy.strict:
        return

    priorities = goal.get('priorities', {})
    if not priorities:
        return

    covered = {a.get('modality') for a in archetypes}
    uncovered = sorted(m for m in priorities if m not in covered)
    if not uncovered:
        return

    where = policy.describe()
    for modality in uncovered:
        result.add_warning(
            'PACKAGE_COVERAGE_GAP',
            f"No {modality.replace('_', ' ')} archetype in {where}. "
            f"Those sessions will be left unfilled rather than taken from "
            f"another philosophy.",
            suggested_fix=(
                f"Add a {modality} archetype to the package, or declare a "
                f"borrows_from entry covering {modality}."
            ),
        )

    top = sorted(priorities.items(), key=lambda kv: kv[1], reverse=True)[:2]
    if top and all(m in uncovered for m, _ in top):
        result.add_error(
            'PHILOSOPHY_NOT_GENERATABLE',
            f"{where} has no archetype for either of its top priorities "
            f"({', '.join(m for m, _ in top)}).",
            suggested_fix="Author the missing archetypes or declare borrows_from.",
        )


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

def _check_forced_framework(goal, constraints, result):
    forced_id = constraints.get('forced_framework')
    if not forced_id:
        return
    primary_sources = goal.get('primary_sources', [])
    if not primary_sources:
        return  # blended goal — skip ownership check

    owned: set = set()
    fw_sel = goal.get('framework_selection', {})
    if fw_sel.get('default_framework'):
        owned.add(fw_sel['default_framework'])
    for alt in fw_sel.get('alternatives', []):
        # Alternatives are {framework_id, condition} dicts; plain ids are tolerated.
        owned.add(alt['framework_id'] if isinstance(alt, dict) else alt)
    for phase in goal.get('phase_sequence', []):
        if phase.get('framework_id'):
            owned.add(phase['framework_id'])

    if forced_id not in owned:
        phil_id = primary_sources[0]
        result.add_error(
            'FRAMEWORK_PHILOSOPHY_MISMATCH',
            f"Framework '{forced_id}' does not belong to philosophy '{phil_id}'. "
            f"Owned frameworks: {sorted(owned)}.",
            suggested_fix=f"Remove framework_id or use one of: {sorted(owned)}.",
        )


def _check_equipment(goal, constraints, archetypes, result):
    available = set(constraints.get('equipment', []))
    priorities = goal.get('priorities', {})
    top_mods = {m for m, _ in sorted(priorities.items(), key=lambda x: x[1], reverse=True)[:3]}

    for arch in archetypes:
        if arch.get('modality') not in top_mods:
            continue
        required = set(arch.get('required_equipment', [])) - {'open_space'}
        missing = required - available
        if not missing:
            continue
        if arch.get('scaling', {}).get('equipment_limited'):
            result.add_info(
                'EQUIPMENT_SCALED',
                f"'{arch['name']}' will use equipment-limited scaling (missing: {missing}).",
            )
        else:
            result.add_warning(
                'EQUIPMENT_MISSING',
                f"Archetype '{arch['name']}' requires {missing} — not available. "
                f"This archetype will be skipped in selection.",
            )


def _check_days(goal, constraints, result):
    try:
        fw = select_framework(goal, constraints)
    except FrameworkResolutionError as exc:
        result.add_error(
            'FRAMEWORK_UNRESOLVED', str(exc),
            suggested_fix="Set primary_framework_id on the philosophy.",
        )
        return
    except Exception:
        return

    applicable = fw.get('applicable_when', {})
    min_days = applicable.get('days_per_week_min', 1)
    max_days = applicable.get('days_per_week_max', 7)
    days = constraints.get('days_per_week', 5)

    if days < min_days:
        result.add_error(
            'INSUFFICIENT_DAYS',
            f"Framework '{fw['name']}' requires at least {min_days} days/week. "
            f"Athlete has {days}.",
            suggested_fix=(
                f"Increase days_per_week to {min_days}, or see "
                f"goal.framework_selection.alternatives for lower-day options."
            ),
        )
    elif days > max_days:
        # Previously unenforced: over the max, cadence_options has no entry for the
        # day count and the scheduler silently fell back to a generic spread.
        result.add_error(
            'EXCESSIVE_DAYS',
            f"Framework '{fw['name']}' supports at most {max_days} days/week. "
            f"Athlete has {days}.",
            suggested_fix=(
                f"Reduce days_per_week to {max_days}, or choose a framework that "
                f"supports more training days."
            ),
        )
    elif days == min_days:
        result.add_warning(
            'MINIMAL_DAYS',
            f"Running at minimum {min_days} day(s)/week — "
            f"lower-priority modalities will be dropped.",
        )

    levels = applicable.get('training_level') or []
    level = constraints.get('training_level', 'intermediate')
    if levels and level not in levels:
        result.add_warning(
            'LEVEL_MISMATCH',
            f"Framework '{fw['name']}' is intended for {', '.join(levels)} athletes; "
            f"this athlete is {level}.",
            suggested_fix=f"Choose a framework that lists {level} in applicable_when.",
        )


def _check_session_time(goal, constraints, archetypes, result):
    weekday = constraints.get('weekday_session_minutes')
    weekend = constraints.get('weekend_session_minutes')
    if weekday and weekend:
        # Weighted average: 5 weekday sessions + 2 weekend sessions per week
        session_time = round((weekday * 5 + weekend * 2) / 7)
    else:
        session_time = constraints.get('session_time_minutes', 75)
    if session_time < 20:
        result.add_error(
            'SESSION_TOO_SHORT',
            f"Session time {session_time} min is too short for any useful training.",
            suggested_fix="Set session_time_minutes >= 30.",
        )
        return

    priorities = goal.get('priorities', {})
    top_mods = {m for m, _ in sorted(priorities.items(), key=lambda x: x[1], reverse=True)[:2]}
    relevant = [a for a in archetypes if a.get('modality') in top_mods]
    if not relevant:
        return

    min_duration = min(a.get('duration_estimate_minutes', 60) for a in relevant)
    if session_time < min_duration:
        has_scaled = any(a.get('scaling', {}).get('time_limited') for a in relevant)
        if has_scaled:
            result.add_warning(
                'SESSION_TIME_SCALED',
                f"Session time ({session_time} min) is below standard archetype duration "
                f"({min_duration} min) — time-limited scaling will be applied.",
            )
        else:
            result.add_warning(
                'SESSION_TIME_SHORT',
                f"Session time ({session_time} min) may be insufficient for primary archetypes "
                f"(shortest is {min_duration} min). Program will attempt generation.",
            )


def _check_injury_conflicts(goal, constraints, modalities, injury_flags_data, result):
    flags = constraints.get('injury_flags', [])
    if not flags:
        return

    excl_patterns: set = set()
    for flag_id in flags:
        flag = injury_flags_data.get(flag_id, {})
        excl_patterns.update(flag.get('excluded_movement_patterns', []))

    result.add_info(
        'INJURY_ACTIVE',
        f"Injury flag(s) {flags} active — exercises using movement patterns "
        f"{sorted(excl_patterns)} will be excluded from selection.",
    )


def _check_phase(goal, constraints, result):
    phase = constraints.get('training_phase', 'base')
    phase_names = [p['phase'] for p in goal.get('phase_sequence', [])]
    if phase_names and phase not in phase_names:
        result.add_warning(
            'PHASE_NOT_IN_GOAL',
            f"Phase '{phase}' is not in goal '{goal['id']}' phase sequence "
            f"({phase_names}). Base-phase priorities will be used.",
        )


def _check_schedule(goal, constraints, result):
    """
    Validate user schedule against framework expectations.

    Warnings:
    - Total weekly time < framework min_session_minutes × min_days_per_week
    - Days available < framework min_days_per_week

    Info:
    - Schedule matches or exceeds framework ideals
    """
    day_configs = constraints.get('day_configs', {})
    if not day_configs:
        return

    # Calculate total weekly minutes and days available
    total_minutes = sum(cfg.get('minutes', 0) for cfg in day_configs.values())
    days_available = len([d for d in day_configs.values() if d.get('minutes', 0) > 0])

    # Get framework expectations
    try:
        fw = select_framework(goal, constraints)
        expectations = fw.get('expectations', {})
        if not expectations:
            return

        min_session_minutes = expectations.get('min_session_minutes', 45)
        min_days = expectations.get('min_days_per_week', 3)
        ideal_days = expectations.get('ideal_days_per_week', 5)
        ideal_session_minutes = expectations.get('ideal_session_minutes', 60)

        # Validate days
        if days_available < min_days:
            result.add_error(
                'SCHEDULE_INSUFFICIENT_DAYS',
                f"Your schedule provides {days_available} training day(s) but this program "
                f"needs at least {min_days}.",
                suggested_fix=f"Add {min_days - days_available} more training day(s) to your schedule.",
            )
        elif days_available < ideal_days:
            result.add_warning(
                'SCHEDULE_BELOW_IDEAL_DAYS',
                f"Your schedule provides {days_available} day(s) (ideal: {ideal_days}). "
                f"Some modalities may be compressed or dropped.",
            )

        # Validate time
        min_weekly = min_session_minutes * min_days
        ideal_weekly = ideal_session_minutes * ideal_days

        if total_minutes < min_weekly:
            result.add_warning(
                'SCHEDULE_INSUFFICIENT_TIME',
                f"Your schedule provides {total_minutes} min/week (minimum: {min_weekly}). "
                f"Sessions will be scaled down.",
            )
        elif total_minutes >= ideal_weekly:
            result.add_info(
                'SCHEDULE_MEETS_IDEAL',
                f"Your schedule ({days_available} days, {total_minutes} min/week) meets or exceeds "
                f"framework recommendations.",
            )
    except Exception:
        pass
