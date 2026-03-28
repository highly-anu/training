# Phase Transition Rules

Rules for when and how the system moves between training phases. Covers time-based transitions, performance-based triggers, fatigue-based overrides, and deload week protocols.

---

## Phase Types (from schema)

```
active      — general training, no defined event
base        — foundational volume, low intensity
build       — increasing volume and intensity
peak        — specificity, reduced volume, high intensity
taper       — pre-event reduction
deload      — recovery week (can be inserted anywhere)
maintenance — holding current level, reduced progression
rehab       — injury-modified training
post_op     — immediate post-surgery or acute injury
```

---

## 1. Time-Based Transitions

Default transitions follow the `phase_sequence` defined on each goal profile. Each phase has a `weeks` field specifying its scheduled duration.

```
SHOULD_TRANSITION_TIME(current_phase, current_week, goal_profile):
  for phase_entry in goal_profile.phase_sequence:
    if phase_entry.phase == current_phase:
      if current_week >= phase_entry.weeks:
        return True, next_phase(goal_profile.phase_sequence, current_phase)
  return False, None

NEXT_PHASE(phase_sequence, current_phase):
  phases_in_order = [p.phase for p in phase_sequence]
  current_index = phases_in_order.index(current_phase)
  if current_index + 1 < len(phases_in_order):
    return phases_in_order[current_index + 1]
  return "maintenance"  # program complete, hold fitness
```

### Standard phase lengths by goal

| Goal | base | build | peak | taper |
|------|------|-------|------|-------|
| Alpine Climbing | 8 wk | 6 wk | 4 wk | 2 wk |
| SOF Operator | 6 wk | 8 wk | 4 wk | 2 wk |
| BJJ Competitor | 6 wk | 6 wk | 3 wk | 1 wk |
| General GPP | 8 wk | 8 wk | — | — |
| Ultra Endurance | 10 wk | 8 wk | 4 wk | 3 wk |
| Max Strength Focus | 4 wk | 4 wk | 3 wk | 1 wk |
| Injury Rehab | varies | — | — | — |

*(Authoritative values come from each goal profile's `phase_sequence.weeks` field.)*

---

## 2. Performance-Based Triggers

A phase transition can also occur early if the athlete demonstrates readiness by hitting phase-exit benchmarks.

```
SHOULD_TRANSITION_PERFORMANCE(current_phase, constraints, goal_profile):
  # Only evaluate performance-based exit if in base or build phase
  if current_phase not in ("base", "build"):
    return False, None

  # Get the relevant benchmarks for this goal
  relevant_benchmarks = load_benchmarks_for_goal(goal_profile.id)

  # Define phase-exit thresholds (what the athlete needs to hit to advance early)
  exit_thresholds = PHASE_EXIT_THRESHOLDS[current_phase]

  # Count how many key benchmarks are met
  met_count = 0
  total_key = 0
  for benchmark in relevant_benchmarks:
    threshold = exit_thresholds.get(benchmark.id)
    if threshold is None: continue
    total_key += 1
    athlete_value = constraints.current_benchmarks.get(benchmark.id)
    if athlete_value is None: continue
    meets = (athlete_value >= threshold) if not benchmark.lower_is_better \
            else (athlete_value <= threshold)
    if meets: met_count += 1

  # Advance early if 80%+ of key benchmarks met AND minimum weeks elapsed
  min_weeks_in_phase = 3  # never advance before 3 weeks regardless
  if (met_count / total_key >= 0.80 and total_key > 0
      and constraints.periodization_week >= min_weeks_in_phase):
    next = next_phase(goal_profile.phase_sequence, current_phase)
    return True, next

  return False, None
```

### Phase exit benchmark thresholds

These define what "ready to advance" means at each phase boundary.

```
PHASE_EXIT_THRESHOLDS = {
  "base": {
    # Athlete should be aerobically capable and structurally solid
    # Values are % of the benchmark's "intermediate" level
    "run_1mile_minutes":      intermediate_level * 1.10,  # within 10% of intermediate
    "back_squat_bw_ratio":    intermediate_level * 0.85,
    "pull_up_reps":           intermediate_level * 0.80,
    "run_3mile_minutes":      intermediate_level * 1.15,
  },
  "build": {
    # Athlete should be close to peak physical capacity for their goal
    "run_3mile_minutes":      intermediate_level * 1.00,  # hitting intermediate
    "back_squat_bw_ratio":    intermediate_level * 1.00,
    "ssst_reps":              intermediate_level * 0.90,
  }
}
```

---

## 3. Fatigue-Based Overrides

Fatigue state can interrupt or delay planned transitions.

```
APPLY_FATIGUE_OVERRIDE(planned_transition, constraints):
  fatigue = constraints.fatigue_state

  if fatigue == "overreached":
    # Override any planned transition — force deload immediately
    # Do not advance to next phase until deload is complete
    return {
      force_deload: True,
      block_transition: True,
      message: "Overreached detected — immediate deload required before phase advance."
    }

  if fatigue == "accumulated":
    # Do not advance phase early; allow time-based transition only
    # If approaching scheduled deload (within 1 week), move it earlier
    if constraints.periodization_week % 4 == 3:  # one week before deload
      return {
        force_early_deload: True,
        block_early_transition: True,
        message: "Accumulated fatigue — deload moved one week earlier."
      }

  return { no_override: True }
```

### Fatigue state determination

The fatigue state is athlete-reported in constraints, but the system can also flag it based on performance trends:

```
INFER_FATIGUE_STATE(athlete_history, current_week):
  # Performance declining across modalities
  recent_sessions = athlete_history.last_n_sessions(n=6)
  failures = count(recent_sessions, where=not success)

  if failures >= 4:  # 4 of last 6 sessions failed
    return "overreached"
  elif failures >= 2:
    return "accumulated"

  # RPE rising without load increase
  rpe_trend = avg_rpe(recent_sessions[-3:]) - avg_rpe(recent_sessions[-6:-3])
  if rpe_trend >= 1.5:
    return "accumulated"

  return "normal"
```

---

## 4. Deload Week Protocol

Deloads are scheduled every 4th week within each mesocycle (matching `framework.deload_protocol.frequency_weeks`). They can also be triggered by fatigue override.

### Deload parameters by framework

| Framework | Frequency | Volume reduction | Intensity |
|-----------|-----------|-----------------|-----------|
| linear_progression | every 4 wk | 85% of working weight, -1 rep | maintain |
| block_periodization | week 4 is built-in | 60% of peak volume | reduce to 70% 1RM |
| polarized_80_20 | every 4 wk | 60% of session duration | Zone 1–2 only |
| concurrent_training | every 4 wk | 60% volume, -1 session | reduce slightly |
| emom_amrap | every 4 wk | reduce time domains by 25% | maintain |
| gpp_circuits | every 4 wk | 60% circuit volume | reduce RPE target by 1 |
| rpe_autoregulation | every 4 wk | normal volume at RPE 6 | RPE 6 cap |
| high_frequency_skill | every 4 wk | 50% practice volume | quality focus only |
| kb_pentathlon | every 4 wk | reduce set duration by 40% | rpm -4 |

### Applying the deload

```
BUILD_DELOAD_WEEK(normal_schedule, framework, constraints):
  deload = deepcopy(normal_schedule)
  protocol = framework.deload_protocol
  reduction = protocol.volume_reduction_pct  # e.g. 0.60

  # Option 1: Reduce frequency (drop lowest-priority session)
  if constraints.days_per_week >= 5:
    drop_session(deload, priority="lowest")

  # Option 2: Reduce volume in each session (mark sessions as deload)
  for day, sessions in deload:
    for session in sessions:
      session.is_deload = True
      session.volume_multiplier = reduction
      # Archetype selector will use archetype.scaling.deload if defined
      # Otherwise: reduce sets by 30%, maintain reps and load

  # Option 3: For linear_load — reduce weight, same reps
  # This is handled in progression.py when is_deload=True

  return deload
```

---

## 5. Deload vs. Easy Week vs. Taper

These are distinct concepts that are easily confused.

| Term | Trigger | Duration | Volume | Intensity | Purpose |
|------|---------|----------|--------|-----------|---------|
| **Deload week** | Scheduled every 4th week | 1 week | −40% | Maintained | Acute recovery within a block |
| **Easy week** | Fatigue == accumulated | 1–2 weeks | −30% | Reduced | Unplanned extra recovery |
| **Taper** | Pre-event phase from goal profile | 1–3 weeks | −40–50% | Maintained | Pre-competition peaking |
| **Forced deload** | fatigue_state == overreached | 1–2 weeks | −50% | Reduced | Emergency recovery |

```
SELECT_RECOVERY_PROTOCOL(trigger, constraints, goal_profile):
  if trigger == "scheduled_deload":
    return DELOAD_WEEK

  if trigger == "fatigue_accumulated":
    return EASY_WEEK

  if trigger == "phase_taper" and current_phase == "taper":
    return TAPER  # governed by goal profile's taper phase settings

  if trigger == "fatigue_overreached":
    return FORCED_DELOAD
```

---

## 6. Phase Transition Execution

When a transition is approved (time-based or performance-based), execute:

```
EXECUTE_PHASE_TRANSITION(from_phase, to_phase, goal_profile, constraints):
  # 1. Update current_phase
  new_phase = to_phase

  # 2. Reset periodization_week to 1
  new_week = 1

  # 3. Apply priority override for new phase
  new_priorities = APPLY_PHASE_OVERRIDE(
    goal_profile.priorities,
    goal_profile.phase_sequence,
    new_phase
  )

  # 4. Reassess framework selection (phase change may qualify new framework)
  new_framework = SELECT_FRAMEWORK(goal_profile, constraints_with_new_phase)

  # 5. Log transition
  log(f"Phase transition: {from_phase} → {to_phase} at week {constraints.periodization_week}")
  log(f"New priority vector: {new_priorities}")
  if new_framework.id != old_framework.id:
    log(f"Framework change: {old_framework.id} → {new_framework.id}")

  return { phase: new_phase, week: new_week, priorities: new_priorities, framework: new_framework }
```

---

## 7. Return to Training After Break

When `athlete_history` shows a gap ≥7 days:

```
RETURN_FROM_BREAK(days_missed, constraints, current_phase):
  # 1. Apply progression model rollbacks (handled in progression_models.md)

  # 2. Consider phase reset
  if days_missed >= 28:
    # Return to beginning of current phase
    constraints.periodization_week = 1
    log(f"28+ day break — returning to week 1 of {current_phase} phase.")

  elif days_missed >= 14:
    # Step back 2 weeks within current phase
    constraints.periodization_week = max(1, constraints.periodization_week - 2)
    log(f"14–27 day break — stepped back to week {constraints.periodization_week}.")

  # 3. Set fatigue_state to fresh (break = unplanned rest)
  constraints.fatigue_state = "fresh"

  # 4. First week back: treat as deload week regardless of schedule
  force_deload_week_on_return = True

  return constraints
```
