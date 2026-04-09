# Training System — Ontology Author Guide

**Audience:** AI agents or humans adding new training content (philosophies, frameworks, goals, archetypes, exercises) to the system. This document is designed to be self-contained — you should be able to produce correct YAML files with only this guide and your research notes.

**Validation:** After writing YAML files, run:
```
python tools/validate_entities.py path/to/your/file.yaml
python tools/validate_entities.py --all    # validate everything
```

---

## 1. The Ontology — What Each Entity Is

This system has 8 layers. Each layer depends on the ones below it. When adding a new methodology, you typically add from the bottom up.

```
Philosophy
    └─ Framework          (how to structure a week of training)
         └─ Modality      (what physical quality is being trained)
              └─ Archetype (what a single session looks like)
                   └─ Exercise (individual movements)
                        └─ Progression (how load/complexity increases)
                             └─ Constraints (athlete-specific limits)
                                  └─ Goal Profile (the athlete's objective)
```

### What each entity means in plain English

**Philosophy** — A named training source or methodology. Examples: Starting Strength, CrossFit, Kelly Starrett's mobility system. A philosophy describes beliefs about training: what matters, what to avoid, how to measure progress. It doesn't describe what to do week-by-week — that's the framework.

**Framework** — A weekly session structure. It answers: "Given this methodology, how many times per week do we train each quality, and how hard?" A framework maps modalities to session counts and distributes intensity across zones. Examples: linear progression (3×/week barbell), polarized 80/20 (mostly easy aerobic + one hard interval session), concurrent training (mix of strength + conditioning).

**Modality** — A physical quality domain. The 12 modalities are fixed: `max_strength`, `aerobic_base`, `strength_endurance`, `power`, `mobility`, `durability`, `rehab`, `movement_skill`, `mixed_modal_conditioning`, `anaerobic_intervals`, `relative_strength`, `combat_sport`. You almost never add a new modality — instead, map new methodology to existing ones.

**Archetype** — A reusable workout template. An archetype belongs to one modality and defines the structure of a session (slots, sets/reps/duration, intensity, movement pattern filters). Examples: 5×5 strength session, 20-min AMRAP conditioning, joint prep circuit.

**Exercise** — A single movement (e.g. back squat, hip circle, reverse sled drag). Exercises have categories, equipment requirements, movement patterns, prerequisites, and contraindications.

**Goal Profile** — What the athlete is training toward. A goal profile has priority weights across modalities (e.g. 60% aerobic base, 20% mobility, 20% strength) and a phase sequence (base → build → peak → taper). The goal is what drives program generation.

---

## 2. Authoring Workflow

When adding a new methodology (e.g. Theragun recovery, triathlon prep, mountaineering):

1. **Identify what's needed** — does the methodology introduce a new philosophy? A new framework? New archetypes/exercises? Or just a new goal profile that uses existing entities?
2. **Create files bottom-up** — philosophy first, then framework, then archetypes + exercises, then goal profile last.
3. **Use existing modalities** — never add a new modality unless the methodology targets something genuinely absent from the 12 existing ones.
4. **Cross-reference accurately** — every framework references a philosophy by ID; every archetype references a modality by ID.
5. **Validate** — run `python tools/validate_entities.py` on each file before finalizing.

### Minimal addition for a new methodology

| New methodology type | Files needed |
|---|---|
| Recovery/prehab tool (e.g. Theragun) | 1 philosophy + 1 framework + 2–3 archetypes + N exercises |
| New sport goal (e.g. triathlon) | 1 philosophy + 1 framework + N archetypes + 1 goal profile |
| Extension of existing methodology | Just archetypes and/or exercises — reference existing philosophy/framework |

---

## 3. File Placement

Each training methodology lives in its own **self-contained package** under `data/packages/`:

```
data/
  packages/
    {your_package_name}/         ← one directory per methodology
      philosophy.yaml            ← the package's philosophy (exactly one)
      frameworks/
        {id}.yaml                ← one file per framework (usually one)
      archetypes/
        strength/                ← barbell/free weight strength sessions
        conditioning/            ← aerobic, intervals, AMRAPs, circuits
        kettlebell/              ← KB-specific sessions
        gpp_durability/          ← carries, sandbag, rucking
        movement_skill/          ← mobility, joint prep, skill practice, recovery tools
      exercises.yaml             ← all exercises for this package (top-level list: exercises: [...])
  modalities/                    ← shared, rarely edited — do not add new ones
  goals/                         ← one file per goal:  {id}.yaml
  goals/custom/                  ← user-created goals (same format, auto-discovered)
```

**Archetypes are package-scoped.** A "Long Zone 2 Run" in the Uphill Athlete package and a "Long Zone 2 Run" in the CrossFit Endurance package are separate files with separate IDs. Do not share archetypes across packages — each package defines the protocols that belong to its methodology.

**Which archetype category subdirectory?**
- Recovery tools, foam rolling, soft tissue → `movement_skill/`
- Mobility circuits, joint prep → `movement_skill/`
- Skill drills, deliberate practice → `movement_skill/`
- Barbell strength → `strength/`
- Aerobic, intervals, AMRAPs, circuits → `conditioning/`
- Carries, rucking, sandbag → `gpp_durability/`
- Kettlebell-primary sessions → `kettlebell/`

---

## 4. Enum Reference Tables

These are the only valid values for each field type. Use exactly as written (lowercase, underscores).

### Modality IDs (12 total — do not add new ones)
```
max_strength          aerobic_base          strength_endurance
power                 mobility              durability
rehab                 movement_skill        mixed_modal_conditioning
anaerobic_intervals   relative_strength     combat_sport
```

### Framework IDs (current — your new framework will extend this list)
```
linear_progression    concurrent_training   rpe_autoregulation
block_periodization   emom_amrap            gpp_circuits
high_frequency_skill  kb_pentathlon         kelly_starrett_mobility
polarized_80_20       atg_joint_health      bjj_performance
```

### Philosophy IDs (current — your new philosophy will extend this list)
```
horsemen_gpp          starting_strength     crossfit
kelly_starrett        marcus_filly          ido_portal
uphill_athlete        wildman_kettlebell    atg
gym_jones             bjj
```

### Training Levels
```
novice    intermediate    advanced    elite
```

### Training Phases
```
base    build    peak    taper    deload    maintenance    rehab    post_op
```

### Progression Models
```
linear_load           rpe_autoregulation    block_periodization
wave_loading          volume_block          intensity_split_shift
density               time_to_task          range_progression
complexity            pentathlon_rpm
```

### Slot Types (for archetype slots)
```
sets_reps        emom             amrap
amrap_movement   for_time         distance
time_domain      skill_practice   static_hold
rounds_for_time
```

### Intensity Values (for archetype slot `intensity` field)
```
low      light    moderate    medium    heavy    submaximal    high
max      max_effort           bodyweight
zone1    zone2    zone3       zone4     zone4_5  zone5
progressing
```

### Recovery Cost
```
low    medium    high
```

### Session Position (for modality — where in a session day this modality should appear)
```
first        ← must be the first activity (e.g. max strength, power)
standalone   ← should not be combined with other high-demand work
any          ← flexible (e.g. mobility, rehab, movement skill)
```

### Equipment IDs
```
barbell        rack           plates         kettlebell      dumbbell
pull_up_bar    rings          parallettes    rower           bike
ski_erg        ruck_pack      sandbag        sled            tire
medicine_ball  resistance_band rope          box             ghd
jump_rope      open_space     none
```

### Exercise Categories
```
barbell    kettlebell    bodyweight    aerobic    carries
sandbag    mobility      skill         rehab      gym_jones
```

### Movement Pattern Aliases (for archetype `exercise_filter.movement_pattern`)
```
squat          hinge / hip_hinge    carry / loaded_carry    rotation
locomotion     ballistic            olympic / olympic_lift   isometric
horizontal_push   vertical_push     horizontal_pull          vertical_pull
press / push      pull              aerobic                  swing
clean             jerk              snatch                   tgu
skill             farmer_carry      rack_carry               step_up
ruck
```

### Interference Levels (for framework `incompatible_with`)
```
manageable    high
```

### Deload Intensity Change Values
```
maintain    reduce_slightly    reduce
```

---

## 5. Schema: Philosophy

**File:** `data/philosophies/{id}.yaml`

A philosophy describes a training source's beliefs and scope. It doesn't describe workouts — just principles and orientation.

```yaml
id: your_philosophy_id              # required — unique, snake_case
name: "Display Name"                # required — human-readable

core_principles:                    # required — list of belief statements
  - principle_one                   # snake_case belief tags, not sentences
  - principle_two                   # (e.g. tissue_prep_before_loading_reduces_injury)

scope:                              # required — which modalities this philosophy addresses
  - mobility                        # use valid modality IDs
  - rehab

bias:                               # optional — which modalities are emphasized
  - mobility

avoid_with:                         # optional — modality IDs that conflict with this methodology
  - max_strength                    # use modality IDs, NOT philosophy names
  - mixed_modal_conditioning        # (e.g. aerobic_base, max_strength, mixed_modal_conditioning)

required_equipment:                 # optional — equipment required for this philosophy
  - resistance_band

intensity_model: skill_based        # required — one of:
                                    #   linear_progression, polarized_80_20,
                                    #   block_periodization, autoregulation_rpe,
                                    #   constant_variation, skill_based,
                                    #   hard_easy_alternation, operator_readiness

progression_philosophy: range_based # required — one of:
                                    #   load_based, volume_based, complexity_based,
                                    #   time_based, density_based, feel_based,
                                    #   rpm_based, range_based

sources:                            # required — citations
  - "Book title (Author, Year)"

notes: >                            # optional but recommended
  Narrative description of the methodology. What makes it distinctive.
  What tools it uses. How it integrates with other work.
```

**Decision guide for `intensity_model`:**
- `linear_progression` — load increases session-by-session on a fixed schedule (e.g. Starting Strength)
- `polarized_80_20` — 80% easy / 20% hard, strict zone discipline (e.g. Uphill Athlete)
- `block_periodization` — training organized into distinct phases with different focuses (strength block → conditioning block)
- `autoregulation_rpe` — intensity set session-to-session based on readiness (RPE-driven)
- `constant_variation` — no fixed structure; varied stimuli across sessions (e.g. CrossFit)
- `skill_based` — intensity increases as skill complexity increases (not external load)
- `hard_easy_alternation` — high-intensity sessions followed by deliberate easy days
- `operator_readiness` — intensity based on readiness state / daily condition assessment

---

## 6. Schema: Framework

**File:** `data/packages/{name}/frameworks/{id}.yaml`

A framework is a weekly training structure. It answers: "Given this methodology's priorities, how do I allocate sessions across a week and manage intensity?"

```yaml
id: your_framework_id               # required — unique, snake_case
name: "Display Name"                # required — human-readable
source_philosophy: philosophy_id    # required — must be a valid philosophy ID

goals_served:                       # required — modality IDs this framework serves
  - mobility
  - rehab

sessions_per_week:                  # required — sessions/week per modality
  mobility: 5                       # keys must match goals_served exactly
  rehab: 2                          # integer values

intensity_distribution:             # required — must sum to exactly 1.0
  zone1_2_pct: 0.80                 # Zone 1–2 aerobic (easy, conversational)
  zone3_pct: 0.10                   # Zone 3 tempo / threshold
  zone4_5_pct: 0.05                 # Zone 4–5 VO2max / anaerobic
  max_effort_pct: 0.05              # Maximal / near-max strength efforts

progression_model: complexity       # required — see progression model enum

applicable_when:                    # required — when this framework is appropriate
  training_level:
    - novice
    - intermediate
    - advanced
    - elite
  days_per_week_min: 3              # minimum days/week the athlete trains
  days_per_week_max: 7              # maximum days/week
  goal_priority_min:                # minimum priority for a goal to trigger this framework
    mobility: 0.3

deload_protocol:                    # required
  frequency_weeks: 8                # deload every N weeks
  volume_reduction_pct: 0.30        # e.g. 0.30 = reduce volume by 30%
  intensity_change: maintain        # maintain / reduce_slightly / reduce

incompatible_with: []               # optional — list of conflicting framework objects
# Example incompatibility entry:
# - framework_id: linear_progression
#   reason: >
#     Why these two frameworks conflict when run together.
#   interference_level: high        # manageable or high
#   mitigation: >
#     What to do if an athlete insists on combining them.

cadence_options:                    # optional — day-of-week patterns per training frequency
  3: [[1, 3, 5], [2, 4, 7]]        # lists of day numbers (1=Mon, 7=Sun)
  4: [[1, 3, 5, 7]]                 # rotate week-to-week if multiple options
  5: [[1, 2, 4, 6, 7]]

sources:                            # required
  - "Citation"

notes: >                            # recommended
  How this framework operates in practice. What makes it distinctive.
  How sessions are sequenced. What recovery structure it assumes.
```

**Decision guide for `intensity_distribution`:**
- Recovery/mobility framework: mostly zone1_2 (0.70–0.90), minimal max effort
- Strength framework: high max_effort (0.40–0.60), low zone1_2
- Concurrent/GPP: balanced distribution
- Polarized endurance: high zone1_2 (0.80), moderate zone4_5 (0.15–0.20)

**Decision guide for `deload_protocol.frequency_weeks`:**
- High-stress frameworks (max strength, high-intensity conditioning): every 4 weeks
- Moderate-stress (concurrent, GPP): every 4–6 weeks
- Low-stress (mobility, rehab): every 6–8 weeks

---

## 7. Schema: Archetype

**File:** `data/packages/{name}/archetypes/{category}/{id}.yaml`

An archetype is a reusable workout template. It defines what a session looks like: sections (slots), duration, equipment, and which movement patterns to draw exercises from.

```yaml
id: your_archetype_id               # required — unique, snake_case
name: "Display Name"                # required
modality: mobility                  # required — ONE valid modality ID
category: movement_skill            # required — archetype directory name
duration_estimate_minutes: 15       # required — approximate session length

required_equipment:                 # required
  - open_space                      # use valid equipment IDs

applicable_phases:                  # required — list of valid phase names
  - base
  - build
  - peak
  - taper
  - deload
  - maintenance
  - rehab
  - post_op

sources:                            # required
  - "Citation"

notes: >                            # recommended
  What this session is for. When to use it. How it fits into a larger program.

slots:                              # required — ordered list of session sections
  - role: section_name              # required — descriptive label for this slot
    slot_type: skill_practice       # required — see slot type enum
    sets: 1                         # optional (for sets_reps, emom)
    reps: 10                        # optional (for sets_reps)
    duration_sec: 300               # optional (use either duration_sec OR duration_minutes)
    duration_minutes: 5             # optional
    intensity: light                # required — see intensity enum
    rest_sec: 30                    # optional
    exercise_filter:                # optional — how to select exercises for this slot
      category: mobility            # filter by exercise category
      movement_pattern: hip_hinge   # filter by movement pattern alias
      bilateral: true               # only bilateral exercises
    notes: >                        # optional — what specifically happens in this slot
      Describe the specific exercises or movements if they are fixed,
      or describe the selection principle if dynamic.

scaling:                            # optional — how to adapt the session
  deload:
    volume_multiplier: 0.6          # multiply all volumes by this
    intensity_pct: 0.9              # scale intensity by this
    drop_slots:                     # remove these slot roles in deload
      - accessory_slot
    notes: "What to do on deload."
  time_limited:
    drop_slots:
      - lower_priority_slot
    notes: "What to drop when time is tight."
  equipment_limited:
    substitutions:
      - missing_equipment: barbell
        substitute_approach: "Use kettlebell or bodyweight variant."
```

**Key decisions for slot design:**
- `skill_practice` — timed, quality-focused, no counting reps (e.g. mobility flows, percussive therapy, deliberate practice)
- `sets_reps` — traditional strength work (3×5, 5×5, etc.)
- `time_domain` — steady-state work for a fixed duration (e.g. 20-min Zone 2 run)
- `amrap` / `for_time` — conditioning formats (as many rounds as possible, race the clock)
- `static_hold` — isometric holds (planks, wall sits, dead hangs)

**For recovery/soft-tissue archetypes:** use `slot_type: skill_practice` with `exercise_filter: {category: rehab}` or `{category: mobility}`. No sets/reps needed — use `duration_sec` or `duration_minutes`.

---

## 8. Schema: Exercise

**File:** `data/packages/{name}/exercises.yaml`

All exercises for a package live in a single file. The file contains a top-level `exercises:` key with a list. Exercises from all packages are merged into a global pool at load time — IDs must be unique across all packages.

```yaml
exercises:

  - id: your_exercise_id            # required — unique across ALL exercise files
    name: "Display Name"            # required
    category: mobility              # required — see exercise category enum
    modality: [mobility]            # required — list of modality IDs
    equipment: [none]               # required — list of equipment IDs
    effort: low                     # required — low / moderate / high
    bilateral: true                 # required — true or false
    movement_patterns:              # required — list of pattern names
      - hip_flexion
    requires: []                    # optional — exercise IDs that should be mastered first
    unlocks: []                     # optional — exercise IDs this progression enables
    contraindicated_with: []        # required (can be empty) — injury flag IDs
    progressions:                   # optional
      volume: increase_duration     # how volume increases
      intensity: add_load           # how intensity increases
      complexity: harder_variant    # next exercise in progression
    scaling_down: []                # optional — easier exercise IDs
    typical_volume:                 # required — standard volume prescription
      sets: 2
      duration_sec: 60              # use duration_sec OR reps, not both
    sources: [Source Name]          # required
    notes: >                        # optional
      Execution cues, context, when to use.
```

**For new exercises:** add them to your package's `exercises.yaml`. All exercises across packages are merged into a global pool at load time, so IDs must be unique across all packages.

**Contraindicated injury flags** (use these IDs in `contraindicated_with`):
```
knee_acl_acute          knee_meniscus_acute     knee_meniscus_post_op
shoulder_impingement    shoulder_post_op        low_back_acute
low_back_chronic        hip_labrum              ankle_sprain_acute
wrist_acute             cervical_spine          general_fatigue_overreach
```

---

## 9. Schema: Goal Profile

**File:** `data/goals/{id}.yaml` or `data/goals/custom/{id}.yaml`

A goal profile is the athlete's objective. It drives program generation by setting priority weights across modalities and defining a phase sequence.

```yaml
id: your_goal_id                    # required — unique, snake_case
name: "Display Name"                # required
description: >                      # required
  What this goal is for. Who it's designed for. What the outcome looks like.

event_date: null                    # optional — ISO date (e.g. 2026-08-15) or null

priorities:                         # required — modality IDs → weights (should sum to ~1.0)
  mobility: 0.50
  rehab: 0.30
  aerobic_base: 0.20

primary_sources:                    # required — philosophy IDs
  - kelly_starrett
  - marcus_filly

phase_sequence:                     # required — ordered list of training phases
  - phase: base                     # valid phase name
    weeks: 8                        # duration
    focus: >                        # what this phase emphasizes
      Descriptive narrative of what happens in this phase.
    priority_override:              # optional — temporarily shift priorities during this phase
      mobility: 0.60
      rehab: 0.20
      aerobic_base: 0.20

minimum_prerequisites: {}           # required (can be empty)
incompatible_with: []               # required (can be empty)

framework_selection:                # required
  default_framework: framework_id   # must be a valid framework ID
  alternatives:                     # optional
    - framework_id: other_framework
      condition: days_per_week <= 3  # free-text condition string

notes: >                            # optional but recommended
  Context, philosophy behind this goal, how to use it.

expectations:                       # required
  min_weeks: 12
  ideal_weeks: 16
  min_days_per_week: 3
  ideal_days_per_week: 5
  min_session_minutes: 20
  ideal_session_minutes: 45
  supports_split_days: true
  notes: >
    Any notes about session structure expectations.
```

---

## 10. Cross-Reference Rules

These constraints must hold. The validator checks types and enums; you must verify IDs manually.

| Entity | Field | Must reference |
|---|---|---|
| Framework | `source_philosophy` | `id` of a philosophy in any `data/packages/*/philosophy.yaml` |
| Framework | `goals_served` items | valid modality IDs |
| Framework | `sessions_per_week` keys | same IDs as `goals_served` |
| Framework | `incompatible_with[].framework_id` | `id` of any framework in `data/packages/*/frameworks/*.yaml` |
| Framework | `applicable_when.goal_priority_min` keys | valid modality IDs |
| Archetype | `modality` | valid modality ID |
| Archetype | `category` | valid archetype category subdirectory name |
| Philosophy | `avoid_with` items | valid modality IDs (not philosophy names) |
| Exercise | `modality` items | valid modality IDs |
| Exercise | `requires` / `unlocks` | existing exercise IDs (anywhere across all packages) |
| Exercise | `contraindicated_with` | valid injury flag IDs |
| Goal | `primary_sources` items | `id` of a philosophy in any `data/packages/*/philosophy.yaml` |
| Goal | `framework_selection.default_framework` | `id` of any framework in `data/packages/*/frameworks/*.yaml` |
| Goal | `priorities` keys | valid modality IDs |

---

## 11. Common Mistakes

**Priorities don't sum to 1.0** — The validator checks this. Adjust weights until they sum to 0.95–1.05.

**intensity_distribution doesn't sum to 1.0** — Same check. All four zone fields must add up to exactly 1.0.

**Wrong slot_type for recovery work** — Recovery/percussive therapy slots should use `skill_practice`, not `sets_reps`. Use `duration_sec` or `duration_minutes`, not `reps`.

**Modality ID not in the valid list** — The 12 modality IDs are fixed. If a new methodology's quality seems absent, map it to the closest existing one. Percussive therapy → `mobility` or `rehab`. Zone 2 cycling → `aerobic_base`. Plyometrics → `power`.

**sessions_per_week keys don't match goals_served** — These must be identical lists.

**Adding exercises to the wrong package** — Exercises belong in the package they were developed for. A Theragun exercise belongs in `data/packages/theragun_recovery/exercises.yaml`, not in another package's file. Exercise IDs must be globally unique across all packages.

**Archetype in the wrong category directory** — Recovery and soft-tissue archetypes go in `movement_skill/`. Don't put them in `conditioning/`.

**`avoid_with` using philosophy names** — `avoid_with` must contain modality IDs (e.g. `max_strength`, `aerobic_base`), not philosophy names (e.g. `starting_strength`, `crossfit`). Philosophies don't reference each other — they express incompatibility through the modalities they conflict with.

---

## 12. Worked Example — Adding a Recovery Methodology

This shows the minimal file set for adding a soft-tissue/recovery methodology like Theragun.

### Step 1: Philosophy file
`data/packages/theragun_recovery/philosophy.yaml`
```yaml
id: theragun_recovery
name: "Hyperice / Theragun Percussive Therapy"
core_principles:
  - tissue_priming_before_load_improves_range_of_motion
  - percussive_stimulus_accelerates_recovery_between_sessions
  - targeted_application_reduces_soreness_and_stiffness
scope:
  - mobility
  - rehab
bias:
  - mobility
avoid_with: []
required_equipment: []           # Theragun device is not in equipment_ids — note in notes
intensity_model: skill_based
progression_philosophy: range_based
sources:
  - "Hyperice — Official Theragun Protocol Guides"
notes: >
  Percussive therapy methodology from Hyperice (Theragun). Requires a percussive
  massage device (not modeled in the equipment system — assumed present when this
  philosophy is selected). Three protocol types: pre-workout activation (short
  duration, higher frequency), post-workout recovery (longer, focused), and
  dedicated recovery day (full-body, lower frequency). Not a standalone training
  philosophy — functions as a tissue quality layer complementary to any other
  methodology.
```

### Step 2: Framework file
`data/packages/theragun_recovery/frameworks/theragun_recovery.yaml`
```yaml
id: theragun_recovery
name: "Theragun Percussive Therapy Integration"
source_philosophy: theragun_recovery
goals_served:
  - mobility
  - rehab
sessions_per_week:
  mobility: 5                    # pre/post-workout daily sessions
  rehab: 2                       # dedicated recovery days
intensity_distribution:
  zone1_2_pct: 0.90
  zone3_pct: 0.05
  zone4_5_pct: 0.02
  max_effort_pct: 0.03
progression_model: range_progression
applicable_when:
  training_level: [novice, intermediate, advanced, elite]
  days_per_week_min: 3
  days_per_week_max: 7
  goal_priority_min:
    mobility: 0.2
deload_protocol:
  frequency_weeks: 8
  volume_reduction_pct: 0.30
  intensity_change: maintain
sources:
  - "Hyperice — Official Theragun Protocol Guides"
notes: >
  Governs how percussive therapy sessions are scheduled alongside other training.
  Pre-workout: 5-min targeted activation before main session. Post-workout: 10–15 min
  recovery after main session. Recovery day: 20–30 min full-body protocol on rest days.
```

### Step 3: Archetypes (one per protocol type)
Three files in `data/packages/theragun_recovery/archetypes/movement_skill/`:
- `theragun_preactivation.yaml` — 5 min pre-workout
- `theragun_post_session.yaml` — 10–15 min post-workout
- `theragun_recovery_day.yaml` — 20–30 min full recovery day

Each uses `modality: mobility`, `category: movement_skill`, `slot_type: skill_practice`.

### Step 4: Exercises
`data/packages/theragun_recovery/exercises.yaml` — one exercise per major muscle group / body region under the top-level `exercises:` key:
- `theragun_quads` — quadriceps, 30–60 sec
- `theragun_hamstrings` — hamstrings + glutes
- `theragun_upper_back` — traps + thoracic spine
- etc.

### Step 5: (optional) Goal Profile
Only needed if you want a standalone "recovery focus" goal in the program builder. Otherwise, the theragun archetypes are available to any goal through normal archetype selection.

---

## 13. Adding to Future Methodologies

This same process applies to every future addition:

| Methodology | Primary new entity | Maps to existing modalities |
|---|---|---|
| Triathlon prep | framework + goal | aerobic_base (0.50+), strength_endurance, durability |
| Mountaineering | framework + goal | aerobic_base, durability, max_strength, mobility |
| Gravel bike race prep | framework + goal | aerobic_base (polarized), anaerobic_intervals, strength_endurance |
| Foam rolling / mobility tools | philosophy + archetypes | mobility, rehab |
| Yoga / flexibility focus | philosophy + framework + archetypes | mobility, movement_skill |

For endurance-dominant goals (triathlon, mountaineering): use `polarized_80_20` or `concurrent_training` as the default framework reference, or create a new framework with high `zone1_2_pct`.

For peaking toward an event: set `event_date` in the goal profile and include a `taper` phase at the end of `phase_sequence`.
