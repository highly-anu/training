# Model Generalization Gaps

What would be needed to make every model type in the training system fully user-creatable and data-driven. Captured from analysis of the pipeline interaction between model types (April 2026).

---

## Current State Summary

| Layer | User-creatable? | Auto-used in generation? | Blocks |
|---|---|---|---|
| Philosophy | ❌ No | N/A (reference only) | No endpoint; no effect on generation |
| Framework | ❌ No | ✅ Yes | `_CADENCE_OPTIONS` hardcoded dict; no endpoint |
| Modality | ⚠️ Partial | ✅ Yes | No POST endpoint; YAML drop-in works but no API/UI |
| Archetype | ✅ Yes | ✅ Yes | Edit/delete not supported |
| Exercise | ✅ Yes | ✅ Yes | `_STARTING_LOADS` miss; edit/delete not supported |
| Goal | ❌ No | User selects | No endpoint |

---

## Per-Layer Gap Analysis

### Philosophy
**Current:** Reference content only. `loader.load_philosophies()` builds a reverse index linking philosophies to frameworks/goals that cite them. No effect on program generation.

**To make fully general:** Philosophy is documentation, not computation — the right call here is probably just a `POST /api/philosophies` endpoint that stores YAML files and lets the Object Browser display custom philosophies. No engine changes needed.

**Effort:** Low. One endpoint + loader file glob.

---

### Framework
**Current:** No API endpoint. Frameworks are read from `data/frameworks/*.yaml`. The scheduler reads `applicable_when`, `sessions_per_week`, `deload_protocol.frequency_weeks` from YAML — these would work for a new framework. The blocker is:

**Hardcoded blocker 1 — `_CADENCE_OPTIONS` in `src/scheduler.py` (lines 280–323):**
```python
_CADENCE_OPTIONS = {
    'linear_progression': [[1, 3, 5], [2, 4, 6], ...],
    'concurrent_training': [[1, 2, 4, 6], ...],
    ...
}
```
A new framework ID with no entry here gets no cadence pattern — the scheduler raises a KeyError or falls back to a generic pattern (unclear). This dict needs to either:
- Accept an inline `cadence_patterns` field in the framework YAML that the scheduler reads dynamically, OR
- Use a generic fallback pattern for unknown IDs (even spacing across available days)

**Hardcoded blocker 2 — `_eval_condition()` in `src/scheduler.py` (lines 12–47):**
Parses `applicable_when` conditions like `days_per_week <= 3`. The supported operators and field names are hardcoded. A new framework with novel condition fields would be silently ignored.

**To make fully general:**
1. Move cadence patterns into the framework YAML as a `cadence_options` list field; scheduler reads from there with a generic fallback
2. Add `POST /api/frameworks` endpoint
3. Optionally: make `_eval_condition` more general (already handles most useful cases)

**Effort:** Medium. Primarily the cadence pattern migration.

---

### Modality
**Current:** No POST endpoint. But if you manually drop a YAML file into `data/modalities/`, the scheduler WILL read it and place it correctly — because `recover_cost`, `recovery_hours_min`, `incompatible_in_session_with`, `session_position` are all read from the YAML data dict. The placement logic in `assign_to_days()` operates on these properties generically.

**What works without code changes:** A new modality YAML with valid `recovery_cost` (high/medium/low), `recovery_hours_min`, and `incompatible_in_session_with` fields would be allocated and scheduled correctly by the existing scheduler. The only thing missing is:
- `POST /api/modalities` endpoint
- The modality must be referenced by a goal's `priorities` dict to be allocated sessions (a goal that doesn't mention the modality won't schedule it)

**Hardcoded blocker — `_RECOVERY_COST_RANK` in `src/scheduler.py` (line 8–9):**
```python
_RECOVERY_COST_RANK = {'high': 3, 'medium': 2, 'low': 1}
```
Only three cost levels are recognised. This is fine as-is — just document that modalities must use one of these three values.

**To make fully general:**
1. Add `POST /api/modalities` endpoint (stores to `data/modalities/custom/`)
2. Ensure goal `priorities` can include custom modality IDs (it already can — priorities are a free dict)
3. Document the required YAML fields

**Effort:** Very low. Just the endpoint. Engine already handles it.

---

### Archetype
**Current:** `POST /api/archetypes` exists. Stored in `data/archetypes/custom/{id}.yaml`. Loaded by `loader.load_all_archetypes()` via recursive glob. Used by `selector.select_archetype()` identically to built-in archetypes.

**Remaining gaps:**
- No `PUT /api/archetypes/{id}` (edit)
- No `DELETE /api/archetypes/{id}`
- No validation that slot `slot_type` values are valid (unknown slot_type silently falls to SetsRepsView on the watch)
- `sources` field on archetype affects scoring (+2 per source match with goal) — user-created archetypes without correct sources will score lower

**Effort:** Low. CRUD completion.

---

### Exercise
**Current:** `POST /api/exercises` exists. Stored in `data/exercises/custom.yaml`. Merged with standard exercises by `loader.load_all_exercises()`. Used by `selector.select_exercise()` identically.

**Remaining gaps:**

**Hardcoded blocker — `_STARTING_LOADS` and `_LINEAR_INCREMENTS` in `src/progression.py` (lines 8–35):**
```python
_STARTING_LOADS = {
    'back_squat': {'novice': 40, 'intermediate': 70, ...},
    'deadlift':   {'novice': 60, 'intermediate': 100, ...},
    ...
}
```
A custom exercise with `slot_type: sets_reps` and `progression_model: linear_load` will hit this dict lookup and fall back to a generic default (currently: `{'novice': 20, 'intermediate': 40, 'advanced': 60, 'elite': 80}`). The load won't be wrong, but it won't be specific to the exercise.

**Fix:** Add optional `starting_load` and `weekly_increment` fields to the exercise YAML schema. `progression.py` checks for these before falling back to `_STARTING_LOADS`. This makes progression fully data-driven for new exercises without requiring engine changes for existing ones.

**Other gaps:**
- No `PUT /api/exercises/{id}` or `DELETE /api/exercises/{id}`
- `unlocks` field creates implicit prerequisites — if a custom exercise unlocks another custom exercise, the `_LEVEL_PREREQS` chain in `selector.py` must include it (currently hardcoded)

**Effort:** Low. Add two optional YAML fields + one dict lookup change in progression.py.

---

### Goal
**Current:** No API endpoint. 7 built-in goals in `data/goals/*.yaml`.

**What would be needed:**
1. `POST /api/goals` endpoint storing to `data/goals/custom/`
2. Goal YAML requires: `id`, `name`, `description`, `priorities` (dict of modality → weight, must sum to ~1.0), `phase_sequence` (list of `{phase, weeks}`)
3. Optionally: `sources` list (affects archetype scoring), `forced_framework`

The schema is well-defined and already documented implicitly by the existing YAMLs. A creation endpoint with basic validation (priorities sum check, valid phase names) would be sufficient.

**Effort:** Low-Medium. Endpoint + validation logic.

---

## The "Knowledge in Code" Problem

Three areas where computation logic is hardcoded in Python rather than expressed in data. Resolving these would make the system fully data-driven:

### 1. `_CADENCE_OPTIONS` (scheduler.py)
Day-of-week patterns per framework ID. **Fix:** Move to `cadence_options` field in each framework YAML. Scheduler reads dynamically.

### 2. `_STARTING_LOADS` + `_LINEAR_INCREMENTS` (progression.py)
Per-exercise starting weights and progression rates. **Fix:** Add `starting_load: {novice: N, intermediate: N, ...}` and `weekly_increment_kg: N` as optional fields on exercise YAMLs. Scheduler reads these first, falls back to the dicts for existing exercises.

### 3. Movement pattern aliases (selector.py, lines 12–48)
30+ alias mappings like `hip_hinge → [deadlift_pattern, rdl_pattern, ...]`. These gate which exercises match which archetype slots. **Fix:** Move to a `data/movement_patterns.yaml` file with explicit alias lists. `selector.py` loads it at startup. New movement patterns are addable without code changes.

---

## Priority Order

1. **Modality** — cheapest win. One endpoint. Engine already handles it. *(~2 hours)*
2. **Exercise progression fields** — `starting_load` + `weekly_increment` on exercise YAML. No API changes, just schema + one lookup in progression.py. *(~1 hour)*
3. **Framework cadence migration** — move `_CADENCE_OPTIONS` to YAML + add endpoint. *(~4 hours)*
4. **Goal creation** — endpoint + validation. *(~3 hours)*
5. **CRUD completion** (edit/delete for exercises + archetypes) — *(~2 hours)*
6. **Movement pattern aliases → YAML** — cleanest but lowest urgency. *(~3 hours)*
7. **Philosophy endpoint** — documentation value only. *(~1 hour)*

**Total to reach full generality: ~16 hours of focused work.**
