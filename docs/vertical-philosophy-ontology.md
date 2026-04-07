# Plan: Vertical Philosophy Package Ontology



## Context



The current `data/` layout is horizontal: one global directory per asset type. Philosophies are pure descriptive metadata with no structural ownership over the archetypes, frameworks, and exercises they produced. Two hardcoded Python dicts encode knowledge that should live in YAML (`_CADENCE_OPTIONS` in scheduler.py, `_STARTING_LOADS` in progression.py).



Goals:

1. Reorganize into vertical philosophy packages — each is a self-contained drop-in folder

2. Eliminate the hardcoded gaps by migrating data to YAML (cadence patterns, starting loads)

3. Support package-scoped exercise prescription — wildman's `kb_swing` can start at 16 kg novice while horsemen's starts at 24 kg, with no silent overwrites



---



## Important: Two Hardcoded Gaps Are Already Half-Solved



Before reading the plan, note two things the codebase already does:



**scheduler.py line 343** already reads `cadence_options` from the framework YAML dict:

```python

yaml_options = (framework or {}).get('cadence_options', {})

options = yaml_options.get(days) or _CADENCE_OPTIONS.get(framework_id, {}).get(days)

```

`_CADENCE_OPTIONS` is already the *fallback*. Adding `cadence_options` to each framework YAML immediately activates YAML-driven cadence for that framework. No scheduler code change needed.



**progression.py line 62** already reads `starting_load_kg` from the exercise dict:

```python

start = (

    exercise.get('starting_load_kg', {}).get(level)

    or _STARTING_LOADS.get(ex_id, {}).get(level)

)

```

Adding `starting_load_kg` / `weekly_increment_kg` fields to exercise YAMLs immediately activates per-exercise prescription. Use these exact field names — they already match. No progression code change needed.



---



## New Directory Structure



```

data/

  commons/

    modalities/             ← move from data/modalities/

    constraints/            ← move from data/constraints/

    movement_patterns.yaml  ← move from data/movement_patterns.yaml

  goals/                    ← unchanged

  packages/

    <philosophy_id>/

      philosophy.yaml       ← move from data/philosophies/<id>.yaml

      exercises.yaml        ← exercises this philosophy owns (with prescription fields)

      archetypes/           ← archetypes sourced from this philosophy

      frameworks/           ← framework YAML with cadence_options field

```



---



## Package → Asset Mapping



| Package | Framework | Primary Archetypes | Sources field match |

|---|---|---|---|

| `starting_strength` | `linear_progression` | `3x5_linear`, `hlm`, `5x5` | "Starting Strength" |

| `wildman_kettlebell` | `kb_pentathlon` | `kb_ballistic_session`, `kb_double_strength`, `kb_pentathlon_training`, `tgu_practice` | "Wildman", "RKC" |

| `gym_jones` | `block_periodization` | `gym_jones_*`, `emom_strength`, `barbell_power_complex`, `gym_jones_tgu_recovery` | "Gym Jones" |

| `horsemen_gpp` | `concurrent_training`, `gpp_circuits` | `horsemen_power_endurance`, `ruck_session`, `loaded_carry_circuit`, `sandbag_complex` | "Horsemen" |

| `crossfit` | `emom_amrap` | `mixed_modal_amrap`, `tabata`, `bodyweight_circuit` | "CrossFit" |

| `uphill_athlete` | `polarized_80_20` | `long_zone_2`, `threshold_intervals` | "Uphill Athlete" |

| `ido_portal` | `high_frequency_skill` | `movement_flow`, `skill_ladder` | "Ido Portal" |

| `marcus_filly` | `rpe_autoregulation` | `bodyweight_strength_session` | "Marcus Filly" |

| `atg` | `atg_joint_health` | `rehab_protocol` | "ATG" |

| `kelly_starrett` | `kelly_starrett_mobility` | `joint_prep_circuit`, `endurance_mobility`, `grappling_mobility`, `strength_mobility` | "Kelly Starrett" |

| `bjj` | `bjj_performance` | `bjj_class`, `grappling_sc` | "BJJ" |



**Archetypes with multiple sources** (e.g. `kb_ballistic_session` lists Wildman, RKC, Gym Jones, Horsemen) — assign to the first/primary source (Wildman for kb_ballistic_session). Loader deduplicates by `id`; `_package` is set to the first-seen owner.



---



## Data Flow After Refactor



```

                     ┌─────────────────────────────────┐

                     │          loader.py               │

                     │                                  │

  packages/*/        │  load_all_exercises()            │

  exercises.yaml ───►│  → global_index (flat)           │

                     │  → exercises_by_package          │

                     │                                  │

  packages/*/        │  load_all_archetypes()           │

  archetypes/**  ───►│  → arch['_package'] annotated    │

                     │                                  │

  packages/*/        │  load_framework(id)              │

  frameworks/*.yaml─►│  → includes cadence_options      │

                     └──────────┬──────────────────────┘

                                │ load_all_data()

                                │ {exercises, exercises_by_package,

                                │  archetypes, modalities, injury_flags}

                                ▼

                     ┌─────────────────────────┐

                     │       generator.py       │

                     │                          │

                     │  passes exercises_by_    │

                     │  package to populate_    │

                     │  session()               │

                     └──────────┬───────────────┘

                                │

                                ▼

                     ┌─────────────────────────┐

                     │      selector.py         │

                     │  populate_session():     │

                     │  arch._package →         │

                     │  merge pkg fields over   │

                     │  global for that arch    │

                     │  → select_exercise()     │

                     └─────────────────────────┘

```



---



## Code Changes



### 1. `src/loader.py` — main target



Add path constants:

```python

_COMMONS_DIR  = os.path.join(_DATA_DIR, 'commons')

_PACKAGES_DIR = os.path.join(_DATA_DIR, 'packages')

```



**`load_all_exercises()` — dual-index:**

```python

def load_all_exercises() -> tuple[dict, dict]:

    global_index = {}

    by_package = {}

    for path in sorted(glob.glob(os.path.join(_PACKAGES_DIR, '*', 'exercises.yaml'))):

        pkg_id = os.path.basename(os.path.dirname(path))

        pkg_exercises = {}

        for ex in _load_yaml(path).get('exercises', []):

            ex['_package'] = pkg_id

            pkg_exercises[ex['id']] = ex

            if ex['id'] not in global_index:

                global_index[ex['id']] = ex

        by_package[pkg_id] = pkg_exercises

    return global_index, by_package

```



**`load_all_archetypes()` — infer `_package` from path:**

```python

def load_all_archetypes() -> list:

    result = []

    seen_ids = set()

    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'archetypes', '**', '*.yaml'), recursive=True):

        arch = _load_yaml(path)

        arch_id = arch.get('id')

        if arch_id not in seen_ids:

            seen_ids.add(arch_id)

            parts = path.replace('\\', '/').split('/')

            pkg_idx = parts.index('packages') + 1

            arch['_package'] = parts[pkg_idx]

            result.append(arch)

    return result

```



**`load_all_data()` — expose both indexes:**

```python

def load_all_data() -> dict:

    exercises, exercises_by_package = load_all_exercises()

    return {

        'modalities': load_all_modalities(),

        'archetypes': load_all_archetypes(),

        'exercises': exercises,

        'exercises_by_package': exercises_by_package,

        'injury_flags': load_injury_flags(),

    }

```



**`load_framework()`** — scan packages:

```python

def load_framework(framework_id: str) -> dict:

    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', f'{framework_id}.yaml')):

        return _load_yaml(path)

    raise FileNotFoundError(f"Framework '{framework_id}' not found")

```



**`load_all_modalities()`** — update glob to `commons/modalities/`



**`load_injury_flags()`** — update path to `commons/constraints/injury_flags.yaml`



**`load_philosophies()`** — scan `packages/*/philosophy.yaml`; update `framework_dir` and `goal_dir` scans accordingly



**`load_movement_patterns()` (new)** — load from `commons/movement_patterns.yaml`



### 2. `src/selector.py` — two changes



**a) Update `_mp_path`** (line 15):

```python

_mp_path = _os.path.join(_os.path.dirname(__file__), '..', 'data', 'commons', 'movement_patterns.yaml')

```



**b) Package-scoped exercise merge in `populate_session()`** — add optional param and merge logic:

```python

def populate_session(

    session, goal, constraints, exercises, archetypes,

    injury_flags_data, phase, week_number,

    recent_arch_ids=None, recent_ex_ids=None,

    collect_trace=False, forced_archetype=None,

    exercises_by_package=None,          # NEW

):

    ...

    # After arch is selected, build merged exercise view:

    arch_package = arch.get('_package') if arch else None

    if arch_package and exercises_by_package and arch_package in exercises_by_package:

        pkg_exs = exercises_by_package[arch_package]

        exercises = {**exercises, **{

            ex_id: {**exercises[ex_id], **pkg_ex} if ex_id in exercises else pkg_ex

            for ex_id, pkg_ex in pkg_exs.items()

        }}

    # existing slot-filling code continues unchanged

```



### 3. `src/generator.py` — one line change



At line 209, pass `exercises_by_package`:

```python

populated = populate_session(

    session, goal, constraints, exercises, archetypes,

    injury_flags_data, phase, week_in_phase,

    recent_arch_ids, recent_ex_ids,

    collect_trace=include_trace,

    exercises_by_package=data.get('exercises_by_package'),   # NEW

)

```



### 4. `src/scheduler.py` — no code change needed



The `_select_cadence()` function already reads `cadence_options` from the framework YAML (line 343). Adding the field to framework YAMLs is sufficient. The `_CADENCE_OPTIONS` dict can be deleted once all 8 frameworks carry `cadence_options` (optional cleanup pass at end).



### 5. `src/progression.py` — no code change needed



`_linear_load()` already reads `starting_load_kg` and `weekly_increment_kg` from exercise dict (lines 62-64). Adding these fields to per-package `exercises.yaml` entries activates them immediately.



### 6. No changes needed: `validator.py`, `output.py`, `summary.py`, `api.py`, frontend



---



## Migration Steps (in order)



1. **Create directory skeleton**

   ```

   data/commons/modalities/

   data/commons/constraints/

   data/packages/<each_of_11_ids>/

   data/packages/<each_id>/archetypes/

   data/packages/<each_id>/frameworks/

   ```



2. **Move infrastructure to commons**

   - `data/modalities/*.yaml` → `data/commons/modalities/`

   - `data/constraints/*.yaml` → `data/commons/constraints/`

   - `data/movement_patterns.yaml` → `data/commons/movement_patterns.yaml`



3. **Move philosophies**

   - `data/philosophies/<id>.yaml` → `data/packages/<id>/philosophy.yaml`



4. **Move + augment frameworks** ← _do all three augmentations in this single edit pass_

   - `data/frameworks/<fw>.yaml` → `data/packages/<source_philosophy>/frameworks/<fw>.yaml`

   - **Add `cadence_options`** to each — data taken from `_CADENCE_OPTIONS` in scheduler.py. `emom_amrap` and `kb_pentathlon` have no entry; use evenly-spaced defaults from `_DEFAULT_SPREAD`.

   - **Add `min_sessions`** per modality — the framework's absolute floor that survives priority scaling. Prevents the allocation math from rounding a "1 session guaranteed" modality down to 0. Example for `polarized_80_20`:
     ```yaml
     sessions_per_week:
       aerobic_base:        {target: 4, min: 3}
       anaerobic_intervals: {target: 1, min: 0}
       strength_endurance:  {target: 1, min: 1}
     ```
     `allocate_sessions()` in `scheduler.py` needs one extension: assign `min` sessions first, then distribute remaining slots proportionally. Frameworks using plain integer values continue to work unchanged — the function checks `isinstance(v, dict)`.

   - **Restructure `sessions_per_week` to be phase-aware** — allows the framework to define how its modality mix evolves across phases. Example for `polarized_80_20`:
     ```yaml
     sessions_per_week:
       base:  {aerobic_base: 4, strength_endurance: 1}
       build: {aerobic_base: 4, anaerobic_intervals: 1, strength_endurance: 1}
       peak:  {aerobic_base: 5, anaerobic_intervals: 1}
       taper: {aerobic_base: 3}
     ```
     `allocate_sessions()` gains a `phase` parameter and reads `framework['sessions_per_week'][phase]` when the value is a dict-of-dicts, falling back to the flat dict for unconverted frameworks. Scheduler.py change: `allocate_sessions(priorities, days_per_week, framework, phase=None)` — two dict-shape checks added, no logic restructuring. This resolves Issue 2 (no threshold intervals in build) at the framework level; see also `docs/before-migration.md` for the goal-level quick fix.



5. **Distribute archetypes to packages**

   - Each archetype YAML copied to its primary package per the mapping table above

   - No changes to archetype content



6. **Create per-package `exercises.yaml`** (most labor-intensive step)

   - Write a migration script (`scripts/migrate_exercises.py`) that:

     - Reads all existing `data/exercises/*.yaml`

     - Groups exercises by their `sources` field into packages

     - Outputs per-package `exercises.yaml` files

     - For exercises in `_STARTING_LOADS`/`_LINEAR_INCREMENTS`, adds `starting_load_kg` and `weekly_increment_kg` fields to the appropriate package's definition

   - Review output for cross-package exercises (exercises listed under multiple sources get duplicated with package-specific prescription fields)



7. **Update `src/loader.py`** — new scan paths, dual exercise index, `_package` annotation, `load_movement_patterns()`



8. **Update `src/selector.py`** — `_mp_path` update + `exercises_by_package` merge in `populate_session()`



9. **Update `src/generator.py`** — pass `exercises_by_package` to `populate_session()`



10. **Verify counts** — unique exercises and archetypes after dedup must match pre-migration baseline (198 exercises, ~35 archetypes)



11. **Optional cleanup** — delete `_CADENCE_OPTIONS` dict from scheduler.py once all frameworks verified



12. **Delete old directories** — `data/philosophies/`, `data/archetypes/`, `data/exercises/`, `data/modalities/`, `data/constraints/`, `data/frameworks/`, `data/movement_patterns.yaml`



---



## Critical Files



| File | Change type |

|---|---|

| `src/loader.py` | Rewrite scan paths; dual exercise index; `_package` annotation |

| `src/selector.py` | Two-line `_mp_path` update; `exercises_by_package` merge in `populate_session` |

| `src/generator.py` | Pass `exercises_by_package` kwarg |

| `data/frameworks/*.yaml` (8 files) | Add `cadence_options` block |

| `data/exercises/*.yaml` (9 files) | Source for migration script |

| `data/archetypes/**/*.yaml` (~35 files) | Copy to package dirs |

| `data/philosophies/*.yaml` (11 files) | Move to package dirs |



---



## Pipeline Step Analysis

What each of the five generation steps reads from data, what a package must provide, and what gaps remain.

---

### 1. Select Framework
**`scheduler.py:49` — `select_framework(goal, constraints)`**

Loads the framework YAML named by `goal.framework_selection.default_framework`. Evaluates `alternatives` condition strings to override it. Validates the chosen framework against `applicable_when.days_per_week_min/max`.

**Package provides:**
- `frameworks/<fw>.yaml` with `applicable_when`, `sessions_per_week`, `deload_protocol.frequency_weeks`
- `cadence_options: {N: [[day, ...], ...]}` — **already wired at line 343**; scheduler checks YAML before falling back to `_CADENCE_OPTIONS`. Adding this field to a framework YAML activates YAML-driven cadence with no code change.

**Remaining gap:** `_eval_condition()` (lines 28–46) only handles numeric comparisons (`<=`, `>=`, `==`, `<`, `>`). A package cannot express conditions like `equipment includes kettlebell` or `injury_flags is empty` in its `alternatives` list. Low urgency — most useful conditions are numeric.

---

### 2. Allocate Sessions
**`scheduler.py:152` — `allocate_sessions(priorities, days_per_week, framework)`**

Converts goal priority weights + `framework.sessions_per_week` ratios into integer session counts per modality using largest-remainder rounding. Framework modalities get slots proportional to their goal-priority share; goal modalities absent from the framework split the remainder.

**Package provides:**
- `framework.sessions_per_week` — ratio guide among modalities
- `goal.priorities` and `goal.phase_sequence[*].priority_override` — the weights

**No hardcoded gaps.** This step is fully data-driven. The rounding algorithm is a universal mathematical rule, not a philosophy-specific choice.

---

### 3. Select Archetype
**`selector.py:154` — `select_archetype(modality, constraints, phase, is_deload, goal, archetypes)`**

Filters all archetypes by modality ID, then by phase, training level, equipment, and duration. Scores survivors:
- `+6` equipment fully satisfied (vs. equipment_limited scaling)
- `+2` per `sources` entry that fuzzy-matches a goal `primary_sources` ID
- `−3` recently used
- `0 to −8` proportional to injury-blocked slot fraction

The sources match (lines 229–233) lowercases the source string and checks if a cleaned philosophy ID appears as a substring. `wildman_kettlebell` → `"wildman kettlebell"` → matches `"Wildman"` in sources.

**Package provides:**
- `archetypes/*.yaml` with correct `modality` (exact ID — the primary filter)
- `applicable_phases`, `training_levels`, `required_equipment`, `duration_estimate_minutes`, `scaling`
- `sources` list — controls the `+2` philosophy-match bonus; must contain strings that will substring-match the goal's `primary_sources` IDs after the underscore-replace transform

**Remaining gap:** `_package` is not yet used in scoring. Archetypes shared across packages (e.g. `5x5` in both `starting_strength` and `gym_jones`) get `_package` set to the first-seen owner. When a horsemen_gpp goal selects that archetype, its `_package` may point to `starting_strength`, and the exercise lookup will use starting_strength's prescription definitions rather than horsemen's. This is a low-impact gap — shared archetypes tend to have similar prescriptions — but it's the one place package-coherence scoring would matter.

---

### 4. Select Exercise
**`selector.py:318` — `select_exercise(slot, constraints, exercises, unlocked_ids, ...)`**

Filters the exercise pool to candidates that pass the slot's `exercise_filter` (movement_pattern alias + category), have available equipment, are accessible at this training level, are not injury-contraindicated, and are not inappropriate for the slot type (mobility/skill blocked from AMRAP/for_time slots). Scores:
- `−2` per recent use
- `+0.5` exercise has defined `movement_patterns`
- `+0.5` exercise has an `unlocks` list

**Package provides per exercise:**
- `movement_patterns` — primary matching mechanism via alias expansion
- `equipment` — equipment gate
- `category` — slot-type gate (AMRAP blocks `skill`/`mobility`/`rehab`)
- `requires` — used by `_get_unlocked()` to compute accessible exercises at each level
- `unlocks` — prerequisite graph traversal + `+0.5` scoring bonus
- `contraindicated_with` — hard exclusion by injury flag ID

**Remaining gap — `_LEVEL_CONCEPTS` (lines 24–47):** The "known at level X" seed set is hardcoded. `_get_unlocked()` starts from this seed and walks `unlocks` chains to expand the pool. A new package introducing a foundational exercise (e.g. `downward_dog` with `requires: []`) is technically accessible at novice — but if the exercise it unlocks requires a concept not in the seed set, that chain goes nowhere. More critically, if the package wants to declare "at intermediate, athletes already know `crow_pose`", there's no mechanism for that. **Fix:** packages provide an optional `level_seeds.yaml` file; loader merges all packages' seeds into `_LEVEL_CONCEPTS` at startup. Requires a small loader change and a one-line change in selector.py to accept the merged dict.

---

### 5. Calculate Load
**`progression.py:184` — `calculate_load(exercise, slot, progression_model, week_number, phase, training_level, is_deload)`**

Dispatches to sub-functions by `slot.slot_type`:

| slot_type | function | what it computes |
|---|---|---|
| `sets_reps` | `_linear_load` or `_rpe_autoregulation` | weight in kg, sets, reps |
| `time_domain` | `_time_to_task` | duration in minutes, zone target |
| `distance` | `_distance_slot` | distance in km |
| `amrap` / `emom` | `_density_slot` | time cap, target rounds |
| `skill_practice` | `_skill_slot` | fixed duration |
| `static_hold` | inline | sets, hold seconds |

**Package provides (already wired):**
- `starting_load_kg: {novice: N, intermediate: N, advanced: N, elite: N}` on the exercise — read at progression.py line 61
- `weekly_increment_kg: N` on the exercise — read at progression.py line 65

**Remaining hardcoded gaps:**

`_time_to_task` phase multipliers (lines 113–119) — `build` is always `1.25×`, `peak` always `1.40×`, `taper` always `0.60×`. A package whose Zone 2 base is 45 min and builds to 60 min (not 56 min) cannot express that ratio. **Fix:** add optional `phase_duration_multipliers: {build: 1.33, peak: 1.50}` to the archetype slot; `_time_to_task` reads these before using hardcoded values.

`_distance_slot` level multipliers (lines 144–147) — `novice: 0.5×`, `intermediate: 0.75×` etc. are universal. A package that starts novices at 5km (not 4km) cannot express that. **Fix:** add optional `level_distance_multipliers` to the slot YAML, same pattern.

`_SESSIONS_PER_WEEK` (lines 38–46) — controls how fast load accumulates per calendar week. A package that trains squat 4×/week will prescribe the same weekly increment as one that trains it 1×/week, making load progression wrong for the high-frequency package. **Fix:** add optional `sessions_per_week_default: N` to the exercise YAML; `_linear_load` checks this before the hardcoded dict.

---

### Gap Resolution Summary

| Gap | Status | Fix |
|---|---|---|
| `_CADENCE_OPTIONS` | ✅ Resolved — YAML field already wired | Add `cadence_options` to framework YAMLs |
| `_STARTING_LOADS` / `_LINEAR_INCREMENTS` | ✅ Resolved — YAML fields already wired | Add `starting_load_kg` / `weekly_increment_kg` to exercises |
| Movement pattern aliases | ✅ Already resolved | Moves to `commons/` |
| `_eval_condition` operator set | ⚠️ Low urgency | Would need engine change; most conditions are numeric |
| `_LEVEL_CONCEPTS` seed set | ⚠️ Needs fix | `level_seeds.yaml` per package + loader merge + 1-line selector change |
| `_time_to_task` phase multipliers | ⚠️ Needs fix | Add `phase_duration_multipliers` to slot YAML + 3-line progression change |
| `_distance_slot` level multipliers | ⚠️ Needs fix | Add `level_distance_multipliers` to slot YAML + 3-line progression change |
| `_SESSIONS_PER_WEEK` | ⚠️ Needs fix | Add `sessions_per_week_default` to exercise YAML + 1-line progression change |
| Package-coherence archetype scoring | ⚠️ Low urgency | `_package` bonus in `select_archetype()` scoring |

### Per-Layer Generalization Status After This Plan

| Layer | Before | After | Remaining |
|---|---|---|---|
| **Philosophy** | Reference only | Unchanged | No generation effect; no API endpoint |
| **Framework** | ❌ Engine blocked | ✅ YAML drop-in with `cadence_options` | No POST endpoint |
| **Modality** | ⚠️ YAML drop-in works | Unchanged | No POST endpoint |
| **Archetype** | ✅ POST endpoint exists | Unchanged (now in package dirs) | No PUT/DELETE |
| **Exercise** | ✅ POST exists; load imprecise | ✅ `starting_load_kg` precise per-package | No PUT/DELETE; `_LEVEL_CONCEPTS` seed |
| **Goal** | ❌ No endpoint | Unchanged | No endpoint |

---

## Why Remaining Gaps Can't Be Closed by Data Files Alone

Every remaining gap follows the same pattern: **packages can provide data, but the engine has to know to look for it.** A YAML field that the engine never reads has no effect. The gaps aren't missing data — they're places where the engine reads from a hardcoded Python structure instead of the data file. Closing each one requires a small code change that redirects the lookup before the fallback.

The pattern across all of them:

**`_LEVEL_CONCEPTS`** — built from hardcoded literals at module load time in `selector.py`. A package can ship a `level_seeds.yaml` right now and nothing happens. The loader would need to load it; the selector would need to accept the merged dict as a parameter instead of reading a module-level constant. Two code changes, neither architectural.

**`_time_to_task` phase multipliers and `_distance_slot` level multipliers** — inline numeric literals in the function body, not even a dict lookup. The functions don't inspect the slot dict for these values. Adding `phase_duration_multipliers` to a slot YAML does nothing until progression.py has a line reading `slot.get('phase_duration_multipliers', {}).get(phase, default)`. Trivial to add; still a code change.

**`_SESSIONS_PER_WEEK`** — same pattern as starting loads, just not yet wired. One additional check before the dict lookup: `exercise.get('sessions_per_week_default')`.

**`_eval_condition` operator set** — the evaluator is hardcoded in `scheduler.py`. A package can't ship a different condition evaluator without a plugin mechanism the engine doesn't have. This is the only gap that would require an architectural change (plugin hooks) rather than a small engine edit. For all practical purposes the numeric operators already cover every useful condition.

**The core constraint:** packages are YAML, the engine is Python. Every YAML field is inert until the Python code that calls into that field exists. The good news is that all the remaining fixes are 1–3 line edits in the engine — they're not architectural gaps, just wiring that hasn't been done yet.

---

## Multi-Philosophy Mixing

When a user generates a program from `general_gpp` (which has `primary_sources: [horsemen_gpp, crossfit, wildman_kettlebell, marcus_filly, kelly_starrett]`), here's what the engine actually does at each pipeline stage — and where the mixing breaks down.

### What works today

**Archetype selection does mix.** The `+2` source-match bonus pulls archetypes from all five referenced philosophies into competition per session slot. A session assigned `aerobic_base` might pick `long_zone_2` (crossfit/uphill_athlete), `tabata` (crossfit), or `horsemen_power_endurance` depending on recent history and equipment. The score-based selection means all installed packages compete fairly in every slot.

**Exercise variety does spread.** Because the recency penalty (`-2` per recent use, rolling 40-exercise window) discourages repetition and package-scoped exercise definitions differ slightly in their unlock chains, the mix of exercises across a multi-philosophy week reflects multiple philosophies naturally.

### What breaks down

**Framework selection picks exactly one.** The engine loads a single framework per generation run — the goal's `default_framework` or a matching alternative. For `general_gpp` that's `concurrent_training` from `horsemen_gpp`. Its `cadence_options`, `sessions_per_week` ratios, and `deload_protocol` come entirely from horsemen. CrossFit's `emom_amrap` and Wildman's `kb_pentathlon` framework are never loaded. Four of the five referenced philosophies have no structural input to the skeleton of the week.

**Exercise prescription anchors to the archetype's `_package`.** When a crossfit archetype wins a session slot, the exercise lookup merges `exercises_by_package['crossfit']` over the global index. If the crossfit package doesn't define `starting_load_kg` for `back_squat` but `starting_strength` does, the global fallback is used — which is the starting_strength prescription, not anything crossfit-specific. And if the archetype that wins the slot is shared (e.g. `5x5`, `_package: starting_strength`), the exercise definitions come from starting_strength even when the running goal is horsemen-dominant.

**No mechanism for per-modality framework blending.** The most impactful gap: a `general_gpp` user might want horsemen's schedule skeleton for strength sessions but uphill_athlete's polarized cadence for aerobic sessions. The engine has no way to express this. One framework governs all modalities for the whole week.

### What would fully solve it

**Near-term fix (extend the goal YAML schema):** Add a `modality_frameworks` field to goals:

```yaml
# In general_gpp.yaml
framework_selection:
  default_framework: concurrent_training   # skeleton for everything
  modality_frameworks:
    aerobic_base: polarized_80_20          # uphill cadence for aerobic sessions
    power: kb_pentathlon                   # wildman cadence for KB sessions
```

The scheduler loads the base framework for the week skeleton, then checks `modality_frameworks` when assigning those specific modalities to days — applying a different cadence pattern just for those sessions. This is an extension to `_build_day_pool` and `assign_to_days`, implementable without redesigning the engine.

**Archetype package priority for shared archetypes:** Replace first-wins `_package` annotation with a list of all owning packages, then at exercise resolution time prefer the package matching the goal's first primary source:

```python
# Loader: track all sources, not just first-seen
arch['_packages'] = ['starting_strength', 'gym_jones']

# Selector: prefer the package that aligns with the goal's philosophy priority
arch_package = next(
    (p for p in arch.get('_packages', []) if p in goal_primary_sources),
    arch.get('_packages', [None])[0]
)
```

This ensures that when a horsemen-dominant goal selects a shared archetype, horsemen's exercise prescriptions are used, not whichever package happened to be loaded first.

**Long-term (out of scope for this plan):** A true multi-framework compositor that builds the week skeleton by modality rather than by one global framework. This would require a significant redesign of `schedule_week` in scheduler.py.

---

## Code Changes for Maximum Benefit

All changes needed beyond the core migration plan, organized by file. These are the edits that turn the package structure from "reorganized files" into a fully exploitable architecture.

---

### `src/loader.py`

These changes are required for the migration (already in the plan) plus two additions:

**Required (in plan):** new scan paths, dual exercise index, `_package` annotation, `load_framework()` scan, `load_philosophies()` scan.

**Addition 1 — `load_level_seeds()`:** merge `level_seeds.yaml` from all packages into a single dict:
```python
def load_level_seeds() -> dict[str, set]:
    """Merge per-package level seed sets. Called once at startup by selector."""
    base = {'novice': set(), 'intermediate': set(), 'advanced': set()}
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'level_seeds.yaml')):
        data = _load_yaml(path)
        for level, ids in data.get('seeds', {}).items():
            base.setdefault(level, set()).update(ids)
    return base
```

**Addition 2 — `load_all_frameworks()`:** expose all frameworks as a dict (needed by API and for package-aware framework listing):
```python
def load_all_frameworks() -> dict:
    result = {}
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'frameworks', '*.yaml')):
        fw = _load_yaml(path)
        result[fw['id']] = fw
    return result
```

---

### `src/selector.py`

**Required (in plan):** `_mp_path` update + `exercises_by_package` merge in `populate_session`.

**Addition 1 — accept merged level seeds:**

Replace the module-level `_LEVEL_CONCEPTS` constant usage in `_get_unlocked()`:
```python
def _get_unlocked(training_level: str, exercises: dict,
                  level_seeds: dict | None = None) -> set:
    concepts = (level_seeds or _LEVEL_CONCEPTS).get(training_level, set())
    ...
```

And in `populate_session`, add:
```python
from . import loader as _loader
_merged_seeds = _loader.load_level_seeds()  # called once at module level
```

Then pass `level_seeds=_merged_seeds` to `_get_unlocked()`.

**Addition 2 — multi-package archetype `_packages` list (for shared archetypes):**

In `select_exercise` call site inside `populate_session`, prefer the package matching the goal's primary sources:
```python
arch_package = next(
    (p for p in arch.get('_packages', [arch.get('_package')])
     if p in set(goal.get('primary_sources', []))),
    arch.get('_package')
)
```

**Addition 3 — package-coherence archetype scoring (low priority):**

In `_score_arch`, add a small bonus for archetypes whose `_package` matches the goal's primary framework's source philosophy:
```python
if arch.get('_package') in primary_sources:
    score += 1
```

---

### `src/scheduler.py`

**Required (in plan):** none — cadence already reads from framework YAML at line 343; `_CADENCE_OPTIONS` can be deleted once all framework YAMLs carry `cadence_options`.

**Addition — `modality_frameworks` support in `_build_day_pool` and `assign_to_days`:**

```python
def schedule_week(goal, constraints, data, phase, week_number, collect_trace=False):
    ...
    framework = select_framework(goal, constraints, _trace=fw_trace)
    modality_fws = goal.get('framework_selection', {}).get('modality_frameworks', {})

    # Load per-modality framework overrides (if any)
    modality_framework_cache = {}
    for mod_id, fw_id in modality_fws.items():
        try:
            modality_framework_cache[mod_id] = loader.load_framework(fw_id)
        except FileNotFoundError:
            pass  # fall back to base framework for this modality
```

Then in `assign_to_days`, when choosing the cadence for a modality's sessions, check `modality_framework_cache.get(modality, framework)` to get the right cadence options.

---

### `src/progression.py`

**Required (in plan):** none — `starting_load_kg` and `weekly_increment_kg` are already wired at lines 61–66.

**Addition 1 — `sessions_per_week_default` on exercise YAML:**
```python
# Line 68 (currently):
sessions_pw = _SESSIONS_PER_WEEK.get(ex_id, _SESSIONS_PER_WEEK['_default'])
# Replace with:
sessions_pw = (exercise.get('sessions_per_week_default')
               or _SESSIONS_PER_WEEK.get(ex_id, _SESSIONS_PER_WEEK['_default']))
```

**Addition 2 — `phase_duration_multipliers` on archetype slots (`_time_to_task`):**
```python
# Lines 113–119 (currently hardcoded dict):
phase_targets = slot.get('phase_duration_multipliers') or {
    'base': base_sec, 'build': int(base_sec * 1.25), ...
}
target_sec = phase_targets.get(phase, base_sec)
```

**Addition 3 — `level_distance_multipliers` on slots (`_distance_slot`):**
```python
level_mult = slot.get('level_distance_multipliers') or {
    'novice': 0.5, 'intermediate': 0.75, 'advanced': 1.0, 'elite': 1.25
}
```

---

### `src/generator.py`

**Required (in plan):** pass `exercises_by_package` to `populate_session` (one line at line 209).

**Addition — pass `level_seeds` through to selector:** no change needed if `selector.py` loads seeds at module level. If seeds are loaded per-call, generator would pass `data.get('level_seeds')`.

---

### `api.py`

The migration breaks **eight** existing helpers that hardcode old directory paths. Each needs to be updated to the new layout.

| Function / route | Current path | Fix |
|---|---|---|
| `get_frameworks()` line 394 | `data/frameworks/*.yaml` | `data/packages/*/frameworks/*.yaml` |
| `get_ontology()` line 412 | `data/philosophies/*.yaml` | `data/packages/*/philosophy.yaml` |
| `get_ontology()` line 423 | `data/frameworks/*.yaml` | `data/packages/*/frameworks/*.yaml` |
| `get_ontology()` line 435 | `data/modalities/*.yaml` | `data/commons/modalities/*.yaml` |
| `_all_exercises()` line 53 | `data/exercises/*.yaml` | `data/packages/*/exercises.yaml` |
| `_all_modalities()` line 65 | `data/modalities/*.yaml` | `data/commons/modalities/*.yaml` |
| `_equipment_profiles()` line 73 | `data/constraints/equipment_profiles.yaml` | `data/commons/constraints/equipment_profiles.yaml` |
| `_injury_flags()` line 77 | `data/constraints/injury_flags.yaml` | `data/commons/constraints/injury_flags.yaml` |
| `create_exercise()` line 493 | writes to `data/exercises/custom.yaml` | write to `data/packages/custom/exercises.yaml` |
| `_find_exercise_file_and_index()` line 506 | scans `data/exercises/*.yaml` | scan `data/packages/*/exercises.yaml` |
| `_find_archetype_file()` line 527 | scans `data/archetypes/**/*.yaml` | scan `data/packages/*/archetypes/**/*.yaml` |
| `create_archetype()` line 578 | writes to `data/archetypes/custom/` | write to `data/packages/custom/archetypes/` |
| `update_framework()` line 554 | `data/frameworks/<fw_id>.yaml` | scan `data/packages/*/frameworks/<fw_id>.yaml` |

The cleanest fix: replace all these path helpers with calls to `loader` functions, which already know the new paths after the loader migration. `_all_exercises()` → `loader.load_all_exercises()`, `_all_modalities()` → `loader.load_all_modalities()`, `_equipment_profiles()` → `loader.load_equipment_profiles()` (new function), `_injury_flags()` → `loader.load_injury_flags()`.

**New endpoints to add after migration:**

```
GET  /api/packages                      List all installed packages with metadata
GET  /api/packages/<id>                 Get one package (philosophy + asset inventory)
POST /api/packages                      Install a new package (JSON body or zip upload)
DELETE /api/packages/<id>               Remove a custom package (cannot delete built-ins)
POST /api/frameworks                    Create a new framework in the appropriate package
POST /api/modalities                    Create a new modality in commons/
POST /api/goals                         Create a custom goal (already partially exists at line 326)
```

**`POST /api/packages` is the highest-value new endpoint.** It makes the entire philosophy drop-in workflow API-native — the frontend can present a "Install Package" flow where the user uploads or pastes a zip/JSON, and the server validates and unpacks it into `data/packages/<id>/`. This is the endpoint that makes the package structure more than a filesystem reorganization.

A minimal package POST body:
```json
{
  "id": "yoga",
  "philosophy": { "id": "yoga", "name": "Yoga", "scope": ["mobility"], ... },
  "exercises": [{ "id": "downward_dog", ... }],
  "archetypes": [{ "id": "yoga_flow", "modality": "mobility", ... }],
  "frameworks": [{ "id": "yoga_practice", "source_philosophy": "yoga", ... }]
}
```

The endpoint validates IDs, checks for conflicts with existing packages, writes the YAML files, and returns the installed package manifest.

**`PUT /api/frameworks/<fw_id>` (line 551) needs expanding.** Currently it only allows updating `name`, `source_philosophy`, `sessions_per_week`, `notes`. After migration it should also allow updating `cadence_options` — the field that makes frameworks fully data-driven. Update the `allowed` set on line 558:
```python
allowed = {'name', 'source_philosophy', 'sessions_per_week', 'cadence_options',
           'deload_protocol', 'applicable_when', 'notes'}
```



---



## Verification



```bash

# 1. Counts match pre-migration

python -c "

from src.loader import load_all_data, load_philosophies, load_framework

d = load_all_data()

print('exercises:', len(d['exercises']))           # expect 198

print('archetypes:', len(d['archetypes']))          # expect ~35

print('modalities:', len(d['modalities']))          # expect 12

print('packages:', len(d['exercises_by_package'])) # expect 11

p = load_philosophies()

print('philosophies:', len(p))                     # expect 11

fw = load_framework('linear_progression')

print('cadence in framework:', 'cadence_options' in fw)  # expect True

"



# 2. End-to-end program generation still works

python -c "

from src.generator import generate

prog = generate('general_gpp', {

    'days_per_week': 4,

    'session_time_minutes': 60,

    'training_level': 'intermediate',

    'equipment': ['barbell', 'kettlebell', 'rack', 'plates']

}, output_format='dict')

print('weeks:', len(prog['weeks']))

week0 = prog['weeks'][0]

for day, sessions in week0['schedule'].items():

    for s in sessions:

        arch = s.get('archetype')

        print(f'  day {day}: {s[\"modality\"]} → {arch[\"id\"] if arch else \"none\"}')

"



# 3. Package-scoped prescription: wildman kb_swing vs horsemen kb_swing

python -c "

from src.loader import load_all_data

d = load_all_data()

wk = d['exercises_by_package'].get('wildman_kettlebell', {}).get('kb_swing_two_hand', {})

hk = d['exercises_by_package'].get('horsemen_gpp', {}).get('kb_swing_two_hand', {})

print('wildman novice load:', wk.get('starting_load_kg', {}).get('novice'))

print('horsemen novice load:', hk.get('starting_load_kg', {}).get('novice'))

"

```


