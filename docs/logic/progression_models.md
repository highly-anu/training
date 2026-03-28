# Progression Model Rules

Decision rules for all 9 progression models. Each section defines inputs, the advance condition, stall detection, deload protocol, and reset-after-break logic. These rules are the direct input to `progression.py` in Phase 4.

---

## Common Concepts

**Session result** — after each session the system records:
- `success`: bool — athlete completed the prescribed work at the prescribed load/pace
- `rpe_actual`: int 1–10 — actual perceived effort
- `rpe_target`: int 1–10 — intended effort

**Stall** — failure to advance for a defined number of consecutive sessions at the same target.

**Deload week** — a scheduled reduction in volume (not intensity) every 4th week. All models follow this regardless of stall state unless otherwise noted.

**Break reset** — athlete has missed ≥7 days. Each model specifies how far to roll back.

---

## 1. Linear Load (`linear_load`)

**Used by:** `max_strength`, `relative_strength` modalities; novice and intermediate athletes.

**Governing data:**
```
modality:        max_strength
progression_model: linear_load
framework:       linear_progression
```

### Inputs
| Field | Type | Description |
|-------|------|-------------|
| `current_weight_kg` | float | Weight used last session |
| `increment_kg` | float | Per-movement increment (see table below) |
| `consecutive_failures` | int | Sessions failed at current weight |
| `weeks_since_stall` | int | Weeks since last stall event |
| `sessions_since_break` | int | Sessions since returning from a break |

### Increments by movement
| Movement pattern | Increment |
|-----------------|-----------|
| squat, deadlift | 2.5–5 kg / session |
| bench, press | 1.25–2.5 kg / session |
| power_clean | 2.5 kg / session |
| kettlebell (load) | 4 kg / 2–3 sessions |

### Rules
```
ADVANCE:
  if last_session.success:
    next_weight = current_weight + increment

STALL DETECTION:
  if consecutive_failures >= 3:
    stall_event = True

ON STALL:
  deload_weight = current_weight * 0.90
  reset consecutive_failures = 0
  note: retry from 90% and advance normally; may hit same weight sooner

GRADUATION (switch framework):
  if stall_events_in_last_8_weeks >= 3:
    recommend_framework_switch(to: "hlm" or "block_periodization")
    log: "linear progression exhausted — intermediate programming required"

SCHEDULED DELOAD (week 4 of every mesocycle):
  session_weight = normal_weight * 0.85
  sets = normal_sets
  reps = normal_reps - 1 (e.g. 3x4 instead of 3x5)

BREAK RESET:
  weeks_missed = days_missed / 7
  reduction_pct = min(weeks_missed * 0.10, 0.50)  # max 50% reduction
  return_weight = current_weight * (1 - reduction_pct)
  # Round down to nearest increment
```

---

## 2. Density (`density`)

**Used by:** `mixed_modal_conditioning`, `strength_endurance` modalities; circuits, AMRAPs, EMOM formats.

**Governing data:**
```
modality:        mixed_modal_conditioning, strength_endurance
progression_model: density
archetype slot_types: amrap, emom, for_time
```

### Inputs
| Field | Type | Description |
|-------|------|-------------|
| `prescribed_rounds` | int | Target rounds in time window |
| `actual_rounds` | float | Completed rounds (partial allowed) |
| `time_window_minutes` | int | Fixed time domain |
| `consecutive_completions` | int | Times target rounds hit in a row |
| `consecutive_failures` | int | Times below target in a row |

### Rules
```
ADVANCE (add density):
  if actual_rounds >= prescribed_rounds for 2 consecutive sessions:
    # Option A — add a round
    prescribed_rounds += 1
    # Option B — shorten time domain by 1 minute (same work, faster)
    # Use Option A during base/build; Option B during peak

STALL:
  if actual_rounds < prescribed_rounds - 1 for 2 consecutive sessions:
    stall_event = True

ON STALL:
  # Reduce total work, not time domain
  prescribed_rounds = max(prescribed_rounds - 1, 1)
  reset consecutive_failures = 0

SCHEDULED DELOAD (week 4):
  time_window_minutes = normal_time * 0.75
  prescribed_rounds = round(normal_rounds * 0.70)

BREAK RESET:
  # Density resets further than load-based models
  weeks_missed = days_missed / 7
  reduction_pct = min(weeks_missed * 0.15, 0.40)
  prescribed_rounds = round(current_rounds * (1 - reduction_pct))
```

---

## 3. Volume Block (`volume_block`)

**Used by:** `strength_endurance`, `max_strength` during block periodization phases; intermediate/advanced athletes.

**Governing data:**
```
modality:        max_strength, strength_endurance
progression_model: volume_block
framework:       block_periodization
```

### Block structure
Each mesocycle = 4 weeks:

| Week | Label | Sets | Reps | Intensity |
|------|-------|------|------|-----------|
| 1 | Accumulation A | 4 | 6–8 | 70–75% 1RM |
| 2 | Accumulation B | 5 | 6–8 | 72–77% 1RM |
| 3 | Intensification | 4 | 3–5 | 82–88% 1RM |
| 4 | Deload / Test | 3 | 3 | 85–90% 1RM (or test) |

### Rules
```
ADVANCE (within block):
  Follow the block schedule exactly — do not self-adjust within a block
  Week N always follows Week N-1 regardless of session feel

BLOCK-TO-BLOCK ADVANCE:
  if week_4_test_session.success:
    next_block_1RM_estimate += 2.5 to 5 kg
    recalculate all block percentages from new 1RM

STALL (block failure):
  if athlete cannot complete week_3 prescribed work:
    repeat current block with 5% intensity reduction
    flag: "block did not progress — reassess training_level or recovery"

SCHEDULED DELOAD:
  Week 4 of each block is the built-in deload — no additional deload needed
  unless fatigue_state == "overreached"

BREAK RESET:
  weeks_missed >= 1 and <= 2: restart from week 1 of current block at -5% intensity
  weeks_missed > 2:           restart from block 1 at -10% intensity
  weeks_missed > 4:           full reset — treat as novice entering linear_load
```

---

## 4. Complexity (`complexity`)

**Used by:** `movement_skill` modality; skill-based progressions (locomotion, handstand, floreio).

**Governing data:**
```
modality:        movement_skill
progression_model: complexity
archetype slot_types: skill_practice
exercise fields: requires, unlocks
```

### Inputs
| Field | Type | Description |
|-------|------|-------------|
| `current_skill_tier` | int 1–5 | Athlete's demonstrated level for this skill |
| `competency_sessions` | int | Consecutive sessions demonstrating competency |
| `quality_rating` | enum | clean / adequate / struggling |
| `unlocked_exercises` | list | Exercise IDs prerequisite graph has cleared |

### Rules
```
ADVANCE:
  if quality_rating == "clean" for 3 consecutive sessions:
    if next_tier_exercise.requires ⊆ unlocked_exercises:
      advance to next_tier
      add new exercises from exercise.unlocks to unlocked_exercises

HOLD:
  if quality_rating == "adequate":
    continue at current tier
    add 5-10% more practice volume (longer skill blocks)

REGRESS:
  if quality_rating == "struggling" for 2 consecutive sessions:
    return to previous tier exercises
    identify and isolate failing prerequisite

SCHEDULED DELOAD (week 4):
  reduce skill session to movement quality only — no new challenges
  review and reinforce current tier competencies

BREAK RESET:
  # Complexity regresses faster than load
  days_missed 7–14:  hold current tier, require 2 quality sessions before advancing
  days_missed 15–30: drop one tier
  days_missed > 30:  drop to entry-level, rebuild from requires graph

DAG ENFORCEMENT:
  # At all times, athlete can only access exercises where:
  for exercise in candidate_exercises:
    assert all(req in unlocked_exercises for req in exercise.requires)
```

---

## 5. Time to Task (`time_to_task`)

**Used by:** `aerobic_base` modality; long slow distance formats (Zone 1–2).

**Governing data:**
```
modality:        aerobic_base
progression_model: time_to_task
archetype:       long_zone_2
```

### Inputs
| Field | Type | Description |
|-------|------|-------------|
| `current_session_minutes` | int | Duration of last session |
| `target_session_minutes` | int | Goal duration (from framework) |
| `pace_or_hr` | float | Average pace (min/km) or heart rate |
| `hr_zone_compliance` | float | % of session in Zone 1–2 |

### Rules
```
ADVANCE:
  if hr_zone_compliance >= 0.90 and session completed without distress:
    next_session_minutes = current_session_minutes * 1.10  # 10% rule
    cap: next_session_minutes <= target_session_minutes

TARGET REACHED:
  if current_session_minutes >= target_session_minutes:
    hold duration, progress by:
    - increasing terrain difficulty (vertical gain, pack weight)
    - or reduce pace slightly and target next aerobic threshold marker

STALL (pace degradation):
  if average_hr increases >5% at same pace over 3 sessions:
    flag: "aerobic fitness declining — check recovery, sleep, nutrition"
    reduce session_minutes by 20%, hold duration for 2 sessions

SCHEDULED DELOAD (every 4th week — the "Down Week"):
  session_minutes = current_session_minutes * 0.60
  maintain Zone 1–2 compliance — no intensity increase

BREAK RESET:
  days_missed 7–14:    reduce by 20%, require 2 full sessions before advancing
  days_missed 15–30:   reduce by 35%
  days_missed > 30:    reduce by 50%, rebuild at 10% increments
```

---

## 6. Intensity Split Shift (`intensity_split_shift`)

**Used by:** `aerobic_base` modality in polarized 80/20 programming.

**Governing data:**
```
modality:        aerobic_base, anaerobic_intervals
progression_model: intensity_split_shift
framework:       polarized_80_20
framework fields: zone1_2_pct, zone3_pct, zone4_5_pct
```

### Baseline splits by phase
| Phase | Zone 1–2 | Zone 3 | Zone 4–5 |
|-------|----------|--------|----------|
| base | 85% | 10% | 5% |
| build | 80% | 12% | 8% |
| peak | 75% | 10% | 15% |
| taper | 90% | 7% | 3% |

### Rules
```
ADVANCE (phase-driven, not performance-driven):
  # Intensity distribution is set by phase, not individual session results
  on PHASE_TRANSITION(new_phase):
    update zone_distribution = baseline_splits[new_phase]

WITHIN-PHASE FINE-TUNING:
  # Weekly adjustment only — if athlete is unable to maintain Zone 1–2 compliance:
  if hr_zone_compliance < 0.75 for Zone 1–2 in last 2 sessions:
    shift 5% from Zone 4–5 back to Zone 1–2
    log: "athlete not aerobically ready for current split — holding polarization"

FATIGUE OVERRIDE:
  if fatigue_state in ("accumulated", "overreached"):
    force_split = base_phase split
    log: "fatigue override — intensity distribution reset to base"

SCHEDULED DELOAD:
  deload_split = base_phase split + 5% to Zone 1–2
  (most permissive split, all hard efforts removed)
```

---

## 7. RPE Autoregulation (`rpe_autoregulation`)

**Used by:** Intermediate and advanced strength athletes; concurrent training framework.

**Governing data:**
```
modality:        max_strength, strength_endurance
progression_model: rpe_autoregulation
framework:       concurrent_training, rpe_autoregulation
```

### RPE Scale Reference
| RPE | Meaning | Reps in reserve |
|-----|---------|-----------------|
| 6 | Light effort | 4+ RIR |
| 7 | Moderate | 3 RIR |
| 8 | Heavy but controlled | 2 RIR |
| 9 | Very hard | 1 RIR |
| 10 | Maximal | 0 RIR |

### Inputs
| Field | Type | Description |
|-------|------|-------------|
| `target_rpe` | int 1–10 | Prescribed effort level for the set |
| `actual_rpe` | int 1–10 | Athlete's reported effort |
| `readiness_score` | int 1–5 | Pre-session self-report (1=poor, 5=excellent) |
| `current_load` | float | Weight used this session |

### Rules
```
LOAD ADJUSTMENT (between sessions):
  if actual_rpe < target_rpe - 1 for 2 consecutive sessions:
    increase load by 2.5–5%
    log: "athlete performing under target RPE — load increase warranted"

  if actual_rpe > target_rpe + 1:
    decrease load by 5%
    log: "athlete above target RPE — load reduction applied"

INTRA-SESSION ADJUSTMENT (real-time, use during implementation):
  if readiness_score <= 2:
    reduce prescribed weight by 10%
    reduce sets by 1
  if readiness_score >= 4:
    may add 1 back-off set at RPE 7

STALL:
  # No stall concept — load is self-regulating
  # Stagnation flag: no load increase in 4 consecutive weeks
  if weeks_no_progress >= 4:
    log: "RPE stagnation — review sleep, nutrition, total training volume"
    recommend: reduce concurrent conditioning volume by 20%

SCHEDULED DELOAD:
  target_rpe = 6 for all sets
  volume = normal_sets × 0.60
  note: athlete should feel under-stimulated — this is correct

BREAK RESET:
  days_missed 7–14:   target_rpe = 7 for first week back, normal from week 2
  days_missed > 14:   target_rpe = 6–7 for 2 weeks, reassess 1RM estimate
```

---

## 8. Pentathlon RPM (`pentathlon_rpm`)

**Used by:** `kb_pentathlon_training` archetype; kettlebell sport athletes.

**Governing data:**
```
modality:        strength_endurance, relative_strength
progression_model: pentathlon_rpm
archetype:       kb_pentathlon_training
```

### Inputs
| Field | Type | Description |
|-------|------|-------------|
| `current_rpm` | int | Repetitions per minute in current set |
| `target_rpm` | int | Competition-target RPM |
| `set_duration_minutes` | int | Working set length (typically 6 or 10 min) |
| `set_quality` | enum | clean / technique_breaks / stopped |

### Rules
```
ADVANCE:
  if set_quality == "clean" (no technique breaks, no stops):
    next_session_rpm = current_rpm + 2
    cap at target_rpm

HOLD:
  if set_quality == "technique_breaks" but set completed:
    hold current_rpm
    focus: technique refinement at current RPM

REGRESS:
  if set_quality == "stopped" (set not completed):
    next_session_rpm = current_rpm - 2
    minimum floor = target_rpm * 0.70

BELL WEIGHT PROGRESSION:
  if athlete completing full set at target_rpm cleanly for 3 sessions:
    increase bell weight by 4 kg (next standard kettlebell size)
    reset rpm to target_rpm * 0.80 with new bell

SCHEDULED DELOAD:
  set_duration_minutes = 4 (down from 6 or 10)
  rpm = current_rpm - 4
  focus: technique, not output

BREAK RESET:
  days_missed >= 7:  reduce rpm by 4, reduce set_duration by 2 min
  days_missed >= 14: reduce rpm by 6, reduce set_duration to 4 min
  rebuild at 2 min/session increments back to full set
```

---

## 9. Range Progression (`range_progression`)

**Used by:** `mobility`, `rehab` modalities; passive and active flexibility work.

**Governing data:**
```
modality:        mobility, rehab
progression_model: range_progression
archetype:       joint_prep_circuit, tgu_practice
```

### Inputs
| Field | Type | Description |
|-------|------|-------------|
| `current_range_tier` | int 1–5 | Demonstrated range at this joint/position |
| `pain_free` | bool | No pain at current range |
| `sessions_at_tier` | int | Sessions completed at current tier |
| `active_vs_passive` | enum | active / passive / loaded |

### Tier definitions (per joint family)
| Tier | Description |
|------|-------------|
| 1 | Entry range — anatomical baseline, no resistance |
| 2 | Functional range — usable in compound movements |
| 3 | Training range — can express force through range |
| 4 | Advanced range — end-range load tolerance |
| 5 | Elite range — loaded, controlled end-range |

### Rules
```
ADVANCE:
  if pain_free for 3 consecutive sessions at current_range_tier:
    if active_vs_passive != "loaded":
      advance active control before adding load
      next: demonstrate tier at active (unloaded) before loaded version
    else:
      advance current_range_tier += 1

HOLD:
  if pain_free but sessions_at_tier < 3:
    hold — do not advance by feel alone

REGRESS:
  if not pain_free:
    immediate regress: drop one tier
    reduce loading (passive only, no active resistance)
    flag: "consult clinician if pain persists > 2 sessions"

SEQUENCE RULE:
  passive → active → loaded
  must pass each stage before advancing to next at same tier

SCHEDULED DELOAD:
  reduce to passive-only work at current tier - 1
  add heat/tissue prep time, reduce mobility session duration by 30%

BREAK RESET:
  days_missed 7–14:   hold current tier, require 2 pain-free sessions before advancing
  days_missed > 14:   drop one tier, rebuild
  days_missed > 30:   return to tier 2 (functional range), rebuild from there
```

---

## Multi-Model Coordination

When a concurrent program runs two models simultaneously (e.g., `linear_load` for strength + `time_to_task` for aerobic base):

```
COORDINATION RULES:

1. Independence by default
   Each model advances and stalls independently.
   A stall in linear_load does NOT affect time_to_task advancement.

2. Fatigue override takes precedence
   If fatigue_state == "overreached":
     all models hold for the current week
     all scheduled deloads are executed together

3. Scheduled deloads align
   Align all models to the same week-4 deload.
   Do not run a linear_load deload in week 3 while density is in week 4 —
   consolidate to a single full deload week.

4. Framework graduation cascade
   If linear_load triggers a framework_switch recommendation:
     only the modality under that model changes framework
     concurrent models are unaffected unless the new framework is
     explicitly incompatible (check framework.incompatible_with)
```
