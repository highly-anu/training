# Selector Logic

Pseudocode for choosing archetypes for session slots and exercises for archetype slots. This is the core of `selector.py` in Phase 4.

The selector runs after the scheduler has produced a `weekly_schedule`. For each session in the schedule, it picks an archetype; for each slot in the archetype, it picks an exercise.

---

## Inputs and Outputs

```
INPUTS:
  weekly_schedule       output of scheduler — { day: [{ modality, is_deload }] }
  constraints           athlete constraints (equipment, injury_flags, training_level)
  current_phase         string
  unlocked_exercises    set of exercise IDs the athlete has cleared prerequisites for
  recent_sessions       list of last 14 days of (archetype_id, exercise_ids) — for variety

OUTPUTS:
  populated_schedule = {
    day_1: [
      {
        modality: "max_strength",
        archetype: { id, name, slots, duration_estimate_minutes },
        exercises: [
          { slot_index: 0, exercise: { id, name, sets, reps, load_target } },
          { slot_index: 1, exercise: { ... } },
          ...
        ]
      }
    ],
    ...
  }
```

---

## Phase 1: Archetype Selection

### Load candidate archetypes

```
GET_ARCHETYPE_CANDIDATES(modality, constraints, current_phase, is_deload):
  all_archetypes = load_archetypes_for_modality(modality)  # scan data/archetypes/**
  candidates = []

  for archetype in all_archetypes:
    # Filter 1: modality match
    if archetype.modality != modality: continue

    # Filter 2: equipment
    required = set(archetype.required_equipment)
    available = set(constraints.equipment)
    if not required.issubset(available):
      # Check if equipment_limited scaling exists
      if archetype.scaling.equipment_limited is defined:
        # Use scaled version — note it for downstream slot population
        archetype = apply_scaling(archetype, "equipment_limited", constraints.equipment)
      else:
        continue  # no valid scaling, skip

    # Filter 3: duration
    if is_deload:
      effective_duration = archetype.scaling.deload.duration_estimate_minutes
                           if archetype.scaling.deload is defined
                           else archetype.duration_estimate_minutes * 0.70
    else:
      effective_duration = archetype.duration_estimate_minutes
    if effective_duration > constraints.session_time_minutes:
      # Check time_limited scaling
      if archetype.scaling.time_limited is defined:
        archetype = apply_scaling(archetype, "time_limited", constraints.session_time_minutes)
      else:
        continue

    # Filter 4: phase applicability
    if archetype.applicable_phases is defined:
      if current_phase not in archetype.applicable_phases:
        continue

    candidates.append(archetype)

  return candidates
```

### Score and select archetype

```
SELECT_ARCHETYPE(modality, constraints, current_phase, is_deload,
                 goal_profile, recent_sessions):
  candidates = GET_ARCHETYPE_CANDIDATES(modality, constraints, current_phase, is_deload)

  if candidates is empty:
    return FAIL(f"No valid archetype for {modality} with current constraints and phase")

  scored = []
  for archetype in candidates:
    score = 0.0

    # Boost: philosophy alignment with goal's primary_sources
    for source in goal_profile.primary_sources:
      if source in archetype.sources:
        score += 2.0

    # Penalty: recently used (avoid repetition within 7 days)
    recent_ids = [s.archetype_id for s in recent_sessions if s.days_ago <= 7]
    if archetype.id in recent_ids:
      score -= 3.0

    # Boost: matches current phase emphasis
    if archetype.applicable_phases and current_phase in archetype.applicable_phases:
      score += 1.0

    scored.append((score, archetype))

  # Select highest-scored; break ties randomly
  return top_scored(scored)
```

---

## Phase 2: Exercise Selection

### Build the prerequisite DAG

This is built once per program generation, not per session.

```
BUILD_PREREQUISITE_DAG(all_exercises):
  dag = {}
  for exercise in all_exercises:
    dag[exercise.id] = {
      requires:  exercise.requires,   # list of exercise IDs or movement pattern IDs
      unlocks:   exercise.unlocks,    # list of exercise IDs
      equipment: exercise.equipment,
      modality:  exercise.modality,
      contraindicated_with: exercise.contraindicated_with
    }
  return dag

GET_UNLOCKED_EXERCISES(athlete_history, dag):
  # An exercise is unlocked if all its requires are in athlete history
  unlocked = set()
  for exercise_id, node in dag:
    if all(req in athlete_history for req in node.requires):
      unlocked.add(exercise_id)
  return unlocked

# Note: athlete_history is seeded from constraints.training_level:
#   novice:       only exercises with requires = []
#   intermediate: exercises requiring up to tier-2 prerequisites
#   advanced:     all exercises with requires met by standard progressions
#   elite:        full library, all prerequisites assumed met
SEED_HISTORY_FROM_LEVEL(training_level):
  levels = {
    "novice":       [],
    "intermediate": ["hip_hinge_pattern", "squat_pattern", "pull_pattern", "push_pattern",
                     "kb_swing_two_hand", "deadlift", "squat_back", "pull_up"],
    "advanced":     intermediate_history + ["power_clean", "snatch_kb", "hspu", "muscle_up"],
    "elite":        all_exercise_ids
  }
  return levels[training_level]
```

### Select exercise for a slot

```
SELECT_EXERCISE(slot, constraints, unlocked_exercises, dag,
                recent_exercises, current_phase):
  candidates = []

  for exercise_id in unlocked_exercises:
    node = dag[exercise_id]
    ex = load_exercise(exercise_id)

    # Filter 1: modality match
    # Slot defines what movement type it needs via slot_type + movement_patterns
    if not modality_matches(ex, slot):
      continue

    # Filter 2: equipment
    ex_equipment = set(ex.equipment)
    if not ex_equipment.issubset(set(constraints.equipment)):
      continue

    # Filter 3: injury contraindications
    if any(flag in ex.contraindicated_with for flag in constraints.injury_flags):
      continue

    # Filter 4: slot_type compatibility
    if not slot_type_compatible(slot.slot_type, ex):
      continue

    # Filter 5: training phase
    # Some exercises are inappropriate for certain phases (e.g., heavy maximal loads during taper)
    if current_phase == "taper" and ex.effort == "max":
      continue

    candidates.append(ex)

  if candidates is empty:
    # Try substitutions from injury_flags
    for flag in constraints.injury_flags:
      flag_data = load_injury_flag(flag)
      for (excluded, substitute) in flag_data.modified_exercises:
        if substitute in unlocked_exercises:
          sub_ex = load_exercise(substitute)
          if not any(f in sub_ex.contraindicated_with for f in constraints.injury_flags):
            candidates.append(sub_ex)
    if candidates is still empty:
      return FAIL(f"No valid exercise for slot '{slot.role}' with current constraints")

  # Score candidates
  scored = []
  for ex in candidates:
    score = 0.0

    # Penalize recent exercises (within 14 days)
    recent_ids = [e.id for e in recent_exercises if e.days_ago <= 14]
    if ex.id in recent_ids:
      times_used = count(recent_exercises, ex.id)
      score -= times_used * 2.0

    # Prefer exercises matching slot.effort
    if ex.effort == slot.effort_preference:
      score += 1.0

    # Prefer exercises that unlock others (forward progress)
    if ex.unlocks:
      score += 0.5

    scored.append((score, ex))

  return top_scored(scored)
```

### Slot type compatibility

```
SLOT_TYPE_COMPATIBLE(slot_type, exercise):
  # Sets/reps slots need exercises that have defined progressions.load or progressions.volume
  if slot_type == "sets_reps":
    return exercise.progressions is not None

  # Time domain slots need aerobic or conditioning exercises
  if slot_type in ("time_domain", "amrap", "for_time"):
    return exercise.modality in ("aerobic_base", "mixed_modal_conditioning",
                                 "strength_endurance", "durability")

  # EMOM slots need exercises executable at regular intervals
  if slot_type == "emom":
    return exercise.effort in ("medium", "high")

  # Skill practice slots
  if slot_type == "skill_practice":
    return exercise.modality in ("movement_skill",) or "skill" in exercise.category

  # Static hold
  if slot_type == "static_hold":
    return exercise.movement_patterns includes "isometric"

  return True  # default: no type restriction
```

---

## Phase 3: Load Calculation Per Slot

After exercise selection, calculate the specific load target for this week.

```
CALCULATE_SLOT_LOAD(slot, exercise, progression_model, current_week,
                    current_phase, training_level, athlete_history):
  # Retrieve the athlete's last recorded weight/reps for this exercise
  last = get_last_session(athlete_history, exercise.id)

  if last is None:
    # First time — use starting point estimates by training_level
    return starting_load(exercise, training_level)

  # Delegate to the appropriate progression model
  return progression_model.calculate_next(
    last_session=last,
    current_week=current_week,
    current_phase=current_phase,
    exercise=exercise,
    slot=slot
  )
```

---

## Complete Selector Flow

```
POPULATE_SCHEDULE(weekly_schedule, constraints, goal_profile,
                  current_phase, current_week, athlete_context):
  # Build DAG once
  all_exercises = load_all_exercises()
  dag = BUILD_PREREQUISITE_DAG(all_exercises)
  unlocked = GET_UNLOCKED_EXERCISES(
    athlete_context.history or SEED_HISTORY_FROM_LEVEL(constraints.training_level),
    dag
  )

  populated = {}

  for day, sessions in weekly_schedule:
    populated[day] = []
    for session in sessions:
      modality = session.modality
      is_deload = session.get("is_deload", False)

      # 1. Pick archetype
      archetype = SELECT_ARCHETYPE(
        modality, constraints, current_phase, is_deload,
        goal_profile, athlete_context.recent_sessions
      )
      if archetype is FAIL: log and skip session

      # 2. Pick exercises for each slot
      exercise_assignments = []
      for slot in archetype.slots:
        exercise = SELECT_EXERCISE(
          slot, constraints, unlocked, dag,
          athlete_context.recent_exercises, current_phase
        )
        if exercise is FAIL: log and use_placeholder(slot)

        # 3. Calculate load
        load = CALCULATE_SLOT_LOAD(
          slot, exercise,
          load_progression_model(modality),
          current_week, current_phase,
          constraints.training_level,
          athlete_context.history
        )

        exercise_assignments.append({
          slot_index: slot.index,
          exercise: exercise,
          load: load
        })

      populated[day].append({
        modality: modality,
        archetype: archetype,
        exercises: exercise_assignments,
        is_deload: is_deload
      })

  return populated
```

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No archetype available for modality + constraints | Log error; drop session; add to constraint feasibility report |
| No exercise available for slot (injury + equipment) | Try substitutions from injury_flags; if none, use placeholder ("rest slot") |
| Athlete history empty | Seed from training_level using SEED_HISTORY_FROM_LEVEL |
| All candidates recently used | Reduce recency penalty, allow repeats — log "variety exhausted for {modality}" |
| Slot requires barbell but athlete has kettlebell only | Apply equipment_limited scaling on archetype; remap slot exercises to KB equivalents |
| Exercise requires a prerequisite not in history | Do not select — DAG enforcement is strict, not advisory |
| deload is_deload=True | Use archetype.scaling.deload if defined; otherwise reduce sets/reps by 30% in load calculation |
