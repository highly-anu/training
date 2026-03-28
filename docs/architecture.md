# System Architecture

> **Status:** Phases 0–2 complete (data). Phase 3 (logic design) and Phase 4 (implementation) pending.

This document describes what has been built, how the layers relate, and how the system is intended to work. It is the single reference for understanding the project as it stands.

---

## What this system does

Takes a **goal** and a set of **constraints** as input and generates a structured **training program** as output.

```
Input:  goal profile (e.g. "Alpine Climbing") + constraints (equipment, days/week, injuries)
Output: N-week program with weekly sessions, archetypes, exercises, and loads
```

The program is not hardcoded — it is assembled from a library of structured data according to rules about scheduling, compatibility, and progression. Changing the goal or constraints produces a different program from the same data.

---

## Current state

| Phase | Scope | Status |
|-------|-------|--------|
| 0 — Data extraction | Source PDFs/files → structured notes | ✅ Complete |
| 1 — Schema design | JSON Schema for all 8 data layers | ✅ Complete |
| 2 — Data population | 73 YAML files, 191 exercises | ✅ Complete |
| 3 — Logic design | Pseudocode for scheduler, selector, validator | ✅ Complete |
| 4 — Implementation | Python generator producing a real program | ✅ Complete |

---

## Directory structure

```
training/
│
├── README.md                        ← project summary
│
├── docs/
│   ├── architecture.md              ← this file
│   ├── plan.md                      ← original design document (ontology reference)
│   ├── roadmap.md                   ← phase completion tracker
│   ├── extraction-guide.md          ← how to add new training sources
│   ├── extracted/                   ← structured notes from source material
│   │   ├── gym-jones.md
│   │   ├── horsemen.md
│   │   ├── ido-portal.md
│   │   ├── crossfit-journal.md
│   │   └── kettlebell.md
│   └── schemas/                     ← JSON Schema definitions (Phase 1)
│       ├── README.md                ← schema reference + shared enums
│       ├── philosophy.schema.json
│       ├── framework.schema.json
│       ├── modality.schema.json
│       ├── archetype.schema.json
│       ├── exercise.schema.json
│       ├── goal_profile.schema.json
│       ├── constraints.schema.json
│       └── benchmark.schema.json
│
└── data/
    ├── philosophies/                ← 11 YAML files, one per source
    ├── frameworks/                  ← 9 YAML files, one per methodology
    ├── modalities/                  ← 12 YAML files, one per training domain
    ├── archetypes/                  ← 20 YAML files in 5 subdirectories
    │   ├── strength/                    (3x5_linear, 5x5, hlm, emom_strength)
    │   ├── conditioning/                (long_zone_2, threshold_intervals, mixed_modal_amrap, tabata, gym_jones_circuit)
    │   ├── movement_skill/              (skill_ladder, movement_flow, joint_prep_circuit)
    │   ├── gpp_durability/              (sandbag_complex, ruck_session, loaded_carry_circuit, bodyweight_circuit, horsemen_power_endurance)
    │   └── kettlebell/                  (kb_ballistic_session, kb_pentathlon_training, tgu_practice)
    ├── exercises/                   ← 191 exercises across 9 category files
    │   ├── barbell.yaml             (27 exercises)
    │   ├── kettlebell.yaml          (24 exercises)
    │   ├── bodyweight.yaml          (31 exercises)
    │   ├── aerobic.yaml             (16 exercises)
    │   ├── carries.yaml             (16 exercises)
    │   ├── sandbag.yaml             (15 exercises)
    │   ├── mobility.yaml            (22 exercises)
    │   ├── skill.yaml               (16 exercises)
    │   └── rehab.yaml               (24 exercises)
    ├── goals/                       ← 7 YAML files, one per goal profile
    ├── constraints/
    │   ├── injury_flags.yaml        ← 12 injury flags with exclusion rules
    │   └── equipment_profiles.yaml  ← 5 preset equipment setups
    └── benchmarks/
        ├── cell_standards.yaml      ← Level I–V Cell Fitness standards
        ├── strength_standards.yaml  ← BW ratio standards for barbell lifts
        └── conditioning_standards.yaml ← SSST, run times, row times
```

---

## The 8-layer ontology

The system is built as a hierarchy of composable layers. Each layer depends on the one below it.

```
Philosophy → Framework → Modality → Archetype → Exercise → Progression → Constraints → Goal → Program
```

### Layer 1: Philosophy (`data/philosophies/`)

The non-negotiable beliefs of each source. Governs what the system will and won't do when drawing from that methodology.

**Key fields:** `scope` (which modalities this source governs), `bias` (what it emphasizes), `avoid_with` (conflicts with other philosophies), `intensity_model`, `progression_philosophy`

**11 sources:** Starting Strength, Uphill Athlete, CrossFit, Gym Jones, Wildman/RKC, Ido Portal, Horsemen GPP, ATG, Marcus Filly, Kelly Starrett, BJJ

**How it's used:** When a goal profile references `primary_sources: [uphill_athlete, horsemen_gpp]`, the system applies each philosophy's rules only within its declared `scope`. SS rules govern strength sessions; UA rules govern aerobic sessions. Conflicts are resolved by source order.

---

### Layer 2: Framework (`data/frameworks/`)

Structured approaches that define how sessions are allocated across the week. This is where programming decisions happen — how many sessions of each type, in what intensity split, with what progression mechanism.

**Key fields:** `sessions_per_week` (map of modality → count), `intensity_distribution` (zone fractions summing to 1.0), `progression_model`, `applicable_when` (training level, days available), `incompatible_with` (interference rules with other frameworks)

**9 frameworks:** Linear Progression, Block Periodization, Polarized 80/20, Concurrent Training, EMOM/AMRAP, High-Frequency Skill, GPP Circuits, RPE Autoregulation, KB Pentathlon

**How it's used:** The generator selects a framework based on the goal profile's `framework_selection` field and the athlete's `training_level`. The framework's `sessions_per_week` object tells the scheduler how many slots of each modality to fill per week.

---

### Layer 3: Modality (`data/modalities/`)

Categories of physical quality. Goal profiles weight these; the scheduler uses recovery costs and compatibility rules to place sessions on specific days.

**Key fields:** `recovery_cost` (low/medium/high), `recovery_hours_min` (minimum rest before repeating), `compatible_in_session_with` / `incompatible_in_session_with`, `session_position` (where in a session this goes), `min_weekly_minutes` / `max_weekly_minutes`

**12 modalities:** Max Strength, Strength Endurance, Relative Strength, Aerobic Base, Anaerobic Intervals, Mixed Modal Conditioning, Power, Mobility, Movement Skill, Durability, Combat Sport, Rehab

**How it's used:** When scheduling, the system checks recovery costs before placing two high-cost modalities on adjacent days. Session pairing logic (`compatible_in_session_with`) determines whether two modalities can share a session and in what order.

---

### Layer 4: Archetype (`data/archetypes/`)

Reusable workout shapes. Each archetype defines the structure of a session — how many exercise slots, of what type, in what format — without specifying which exercises fill them. Exercises are assigned at generation time by the selector.

**Key fields:** `slots` (ordered list of exercise roles with volume params and `slot_type`), `scaling` (deload, time-limited, equipment-limited variants), `duration_estimate_minutes`, `applicable_phases`, `required_equipment`

**Slot types:** `sets_reps`, `time_domain`, `distance`, `amrap`, `emom`, `for_time`, `skill_practice`, `static_hold`

**20 archetypes** across 5 categories (see directory structure above)

**How it's used:** The scheduler assigns archetypes to session slots based on modality match and constraint filtering. The 3×5 Linear archetype gets assigned to a max_strength slot; Long Zone 2 to an aerobic_base slot.

---

### Layer 5: Exercise (`data/exercises/`)

Atomic training elements. Each exercise carries all metadata needed for filtering, prerequisite checking, and progression chaining.

**Key fields:** `movement_patterns` (for injury exclusion matching), `equipment` (for constraint filtering), `requires` / `unlocks` (prerequisite graph edges), `contraindicated_with` (injury flag IDs), `effort` (low/medium/high/max), `progressions` (load/volume/complexity axes)

**191 exercises** across 9 category files

**How it's used:** The selector populates archetype slots with exercises. For each slot, it filters the exercise library by: modality match, equipment availability, no active contraindications, prerequisites met. The `requires`/`unlocks` fields across all exercises form a directed acyclic graph (DAG) — the generator builds this at runtime to enforce prerequisite checks.

---

### Layer 6: Progression (embedded in frameworks and exercises)

Rules for how training advances over time. Not a separate data layer — progression logic lives in:
- `frameworks/*.yaml` → `progression_model` field (which model governs this framework)
- `exercises/*.yaml` → `progressions` object (load/volume/complexity axes per exercise)
- Phase 3 will formalize the algorithmic rules for each of the 9 progression models

**9 progression models:** Linear Load, Density, Volume Block, Complexity, Time-to-Task, Intensity Split Shift, RPE Autoregulation, Pentathlon RPM, Range Progression

---

### Layer 7: Constraints (`data/constraints/`)

Runtime filters provided by the athlete. The constraint layer is the only layer that is not a library — it is input, not data.

**Two library files support constraint resolution:**
- `injury_flags.yaml` — 12 injury flags, each with excluded movement patterns, excluded exercises, and substitution pairs
- `equipment_profiles.yaml` — 5 preset equipment setups for fast constraint entry

**Constraint fields:** `equipment`, `days_per_week`, `session_time_minutes`, `training_level`, `injury_flags`, `avoid_movements`, `training_phase`, `fatigue_state`

**Hard vs. soft:** `constraint_priority` marks constraints as hard (cannot be violated) or soft (prefer to respect). Equipment and injury flags default to hard; time limits default to soft.

---

### Layer 8: Goal Profile (`data/goals/`)

Weighted priority vectors that tell the system what to optimize for. The goal profile is the primary input that drives framework selection, session allocation, and phase sequencing.

**Key fields:** `priorities` (modality weights summing to 1.0), `phase_sequence` (ordered meso phases), `primary_sources` (philosophy IDs), `minimum_prerequisites` (entry benchmarks), `incompatible_with` (goals that cannot run concurrently), `framework_selection`

**7 goal profiles:** Alpine Climbing, SOF Operator, BJJ Competitor, General GPP, Ultra Endurance, Max Strength Focus, Injury Rehab

**How it's used:** The generator reads `priorities` to decide how many sessions of each modality to schedule per week (e.g. aerobic_base: 0.50 → roughly half of all sessions are aerobic). It reads `phase_sequence` to determine the current phase and adjust priorities with any `priority_override` defined for that phase.

---

## How the layers connect: program generation flow

This is the intended flow for Phase 4. The data to support every step exists; the code does not yet.

```
1. LOAD          Read goal profile + athlete constraints
                 ↓
2. VALIDATE      Check minimum_prerequisites against benchmark data
                 Check constraints are not self-contradictory
                 Warn if goal is incompatible with another active goal
                 ↓
3. SELECT        Choose framework from goal.framework_selection
                 (filtered by training_level, days_per_week)
                 ↓
4. ALLOCATE      Convert priority vector → session counts per modality per week
                 (e.g. aerobic_base: 0.5 × 5 days = 2.5 → 3 aerobic sessions)
                 ↓
5. SCHEDULE      Assign modalities to specific days
                 Respect recovery_hours_min between high-cost modalities
                 Respect session compatibility rules (can X and Y share a day?)
                 ↓
6. ASSIGN        For each session slot: pick archetype matching the modality
                 Filter by: required_equipment ⊆ athlete_equipment
                             duration_estimate ≤ session_time_minutes
                             applicable_phases includes current phase
                 ↓
7. POPULATE      For each archetype slot: select exercise
                 Filter by: modality match, equipment match,
                             no active contraindications,
                             prerequisites met (check DAG)
                 ↓
8. LOAD CALC     Apply progression model to determine sets/reps/load
                 (current week, phase, training_level → specific targets)
                 ↓
9. OUTPUT        Render as structured JSON + human-readable weekly plan
```

---

## Key design decisions

**Prerequisite graph is embedded in exercises, not a separate file.**
Each exercise has `requires` and `unlocks` arrays. The generator builds the DAG at runtime by scanning all exercises. A separate graph file would go stale every time an exercise was added or renamed.

**Philosophy conflict resolution uses source ordering, not a matrix.**
When two philosophies conflict on the same domain, the goal profile's `primary_sources` list determines priority — first listed wins. A full conflict matrix would require O(n²) entries and become unmaintainable. Source ordering is simpler and matches how real coaches actually think ("I'm primarily running UA, using SS for the strength days").

**Phase-level priority overrides live on goal profiles, not frameworks.**
The same framework (e.g. concurrent training) can be used by both Alpine Climbing and SOF Operator, but each has a different phase structure and different emphasis shifts within phases. Putting `priority_override` on `phase_sequence` entries keeps the framework reusable and the goal-specific logic centralized.

**Constraint priority (hard/soft) is explicit.**
Injury flags and equipment are hard by default; session time is soft. This lets the validator give different responses: "cannot generate program — no barbell available for this archetype" vs. "session exceeds time budget — dropped finisher slot".

**Modality weekly volume bounds (`min_weekly_minutes`, `max_weekly_minutes`) live on modalities, not frameworks.**
These are physiological constraints, not programming preferences. They apply regardless of which framework is active.

---

## Phase 3 logic documents

Five documents in `docs/logic/` define the complete algorithmic rules:

| File | Covers |
|------|--------|
| `progression_models.md` | All 9 progression models — advance, stall, deload, reset rules |
| `scheduler.md` | Priority → session count allocation; recovery-aware day assignment; intra-session ordering |
| `selector.md` | Archetype selection; exercise selection; prerequisite DAG traversal; load calculation |
| `validator.md` | Pre-generation feasibility check; post-schedule conflict audit; error code reference |
| `phase_transitions.md` | Time-based and performance-based transitions; fatigue overrides; deload protocols; break return |

Phase 4 implements these rules in Python using the data layer built in Phase 2.
