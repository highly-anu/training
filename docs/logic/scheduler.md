# Scheduler Logic

Pseudocode for assigning modalities to days and populating a weekly training schedule. This is the core of `scheduler.py` in Phase 4.

The scheduler takes a goal profile and athlete constraints and returns a `weekly_schedule`: a map of day → list of sessions, where each session has a modality and eventually an archetype.

---

## Inputs and Outputs

```
INPUTS:
  goal_profile        from data/goals/*.yaml
  constraints         athlete-provided (days_per_week, equipment, etc.)
  current_phase       string (base, build, peak, taper, deload)
  current_week        int (week number within mesocycle, 1-indexed)

OUTPUT:
  weekly_schedule = {
    day_1: [{ modality, session_type, priority_rank }],
    day_2: [...],
    ...
    day_N: [...]   # N = constraints.days_per_week
  }
```

---

## Step 1: Framework Selection

```
SELECT_FRAMEWORK(goal_profile, constraints):
  candidates = []

  # Start with the goal's default framework
  default = goal_profile.framework_selection.default_framework
  candidates.append(load_framework(default))

  # Check alternatives in declared order
  for alt in goal_profile.framework_selection.alternatives:
    if eval_condition(alt.condition, constraints):
      candidates.insert(0, load_framework(alt.framework_id))
      break  # first matching alternative wins

  # Filter by training_level and days_per_week
  valid = []
  for fw in candidates:
    if constraints.training_level in fw.applicable_when.training_level:
      if fw.applicable_when.days_per_week_min <= constraints.days_per_week <= fw.applicable_when.days_per_week_max:
        valid.append(fw)

  if valid is empty:
    # Fall back to most permissive framework for this goal
    return fallback_framework(goal_profile)

  return valid[0]  # first valid (default wins unless alternative condition matched)
```

---

## Step 2: Priority Vector → Session Count Allocation

```
ALLOCATE_SESSIONS(priorities, days_per_week, framework):
  allocation = {}

  # If framework specifies hard session counts, use them directly
  if framework.sessions_per_week is defined:
    # Scale framework counts to available days
    fw_total = sum(framework.sessions_per_week.values())
    scale_factor = days_per_week / fw_total
    for modality, count in framework.sessions_per_week:
      allocation[modality] = round(count * scale_factor)
    # Adjust rounding errors to hit days_per_week exactly
    allocation = fix_rounding(allocation, days_per_week)
    return allocation

  # Otherwise, derive from goal priority weights
  raw = {}
  for modality, weight in priorities:
    raw[modality] = weight * days_per_week

  # Round to integers, preserving total
  allocation = proportional_round(raw, target_total=days_per_week)

  # Enforce modality weekly volume bounds
  modality_data = load_all_modalities()
  for modality, count in allocation:
    mod = modality_data[modality]
    # Check minimum sessions (skip if modality has min_weekly_minutes)
    min_sessions = ceil(mod.min_weekly_minutes / mod.typical_session_minutes.max)
    if count < min_sessions and weight > 0:
      # Steal from lowest-priority modality
      allocation = redistribute(allocation, give_to=modality, min_count=min_sessions)

  return allocation

PROPORTIONAL_ROUND(raw, target_total):
  # Classic largest-remainder method
  floors = {k: floor(v) for k, v in raw}
  remainders = {k: v - floor(v) for k, v in raw}
  deficit = target_total - sum(floors.values())
  # Add 1 to the 'deficit' modalities with largest remainders
  sorted_by_remainder = sort(remainders, desc)
  for i in range(deficit):
    floors[sorted_by_remainder[i].key] += 1
  return floors
```

---

## Step 3: Phase Priority Override

```
APPLY_PHASE_OVERRIDE(base_priorities, phase_sequence, current_phase):
  for phase_entry in phase_sequence:
    if phase_entry.phase == current_phase:
      if phase_entry.priority_override is defined:
        return phase_entry.priority_override
  return base_priorities  # no override for this phase

# Example: Alpine Climbing in peak phase
# base_priorities:  { aerobic_base: 0.50, durability: 0.20, max_strength: 0.15, ... }
# override in peak: { aerobic_base: 0.40, durability: 0.30, power: 0.15, ... }
```

---

## Step 4: Day Assignment (Recovery-Aware Scheduling)

This is the most complex step. Modalities must be assigned to specific days respecting recovery constraints and session compatibility.

```
ASSIGN_TO_DAYS(allocation, constraints, modality_data):
  days = list(range(1, constraints.days_per_week + 1))
  schedule = { day: [] for day in days }

  # Sort modalities by recovery_cost descending
  # Place the highest-cost modalities first — they are hardest to schedule
  sorted_modalities = sort_by_recovery_cost(allocation.keys(), modality_data)

  for modality in sorted_modalities:
    count = allocation[modality]
    mod = modality_data[modality]
    placed = 0

    # Try each day, prefer days with maximum gap from last same/high-cost session
    candidates = score_days(days, schedule, modality, mod, modality_data)

    for day in candidates:
      if placed >= count:
        break
      if is_recovery_safe(day, modality, mod, schedule, modality_data):
        if is_session_compatible(day, modality, mod, schedule, modality_data):
          schedule[day].append(modality)
          placed += 1

    if placed < count:
      # Fallback: try pairing with a compatible modality on the same day
      placed = try_pairing(modality, count - placed, schedule, modality_data, days)

    if placed < count:
      log_warning(f"Could not place all {count} sessions of {modality} — " +
                  f"placed {placed}/{count}. Consider adding training days.")

  return schedule

SCORE_DAYS(days, schedule, modality, mod, modality_data):
  scored = []
  for day in days:
    # Prefer days furthest from last high-cost session
    gap = hours_since_last_high_cost_session(day, schedule, modality_data)
    sessions_today = len(schedule[day])
    # Prefer days with 0 or 1 existing sessions
    score = gap - (sessions_today * 12)  # each existing session costs 12h equivalent
    scored.append((score, day))
  return [day for (_, day) in sort(scored, desc)]

IS_RECOVERY_SAFE(day, modality, mod, schedule, modality_data):
  # Check recovery_hours_min for this modality
  for prev_day in range(day - 3, day):
    if prev_day < 1: continue
    for prev_modality in schedule[prev_day]:
      prev_mod = modality_data[prev_modality]
      hours_between = (day - prev_day) * 24
      # Two high-cost modalities need separation
      if mod.recovery_cost == "high" and prev_mod.recovery_cost == "high":
        if hours_between < mod.recovery_hours_min:
          return False
      # Same modality always needs its recovery window
      if prev_modality == modality:
        if hours_between < mod.recovery_hours_min:
          return False
  return True

IS_SESSION_COMPATIBLE(day, modality, mod, schedule, modality_data):
  existing_modalities = schedule[day]
  # Empty day is always compatible
  if not existing_modalities:
    return True
  # Check bidirectional incompatibility
  for existing in existing_modalities:
    existing_mod = modality_data[existing]
    if existing in mod.incompatible_in_session_with:
      return False
    if modality in existing_mod.incompatible_in_session_with:
      return False
  return True
```

---

## Step 5: Intra-Session Ordering

When multiple modalities share a day, order them correctly.

```
ORDER_SESSION(modalities_on_day, modality_data):
  # session_position field on modality: first / main / accessory / finisher / cooldown

  POSITION_ORDER = {
    "first":     0,   # mobility, joint prep — always opens session
    "main":      1,   # primary modality (strength, high-intensity conditioning)
    "accessory": 2,   # secondary modality (movement skill after strength)
    "finisher":  3,   # short conditioning, carries
    "cooldown":  4    # mobility again, light aerobic, rehab
  }

  return sort(modalities_on_day, key=lambda m: POSITION_ORDER[modality_data[m].session_position])

# Example: day has max_strength + mobility
# max_strength.session_position = "first"  → goes first?
# Actually: mobility is warm-up (first), strength is main
# The position field names this correctly:
#   mobility:        session_position: cooldown  (or first for warm-up — see modality file)
#   max_strength:    session_position: first      (within the main block)
# But in a combined day, mobility runs as warm-up BEFORE strength
# Resolution: treat "first" as the primary session anchor;
# compatible modalities with session_position=cooldown go after
```

---

## Step 6: Deload Week Detection

```
IS_DELOAD_WEEK(current_week, framework):
  if current_week % framework.deload_protocol.frequency_weeks == 0:
    return True
  if constraints.fatigue_state == "overreached":
    return True  # Force deload regardless of schedule
  return False

APPLY_DELOAD(schedule, framework, modality_data):
  deload_schedule = deepcopy(schedule)
  reduction = framework.deload_protocol.volume_reduction_pct

  for day, sessions in deload_schedule:
    for i, modality in enumerate(sessions):
      mod = modality_data[modality]
      # Mark the session as a deload — archetype selector will use scaling variants
      deload_schedule[day][i] = {
        modality: modality,
        is_deload: True,
        volume_multiplier: reduction
      }

  # Optionally drop one session if >= 5 days/week
  if constraints.days_per_week >= 5:
    drop_lowest_priority_session(deload_schedule)

  return deload_schedule
```

---

## Complete Scheduler Flow

```
SCHEDULE(goal_profile, constraints, current_phase, current_week):
  # 1. Get phase-adjusted priorities
  priorities = APPLY_PHASE_OVERRIDE(
    goal_profile.priorities,
    goal_profile.phase_sequence,
    current_phase
  )

  # 2. Select framework
  framework = SELECT_FRAMEWORK(goal_profile, constraints)

  # 3. Allocate session counts
  allocation = ALLOCATE_SESSIONS(priorities, constraints.days_per_week, framework)

  # 4. Assign to days
  schedule = ASSIGN_TO_DAYS(allocation, constraints, load_all_modalities())

  # 5. Order within each day
  for day in schedule:
    schedule[day] = ORDER_SESSION(schedule[day], load_all_modalities())

  # 6. Apply deload if needed
  if IS_DELOAD_WEEK(current_week, framework):
    schedule = APPLY_DELOAD(schedule, framework, load_all_modalities())

  return schedule
```

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| days_per_week = 1 | Single day gets the top-priority modality only; others dropped with warning |
| All days filled, modality still unplaced | Log warning, suggest adding a training day or dropping lowest-priority modality |
| Two high-cost modalities both need day 1 | Recovery check fails — push second modality to next available gap day |
| Deload week + overreached | Double deload: apply deload protocol AND drop 1 session |
| fatigue_state = "overreached" | Trigger immediate deload regardless of week number; log override |
| Modality has no available day with recovery gap | Place on closest available day, log "recovery gap violation — consider reducing frequency" |
