# How to write a package

The one document that says what a package is, what goes in each file, which values are
allowed and how a package is checked. It is written for whoever writes one without having
read the code: a person, an agent through the MCP server, or the app's package builder.

Its lists are not written by hand. Every block marked `gen:` is written by
`tools/gen_package_spec.py` from the place the fact lives — the commons, the schemas, the
gate — and a push gate fails when one is stale. The field-level truth is the JSON schema
beside this file (`<kind>.schema.json`); this document says how the files fit together.

The server serves it (`GET /api/dev/package-spec`, the MCP server's `get_package_spec`), so
it ships in the image: it lives in `docs/schemas/`, the one part of `docs/` that does.

---

## 1. What a package is

A package is **one folder of YAML** that describes a training method. The engine generates
periodized programs from it. Nothing in the code names a package: a folder that passes the
checks below is picked up and used with no code change.

```
Philosophy          the method: beliefs, scope, and one or more tracks
  └─ Track          one way to follow it: an ordered list of the method's own phases
       └─ Phase     a block of weeks: a kind the engine reads, and the framework that builds its weeks
            └─ Framework   how a week is built
                 └─ Modality    what physical quality a session trains (shared vocabulary)
                      └─ Archetype   a session shape: its slots
                           └─ Exercise   a movement, with the package's own loads
```

Two things belong to the engine, not to a package, and a package only chooses among them:
**how a week is built** (three shapes, section 3) and **how a load progresses** (the
progression models). A package cannot add a slot type, a progression or contract model, a
phase kind, a training level, an intensity, a watch template or an icon.

A package may **only draw on itself** (and on packages its philosophy lists in
`borrows_from`). When it cannot fill a session or a slot, the slot is left empty and
reported; nothing is taken from another method.

## 2. The files

<!-- gen:files -->
| File | Required | Schema | An athlete's package may carry it | What it is |
|---|---|---|---|---|
| `philosophy.yaml` | yes | `philosophy.schema.json` | yes | The method: its beliefs, scope and tracks, each an ordered list of its own phases. |
| `frameworks/` | yes | `framework.schema.json` | yes | One file per framework, named `<framework id>.yaml`: how a week of a phase is built. |
| `archetypes/` | yes | `archetype.schema.json` | yes | One file per session shape, in any subfolders: the slots a session is made of. |
| `exercises.yaml` | yes | `exercise.schema.json` | yes | `exercises:` — the movements the package owns, with its own loads. |
| `exercise_media.yaml` | no | — | yes | Demo links per exercise id. |
| `level_seeds.yaml` | no | — | yes | What an athlete of each level is assumed to know already (unlocks `requires`). |
| `analytics.yaml` | no | `analytics.schema.json` | yes | What progress means for the method. Without it a spec is synthesised from the frameworks. |
| `watch.yaml` | no | `watch.schema.json` | yes | How its sessions look on the watches. Without it, the slot types' default screens. |
| `training_contract.yaml` | no | `training_contract.schema.json` | yes | Per track, modules the engine places as written, with earned progress (the advanced shape). |
| `standards.yaml` | no | `standards.schema.json` | yes | Standards the method tests that the commons lack. |
| `vocabulary.yaml` | no | `vocabulary.schema.json` | yes | Modalities, movement patterns and equipment the package adds for itself. |
| `fidelity.yaml` | no | `fidelity.schema.json` | yes | Its sources, rules and inventions (a package that ships in the repository). |
| `source_weeks.yaml` | no | `source_weeks.schema.json` | no | The source's own example weeks, compared with generation (repository packages). |
| `tests/` | no | — | no | Its own tests (repository packages). |
<!-- /gen:files -->

Every id is a slug: lower-case letters, digits and underscores.

## 3. Choose how a week is built

The data decides, per track:

| Shape | Chosen when | The week is | Write it when |
|---|---|---|---|
| **Modality scheduler** | nothing below applies | the framework's `sessions_per_week` (modality → sessions), placed on the athlete's days by recovery rules; each session takes the package's best-fitting archetype of that modality | the method is "so many sessions of each quality a week". **The shape to start with**, and the worked example's. |
| **Week templates** | a phase has `week_templates` | the source's week, day by day: each day names a category of the framework's `categories`, a pool of named-workout archetypes (`pool_only: true`) taken in rotation | the source writes its weeks as named workouts on named days |
| **Training contract** | the track is listed in `training_contract.yaml` | modules placed as written, with progress earned by confirmed sessions | the method is a strict progression with pass/repeat rules. The advanced shape: read `training_contract.schema.json` before attempting it. |

For the scheduler, the framework's `sessions_per_week` is turned into priorities, and the
week is laid on the athlete's training days. Two rules decide what survives when days are
scarce: a modality's `priority_tier` (1 kept first; `mobility` is tier 4 and is dropped
under five days) and its recovery cost (two high-cost sessions are kept 48 h apart). Write
`sessions_per_week` so that its total is the framework's `expectations.ideal_days_per_week`.

## 4. What goes in each file

**`philosophy.yaml`** — required: `id` (the folder's name), `name`, `core_principles`,
`scope` (the modalities it trains), `bias` (the ones it emphasises, a subset of scope),
`tracks`. Each track: `id`, `name`, `phases`; each phase: `id`, `name`, `kind`, `weeks`,
`framework_id` (one of this package's frameworks), and its own words (`focus`,
`description`). Set `self_contained: true`. The phase's `id` and `name` are the method's
own ("Foundation"); its `kind` is the engine's vocabulary. With several tracks, name the
default in `primary_track_id`.

**`frameworks/<id>.yaml`** — required: `id` (the file's name), `name`, `source_philosophy`
(the package id), `sessions_per_week`, `progression_model`. Also write `expectations`
(minimum and ideal weeks, days a week and session minutes — the builder shows them and the
checks generate at the ideal), `applicable_when` (levels, `days_per_week_min`/`max`) and,
unless the method never deloads, `deload_protocol` (`frequency_weeks`, and
`volume_reduction_pct`: the share of volume a deload week **keeps**).

**`archetypes/**/<id>.yaml`** — required: `id`, `name`, `modality`, `category`,
`duration_estimate_minutes`, `slots`. Also `applicable_phases` (the phase kinds it suits —
an archetype is only picked in a phase whose kind is listed), `training_levels`,
`required_equipment`. Every modality a framework schedules needs at least one archetype
that applies to each phase kind and level the track is written for, or the session is
substituted or left out.

A **slot** has a `role` (free text, unique within the archetype), a `slot_type`, the
numbers that type needs (`sets`/`reps`; `duration_minutes` or `duration_sec`; `distance_m`;
`rounds`; `hold_seconds`), an `intensity`, and an `exercise_filter` that says what may fill
it:

- `exercise_ids: [..]` — only these (use `ordered: true` to take the first the athlete can do);
- else `movement_pattern` (a pattern or a slot-filter alias) and/or `category`.

The exercise comes from **this package's** `exercises.yaml` only, filtered by the athlete's
level, equipment and injuries. A slot nothing fits is left empty with the reason.

**`exercises.yaml`** — `exercises:` a list; each requires `id`, `name`, `category`,
`modality` (a list), `equipment` (a list; `none` or `open_space` for nothing), `effort`.
Also `movement_patterns` (what slot filters and injury flags match on), `contraindicated_with`
(injury flags that rule it out), `requires` / `unlocks` (prerequisites), and for a loaded
lift `starting_load_kg` (per level), `weekly_increment_kg`, `sessions_per_week`. An exercise
id another package declares may be re-declared: each package keeps its own prescription.

**`vocabulary.yaml`** (optional) — what the package adds to the shared vocabulary, for
itself: `modalities` (a modality with its `family`, `progression_model` and `display`),
`movement_patterns` (the body `regions` it loads, and `excluded_by`: the injury flags that
rule it out — required, `[]` says none) and `equipment` (`id`, `label`). Never an id the
commons already define. Prefer the commons' vocabulary; add only what the method really
lacks.

**`analytics.yaml`** (optional) — `id` and `progress`: what the method's progress is, each
entry a `primitive` with a `scope`. One entry is the `headline`.

**`standards.yaml`**, **`watch.yaml`**, **`level_seeds.yaml`**, **`exercise_media.yaml`**
(optional) — see their schemas; none is needed for a package to generate.

## 5. Valid values

<!-- gen:values -->
**Modalities** (`data/commons/modalities/`; a package adds its own in `vocabulary.yaml`):

| id | name | family | recovery cost | progression model |
|---|---|---|---|---|
| `max_strength` | Max Strength | strength | high | `linear_load` |
| `relative_strength` | Relative Strength | strength | medium | `volume_block` |
| `strength_endurance` | Strength Endurance | strength | high | `density` |
| `power` | Power / Explosiveness | strength | high | `linear_load` |
| `aerobic_base` | Aerobic Base | aerobic | low | `intensity_split_shift` |
| `anaerobic_intervals` | Anaerobic Intervals | intervals | high | `time_to_task` |
| `mixed_modal_conditioning` | Mixed Modal Conditioning | intervals | high | `density` |
| `durability` | Durability / Work Capacity | durability | medium | `time_to_task` |
| `mobility` | Mobility / Tissue Prep | skill | low | `range_progression` |
| `movement_skill` | Movement / Skill | skill | medium | `complexity` |
| `combat_sport` | Combat Sport | combat | high | `density` |
| `rehab` | Rehab | skill | low | `range_progression` |

**Modality families** (`vocabulary.yaml` `family`): `strength`, `aerobic`, `intervals`, `durability`, `skill`, `combat`.

**Phase kinds** (a phase's `kind`, an archetype's `applicable_phases`): `transition`, `base`, `build`, `specific`, `peak`, `taper`, `maintenance`, `deload`, `recovery`, `rehab`, `post_op`, `active`.

**Training levels**: `novice`, `intermediate`, `advanced`, `elite`.

**Slot types** (`slot_type`): `sets_reps`, `time_domain`, `distance`, `amrap`, `amrap_movement`, `emom`, `for_time`, `rounds_for_time`, `skill_practice`, `static_hold`.

**Intensities** (a slot's `intensity`): `max`, `max_effort`, `heavy`, `submaximal`, `progressing`, `moderate`, `medium`, `light`, `low`, `high`, `bodyweight`, `zone1`, `zone2`, `zone3`, `zone4`, `zone4_5`, `zone5`.

**Progression models** (a framework's or modality's `progression_model`): `linear_load`, `density`, `volume_block`, `complexity`, `time_to_task`, `intensity_split_shift`, `rpe_autoregulation`, `pentathlon_rpm`, `range_progression`, `as_written`.

**Archetype categories**: `strength`, `conditioning`, `movement_skill`, `gpp_durability`, `kettlebell`, `recovery`, `rehab`, `combat_sport`.

**Exercise categories**: `barbell`, `kettlebell`, `bodyweight`, `aerobic`, `loaded_carry`, `carries`, `sandbag`, `mobility`, `skill`, `rehab`, `accessory`. **Effort**: `low`, `medium`, `high`, `max`.

**Philosophy `intensity_model`**: `linear_progression`, `polarized_80_20`, `polarized_80_20_uphill`, `block_periodization`, `autoregulation_rpe`, `constant_variation`, `skill_based`, `hard_easy_alternation`, `operator_readiness`.

**Philosophy `progression_philosophy`**: `load_based`, `volume_based`, `complexity_based`, `time_based`, `density_based`, `feel_based`, `rpm_based`, `range_based`.

**Equipment** (`data/commons/constraints/equipment.yaml`; an exercise may also say `none`; a package adds its own in `vocabulary.yaml`): `barbell`, `rack`, `plates`, `kettlebell`, `dumbbell`, `pull_up_bar`, `rings`, `parallettes`, `hangboard`, `rope`, `box`, `dip_belt`, `rower`, `bike`, `ski_erg`, `pool`, `ruck_pack`, `sandbag`, `jump_rope`, `resistance_band`, `ghd`, `medicine_ball`, `sled`, `tire`, `sledgehammer`, `cable_machine`, `hurdles`, `agility_ladder`, `training_partner`, `open_space`.

**Body regions** (a package pattern's `regions`): `lower`, `upper_push`, `upper_pull`, `trunk`, `cardio`.

**Movement patterns that load a region** (`data/commons/recovery_regions.yaml`): `squat`, `hip_hinge`, `hip_extension`, `knee_extension`, `knee_flexion`, `lunge`, `step_up`, `single_leg`, `jump`, `ballistic`, `olympic_lift`, `vertical_push`, `horizontal_push`, `elbow_extension`, `shoulder_flexion`, `shoulder_abduction`, `vertical_pull`, `horizontal_pull`, `elbow_flexion`, `grip`, `shoulder_external_rotation`, `loaded_carry`, `farmer_carry`, `rack_carry`, `get_up`, `rotation`, `spinal_extension`, `spinal_flexion`, `lateral_flexion`, `core_flexion`, `core_stability`, `hip_flexion`, `isometric`, `locomotion`, `aerobic_monostructural`.

**Movement patterns that load nothing**: `mobilization`, `stretching`, `breathing`, `balance`, `ankle_dorsiflexion`, `ankle_plantarflexion`, `hip_external_rotation`, `hip_abduction`.

**Slot-filter aliases** (a slot's `exercise_filter.movement_pattern` may name one; anything else is matched as a pattern directly): `squat` (or: squat), `hinge` (or: hip_hinge), `hip_hinge` (or: hip_hinge), `carry` (or: loaded_carry), `loaded_carry` (or: loaded_carry), `rotation` (or: rotation), `locomotion` (or: locomotion), `ballistic` (or: ballistic), `olympic` (or: olympic_lift), `olympic_lift` (or: olympic_lift), `isometric` (or: isometric), `horizontal_push` (or: horizontal_push), `vertical_push` (or: vertical_push), `horizontal_pull` (or: horizontal_pull), `vertical_pull` (or: vertical_pull), `press` (or: horizontal_push, vertical_push), `push` (or: horizontal_push, vertical_push), `pull` (or: horizontal_pull, vertical_pull), `aerobic` (or: aerobic_monostructural, locomotion), `swing` (and: hip_hinge, ballistic), `clean` (and: hip_hinge, olympic_lift), `jerk` (and: vertical_push, ballistic), `snatch` (and: hip_hinge, ballistic, olympic_lift), `tgu` (and: isometric, vertical_push), `skill` (category: skill), `farmer_carry` (or: farmer_carry), `rack_carry` (or: rack_carry), `step_up` (or: step_up), `ruck` (and: locomotion, loaded_carry).

**Injury flags** (an exercise's `contraindicated_with`, a package pattern's `excluded_by`): `knee_meniscus_post_op`, `shoulder_impingement`, `shoulder_instability`, `lumbar_disc`, `ankle_sprain`, `wrist_injury`, `hip_flexor_strain`, `tennis_elbow`, `golfers_elbow`, `neck_strain`, `achilles_tendinopathy`, `patellar_tendinopathy`.

**Analytics primitives** (`analytics.yaml` `primitive`): `aerobic_efficiency`, `benchmark_level`, `distance`, `duration`, `hold_seconds`, `load_at_rpe`, `rate`, `rounds`, `session_completion`, `set_load`, `unlocks`, `zone_minutes`.

**Watch templates** (`watch.yaml` `template`): `sets`, `hold`, `interval`, `rounds`, `for_time`, `distance`, `timed`, `round_timer`.
<!-- /gen:values -->

## 6. How a package is checked

One call checks a folder, in order, and stops at the first stage that finds something
(`src/package_gate.check_package`; the MCP server's `validate_package`; `POST
/api/packages` with `dry_run: true`):

<!-- gen:gate -->
| Stage | Passes when |
|---|---|
| `files` | A `philosophy.yaml` whose `id` is the folder's name. |
| `schema` | Every file against its schema and the checks beside it (section 6). |
| `ids` | The files a package needs; no id another package or the commons declare; every modality, movement pattern, equipment, phase kind, standard and watch template it names is the commons', its own (`vocabulary.yaml`, `standards.yaml`) or one it borrows; for an athlete's own package, the owner's prefix on every id it declares. |
| `smoke` | Every phase of every track validates and generates one week on the framework it names — an intermediate with every implement, at the framework's ideal days and minutes — and a phase that tests places every test. |
| `provenance` | Nothing in those programs comes from outside the package and what it borrows. |
<!-- /gen:gate -->

The answer is data: `ok`, and `problems`, each `{stage, code, file, message}` — fix the
file a problem names and check again. `warnings` do not stop an install: a modality in
scope that no archetype serves, and what the generated weeks could not cover with every
implement to hand — a session no archetype serves (`unfilled_session`), one replaced by
another modality (`substituted_session`), a slot no exercise fills (`unfilled_slot`). They
are nearly always authoring, and the app's builder treats them as problems in a package it
writes. `skipped` lists the stages that did not run and why;
a result with anything skipped is not `ok`.

Beside the schemas, the `schema` stage holds a package to:

- track and phase ids unique; a phase's `framework_id` is one of this package's frameworks;
- a templated phase's day categories are its framework's, each naming this package's
  `pool_only` archetypes;
- a test archetype measures a standard that exists and names its `exercise_ids`;
- `vocabulary.yaml`: a known family, progression model, body region, injury flag and
  colour family; no id the commons define.

## 7. An athlete's own package

A package installed for one athlete (`POST /api/packages {files: {path: yaml text}}`) is
private to them and read beside the shipped packages only in their own requests.

<!-- gen:limits -->
- at most **200 files** and **512 KB** of YAML in a package, and **20 packages** an athlete;
- only the files the table above marks, as lower-case paths: `analytics.yaml`, `exercise_media.yaml`, `exercises.yaml`, `fidelity.yaml`, `level_seeds.yaml`, `philosophy.yaml`, `standards.yaml`, `training_contract.yaml`, `vocabulary.yaml`, `watch.yaml`, `frameworks/<id>.yaml`, `archetypes/<…>/<id>.yaml` (up to three subfolders);
- the package id is 3–64 characters of `a-z`, `0-9` and `_`, starting with a letter;
- every id the package declares for itself — the package, frameworks, archetypes, standards and their categories, modalities, movement patterns, equipment — starts with the owner's prefix, `u<8 hex>_` (`GET /api/packages` says it). An exercise id either carries it or is an exercise a shipped package declares, which the package may re-declare with its own loads.
<!-- /gen:limits -->

It can never replace anything shipped: a shipped framework, archetype or philosophy id keeps
the shipped copy.

## 8. Common mistakes

- **A phase kind used as a phase id.** `kind: base` is shared vocabulary; `id` and `name`
  are the method's own.
- **A modality nothing serves.** A framework schedules a modality for which the package has
  no archetype that applies in that phase kind and level: the session is substituted or
  dropped.
- **A slot nothing can fill.** Its filter names a pattern or category none of the package's
  exercises has, or every candidate needs equipment or a level the check's athlete lacks.
- **An id that is not the package's.** Prefix frameworks and archetypes with the package's
  own word; a collision is refused.
- **A new modality or pattern named but not declared.** Naming it in `scope` or on an
  exercise does not define it: `vocabulary.yaml` does.
- **A week that does not add up.** `sessions_per_week` totals more than the days the
  framework says it needs, or schedules `mobility` on a four-day week.
- **`volume_reduction_pct` read as the cut.** It is the share a deload week keeps.

## 9. A worked example

A package written from nothing: its own modality, movement pattern, implement and
exercises, one track of two phases on the modality scheduler. It passes every stage above
(`test_package_gate.py` holds it to them), and this section is printed from its files
(`test_packages/scratch_minimal/`).

<!-- gen:example -->
`analytics.yaml`

```yaml
# What progress means for the method: the stone getting heavier, the days done.
id: scratch_minimal

progress:
  - id: stone_load
    label: Stone to shoulder
    primitive: set_load
    headline: true
    scope: {exercises: [scratch_minimal_stone_to_shoulder]}

  - id: days_done
    label: Days done as written
    primitive: session_completion
```

`exercises.yaml`

```yaml
exercises:
  - id: scratch_minimal_stone_to_shoulder
    name: Stone to shoulder
    category: accessory
    modality: [scratch_odd_object_strength]
    equipment: [scratch_stone]
    effort: high
    bilateral: false
    movement_patterns: [scratch_shouldering]
    typical_volume: {sets: 5, reps: 3}
    starting_load_kg: {novice: 20, intermediate: 40, advanced: 60, elite: 80}
    weekly_increment_kg: 2.5
    sessions_per_week: 2

  - id: scratch_minimal_stone_carry
    name: Stone carry
    category: accessory
    modality: [scratch_odd_object_strength]
    equipment: [scratch_stone]
    effort: medium
    movement_patterns: [loaded_carry]
    # What a pattern does not say: the flags that rule this exercise out.
    contraindicated_with: [lumbar_disc]
    typical_volume: {sets: 3, reps: 1}
    starting_load_kg: {novice: 20, intermediate: 40, advanced: 60, elite: 80}
    weekly_increment_kg: 2.5
    sessions_per_week: 2

  - id: scratch_minimal_walk
    name: Easy walk
    category: aerobic
    modality: [aerobic_base]
    equipment: [open_space]
    effort: low
    movement_patterns: [locomotion, aerobic_monostructural]
    typical_volume: {duration_sec: 2400}
```

`philosophy.yaml`

```yaml
id: scratch_minimal
# A package written from nothing the repository ships: its own modality,
# movement pattern, implement and exercises (docs/schemas/PACKAGE_SPEC.md
# prints it as the worked example, and tools/gen_package_spec.py fails when
# they part). Small on purpose — one track, two phases, one framework on the
# modality scheduler — and held to every gate by test_package_gate.py and
# test_package_dropin.py. Never shipped, never graded.
name: "Odd-object strength (from scratch)"
core_principles:
  - lift_awkward_things_from_the_ground
  - easy_walking_between_hard_days
  - one_progression_at_a_time
scope:
  - scratch_odd_object_strength
  - aerobic_base
bias:
  - scratch_odd_object_strength
required_equipment:
  - scratch_stone
# Only this package's sessions and exercises may reach its programs.
self_contained: true
intensity_model: hard_easy_alternation
progression_philosophy: load_based

primary_track_id: standard
tracks:
  - id: standard
    name: "Stone work"
    description: "Two stone days and two easy walks a week; eight weeks, heavier in the second four."
    phases:
      - id: scratch_foundation
        name: "Foundation"
        kind: base
        weeks: 4
        framework_id: scratch_minimal_week
        focus: "Learn the lift"
        description: "Light stones, the same lift every session, until shouldering is unremarkable."
      - id: scratch_loading
        name: "Loading"
        kind: build
        weeks: 4
        framework_id: scratch_minimal_week
        focus: "Heavier stones"
        description: "The same week, a heavier stone each week."

sources:
  - "Written for the repository's tests; no published source."
```

`vocabulary.yaml`

```yaml
# What this package adds to the commons' vocabulary, for itself
# (docs/schemas/vocabulary.schema.json). Never an id the commons define.
modalities:
  - id: scratch_odd_object_strength
    name: Odd-object strength
    description: Lifting, shouldering and carrying stones and other awkward loads.
    recovery_cost: high
    recovery_hours_min: 48
    session_position: first
    priority_tier: 1
    typical_duration_minutes: 45
    progression_model: linear_load
    family: strength
    compatible_in_session_with: [mobility]
    display:
      label: Odd object
      short: Stone
      order: 20
      color: '#ef4444'
      tint: red
      text_shade: 700
      icon: {web: Weight, ios: figure.strengthtraining.traditional, watch: figure.strengthtraining.traditional}

movement_patterns:
  - id: scratch_shouldering
    name: Ground to shoulder
    regions: {lower: 1, trunk: 1, upper_pull: 0.5}
    # The injury flags that rule it out. Required: [] would say none does.
    excluded_by: [lumbar_disc]

equipment:
  - {id: scratch_stone, label: Atlas stone}
```

`archetypes/scratch_minimal_easy_walk.yaml`

```yaml
id: scratch_minimal_easy_walk
name: "Easy walk"
modality: aerobic_base
category: conditioning
duration_estimate_minutes: 40
applicable_phases: [base, build]
training_levels: [novice, intermediate, advanced, elite]

slots:
  - role: walk
    slot_type: time_domain
    duration_minutes: 40
    intensity: zone2
    exercise_filter:
      exercise_ids: [scratch_minimal_walk]

sources:
  - "Written for the repository's tests."
```

`archetypes/scratch_minimal_stone_day.yaml`

```yaml
id: scratch_minimal_stone_day
name: "Stone day"
modality: scratch_odd_object_strength
category: strength
duration_estimate_minutes: 40
required_equipment:
  - scratch_stone
applicable_phases: [base, build]
training_levels: [novice, intermediate, advanced, elite]

slots:
  - role: stone_to_shoulder
    slot_type: sets_reps
    sets: 5
    reps: 3
    intensity: heavy
    rest_sec: 120
    exercise_filter:
      movement_pattern: scratch_shouldering   # this package's own pattern, named directly
  - role: stone_carry
    slot_type: sets_reps
    sets: 3
    reps: 1
    intensity: moderate
    rest_sec: 90
    exercise_filter:
      exercise_ids: [scratch_minimal_stone_carry]

sources:
  - "Written for the repository's tests."
```

`frameworks/scratch_minimal_week.yaml`

```yaml
id: scratch_minimal_week
name: "Stone week"
source_philosophy: scratch_minimal

goals_served:
  - scratch_odd_object_strength

# The modality scheduler builds the week from these.
sessions_per_week:
  scratch_odd_object_strength: 2
  aerobic_base: 2

intensity_distribution:
  zone1_2_pct: 0.5
  zone3_pct: 0.0
  zone4_5_pct: 0.0
  max_effort_pct: 0.5

progression_model: linear_load

applicable_when:
  training_level: [novice, intermediate, advanced, elite]
  days_per_week_min: 3
  days_per_week_max: 6

deload_protocol:
  frequency_weeks: 4
  volume_reduction_pct: 0.6
  intensity_change: maintain

expectations:
  min_weeks: 4
  ideal_weeks: 8
  min_days_per_week: 3
  ideal_days_per_week: 4
  min_session_minutes: 30
  ideal_session_minutes: 45
  supports_split_days: false

sources:
  - "Written for the repository's tests."
```
<!-- /gen:example -->
