# Roadmap to a Working Training System

Companion to `docs/plan.md`. Goes section by section through the design document, identifies concrete gaps, and maps a path from current state to a system that can actually generate programs.

---

## How to Read This Document

Each section below maps to the corresponding section in `plan.md`. For each:

- **Have** — what is actually defined right now
- **Missing** — specific gaps blocking progress
- **Bridge** — concrete actions to fill those gaps
- **Depends on** — what must exist before this work is useful

At the end: a phased roadmap ordering all of this.

---

## Section 1: Training Philosophies

**Have:**
- 11 sources with bullet-point principles
- 1 JSON schema (Starting Strength only)

**Missing:**
- JSON schemas for the other 10 sources — the system can't query or compare philosophies without structured data
- Gym Jones and Horsemen schemas are drawn from general knowledge, not from the source PDFs in `data/`; they may be incomplete or imprecise
- No **compatibility matrix** — when combining sources (e.g., SS + UA), the system needs to know which principles conflict and how to resolve them
- No **priority/weight field** on philosophies — when two sources are in the same program, which one governs a contested decision (e.g., Gym Jones says "discomfort is the stimulus" but Filly says "RPE 7-8, no grinding")
- No **scope limits** — each philosophy should declare what domains it claims authority over, so the system knows not to apply SS loading rules to conditioning sessions

**Bridge:**
1. Extract Gym Jones methodology from `data/gym jones/` PDFs — write a proper schema from the source material, not from memory
2. Extract Horsemen philosophy from `data/horsemen/Horsemen Training Program.pdf`
3. Write JSON schemas for all 11 sources (15 minutes each, once the extraction is done)
4. Build a **philosophy conflict table**: a matrix of (source A, source B) → conflicting fields + resolution rule. Example: SS vs. CFE on intensity — resolution: use SS rules on strength days, CFE rules on conditioning days
5. Add `scope` field to each philosophy: which modalities it governs

**Depends on:** PDF extraction (Gym Jones, Horsemen)

---

## Section 2: Methodological Frameworks

**Have:**
- Table of 9 frameworks with goals, weekly structure, and progression mechanism

**Missing:**
- No JSON schemas — can't be queried or composed programmatically
- No link between frameworks and their source philosophies (which framework comes from which source?)
- No **interference rules** — concurrent training of conflicting frameworks needs explicit handling. E.g., linear progression fails if conditioning volume is too high; polarized 80/20 is incompatible with daily max-effort work
- No **applicability criteria** — when should the system choose one framework over another? Should depend on athlete level, available days, goal profile, and current phase
- No **weekly slot budget** — each framework implicitly defines how many sessions of each type it needs; this needs to be explicit for the scheduling algorithm
- No **framework mixing rules** — can you run SS + polarized 80/20 simultaneously? Under what conditions? What are the guardrails?

**Bridge:**
1. Add JSON schema for each framework, including: `source`, `sessions_per_week` (by type), `intensity_distribution`, `progression_model`, `applicable_when` (conditions), `incompatible_with`
2. Define **interference matrix**: pairs of frameworks + their interference level (none / manageable / high) and the mitigation rule
3. Document the "novice vs. intermediate vs. advanced" decision tree for framework selection — this is how the system picks a framework from a goal profile

**Example interference rule (to be written):**
```
SS linear progression + aerobic conditioning:
- Low interference: ≤2 conditioning sessions/week, Zone 1-2 only
- High interference: ≥3 sessions OR any Zone 3+ → stalls linear progress
- Resolution: if goal = aerobic_base > 0.4, switch from SS to HLM or 3-day concurrent
```

**Depends on:** Philosophy schemas (section 1)

---

## Section 3: Training Modalities / Domains

**Have:**
- 12 modalities listed with one-line descriptions and source tags

**Missing:**
- No JSON schemas
- No **recovery cost** per modality — the scheduling algorithm needs to know that max strength and mixed modal conditioning are high-cost (need 48h before repeating) while Zone 2 and mobility are low-cost (can stack on adjacent days)
- No **session compatibility** rules — which modalities can share a session? (Strength + skill: yes. Max strength + threshold intervals: usually no. Mobility + anything: usually yes as warm-up or cool-down)
- No **minimum effective dose** and **maximum recoverable volume** parameters — these bound the scheduling algorithm
- No **progression linkage** — each modality should reference which progression model governs it
- "Combat Sport" and "Rehab" are listed but less developed than the others — no source attribution, no intensity profile

**Bridge:**
1. Write JSON schema for each modality including: `recovery_cost` (low/medium/high), `compatible_in_session_with`, `min_weekly_dose_minutes`, `max_weekly_volume_minutes`, `progression_model`, `intensity_zones`
2. Define a **session pairing table**: matrix of modality pairs → can share session (yes / conditional / no) + ordering rule (which goes first)
3. Define recovery cost explicitly so the scheduler can space sessions correctly

**Example modality schema (to be written):**
```json
{
  "modality": "aerobic_base",
  "recovery_cost": "low",
  "compatible_in_session_with": ["mobility", "movement_skill"],
  "incompatible_in_session_with": ["max_strength", "anaerobic_intervals"],
  "sequence_in_session": "standalone_or_after_mobility",
  "min_weekly_minutes": 90,
  "max_weekly_minutes": 600,
  "progression_model": "time_to_task"
}
```

**Depends on:** Nothing — can be done in parallel with section 1 and 2

---

## Section 4: Workout Archetypes

**Have:**
- 5 category tables (~20 archetypes) with format and brief notes

**Missing:**
- No JSON schemas — tables are not machine-readable
- No **internal slot structure** — an archetype like "3×5 Linear" needs to define how many exercise slots it has, what type (primary compound, accessory, etc.), and what parameters (sets, reps, load target)
- No **duration estimates** per archetype — needed for constraint matching
- No **warm-up / cool-down defaults** attached to archetype types
- No **scaling rules** — how does the archetype adapt when equipment is limited, time is short, or the athlete is in a deload week?
- Missing archetypes:
  - Ido Portal skill-specific formats (floreio, locomotion patterns, hanging practice) — need extraction from `data/portal/`
  - BJJ-specific conditioning archetypes (positional drilling rounds, grip conditioning circuits)
  - KB-specific archetypes from `data/kettlebell/Kettlebell workouts.xlsx` (need extraction)
  - Horsemen-specific circuits from PDF (need extraction)
  - Gym Jones operator circuits from PDFs (need extraction)

**Bridge:**
1. Define JSON schema for archetypes:
```json
{
  "archetype": "3x5_linear",
  "modality": "max_strength",
  "duration_estimate_minutes": 60,
  "slots": [
    {"role": "primary_compound", "sets": 3, "reps": 5, "intensity": "progressing"},
    {"role": "secondary_compound", "sets": 3, "reps": 5, "intensity": "progressing"},
    {"role": "posterior_chain", "sets": 1, "reps": 5, "intensity": "progressing"}
  ],
  "deload_modifier": {"sets": 3, "reps": 5, "intensity_pct": 0.9},
  "required_equipment": ["barbell", "rack"],
  "sources": ["Starting_Strength"]
}
```
2. Extract Horsemen circuits and Gym Jones operator workouts from PDFs and define as archetypes
3. Extract KB flows and pentathlon training formats from XLSX
4. Extract Ido Portal floreio and locomotion formats from `data/portal/Ido Portal Floreio Routines.pdf`

**Depends on:** PDF/XLSX extraction

---

## Section 5: Exercises

**Have:**
- 2 JSON examples (KB Swing, Ruck)
- A list of 9 exercise category names

**Missing:**
- This is the largest single gap. The exercise library is essentially empty. 2 examples vs. the ~150-200 exercises needed for the system to be useful.
- No exercise database file — exercises need to live somewhere (e.g., `data/exercises.json` or per-modality YAML files)
- No **prerequisite graph** — which exercises unlock others? This is critical for the system to avoid programming snatches before swings, or weighted pull-ups before bodyweight pull-ups
- No **equipment tagging** on most exercises — needed for constraint filtering
- No **injury exclusion tags** — which exercises are contraindicated for which injury flags?
- No **intensity/effort classification** (low / medium / high / max effort) — needed for session load management
- Exercises from source materials not yet extracted:
  - `data/kettlebell/Kettlebell workouts.xlsx` — KB exercise library
  - `data/horsemen/` — sandbag, bodyweight, ruck exercises
  - `data/gym jones/` — operator exercise selections
  - `data/portal/Ido Portal Floreio Routines.pdf` — movement skill exercises
  - `data/crossfit/crossfit journal/` — CF benchmark movements
  - Rehab exercises listed in plan.md as text — need to be formalized

**Bridge:**
1. Finalize the JSON schema for exercises (build on the 2 existing examples)
2. Create `data/exercises/` directory with per-category YAML or JSON files:
   - `barbell.yaml`, `kettlebell.yaml`, `bodyweight.yaml`, `aerobic.yaml`, `carries.yaml`, `sandbag.yaml`, `mobility.yaml`, `skill.yaml`, `rehab.yaml`
3. Extract and populate from each source PDF/XLSX — this is the most labor-intensive task in the project
4. Build the prerequisite graph as a separate data structure (directed acyclic graph): each exercise lists `unlocks` and `requires`
5. Add `contraindicated_with` tags referencing injury flag names from the constraint layer

**Suggested exercise schema:**
```json
{
  "id": "kb_swing_two_hand",
  "name": "Kettlebell Swing (two-hand)",
  "category": "ballistic",
  "modality": ["power", "conditioning"],
  "equipment": ["kettlebell"],
  "effort": "medium",
  "requires": ["hip_hinge_pattern", "bracing"],
  "unlocks": ["kb_swing_single_arm"],
  "contraindicated_with": ["lumbar_disc", "acute_hamstring"],
  "progressions": {
    "load": "increase_bell_weight",
    "volume": "increase_reps_per_set",
    "complexity": "kb_swing_single_arm"
  },
  "sources": ["Wildman", "Pavel"]
}
```

**Depends on:** PDF/XLSX extraction; schema finalization

---

## Section 6: Progression Models

**Have:**
- Table of 9 models with mechanism, source, and application

**Missing:**
- No **algorithmic rules** — the table names the models but doesn't define how they work. "Linear Load" needs: starting weight, increment amount, deload trigger, deload protocol, reset protocol
- No **failure/stall conditions** for each model — when does linear progression stall? What is the threshold? What happens next?
- No **multi-model coordination** — in a concurrent program (strength + conditioning), two different progression models are running simultaneously. How do they interact? Who gets priority?
- No **parameter defaults** — "add weight each session" is not a rule, it's a description. A rule is: "add 2.5kg to press, 5kg to squat and deadlift each session; if three consecutive failures at same weight, deload to 90% and reset"
- RPE Autoregulation has no defined RPE scale or decision rules

**Bridge:**
1. For each progression model, define:
   - Input parameters (starting point, increment, target)
   - Advancement rule (when to progress)
   - Stall definition (how many failures = stall)
   - Deload protocol (% reduction, duration)
   - Reset protocol (where to restart after extended break)
2. Define a **progression model selector**: given an athlete's training age and goal profile, which model applies to which modality?
3. Write pseudocode or decision trees for the 3 most important models (Linear Load, Density, RPE Autoregulation) first — these cover most of the use cases

**Example (to be written):**
```
LinearLoad:
  increment: { squat: 5kg, deadlift: 5kg, press: 2.5kg, bench: 2.5kg }
  stall_threshold: 3 consecutive sessions at same weight
  deload_on_stall: reduce to 90% of stalled weight
  reset_on_extended_break: reduce by 10% per week missed, min 50%
  graduation: when 3 stalls in 8 weeks → switch to HLM or volume periodization
```

**Depends on:** Nothing — pure logic design, no extraction needed

---

## Section 7: Constraint Layer

**Have:**
- 1 JSON constraint example
- 2 injury flag examples (knee, shoulder) with brief exclusion notes

**Missing:**
- No comprehensive **injury flag → exclusion list** mapping — only 2 of many possible injuries covered. Common missing: lumbar disc, ankle, wrist/grip, neck, hip flexor, elbow (golfer's/tennis)
- No **equipment → available exercise** mapping — the system needs to know what exercises are possible given a specific equipment set (e.g., KB only → which archetypes are available?)
- No distinction between **hard constraints** (can't do: injury, no equipment) vs. **soft constraints** (prefer not: time preference, lifestyle)
- No **constraint validation** logic — what happens when constraints make a goal impossible? (e.g., goal = alpine performance, days_per_week = 2, session_time = 30min → not achievable; system should warn)
- Training phase constraint not connected to archetype availability — "base phase" should limit available archetypes (no peaking templates, no test-day archetypes)
- No **fatigue state** as a constraint — accumulated fatigue should modify what the system is willing to schedule

**Bridge:**
1. Build the **injury flag library**: for each common injury, define the exclusion list (exercises and movement patterns to avoid) and the modified exercise list (what to substitute). Start with the injuries documented in plan.md notes (knee meniscus, shoulder) then expand
2. Build the **equipment profile library**: for each plausible equipment setup, define which exercise categories are available
   - `barbell_gym`: full library
   - `home_kb_only`: kb, bodyweight, carries, aerobic
   - `bodyweight_only`: bodyweight, aerobic, mobility, skill
   - `outdoor_ruck_only`: ruck, bodyweight
3. Add constraint priority levels (hard / soft) to the schema
4. Write validation logic: given constraints + goal profile, is the goal achievable? If not, what's the minimum constraint change that would make it achievable?

**Depends on:** Exercise library (section 5) for equipment and injury tag definitions

---

## Section 8: Goal Profiles

**Have:**
- 1 JSON example (Alpine Climbing)
- 7 goal types listed by name

**Missing:**
- 6 of 7 goal profiles have no JSON schema — only Alpine Climbing is defined
- No **phase sequence** per goal — Alpine prep follows base → build → peak → taper, but SOF operator prep or BJJ competition prep has a different structure
- No **minimum entry prerequisites** — you can't program a 24-week alpine prep for someone who can't run 5km. Goals need a fitness floor
- No **time-to-goal estimation** — given current fitness level (from benchmarks), how long does it realistically take to reach the goal?
- No **conflict detection** between simultaneous goals — "I want max strength AND alpine climbing performance" has known interference; the system should flag it and propose a priority ranking

**Bridge:**
1. Write JSON schemas for all 7 goal profiles — define priority vectors, primary sources, phase sequence, and event date field
2. Add to each profile: `minimum_prerequisites` (minimum benchmark values that must be met before program starts), `incompatible_with` (other goals that cannot be run concurrently)
3. Add a `phase_sequence` array to each profile defining the meso structure:
```json
{
  "goal": "BJJ_competitor",
  "phase_sequence": [
    {"phase": "base", "weeks": 6, "focus": "aerobic_base + strength_endurance"},
    {"phase": "build", "weeks": 6, "focus": "combat_conditioning + max_strength"},
    {"phase": "peak", "weeks": 3, "focus": "specific_conditioning + technique"},
    {"phase": "taper", "weeks": 1, "focus": "active_recovery"}
  ]
}
```

**Depends on:** Modality schemas (section 3), benchmark standards (section 9)

---

## Section 9: Performance Benchmarks / Standards

**Have:**
- Personal rucking benchmarks table (3 tiers)
- KB pentathlon scoring table
- Brief strength benchmark bullets
- Reference to The Cell Standards PDF (not extracted)

**Missing:**
- **The Cell Standards not extracted** — the PDF `data/the cell fitness standards.pdf` contains a full Level I-V framework that is directly useful here. This is the most important extraction task for this section
- **Horsemen standards not extracted** — the Horsemen program likely contains specific performance targets
- No **benchmark → goal profile mapping** — which benchmarks are relevant to which goal? Alpine climbing doesn't care about your deadlift 1RM the same way an SS program does
- No **assessment protocol** — how does an athlete actually test these benchmarks? Some require equipment, some require a partner, some need a specific warm-up protocol
- No **intermediate milestone benchmarks** — the table has entry/intermediate/advanced but many goals need quarterly milestones to track progress
- CrossFit benchmark workouts (the Girls: Fran, Grace, Helen; the Heroes: Murph) not included — these are useful as conditioning benchmarks
- No BJJ-specific conditioning benchmarks (grip endurance test, positional rounds capacity)

**Bridge:**
1. Extract The Cell Standards from PDF — create `data/benchmarks/cell_standards.yaml` with all Level I-V criteria by domain
2. Extract Horsemen performance standards from PDF
3. Write a **benchmark → goal mapping table**: for each goal profile, list the 3-5 benchmarks most predictive of readiness
4. Add CrossFit Girls/Heroes as conditioning benchmarks (these are freely documented)
5. Add a simple self-assessment protocol for each benchmark (how to test it)

**Depends on:** PDF extraction (The Cell, Horsemen)

---

## Section 10: Injury / Rehab as Training Phase

**Have:**
- Phase type taxonomy (8 phase types)
- 2 rehab protocols (knee meniscus post-op, shoulder impingement)

**Missing:**
- Only 2 of many common injuries have protocols. Missing: lumbar disc herniation, hip flexor strain, ankle sprain, tennis/golfer's elbow, wrist injury (critical for BJJ), neck strain
- No **progression criteria** within rehab phases — "early phase → mid phase" transition requires something testable (pain level, ROM measurement, movement milestone). Currently the phases are named but have no defined exit criteria
- No **return-to-sport criteria** — when is an athlete cleared to return to full training? Needs objective criteria, not just "when it feels right"
- No **load management algorithm** during rehab — how does training volume and intensity scale during injury? A partially injured athlete should still train what they can
- No **prehab defaults** — injury prevention exercises that should be scheduled for athletes with known risk factors (e.g., BJJ athlete should always include shoulder prehab and neck work)
- Rehab phases not integrated into the constraint layer — the `post_op` phase type exists but doesn't automatically modify the constraint layer

**Bridge:**
1. Expand injury library with 4-6 more common injuries, each with:
   - Exercise exclusion list
   - Modified training focus
   - Rehabilitation protocol (early/mid/late phases)
   - Phase transition criteria (objective, testable)
   - Return-to-sport criteria
2. Define automatic constraint modifications for each phase type (post_op → constraint additions applied automatically)
3. Define prehab defaults: for each sport modality (BJJ, alpine, SOF), what maintenance exercises should always appear?
4. Add "modified but still training" logic: when injured, what percentage of normal volume is maintained in unaffected domains?

**Depends on:** Constraint layer schema (section 7)

---

## Section 11: Periodization

**Have:**
- 3 weekly template examples (SS 3-day, Alpine 5-day, Horsemen 4-day)

**Missing:**
- No **meso-level templates** (4-6 week blocks) — only micro (weekly) templates exist
- No **macro-level templates** (12-24 week programs) — the system needs to know what a complete program looks like, not just one week
- No **deload week structure** — what does a deload week look like for each framework? Not just "reduce volume" but specific modifications
- No **phase transition criteria** — when does the system decide to move from base to build? This needs a trigger (time-based, performance-based, or both)
- Only 3 weekly templates; missing: BJJ + strength concurrent, SOF prep, pure conditioning/aerobic base, injury-modified week
- No **session ordering rules** — given a 5-day week with strength, conditioning, and skill sessions, in what order should they appear? (Recovery-aware scheduling)
- No **volume tracking** across the week — the system needs to track total weekly load to avoid over-programming

**Bridge:**
1. Write meso templates (4-6 week blocks) for each of the 3 current weekly templates — show week-by-week volume and intensity progression within the block
2. Write 2-3 macro templates (16-week programs) showing the full phase sequence
3. Define deload week rules: for each framework, reduce volume to X% of peak week, maintain intensity
4. Define phase transition criteria: time-based (after N weeks) + performance-based (hit benchmark Y)
5. Write session ordering rules as a priority list (e.g., skill before conditioning; conditioning before strength is recoverable; strength before conditioning is suboptimal)

**Depends on:** Archetype schemas (section 4), modality recovery costs (section 3)

---

## Section 12: System Architecture

**Have:**
- 6-step process description
- 1 JSON output example (2 sessions)

**Missing:**
- No **tech stack decision** — is this Python? TypeScript? A rule engine? A simple script? This affects everything downstream
- No **data storage approach** — flat JSON/YAML files (simple, portable) vs. a database (queryable, scalable). For the current scope, flat files are probably right
- No **scoring algorithm** for step 3 ("assign archetypes to slots by priority weights") — what is the actual math? How does a 0.5 aerobic_base weight translate to session slot allocation?
- No **prerequisite enforcement** — step 4 filters by equipment and injury, but doesn't check whether exercise prerequisites are met (athlete hasn't established hip hinge pattern → no swings)
- No **conflict detection** — step 2 filters archetypes by constraints, but doesn't detect when two selected archetypes interfere with recovery (e.g., max strength Monday + threshold intervals Tuesday)
- No **explanation layer** — a good system should be able to explain why it chose a given program. "This week has 3 Zone 2 sessions because your aerobic_base weight is 0.5 and you are 8 weeks from your event"
- No **feedback loop** — athlete rates workout (too hard, right, too easy), system adjusts future programming
- The 6-step process is a description, not an algorithm — steps 3 and 4 need to be formalized as pseudocode before they can be implemented

**Bridge:**
1. **Choose tech stack** — recommended starting point: Python with YAML data files. Simple, readable, fast to prototype. No framework needed initially.
2. **Design file structure** for the data layer:
```
data/
  philosophies/       one YAML per source
  frameworks/         one YAML per methodology
  modalities/         one YAML per domain
  archetypes/         one YAML per category
  exercises/          one YAML per category
  goals/              one YAML per goal profile
  benchmarks/         cell_standards.yaml, personal.yaml, crossfit.yaml
  constraints/
    injury_flags.yaml
    equipment_profiles.yaml
src/
  scheduler.py        slot assignment algorithm
  selector.py         archetype and exercise selection
  progression.py      advancement rules
  validator.py        constraint validation
  generator.py        top-level program generator
  output.py           render to human-readable format
```
3. **Formalize the slot assignment algorithm** (step 3):
   - Convert goal priority vector to session count per modality per week
   - Score available archetypes against modality needs
   - Assign archetypes to days respecting recovery constraints
4. **Implement prerequisite graph** as a directed graph over exercise IDs — check before placing any exercise
5. **Define output formats**: minimum viable is a structured JSON + a plain-text weekly plan readable by a human

**Depends on:** All schema work; all data population

---

## Phased Roadmap

### Phase 0: Data Extraction (prerequisite for phases 1-3) ✅ COMPLETE

These tasks unblock everything else. None of the schema or library work can be finalized without the source material.

| Task | Source | Output | Status |
|------|--------|--------|--------|
| Extract Gym Jones methodology | `data/gym jones/*.pdf` | `docs/extracted/gym-jones.md` | ✅ Done |
| Extract Horsemen program | `data/horsemen/*.pdf` | `docs/extracted/horsemen.md` | ✅ Done |
| Extract The Cell Standards | `data/the cell fitness standards.pdf` | `data/benchmarks/cell_standards.yaml` | ✅ Done |
| Extract Ido Portal floreio | `data/portal/*.pdf` | `docs/extracted/ido-portal.md` | ✅ Done |
| Extract KB workouts | `data/kettlebell/Kettlebell workouts.xlsx` | `docs/extracted/kettlebell.md` | ✅ Done |
| Extract CrossFit Journal articles | `data/crossfit/crossfit journal/` | `docs/extracted/crossfit-journal.md` | ✅ Done |

---

### Phase 1: Schema Design ✅ COMPLETE

Define the data model for every layer. No data population yet — just the schema shapes. All schemas should be agreed on before population begins, to avoid having to reformat 200 exercises because the schema changed.

| Task | Output | Status |
|------|--------|--------|
| Finalize philosophy JSON schema | `docs/schemas/philosophy.schema.json` | ✅ Done |
| Finalize framework JSON schema | `docs/schemas/framework.schema.json` | ✅ Done |
| Finalize modality JSON schema | `docs/schemas/modality.schema.json` | ✅ Done |
| Finalize archetype JSON schema | `docs/schemas/archetype.schema.json` | ✅ Done |
| Finalize exercise JSON schema | `docs/schemas/exercise.schema.json` | ✅ Done |
| Finalize goal profile JSON schema | `docs/schemas/goal_profile.schema.json` | ✅ Done |
| Finalize constraint schema | `docs/schemas/constraints.schema.json` | ✅ Done |
| Finalize benchmark schema | `docs/schemas/benchmark.schema.json` | ✅ Done |

See `docs/schemas/README.md` for shared enumerations and design decisions.

---

### Phase 2: Data Population ✅ COMPLETE

Fill every schema with real data. This is the longest phase.

| Task | Output | Status |
|------|--------|--------|
| Write all 11 philosophy schemas | `data/philosophies/*.yaml` | ✅ Done |
| Write all 9 framework schemas | `data/frameworks/*.yaml` | ✅ Done |
| Write all 12 modality schemas | `data/modalities/*.yaml` | ✅ Done |
| Write all 20 archetype schemas | `data/archetypes/**/*.yaml` | ✅ Done |
| Build exercise library (191 exercises, 9 categories) | `data/exercises/*.yaml` | ✅ Done |
| Write all 7 goal profile schemas | `data/goals/*.yaml` | ✅ Done |
| Write injury flag library (12 injuries) | `data/constraints/injury_flags.yaml` | ✅ Done |
| Write equipment profile library (5 profiles) | `data/constraints/equipment_profiles.yaml` | ✅ Done |
| Write benchmark library | `data/benchmarks/*.yaml` (3 files + cell_standards) | ✅ Done |
| Build philosophy conflict matrix | Embedded in `frameworks/*.yaml` incompatible_with fields | ✅ Done |
| Build prerequisite graph | Embedded in `exercises/*.yaml` requires/unlocks fields | ✅ Done |

**Totals:** 73 YAML files, 191 exercises, 0 parse errors

---

### Phase 3: Logic Design ✅ COMPLETE

Write the algorithms and rules as pseudocode or structured rules before implementing anything. Validate the logic on paper first.

| Task | Output | Status |
|------|--------|--------|
| Progression model rules (all 9 models) | `docs/logic/progression_models.md` | ✅ Done |
| Session pairing / recovery rules | `docs/logic/scheduler.md` | ✅ Done |
| Slot assignment algorithm | `docs/logic/scheduler.md` | ✅ Done |
| Prerequisite enforcement logic | `docs/logic/selector.md` | ✅ Done |
| Constraint validation logic | `docs/logic/validator.md` | ✅ Done |
| Phase transition criteria | `docs/logic/phase_transitions.md` | ✅ Done |
| Conflict detection logic | `docs/logic/validator.md` | ✅ Done |

**Depends on:** Phase 2 (need real data to validate logic against)

---

### Phase 4: Implementation (MVP) ✅ COMPLETE

Build the smallest version that can generate a complete weekly program.

**MVP scope delivered:**
- All 7 goal profiles (loaded from YAML)
- All equipment profiles via `--equipment` flag or preset names
- All 20 archetypes selected dynamically per constraints
- 191 exercises with injury + equipment filtering
- 3 progression models: linear_load, time_to_task, rpe_autoregulation (+ density, distance variants)
- Constraint filtering: equipment (hard), injury flags (hard), phase gates, zone intensity
- Output: human-readable markdown weekly plan
- 4-week program generation (configurable with `--weeks`)

**Not in MVP (Phase 5):**
- Feedback loop
- Phase transition automation
- KB-only strength archetype fallback
- Exercise variety improvements for limited-equipment scenarios
- Multi-goal conflict detection

**File structure:**
```
src/
  generator.py    — entry point: takes goal + constraints, returns 4-week program
  scheduler.py    — priority vector → day assignment with recovery constraints
  selector.py     — archetype + exercise selection, prerequisite seeding by level
  progression.py  — load calculation (linear_load, time_to_task, rpe, density, distance)
  validator.py    — pre-generation feasibility checks with error/warning codes
  output.py       — markdown formatting
  loader.py       — YAML data loading
main.py           — CLI entry point (argparse)
requirements.txt  — pyyaml>=6.0
```

**Usage:**
```
python main.py --goal general_gpp --days 4 --level intermediate
python main.py --goal alpine_climbing --days 5 --phase build --week 5
python main.py --goal general_gpp --days 3 --equipment home_kb_only
python main.py --goal general_gpp --injuries knee_meniscus_post_op --days 4
```

**Depends on:** Phases 1-3

---

### Phase 5: Validation and Expansion ✅ COMPLETE

| Task | Status | Notes |
|------|--------|-------|
| Run all 7 goal profiles | ✅ Done | Zero slot errors across all goals |
| Fix data bugs found in generation | ✅ Done | carry slot categories, ruck slot category, meta-slot skip, joint_prep filter |
| Fix selector bugs | ✅ Done | slot_type ordering, equipment `none`, zone2 filter, AMRAP skill exclusion |
| Fix progression bugs | ✅ Done | time_domain 30 min floor, for_time distance dispatch, short distance meters |
| Fix output bugs | ✅ Done | meta slot skip, `distance_m` key support |
| Manual quality review (SOF 2-week output) | ✅ Done | Load prescriptions, archetypes, exercise variety reviewed |

**Remaining known gaps (deferred to Phase 6):**
- KB-only strength fallback: no `max_strength` archetypes without barbell → falls back to aerobic_base
- Exercise variety in limited-equipment scenarios (same exercise fills multiple aerobic slots)
- Phase transition automation (currently manual `--phase` / `--week` flags)
- README.md still contains stale brainstorm content

---

### Phase 6: Polish and Completeness ✅ COMPLETE

| Task | Priority | Status | Notes |
|------|----------|--------|-------|
| KB-only strength archetypes | High | ✅ Done | New `kb_double_strength` archetype; archetype scorer prefers fully-equipped over `equipment_limited` fallbacks |
| Exercise variety scoring | High | ✅ Done | Intra-session hard dedup via `session_used_ids` two-pass filter |
| Phase automation | Medium | Deferred → Phase 7 | `--event-date` flag; auto-advance through base→build→peak→taper |
| Methodology review | Medium | Deferred → Phase 7 | "Would Rippetoe / House recognize this?" quality pass |
| Gym Jones operator circuit quality | Medium | Deferred → Phase 7 | Barbell-heavy slots still empty in KB-only; more operator archetypes |
| README.md update | Low | Deferred → Phase 7 | Replace stale brainstorm content |

**Data fixes in Phase 6:**
- `kb_press_single.requires`: `[kb_clean_single]` → `[push_pattern, bracing_mechanics]` (pressing doesn't require the clean)
- `kb_halo.movement_patterns`: removed `vertical_push` (halo is rotational, not a press)
- `kb_figure_eight.movement_patterns`: removed `hip_hinge` (coordination drill, not a strength hinge)
- Added `exclude_movement_pattern` field to slot exercise_filter (used to block ballistic exercises from slow-hinge slots)

---

### Phase 7: Methodology Review and Phase Automation ✅ COMPLETE

**Track A — Methodology review: ✅ Done**

| Check | Result |
|-------|--------|
| Starting Strength (max_strength_focus) | ✅ 5×5 / HLM cycling correctly; squat slot now picks proper squat exercises; no novice-only 3×5 for intermediate |
| Uphill Athlete (alpine_climbing, build) | ✅ Threshold intervals + 3× Zone 2 + 1× strength; no Tabata in build phase |
| Injury rehab (knee flag) | ✅ No squat/locomotion/ballistic exercises; joint prep circuit all mobility |

**Bugs fixed in Track A:**
- `sumo_deadlift.movement_patterns`: removed `squat` (it's a hinge, not a squat)
- `3x5_linear.yaml`: added `training_levels: [novice]`; `select_archetype` now filters by training_level
- `tabata.yaml`: `applicable_phases` changed from `[build, peak, maintenance]` → `[peak, maintenance]`
- `joint_prep_circuit.yaml`: all 4 slots now have `exercise_filter: { category: mobility }` and explicit `duration_minutes`
- `output.py`: skill slot no longer renders duration twice

**Track B — Phase automation:**

| Task | Description |
|------|-------------|
| `--event-date` CLI flag | Parse date, compute weeks remaining, map to phase sequence from goal YAML |
| Phase sequence in goal data | Verify all 7 goal YAMLs have `phase_sequence` with week counts per phase |
| Auto week-in-phase calculation | `weeks_remaining` → which phase + which week within it |
| Taper auto-trigger | Final N weeks before event → force taper phase regardless of calculated phase |

---

### Phase 8: Phase Automation

Add `--event-date` flag so the system computes phase and week automatically from the calendar.

| Task | Description |
|------|-------------|
| Verify `phase_sequence` in all goal YAMLs | Each goal needs `phase_sequence` list with `{ phase, weeks }` entries |
| `compute_phase_from_date(goal, event_date, today)` | New function in `scheduler.py`: weeks_remaining → walk phase_sequence backwards from event → current phase + week |
| `--event-date YYYY-MM-DD` CLI flag | `main.py`: parse date, call compute function, override `--phase` and `--week` |
| Taper auto-trigger | If `weeks_remaining <= taper_weeks`, force phase=taper regardless |
| Conflict with explicit `--phase` / `--week` | If user passes both, `--event-date` wins with a notice |

---

## Priority Order (If Starting Today)

1. **Extract The Cell Standards PDF** — highest-leverage extraction; defines the benchmark layer that anchors everything else
2. **Extract Gym Jones and Horsemen PDFs** — fills the two largest philosophy gaps
3. **Finalize exercise schema** — the exercise library blocks more downstream work than any other single item
4. **Write all philosophy + framework schemas** — small effort, high architectural value
5. **Build exercise library (barbell + KB + bodyweight first)** — the 3 categories that appear in every goal profile
6. **Write remaining 6 goal profile schemas** — needed before any program generation is possible
7. **Write progression model rules** — logic design, no extraction needed, can be done in parallel with extraction
8. **Implement MVP generator** — once exercise library has 40+ exercises and 2 goal profiles are complete

---

## What Would Make This "Done Enough to Be Useful"

A usable v1 needs:
- [ ] Exercise library with 60+ exercises (barbell, KB, bodyweight, aerobic, carries)
- [ ] 3 complete goal profiles with JSON schemas
- [ ] 5+ archetypes with JSON schemas (one per major modality)
- [ ] Constraint filtering by equipment and 3 common injury flags
- [ ] Linear load + density + RPE progression models implemented
- [ ] A generator that accepts (goal, constraints) and returns a 4-week program in readable format
- [ ] The Cell Standards extracted and accessible as benchmark reference

Everything after that is refinement: more exercises, more goal profiles, smarter scheduling, feedback loops, UI.
