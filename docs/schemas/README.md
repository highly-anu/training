# Schema Reference

JSON Schema (Draft-07) definitions for every data layer in the training system. All data files written in Phase 2 must conform to the relevant schema here.

---

## Schemas

| File | What it governs | Location in repo |
|------|-----------------|-----------------|
| `philosophy.schema.json` | One entry per training source (SS, UA, Gym Jones, etc.) | `data/packages/{name}/philosophy.yaml` |
| `framework.schema.json` | One entry per methodological framework | `data/packages/{name}/frameworks/{id}.yaml` |
| `modality.schema.json` | One entry per training domain | `data/modalities/{id}.yaml` (shared, rarely edited) |
| `archetype.schema.json` | One entry per workout shape | `data/packages/{name}/archetypes/{category}/{id}.yaml` |
| `exercise.schema.json` | One entry per exercise | `data/packages/{name}/exercises.yaml` (list under `exercises:` key) |
| `goal_profile.schema.json` | One entry per goal type | `data/goals/{id}.yaml` |
| `constraints.schema.json` | Runtime athlete input (not a library) | Input to generator |
| `benchmark.schema.json` | One entry per measurable standard | `data/benchmarks/*.yaml` |

### Package structure

Each training methodology lives in its own self-contained package directory:

```
data/packages/{name}/
  philosophy.yaml          ← the package's philosophy (exactly one)
  frameworks/
    {id}.yaml              ← one file per framework (usually one)
  archetypes/
    strength/              ← barbell/free weight strength sessions
    conditioning/          ← aerobic, intervals, AMRAPs, circuits
    kettlebell/            ← KB-specific sessions
    gpp_durability/        ← carries, sandbag, rucking
    movement_skill/        ← mobility, joint prep, skill practice
  exercises.yaml           ← all exercises for this package (list under exercises: key)
```

Modalities are shared infrastructure (`data/modalities/`) — they are not owned by any package and almost never change.

---

## Shared enumerations

These values appear across multiple schemas. Adding a new value to any enum requires updating every schema that references it.

### Modality IDs
```
max_strength, strength_endurance, relative_strength,
aerobic_base, anaerobic_intervals, mixed_modal_conditioning,
power, mobility, movement_skill, durability,
combat_sport, rehab
```

### Equipment IDs
```
barbell, rack, plates, kettlebell, dumbbell, pull_up_bar,
rings, parallettes, rower, bike, ski_erg, ruck_pack,
sandbag, sled, tire, medicine_ball, resistance_band,
rope, box, ghd, jump_rope, open_space
```

### Movement Pattern IDs

**Exercise `movement_patterns` field** — use these exact IDs:
```
hip_hinge, squat, horizontal_push, horizontal_pull,
vertical_push, vertical_pull, loaded_carry, rotation,
hip_flexion, knee_extension, locomotion, ballistic,
olympic_lift, isometric, aerobic_monostructural,
farmer_carry, rack_carry, step_up
```

**Archetype `exercise_filter.movement_pattern` field** — these are *aliases* resolved at runtime, not raw pattern IDs. The resolver in `data/commons/movement_patterns.yaml` expands them to one or more of the exercise pattern IDs above:
```
squat       hinge / hip_hinge    carry / loaded_carry    rotation
locomotion  ballistic            olympic / olympic_lift   isometric
horizontal_push  vertical_push  horizontal_pull  vertical_pull
press / push     pull            aerobic          swing
clean       jerk    snatch    tgu    skill    ruck
farmer_carry    rack_carry    step_up
```

### Training Phase IDs
```
active, base, build, peak, taper, deload, maintenance, rehab, post_op
```

### Progression Model IDs
```
linear_load, density, volume_block, complexity, time_to_task,
intensity_split_shift, rpe_autoregulation, pentathlon_rpm, range_progression
```

### Injury Flag IDs
```
knee_meniscus_post_op, shoulder_impingement, shoulder_instability,
lumbar_disc, ankle_sprain, wrist_injury, hip_flexor_strain,
tennis_elbow, golfers_elbow, neck_strain,
achilles_tendinopathy, patellar_tendinopathy
```

---

## Key design decisions

**Why `scope` on philosophy?**
Prevents SS loading rules from being applied to conditioning sessions. Each philosophy only governs the modalities listed in its `scope` field. A combined SS + UA program uses SS rules for strength sessions and UA rules for aerobic sessions.

**Why `requires`/`unlocks` on exercise rather than a separate graph file?**
Keeps the DAG embedded in the data. The generator builds the prerequisite graph at runtime by collecting all `requires`/`unlocks` edges. A separate graph file would go stale whenever exercises are added.

**Why `constraint_priority` (hard/soft) on constraints?**
Some constraints are absolute (injury flags, equipment), others are preferences (session time). Marking them allows the validator to distinguish "cannot do this" from "prefer not to" when checking goal feasibility.

**Why `phase_sequence` on goal profile rather than in the framework?**
Different goals using the same framework (e.g. concurrent training) can have different phase sequences. Alpine climbing and BJJ competition prep might both use concurrent training but require different periodization structures around their event dates.

**Why `slot_type` on archetype slots?**
The generator needs to know how to represent a slot to the athlete (sets×reps vs. 20-min AMRAP vs. 400m run). Different slot types also have different scaling rules.

---

## Validating data files

Validate YAML files against these schemas using any JSON Schema validator. Example with Python:

```python
import json, yaml
from jsonschema import validate

schema = json.load(open('docs/schemas/exercise.schema.json'))
data   = yaml.safe_load(open('data/packages/starting_strength/exercises.yaml'))

for exercise in data['exercises']:
    validate(instance=exercise, schema=schema)
```
