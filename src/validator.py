"""Validate goal + constraints feasibility before generation."""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import List

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

    def add_warning(self, code: str, message: str):
        self.warnings.append({'code': code, 'message': message})

    def add_info(self, code: str, message: str):
        self.info.append({'code': code, 'message': message})


def validate(
    goal: dict,
    constraints: dict,
    archetypes: list,
    modalities: dict,
    injury_flags_data: dict,
) -> ValidationResult:
    result = ValidationResult()
    _check_equipment(goal, constraints, archetypes, result)
    _check_days(goal, constraints, result)
    _check_session_time(goal, constraints, archetypes, result)
    _check_injury_conflicts(goal, constraints, modalities, injury_flags_data, result)
    _check_phase(goal, constraints, result)
    return result


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

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
        min_days = fw.get('applicable_when', {}).get('days_per_week_min', 1)
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
        elif days == min_days:
            result.add_warning(
                'MINIMAL_DAYS',
                f"Running at minimum {min_days} day(s)/week — "
                f"lower-priority modalities will be dropped.",
            )
    except Exception:
        pass


def _check_session_time(goal, constraints, archetypes, result):
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
