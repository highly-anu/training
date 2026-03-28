# Validator Logic

Pseudocode for constraint validation and conflict detection. This is the core of `validator.py` in Phase 4.

The validator runs in two places:
1. **Before generation** — feasibility check: can this goal be achieved with these constraints?
2. **After scheduling** — conflict audit: does the produced schedule violate any rules?

---

## Validation Result Structure

```
ValidationResult = {
  feasible: bool,
  errors:   list[{ code, message, field, suggested_fix }],  # hard failures
  warnings: list[{ code, message, field }],                  # soft issues
  info:     list[{ code, message }]                          # informational
}
```

Errors block generation. Warnings proceed but are surfaced to the user. Info is logged for transparency.

---

## Pre-Generation Feasibility Check

```
VALIDATE_FEASIBILITY(goal_profile, constraints):
  result = ValidationResult(feasible=True, errors=[], warnings=[], info=[])

  CHECK_EQUIPMENT(goal_profile, constraints, result)
  CHECK_DAYS(goal_profile, constraints, result)
  CHECK_SESSION_TIME(goal_profile, constraints, result)
  CHECK_PREREQUISITES(goal_profile, constraints, result)
  CHECK_INJURY_CONFLICTS(goal_profile, constraints, result)
  CHECK_GOAL_INCOMPATIBILITY(goal_profile, constraints, result)
  CHECK_PHASE_FEASIBILITY(goal_profile, constraints, result)

  result.feasible = (len(result.errors) == 0)
  return result
```

### Equipment Check

```
CHECK_EQUIPMENT(goal_profile, constraints, result):
  # Identify the minimum equipment archetypes needed for this goal
  # (those archetypes used for the goal's top-priority modalities)
  top_modalities = get_top_n_modalities(goal_profile.priorities, n=3)
  archetypes = load_archetypes_for_modalities(top_modalities)

  for archetype in archetypes:
    required = set(archetype.required_equipment)
    available = set(constraints.equipment)
    missing = required - available

    if missing:
      has_scaling = archetype.scaling.equipment_limited is defined
      priority = constraints.constraint_priority.get("equipment", "hard")

      if not has_scaling:
        if priority == "hard":
          result.errors.append({
            code: "EQUIPMENT_MISSING",
            message: f"Archetype '{archetype.name}' requires {missing} — not in athlete equipment.",
            field: "equipment",
            suggested_fix: f"Add {missing} to equipment, or switch to an equipment profile that includes it."
          })
        else:
          result.warnings.append({
            code: "EQUIPMENT_MISSING_SOFT",
            message: f"Archetype '{archetype.name}' requires {missing} — will attempt to substitute."
          })
      else:
        result.info.append({
          code: "EQUIPMENT_SCALED",
          message: f"'{archetype.name}' will use equipment-limited scaling (missing: {missing})."
        })
```

### Days Per Week Check

```
CHECK_DAYS(goal_profile, constraints, result):
  framework = SELECT_FRAMEWORK(goal_profile, constraints)  # from scheduler
  min_days = framework.applicable_when.days_per_week_min

  if constraints.days_per_week < min_days:
    priority = constraints.constraint_priority.get("days_per_week", "hard")
    if priority == "hard":
      result.errors.append({
        code: "INSUFFICIENT_DAYS",
        message: f"Goal '{goal_profile.name}' via framework '{framework.name}' requires "
                 f"at least {min_days} days/week. Athlete has {constraints.days_per_week}.",
        field: "days_per_week",
        suggested_fix: f"Increase days_per_week to {min_days}, or select a more permissive "
                       f"framework (see goal alternatives: {goal_profile.framework_selection.alternatives})."
      })

  # Soft warning: days available but likely under-programming
  if constraints.days_per_week == min_days:
    result.warnings.append({
      code: "MINIMAL_DAYS",
      message: f"Running at minimum days ({min_days}/week) — lower-priority modalities will be dropped."
    })
```

### Session Time Check

```
CHECK_SESSION_TIME(goal_profile, constraints, result):
  top_modalities = get_top_n_modalities(goal_profile.priorities, n=2)
  archetypes = load_archetypes_for_modalities(top_modalities)

  # Find the minimum session length needed for any required archetype
  min_required = min(a.duration_estimate_minutes for a in archetypes
                     if not a.scaling.time_limited)
  scaled_min = min(a.scaling.time_limited.duration_estimate_minutes
                   for a in archetypes if a.scaling.time_limited is defined)

  if constraints.session_time_minutes < scaled_min:
    priority = constraints.constraint_priority.get("session_time_minutes", "soft")
    if priority == "hard":
      result.errors.append({
        code: "SESSION_TOO_SHORT",
        message: f"Minimum session time for {goal_profile.name} is {scaled_min} min. "
                 f"Athlete has {constraints.session_time_minutes} min.",
        field: "session_time_minutes",
        suggested_fix: "Increase session_time_minutes or set constraint_priority.session_time_minutes to 'soft'."
      })
    else:
      result.warnings.append({
        code: "SESSION_TIME_CONSTRAINT",
        message: f"Session time {constraints.session_time_minutes} min is short — "
                 f"finisher/accessory slots will be dropped to fit."
      })

  elif constraints.session_time_minutes < min_required:
    result.warnings.append({
      code: "SESSION_TIME_SCALED",
      message: f"Some archetypes will use time_limited scaling "
               f"({constraints.session_time_minutes} min < standard {min_required} min)."
    })
```

### Prerequisite / Entry Benchmark Check

```
CHECK_PREREQUISITES(goal_profile, constraints, result):
  if goal_profile.minimum_prerequisites is None:
    return

  # prerequisites are recorded on constraints.current_benchmarks (if provided)
  if constraints.current_benchmarks is None:
    result.warnings.append({
      code: "NO_BENCHMARKS",
      message: "No current_benchmarks provided — cannot verify entry prerequisites. "
               "Program generated assuming prerequisites met."
    })
    return

  for prereq_id, threshold in goal_profile.minimum_prerequisites:
    benchmark = load_benchmark(prereq_id)
    athlete_value = constraints.current_benchmarks.get(prereq_id)

    if athlete_value is None:
      result.warnings.append({
        code: "PREREQ_UNTESTED",
        message: f"Prerequisite '{benchmark.name}' not assessed — cannot verify."
      })
      continue

    meets = (athlete_value >= threshold) if not benchmark.lower_is_better \
            else (athlete_value <= threshold)

    if not meets:
      result.warnings.append({
        code: "PREREQ_NOT_MET",
        message: f"Entry prerequisite not met: {benchmark.name} "
                 f"(required {threshold}, athlete has {athlete_value}). "
                 f"Program will generate but results may be suboptimal."
      })
```

### Injury Conflict Check

```
CHECK_INJURY_CONFLICTS(goal_profile, constraints, result):
  if not constraints.injury_flags:
    return

  # Load all injury flags and their excluded movement patterns
  injury_data = {flag: load_injury_flag(flag) for flag in constraints.injury_flags}

  # Get all movement patterns excluded by active injuries
  all_excluded_patterns = set()
  for flag, data in injury_data:
    all_excluded_patterns.update(data.excluded_movement_patterns)

  # Check if top-priority modalities heavily rely on excluded patterns
  modality_data = load_all_modalities()
  for modality, weight in sorted(goal_profile.priorities, by=weight, desc):
    if weight < 0.10: break  # stop at minor priorities

    # Load exercises for this modality, check how many are affected
    modality_exercises = load_exercises_for_modality(modality)
    excluded_count = sum(
      1 for ex in modality_exercises
      if any(p in all_excluded_patterns for p in ex.movement_patterns)
    )
    pct_excluded = excluded_count / len(modality_exercises) if modality_exercises else 0

    if pct_excluded > 0.60:
      result.warnings.append({
        code: "INJURY_GOAL_CONFLICT",
        message: f"Injury flag(s) {constraints.injury_flags} exclude {pct_excluded:.0%} of "
                 f"exercises in '{modality}' (priority weight {weight}). "
                 f"Program will be heavily substituted for this modality."
      })
    elif pct_excluded > 0.30:
      result.info.append({
        code: "INJURY_PARTIAL_IMPACT",
        message: f"Injury flags affect {pct_excluded:.0%} of {modality} exercises — "
                 f"substitutions will be applied."
      })
```

### Goal Incompatibility Check

```
CHECK_GOAL_INCOMPATIBILITY(goal_profile, constraints, result):
  # Check if constraints.active_goals contains any goals incompatible with this one
  if not constraints.get("active_goals"):
    return

  for incompatible in goal_profile.incompatible_with:
    if incompatible.goal_id in constraints.active_goals:
      result.warnings.append({
        code: "GOAL_CONFLICT",
        message: f"Goal '{goal_profile.name}' is incompatible with active goal "
                 f"'{incompatible.goal_id}': {incompatible.reason}",
        field: "active_goals"
      })
```

### Phase Feasibility Check

```
CHECK_PHASE_FEASIBILITY(goal_profile, constraints, result):
  if constraints.training_phase in ("post_op", "rehab"):
    # Check if goal profile includes a rehab phase
    phase_names = [p.phase for p in goal_profile.phase_sequence]
    if "rehab" not in phase_names:
      result.warnings.append({
        code: "PHASE_MISMATCH",
        message: f"Athlete is in '{constraints.training_phase}' phase but goal "
                 f"'{goal_profile.name}' has no rehab phase defined. "
                 f"Consider using 'injury_rehab' goal profile first."
      })

  # Check if periodization_week exceeds current phase length
  if constraints.periodization_week is not None:
    for phase_entry in goal_profile.phase_sequence:
      if phase_entry.phase == constraints.training_phase:
        if constraints.periodization_week > phase_entry.weeks:
          result.warnings.append({
            code: "WEEK_EXCEEDS_PHASE",
            message: f"Week {constraints.periodization_week} exceeds {constraints.training_phase} "
                     f"phase length ({phase_entry.weeks} weeks). Phase transition may be overdue."
          })
```

---

## Post-Schedule Conflict Audit

After the scheduler produces a weekly schedule, validate the output.

```
AUDIT_SCHEDULE(weekly_schedule, modality_data, constraints):
  result = ValidationResult(feasible=True, errors=[], warnings=[], info=[])

  AUDIT_RECOVERY_GAPS(weekly_schedule, modality_data, result)
  AUDIT_WEEKLY_VOLUME(weekly_schedule, modality_data, result)
  AUDIT_SESSION_PAIRING(weekly_schedule, modality_data, result)
  AUDIT_FRAMEWORK_INTERFERENCE(weekly_schedule, result)

  return result
```

### Recovery Gap Audit

```
AUDIT_RECOVERY_GAPS(weekly_schedule, modality_data, result):
  for day in range(2, len(weekly_schedule) + 1):
    for modality in weekly_schedule[day]:
      mod = modality_data[modality]
      hours_needed = mod.recovery_hours_min

      # Look back at previous 3 days
      for prev_day in range(max(1, day - 3), day):
        hours_between = (day - prev_day) * 24
        for prev_modality in weekly_schedule[prev_day]:
          prev_mod = modality_data[prev_modality]

          # Same modality repeated too soon
          if prev_modality == modality and hours_between < hours_needed:
            result.warnings.append({
              code: "RECOVERY_VIOLATION",
              message: f"{modality} on day {day} after {modality} on day {prev_day} "
                       f"({hours_between}h gap, {hours_needed}h required)."
            })

          # Two high-cost modalities back to back
          if (mod.recovery_cost == "high" and prev_mod.recovery_cost == "high"
              and hours_between < 48):
            result.warnings.append({
              code: "HIGH_COST_ADJACENCY",
              message: f"High-cost modalities {modality} and {prev_modality} "
                       f"on adjacent days ({hours_between}h gap). Recovery risk."
            })
```

### Weekly Volume Audit

```
AUDIT_WEEKLY_VOLUME(weekly_schedule, modality_data, result):
  weekly_minutes = {}

  for day, sessions in weekly_schedule:
    for session in sessions:
      mod_id = session.modality
      mod = modality_data[mod_id]
      # Estimate minutes from archetype duration if available, else typical_session_minutes.max
      minutes = session.get("duration_estimate_minutes", mod.typical_session_minutes.max)
      weekly_minutes[mod_id] = weekly_minutes.get(mod_id, 0) + minutes

  for mod_id, total_minutes in weekly_minutes:
    mod = modality_data[mod_id]

    if total_minutes < mod.min_weekly_minutes:
      result.info.append({
        code: "VOLUME_BELOW_MIN",
        message: f"{mod_id}: {total_minutes} min/week below minimum {mod.min_weekly_minutes} min. "
                 f"May be insufficient for adaptation."
      })

    if total_minutes > mod.max_weekly_minutes:
      result.warnings.append({
        code: "VOLUME_EXCEEDS_MAX",
        message: f"{mod_id}: {total_minutes} min/week exceeds maximum recoverable volume "
                 f"({mod.max_weekly_minutes} min). Reduce frequency or session duration."
      })
```

### Session Pairing Audit

```
AUDIT_SESSION_PAIRING(weekly_schedule, modality_data, result):
  for day, sessions in weekly_schedule:
    modalities_today = [s.modality for s in sessions]
    for i, mod_a in enumerate(modalities_today):
      for mod_b in modalities_today[i+1:]:
        mod_a_data = modality_data[mod_a]
        mod_b_data = modality_data[mod_b]

        if mod_b in mod_a_data.incompatible_in_session_with:
          result.warnings.append({
            code: "SESSION_INCOMPATIBILITY",
            message: f"Day {day}: {mod_a} and {mod_b} are incompatible in the same session. "
                     f"Consider splitting to separate days."
          })
```

### Framework Interference Audit

```
AUDIT_FRAMEWORK_INTERFERENCE(weekly_schedule, result):
  # Count sessions per modality
  modality_counts = count_sessions_per_modality(weekly_schedule)

  # Check for known interference patterns
  if modality_counts.get("aerobic_base", 0) >= 3 and modality_counts.get("max_strength", 0) >= 3:
    result.warnings.append({
      code: "INTERFERENCE_RISK",
      message: "High aerobic volume (≥3 sessions) concurrent with high strength volume (≥3 sessions). "
               "Interference effect likely — consider reducing one or applying concurrent_training framework rules."
    })

  if modality_counts.get("anaerobic_intervals", 0) >= 3:
    result.warnings.append({
      code: "ANAEROBIC_OVERLOAD",
      message: "≥3 anaerobic interval sessions per week. Recovery demand is very high. "
               "Cap at 2 sessions or distribute across minimum 3 days."
    })
```

---

## Error Codes Reference

| Code | Severity | Description |
|------|----------|-------------|
| `EQUIPMENT_MISSING` | Error | Required equipment not available, no scaling exists |
| `EQUIPMENT_MISSING_SOFT` | Warning | Equipment missing but constraint is soft |
| `EQUIPMENT_SCALED` | Info | Archetype will use equipment_limited scaling |
| `INSUFFICIENT_DAYS` | Error | Days per week below framework minimum |
| `MINIMAL_DAYS` | Warning | Running at exact minimum — some modalities dropped |
| `SESSION_TOO_SHORT` | Error | Session time below minimum even with scaling |
| `SESSION_TIME_CONSTRAINT` | Warning | Finisher/accessory slots will be dropped |
| `SESSION_TIME_SCALED` | Info | time_limited scaling will be applied |
| `NO_BENCHMARKS` | Warning | Prerequisites cannot be verified |
| `PREREQ_UNTESTED` | Warning | Specific prerequisite not assessed |
| `PREREQ_NOT_MET` | Warning | Entry benchmark below threshold |
| `INJURY_GOAL_CONFLICT` | Warning | Injuries exclude >60% of primary modality exercises |
| `INJURY_PARTIAL_IMPACT` | Info | Injuries affect 30–60% of modality exercises |
| `GOAL_CONFLICT` | Warning | Active goal incompatible with requested goal |
| `PHASE_MISMATCH` | Warning | Athlete phase not represented in goal's phase_sequence |
| `WEEK_EXCEEDS_PHASE` | Warning | periodization_week beyond phase length |
| `RECOVERY_VIOLATION` | Warning | Same modality repeated before recovery_hours_min |
| `HIGH_COST_ADJACENCY` | Warning | Two high-cost modalities on adjacent days |
| `VOLUME_BELOW_MIN` | Info | Modality below min_weekly_minutes |
| `VOLUME_EXCEEDS_MAX` | Warning | Modality above max_weekly_minutes |
| `SESSION_INCOMPATIBILITY` | Warning | Incompatible modalities sharing a session |
| `INTERFERENCE_RISK` | Warning | High concurrent volume in conflicting modalities |
| `ANAEROBIC_OVERLOAD` | Warning | Too many high-intensity sessions per week |
