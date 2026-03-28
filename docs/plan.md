# Training System Design

A programmable training system that algorithmically generates programs from a set of methodologies, goals, and constraints.

Hierarchy:

```
Philosophy → Methodology → Modalities → Archetypes → Exercises → Progression → Constraints → Goal → Program
```

---

## 1. Training Philosophies

Non-negotiable principles per source. These govern what the system will and won't do when drawing from a given methodology.

### Starting Strength / Mark Rippetoe
- Linear progression is the fastest path for a novice
- Barbell compound lifts are the most efficient stress stimulus
- Stress → Recovery → Adaptation is the fundamental cycle
- Squatting is a proxy for overall development

```json
{
  "name": "Starting Strength",
  "core_principles": ["linear_progression", "compound_lifts", "SRA_cycle"],
  "required_equipment": ["barbell", "rack", "plates"],
  "bias": ["max_strength"],
  "avoid_with": ["high_frequency_conditioning", "concurrent_fatigue"]
}
```

### Uphill Athlete (Steve House, Scott Johnston)
- Aerobic base is the foundation of all mountain performance
- Zone 2 polarization: 80% easy / 20% hard
- Strength is supplementary, not dominant
- Sport-specific load (vertical gain, pack weight) matters more than gym PRs
- Periodization orients toward a specific objective date

### CrossFit / CrossFit Endurance
- Intensity > volume
- Broad GPP is protective and transferable
- Mixed modal conditioning reveals weaknesses
- Constant variation prevents accommodation
- CrossFit Endurance: apply CFE principles to monostructural domains (run, row, bike)

### Gym Jones (Mark Twight)
- The mind is the primary limiter
- Discomfort is the training stimulus
- Operator fitness = relative strength + aerobic capacity + mental durability
- Block periodization with hard periodization phases
- General fitness before sport-specific

### Mark Wildman / RKC Kettlebell
- Ballistic patterning (swing, clean, snatch) builds power and conditioning simultaneously
- Breathing mechanics govern intensity and technique ceiling
- Progression: single swing → clean & jerk → TGU → squat → snatch → double KB
- KB pentathlon as benchmark and competition format

### Ido Portal
- Movement quality precedes loading
- Complexity and novelty are forms of progression
- Joint preparation is non-negotiable before loading
- Skill acquisition: isolation → integration → spontaneous expression
- Daily practice habits (time-based) matter more than session intensity

### Horsemen GPP / SOF-style
- Durability over peak performance
- Simple equipment (sandbag, bodyweight, ruck)
- Repeatable output under fatigue
- No single-quality specialization

### ATG / Knees Over Toes Guy (Ben Patrick)
- Posterior chain health is the foundation of durability
- Reverse movements (backward sled, Nordic curl, reverse treadmill) accelerate recovery
- Progressive range of motion is as important as progressive load
- Knee health is achievable; full range terminal extension work is the key

### Marcus Filly / Functional Bodybuilding
- RPE-based autoregulation prevents overtraining
- Aesthetics and function are compatible
- Shoulder and joint health require dedicated maintenance work
- Controlled eccentrics and isometrics build tissue resilience
- Sustainable training over max intensity

### Kelly Starrett / Supple Leopard
- Movement quality is testable and correctable
- Tissue prep before training reduces injury risk
- Global and local joint mobility have distinct maintenance protocols
- Breathing and bracing are mechanical skills, not assumptions

### BJJ (combat sport as modality and constraint)
- Mat time is non-transferable; sparring has no substitute
- Conditioning for BJJ: isometric endurance, hip explosiveness, grip endurance
- Rolling is both training stimulus and test
- Joint health (shoulders, knees, neck) must be actively maintained

---

## 2. Methodological Frameworks

Structured approaches to organizing training. This is the level where programming decisions happen.

| Framework | Goals Served | Weekly Structure | Progression Mechanism |
|-----------|-------------|------------------|-----------------------|
| Linear Progression | Max strength (novice) | 3×/week full body | Add weight each session |
| Block Periodization | Strength, peaking | 4-6 week blocks | Volume → Intensity → Peaking |
| Polarized 80/20 | Aerobic base + top-end | 80% Z1/Z2, 20% Z3-Z5 | Increasing base volume |
| Concurrent Training | GPP, balanced fitness | Alternate S/C days | Fatigue management, goal priority |
| EMOM / AMRAP | Conditioning, work capacity | Session-based | Density or rounds |
| High-Frequency Skill | Movement quality | Daily short sessions | Complexity progression |
| GPP Circuits | Work capacity, durability | 2-4×/week | Time, reps, load |
| RPE Autoregulation | Sustainable training | Flexible intensity | Feel-based load management |
| KB Pentathlon | KB conditioning + strength | 1-2 dedicated sessions | RPM targets per bell weight |

---

## 3. Training Modalities / Domains

Categories of physical quality. A goal profile weights these; the system selects matching archetypes and exercises.

- **Max Strength** — 1-5RM, barbell or KB. Sources: SS, Horsemen, Gym Jones
- **Strength Endurance** — higher reps under significant load. Sources: CF, KB, circuits
- **Relative Strength** — strength-to-bodyweight. Sources: gymnastics, rings, bodyweight
- **Aerobic Base** — Zone 1-2, long duration. Sources: Uphill Athlete, CFE
- **Anaerobic Intervals** — short, high-intensity. Sources: CF, Tabata, sprint work
- **Mixed Modal Conditioning** — movement types combined under time pressure. Sources: CF, Gym Jones
- **Power / Explosiveness** — fast force production. Sources: KB ballistics, plyometrics, Olympic lifts
- **Mobility / Tissue Prep** — joint health, range of motion. Sources: Supple Leopard, Ido Portal, ATG
- **Movement / Skill** — locomotion, coordination, pattern acquisition. Sources: Ido Portal
- **Durability / Work Capacity** — loaded carries, rucking, sandbag. Sources: Horsemen, SOF
- **Combat Sport** — BJJ drilling, positional sparring, grip/isometric conditioning
- **Rehab** — injury-specific loading, isometrics, progressive loading under clinical constraints

---

## 4. Workout Archetypes

Reusable shapes. Each archetype maps to modalities and gets populated with exercises.

### Strength
| Archetype | Sets×Reps | Intensity | Notes |
|-----------|-----------|-----------|-------|
| 5×5 | 5×5 | ~85% | Classic strength volume |
| 3×5 Linear | 3×5 | Progressing | Add weight each session |
| Heavy/Light/Medium | Varies | H=90%+, L=80%, M=85% | Rippetoe HLM |
| EMOM Strength Wave | 10×1 | 85-95% | Accumulate singles |
| Wave Loading | 3-2-1, 3-2-1 | Escalating | PAP potentiation |

### Conditioning
| Archetype | Format | Duration | Notes |
|-----------|--------|----------|-------|
| Long Zone 2 | Steady state | 60-180 min | HR <135 or AeT |
| Threshold Intervals | 3-5 × 8min | Zone 4 | ~LT2 |
| Mixed Modal AMRAP | AMRAP 20min | High | CF-style |
| Tabata | 8×20s/10s | Max | Anaerobic |
| Pyramid Intervals | 1-2-3-4-3-2-1 min | Zone 3-4 | CFE format |

### Movement / Skill
| Archetype | Format | Notes |
|-----------|--------|-------|
| Skill Ladder | 10-15min blocks | One movement, increasing complexity |
| Movement Flow | 20-30min | Continuous locomotion sequence |
| Joint Prep Circuit | 10-15min | Before session, mobility-focused |
| Density Practice | Fixed time window | Low intensity, movement quality focus |

### GPP / Durability
| Archetype | Format | Notes |
|-----------|--------|-------|
| Sandbag Complex | 5-8 movements, 3-5 rounds | Horsemen-style |
| Ruck | Distance × Load | Fan Dance: 22km, +1000m, 30kg, 4h |
| Loaded Carry Circuit | Farmer, rack, overhead | Distance or time |
| Bodyweight Circuit | Time domain | Push/pull/hinge/squat |

### Kettlebell
| Archetype | Format | Notes |
|-----------|--------|-------|
| Ballistic Session | Swings, cleans, snatches | Power-conditioning |
| Pentathlon Training | 6min/exercise × 5 | Competition prep |
| KB Flow | Continuous movement | Troy van Spanje style |
| TGU Practice | 5-10 per side | Skill and durability |

---

## 5. Exercises

Atomic elements. Each carries metadata that enables filtering, prerequisite checking, and progression chaining.

```json
{
  "exercise": "Kettlebell Swing",
  "modality": "power",
  "category": "ballistic",
  "equipment": ["kettlebell"],
  "prerequisites": ["hip_hinge_pattern", "bracing_mechanics"],
  "progressions": ["two_hand_swing → single_arm_swing → clean → snatch"],
  "scaling_down": ["deadlift", "Romanian_deadlift"],
  "sources": ["Wildman", "Pavel", "CFE"]
}
```

```json
{
  "exercise": "Ruck",
  "modality": "durability",
  "category": "loaded_carry",
  "equipment": ["pack", "weight"],
  "progressions": ["distance → load → speed"],
  "benchmarks": {
    "entry": "2km in 10min with pack",
    "intermediate": "10km in 48min unloaded",
    "advanced": "20km in 2h20 with pack",
    "elite": "22km +1000m 30kg in 4h (Fan Dance standard)"
  },
  "sources": ["Horsemen", "SOF"]
}
```

Exercise categories to build out:
- Barbell lifts (squat, deadlift, press, bench, power clean, front squat)
- Kettlebell patterns (swing, clean, snatch, press, TGU, squat, jerk)
- Bodyweight / gymnastics (push-up, pull-up, dip, handstand, ring work)
- Aerobic modalities (run, row, ski erg, ruck, bike, swim)
- Loaded carries (farmer, rack, overhead, sandbag shoulder)
- Sandbag (deadlift, clean & press, front squat, bent row, carry, lunges, swings)
- Mobility (joint circles, loaded stretches, tissue prep)
- Skill / movement (locomotion, tumbling, floreio, balance)
- Rehab (quad sets, SLR, band pull-aparts, terminal knee extension, face pull)

---

## 6. Progression Models

How training advances over time. Each source has an implicit or explicit model.

| Model | Mechanism | Source | Application |
|-------|-----------|--------|-------------|
| Linear Load | +weight each session | SS | Novice barbell, KB progression |
| Density | Same work in less time | CF | Metcon improvement |
| Volume Block | More sets/reps per phase | Block periodization | Intermediate strength |
| Complexity | Harder movement patterns | Ido Portal | Movement skill acquisition |
| Time-to-Task | Faster completion of fixed task | UA | Mountain prep, rucking standards |
| Intensity Split Shift | 80/20 → 70/30 | UA | Aerobic base → build phase transition |
| RPE Autoregulation | Load by feel vs. % 1RM | Filly | Fatigue management in concurrent training |
| Pentathlon RPM | Reps per minute targets | Wildman | KB competition prep |
| Range Progression | Increasing ROM under load | ATG | Posterior chain, knee health |

---

## 7. Constraint Layer

Filters which building blocks are valid for a given context.

```json
{
  "constraints": {
    "equipment": ["barbell", "kettlebell", "ruck", "pull_up_bar"],
    "days_per_week": 5,
    "session_time_minutes": 75,
    "injury_flags": ["right_knee_meniscus_post_op"],
    "training_phase": "base",
    "periodization_week": 4,
    "avoid_movements": ["bilateral_squat", "running_impact", "jumping"]
  }
}
```

Injury flags modify exercise availability:
- `right_knee_meniscus_post_op` → disable: bilateral squats, running, jumping / enable: quad sets, SLR, bike, swimming, upper body
- `shoulder_impingement` → disable: overhead pressing, kipping / enable: isometrics, face pulls, landmine press, eccentric push-ups
- `active` (no flags) → full exercise library available

---

## 8. Goal Profiles

Goals are weighted priority vectors across modalities. The system uses these to select methodologies and allocate session slots.

```json
{
  "goal": "Alpine Climbing Performance",
  "event_date": "2026-07-01",
  "priorities": {
    "aerobic_base": 0.50,
    "max_strength": 0.15,
    "durability": 0.20,
    "mobility": 0.10,
    "power": 0.05
  },
  "primary_sources": ["Uphill Athlete", "Horsemen"],
  "periodization": "base → build → peak → taper"
}
```

Goal profiles to define:
1. **Alpine climbing performance** — aerobic base dominant, durability, light strength
2. **SOF operator / Horsemen standard** — durability, work capacity, strength endurance
3. **BJJ competitor** — combat conditioning, strength endurance, mobility, grip endurance
4. **General GPP** — broad physical preparedness, no single weakness
5. **Ultra / expedition endurance** — aerobic base, fat adaptation, time-on-feet
6. **Max strength focus** — barbell strength, minimal conditioning interference
7. **Injury rehab → return to sport** — tissue loading, joint prep, progressive return

---

## 9. Performance Benchmarks / Standards

Reference points for assessing fitness level relative to goal profiles.

### The Cell Standards (Levels I–V)
Multi-dimensional tiered standards across strength, conditioning, power, mobility, and work capacity. Source: `data/the cell fitness standards.pdf`. Full Level I-V benchmarks to be extracted and mapped into this schema.

### Personal Benchmarks
| Domain | Entry | Intermediate | Advanced / Elite |
|--------|-------|--------------|------------------|
| Rucking | 2km in 10min with pack | 10km in 48min unloaded | 20km in 2h20 with pack |
| Fan Dance standard | — | — | 22km, +1000m, 30kg, 4h |
| KB Pentathlon | 8kg = 1pt | 16kg = 2pt | 24kg = 3pt (per rep) |

### KB Pentathlon Scoring
6 minutes per exercise, 5 min rest between. Exercises: cleans (120 reps / 20 RPM), long cycle press (60 reps / 10 RPM), jerks (120 reps), half snatch (108 reps), push press (120 reps). Points scale with bell weight (8kg=1pt, 12kg=1.5pt, 16kg=2pt, 20kg=2.5pt, 24kg=3pt, 28kg=3.5pt...).

### Strength Benchmarks
- SS novice completion: squat 1.5× BW, deadlift 2× BW, press 0.75× BW
- Relative strength: strict pull-ups 10+, dips 15+, HSPU, front lever hold

---

## 10. Injury / Rehab as Training Phase

Injury is not an interruption — it's a phase with its own programming constraints. First-class concept in the system.

### Phase Types
- `active` — full training, performance optimization
- `base` — building aerobic / strength foundation
- `build` — increasing volume and load
- `peak` — intensity focus, volume drops
- `taper` — pre-event reduction (1-2 weeks)
- `deload` — planned recovery week (every 4th week typical)
- `maintenance` — hold fitness, reduce volume
- `rehab` — injury-specific loading, clinical constraints apply
- `post_op` — weeks 0-8 post-surgery, very restricted

### Rehab Protocol: Knee (meniscus post-op)
Sources: clinical protocols, Marcus Filly principles

**Early phase:**
- Quad sets, straight leg raises, heel slides, ankle pumps, hamstring sets

**Mid phase:**
- Single-leg press (light, progressing), Bulgarian split squats, step-ups, SL deadlifts

**Late phase:**
- Barbell squat (partial range, cleared by doctor), plyometrics, sport-specific drills
- Stationary bike intervals, swimming, elliptical, anti-gravity treadmill

### Rehab Protocol: Shoulder (impingement / instability)
Source: Marcus Filly

**Isometrics:** dip support holds, side plank with lat activation

**Pushing:** landmine press, eccentric push-up (parallettes, slow negative)

**Pulling:** face pull (thumbs-up grip, elbows high, full ROM), elbow-out row

**Rotator cuff:** DB external rotation (elbow on knee), band pull-apart (horizontal, overhead, waist)

**Progressive carries:** TGU, KB rack hold walk

---

## 11. Periodization

Macro > Meso > Microcycle.

### Macro (12-24 weeks): base → build → peak → taper
### Meso (4-6 weeks): defines phase type and volume/intensity ratio
### Micro (1 week): actual session layout

### Weekly Template Examples

**3-day strength (SS):**
```
Mon: Squat / Press / Deadlift
Wed: Squat / Bench / Power Clean
Fri: Squat / Press / Deadlift (heavier)
```

**5-day concurrent (Alpine prep, base phase):**
```
Mon: Zone 2 (75min)
Tue: Strength (3×5 squat, press, deadlift)
Wed: Zone 2 (75min) + mobility (30min)
Thu: Threshold intervals
Fri: Strength + KB conditioning
Sat: Long Zone 2 (2-3h) or ruck
Sun: Rest / joint prep
```

**4-day GPP (Horsemen-style):**
```
Mon: Strength complex (sandbag or barbell)
Tue: Conditioning (AMRAP / circuit)
Thu: Loaded carries + bodyweight
Sat: Long ruck or GPP circuit
```

---

## 12. System Architecture (Program Generation)

### Input
- Goal profile (weighted modality priorities + event date)
- Constraints (equipment, time, days/week, injury flags, current phase)
- Training history (current level, recent load, accumulated fatigue)

### Process
1. Match goal priorities to methodology frameworks
2. Filter available archetypes by constraints and injury flags
3. Assign archetypes to weekly session slots weighted by priority
4. Populate archetypes with exercises (filter by equipment, prerequisites met, injury flags)
5. Apply progression model rules to determine load/volume
6. Output weekly plan as structured data

### Output (example skeleton)
```json
{
  "week": 4,
  "phase": "base",
  "sessions": [
    {
      "day": "Monday",
      "modality": "aerobic_base",
      "archetype": "long_zone_2",
      "duration_min": 75,
      "exercises": [{"movement": "run", "intensity": "Z2", "minutes": 75}]
    },
    {
      "day": "Tuesday",
      "modality": "max_strength",
      "archetype": "3x5_linear",
      "exercises": [
        {"exercise": "squat", "sets": 3, "reps": 5, "load": "progressing"},
        {"exercise": "press", "sets": 3, "reps": 5, "load": "progressing"},
        {"exercise": "deadlift", "sets": 1, "reps": 5, "load": "progressing"}
      ]
    }
  ]
}
```

---

## Open Questions / Missing

**Sources not yet mapped into schema (need PDF extraction):**
- Gym Jones — full methodology from `data/gym jones/` PDFs
- The Cell Standards — full Level I-V benchmarks from `data/the cell fitness standards.pdf`
- Horsemen — full program from `data/horsemen/`
- CrossFit Journal articles — programming philosophy from `data/crossfit/crossfit journal/`
- Nutrition (Zone Diet) — recovery/performance layer (out of scope for now)

**Design decisions still open:**
- How does the system handle conflicting philosophies in the same week (e.g., SS linear + CFE intervals)?
- What is the interference management model for concurrent training?
- How are prerequisites enforced algorithmically? (can't program snatch before swing is clean)
- Should nutrition be a constraint modifier? (caloric deficit → reduce intensity, avoid high-volume strength)
- How does the system handle athlete-reported fatigue or HRV data?
