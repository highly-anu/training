# Next Features — Planning Document

Ideas captured 2026-03-27. Each item includes a technical analysis of the current system and a recommended implementation path.

---

## 1. Multi-Goal and Custom Goal Programs

**The idea:** Users should be able to combine multiple simultaneous goals (GPP + ultra trail race, SOF operator + BJJ competitor) and/or describe their own goal in free text instead of picking from the 7 presets.

### Technical context

The engine's core input is a `priorities` dict — a weighted vector over 12 modality IDs summing to 1.0. This drives everything: session allocation, framework selection, archetype scoring. Two goals can be merged by weighted-averaging their priority vectors, which is mathematically sound and produces a valid input to the existing engine with zero changes downstream of `generate()`.

Three explicit incompatible pairs already exist in goal YAML `incompatible_with` fields:
- `alpine_climbing` ↔ `max_strength_focus` (CNS/recovery interference)
- `ultra_endurance` ↔ `max_strength_focus` (AMPK-mTOR molecular conflict)

### Algorithm

1. **Blend priority vectors** — weighted average across N goals with user-supplied weights summing to 1.0. Union `primary_sources` and `minimum_prerequisites`. ~5 lines in a new `src/blender.py`.
2. **Select convergence framework** — don't average frameworks (categorically incompatible); instead pick based on dominant modality in the merged vector. `concurrent_training` is the natural fallback for mixed profiles and already handles max_strength + aerobic_base + durability.
3. **Phase calendar: anchor to nearest event** — if any constituent goal has an event date, that goal's phase sequence governs. Other goals are treated as background maintenance.
4. **Per-phase weight blend** — re-blend `priority_override` values at each phase using the same weights.
5. **Incompatibility pre-flight** — check all pairs' `incompatible_with` lists before generation; surface as structured warnings or blocking errors with the reason text from the YAML.

### What needs to change

**Backend (~200 lines new Python, minimal changes to existing):**
- New `src/blender.py` — `blend_goals(goals_with_weights) -> dict`
- `api.py` generate endpoint: detect `goal_ids` array vs `goal_id` string; call blender; pass merged dict to `generate()`
- `generate()` in `src/generator.py`: accept `goal: dict` directly in addition to `goal_id: str` (the dict is already loaded internally, trivial to hoist)
- `validator.py`: add incompatibility pair check

**Frontend (~150 lines modified TypeScript):**
- `builderStore.ts`: add `selectedGoalIds: string[]` + `goalWeights: Record<string, number>`
- `GoalGrid.tsx`: convert from single-select to multi-select with weight slider for 2+ goals
- `programs.ts`: send `goal_ids` array instead of `goal_id`
- Show incompatibility banners on step 1 before advancing (text already in YAML `reason` fields)

### Full vision additions
- Recharts radar chart showing merged priority vector live as weights change
- NLP `/api/goals/interpret` endpoint: keyword mapping ("trail race" → `ultra_endurance`) returns suggested goal blend for user confirmation — no LLM needed, a 20-30 entry keyword map covers most real inputs
- Per-phase weight adjustment (more complex; modifies `get_phase_priorities()` in `scheduler.py`)
- Multiple event date handling: user designates primary goal; secondary goal's periodization suppressed in primary goal's peak/taper

### Key files
- `src/generator.py:44` — `generate()` signature
- `src/scheduler.py:16` — `get_phase_priorities()`
- `src/scheduler.py:105` — `allocate_sessions()`
- `src/validator.py:27` — `validate()`
- `data/goals/*.yaml` — `incompatible_with` entries
- `frontend/src/store/builderStore.ts`
- `frontend/src/api/programs.ts`

---

## 2. Granular Equipment Selection

**The idea:** Instead of only selecting broad equipment profiles (full_gym, home_kb_only, etc.), users should be able to select individual pieces of equipment they have available.

### Technical context

The engine already operates on individual item IDs — the profiles are a **frontend-only convenience**. `_equipment_ok()` in `selector.py:99` does a pure set-intersection against individual item IDs. The archetype gate at `selector.py:215` does the same. The `equipment_profile` field on `AthleteConstraints` in `types.ts` is declared but never read by the backend. **Zero backend changes needed.**

### Individual equipment items in the exercise data (19 usable items)

`barbell`, `rack`, `plates`, `kettlebell`, `dumbbell`, `pull_up_bar`, `rings`, `parallettes`, `rope`, `box`, `rower`, `bike`, `ski_erg`, `ruck_pack`, `sandbag`, `jump_rope`, `resistance_band`, `ghd`, `medicine_ball`

**Data gaps found:**
- `bike`, `ski_erg`, `sandbag` appear in exercises but are absent from all 5 preset profiles
- `ghd`, `medicine_ball`, `sled`, `tire` are in the profile schemas but no exercise uses them — should be grayed out in UI
- Carries exercises require `sled` and `tire` which no profile includes

### Recommended UI pattern: profile-then-customize

1. Top row: existing 5 profile quick-picks (unchanged). Clicking one hydrates the checkboxes below.
2. Expandable "Customize" section with grouped checkboxes:
   - **Free weights**: barbell, rack, plates, kettlebell, dumbbell
   - **Gymnastics / bodyweight**: pull_up_bar, rings, parallettes, rope, box
   - **Cardio machines**: rower, bike, ski_erg
   - **Field / load**: ruck_pack, sandbag, jump_rope, resistance_band
   - **Specialty**: ghd, medicine_ball, sled, tire *(grayed out — no exercises yet)*
3. Profile button highlights only when selection exactly matches that preset (existing logic at `EquipmentPicker.tsx:43` already handles this)
4. Auto-select co-dependent items: toggling `barbell` auto-selects `rack` and `plates`

### Full vision additions
- `EquipmentCoverage` component: uses already-fetched `useExercises()` data to show how many exercises are available per modality given current selection — pre-validates before generation
- Stronger validator warning when the top-priority modality has zero valid archetypes given selected equipment
- Add `sandbag`, `bike`, `ski_erg` to appropriate preset profiles in `equipment_profiles.yaml`

### Key file
- `frontend/src/components/builder/EquipmentPicker.tsx` — only file requiring significant changes

---

## 3. Carries Filter Shows No Exercises (Bug)

**Root cause:** Category key mismatch. All 16 exercises in `data/exercises/carries.yaml` use `category: loaded_carry`. The ExerciseFilters tab uses `id: 'carries'`. Strict equality fails, returning zero results from the real API.

**Fix:** One line in `frontend/src/components/exercises/ExerciseFilters.tsx`:
```ts
// Change:
{ id: 'carries', label: 'Carries' }
// To:
{ id: 'loaded_carry', label: 'Carries' }
```

No YAML changes. No API changes. The loader already picks up `carries.yaml` correctly.

**Secondary issue:** The MSW mock fixture (`frontend/src/mocks/fixtures/exercises.json`) is a 20-exercise stub, not synced to the real 198-exercise dataset. It uses wrong category strings. Regenerating it from the real API would fix all mock-mode category mismatches.

**The carries library is complete** — 16 well-documented exercises covering farmer carries, rack carries, overhead carries, suitcase carry, zercher carry, yoke carry, sandbag carries, ruck carry, sled push, tire drags. No content gap.

---

## 4. Week Navigation Capped at Week 4 (Bug)

**Root cause:** `api.py:300` defaults `num_weeks` to 4 when not provided:
```python
num_weeks = body.get('num_weeks', 4)
```
The frontend never sends `num_weeks` in the POST body (`frontend/src/api/programs.ts:17`). Every generation call hits the 4-week default regardless of goal phase sequence. `ProgramView.tsx:63` clamps navigation to `program.weeks.length - 1`, which is always 3.

**Fix:** Replace the hardcoded default in `api.py` with the goal's total phase sequence:
```python
phase_total = sum(p.get('weeks', 0) for p in goal.get('phase_sequence', []))
num_weeks = body.get('num_weeks', phase_total or 4)
```

No frontend changes required. Callers that want a shorter preview can still pass `num_weeks` explicitly.

---

## 5. Program Overview / Phase Summary

**The idea:** A view that explains the generated program's structure — phases, timing, what each phase trains and why, volume progression across the arc.

### Technical context — data already available

All necessary data is already in the current API response, fully typed, partially unused:

- `program.goal.phase_sequence[].focus` — rich 2–6 sentence prose description per phase, present in all 7 goal YAMLs, **never rendered anywhere**
- `program.goal.notes` — overall program rationale paragraph, present in all 7 goals, never rendered
- `program.goal.primary_sources` — source philosophies, never rendered
- `program.weeks[n].phase` / `is_deload` — phase + deload markers per week
- `program.volume_summary[]` — all weeks' volume by domain (strength sets, cond minutes, durability minutes, mobility minutes)
- `usePhaseCalendar()` already computes `segments` with `focus`, `startWeek`, `endWeek` — used only for the `PhaseBar` display, not for text content

**One backend addition recommended** (not required for MVP): Add `framework` object to `_transform_program` in `api.py` so the frontend can show framework rationale and intensity distribution without a second API call.

### What the overview should show

1. **Program header** — goal name, description, total weeks, `goal.notes` rationale, `primary_sources` as chips
2. **Phase timeline** — each phase as a card: name, week range, `focus` prose, priority bar (using `priority_override` from the phase entry)
3. **Volume progression chart** — full-width `VolumeBar` spanning all weeks with phase shading bands and deload markers overlaid; the existing `VolumeBar` component is capped at 8 weeks and needs to be opened up
4. **Framework rationale** — framework name, notes, intensity distribution (requires backend addition)
5. **Prerequisites** — `goal.minimum_prerequisites` as a checklist cross-referenced against `profileStore` benchmarks

### UI location

Collapsible panel above the week calendar in `ProgramView.tsx`. Not a separate route. A tab strip "Overview | Calendar" avoids adding navigation while keeping the two views clean. The Dashboard `PhaseTimeline` widget is the compact version of this — the Overview is the expanded form.

### Implementation

MVP: 1 new component (`ProgramOverview.tsx`), 1-line addition to `ProgramView.tsx` to render it. No API changes, no new types. The `segments` array from `usePhaseCalendar` (already destructured at `ProgramView.tsx:19`) carries everything needed.

### Key files
- `frontend/src/pages/ProgramView.tsx:19` — `segments` already available, never fully used
- `frontend/src/hooks/usePhaseCalendar.ts` — `focus` already on each segment
- `frontend/src/components/dashboard/VolumeBar.tsx` — needs 8-week cap removed
- `frontend/src/lib/phaseColors.ts` — phase color tokens ready
- `api.py:171` `_transform_program` — add `framework` object (full vision)

---

## 6. Custom Injury Entry + Mid-Program Injury Management

**The idea (two parts):**
1. Custom injury entry via body-part → exercise flow: user picks a body part, sees relevant exercises, marks what they can't do, system infers movement pattern exclusions
2. Add/remove injuries during an active program — future weeks regenerate with updated constraints

### Current system

12 preset flags in `data/constraints/injury_flags.yaml`. The engine applies them via two independent mechanisms:
- Pattern exclusion: `excluded_movement_patterns` blocks slots whose required movement pattern overlaps (`selector.py:149`)
- Exercise exclusion: `excluded_exercises` + `contraindicated_with` on individual exercises (`selector.py:299`)

The frontend stores `injuryFlags: InjuryFlagId[]` — a closed literal union type, locked to 12 values.

### Custom injury data structure

A custom injury is a synthetic `InjuryFlag`-shaped object injected at the API boundary:

```json
{
  "id": "custom_<uuid>",
  "name": "Left Knee Pain",
  "body_part": "left_knee",
  "side": "left",
  "excluded_movement_patterns": ["squat", "knee_extension"],
  "excluded_exercises": ["barbell_squat", "box_jump"],
  "severity": "moderate",
  "is_custom": true,
  "created_at": "2026-03-27"
}
```

The engine is fully transparent to the distinction — all fields it reads (`excluded_movement_patterns`, `excluded_exercises`) are present. New fields (`body_part`, `side`, `severity`) are ignored by the engine.

**API change:** Add `custom_injury_flags` optional field to the POST `/programs/generate` body. Merge these into `injury_flags_data` before passing to `validate()` and `generate()`. ~10 lines in `api.py`.

### Body-part → exercise flow

**Proposed body parts and their movement pattern mappings:**

| Body part | Excluded patterns | Overlapping presets |
|---|---|---|
| lower_back | hip_hinge, rotation, loaded_carry | lumbar_disc |
| knee (bilateral) | squat, knee_extension, ballistic, locomotion | knee_meniscus_post_op, patellar_tendinopathy |
| left_knee / right_knee | same + side metadata | same |
| shoulder | vertical_push, horizontal_push, ballistic, olympic_lift | shoulder_impingement, shoulder_instability |
| elbow | horizontal_pull, vertical_pull, horizontal_push | tennis_elbow, golfers_elbow |
| wrist / hand | horizontal_push, vertical_push, olympic_lift | wrist_injury |
| ankle | locomotion, ballistic | ankle_sprain, achilles_tendinopathy |
| hip_flexor | hip_flexion, ballistic, locomotion | hip_flexor_strain |

**Flow:**
1. User picks body part
2. Frontend filters `useExercises()` by associated movement patterns — no new API call needed
3. User marks which exercises cause pain / aren't possible
4. System infers `excluded_movement_patterns` via threshold rule: include a pattern only if >50% of marked exercises share it
5. Show inferred patterns to user for confirmation before saving
6. If selection strongly resembles a preset flag, offer: "This looks like Patellar Tendinopathy — use the clinical preset instead?"

### Mid-program injury updates (MVP approach)

**Full regeneration:** When user adds/removes an injury from `ProgramView`, the frontend:
1. Calls `POST /programs/generate` with updated flags + `periodization_week = currentWeekIndex + 1` + `num_weeks = totalWeeks - currentWeekIndex`
2. Splices the result into the existing program's `weeks` array: keep weeks 0..currentWeekIndex-1 as-is, replace the rest

No new API endpoint needed. `generate()` already accepts `periodization_week` for starting phase position.

### Edge cases
- **Partial injuries** (can squat but not heavy): use `excluded_exercises` for specific heavy variants without blocking the entire pattern — clean with no engine changes
- **Bilateral side**: store `side` field for future use; engine currently applies symmetrically (note this to user)
- **Severity → phase forcing**: map `severe`/`post_op` to `training_phase_forced` field — requires a small `api.py` addition to read and apply this field (currently data-only)

### Key files
- `api.py:261` — merge point for custom flags
- `frontend/src/components/builder/InjuryPicker.tsx` — replace with tabbed Presets + Custom component
- `frontend/src/store/builderStore.ts` — add `customInjuryFlags: CustomInjuryFlag[]`
- `frontend/src/api/types.ts:56` — widen `InjuryFlagId` to allow custom string IDs
- `frontend/src/pages/ProgramView.tsx` — "Update Injuries" button + week-splice logic

---

## 7. Philosophies & Influences Page

**The idea:** A page explaining each source philosophy — what it stands for, its core principles, and how it concretely shows up in the programming.

### Data already available

11 philosophy YAMLs in `data/philosophies/` (9 named sources + `bjj.yaml` + `kelly_starrett.yaml`). Each has:
- `core_principles` — 7–11 semantic identifiers per philosophy
- `scope` / `bias` — domains covered and dominant emphasis
- `avoid_with` — cross-philosophy conflict pairs (useful for "not compatible with" UI)
- `intensity_model` + `progression_philosophy`
- `notes` — 5–10 sentence narrative with specific details (RPM targets, benchmark standards, protocol sequences). This is the richest field and is page-ready content.
- `sources` — book/document citations

**Cross-system connections already machine-readable:**
- `data/frameworks/*.yaml` has `source_philosophy` field → clean philosophy-to-framework mapping
- `data/goals/*.yaml` has `primary_sources` array → philosophy-to-goal mapping
- Archetypes and exercises have `sources` string arrays → needs normalization to philosophy IDs

**Two ID mismatches to fix before automated cross-referencing:**
- `data/frameworks/rpe_autoregulation.yaml`: `source_philosophy: functional_bodybuilding` → should be `marcus_filly`
- `data/frameworks/kb_pentathlon.yaml`: `source_philosophy: rkc_kettlebell` → should be `wildman_kettlebell`

**Data gaps (non-blocking):**
- ATG and Ido Portal not in any goal's `primary_sources`
- Rehab exercises cite `plan.md section 10` not `Marcus Filly` — 24 exercises in `rehab.yaml` to update
- Mobility exercises have no philosophy sources — Kelly Starrett exercises would go here

### What the page should show per philosophy

1. Identity: name, tagline (derive from `bias` + `intensity_model`), required equipment, intensity/progression model
2. Core principles (YAML list → readable prose)
3. Narrative (`notes` field verbatim)
4. Domain coverage: `scope` + `bias` as visual badges/chart
5. "Conflicts with" list — linkable to other philosophy entries (`avoid_with`)
6. **How it shows up in this system:**
   - Frameworks it drives (from `source_philosophy`)
   - Goal profiles it influences (from `primary_sources`)
   - Archetypes attributed to it (from archetype `sources` arrays)
   - Exercise count attributed to it
7. Source citations

### UI structure

Sidebar navigation + scrollable card layout at `/philosophies`. Each philosophy gets a card with a two-column layout (principles + narrative) and a "shows up as" footer row. Color-code by primary domain bias. The existing `Sidebar.tsx` needs one nav item added.

Alternative: grid of cards on `/philosophies`, click opens a full-detail drawer. More scannable at a glance.

### API

New `GET /api/philosophies` endpoint returning the full philosophy array with a `system_connections` object pre-joined server-side:

```json
{
  "id": "gym_jones",
  ...philosophy fields...,
  "system_connections": {
    "frameworks": ["block_periodization"],
    "goals": ["max_strength_focus", "sof_operator"],
    "archetypes": ["gym_jones_operator_strength", "gym_jones_circuit", ...],
    "exercise_count": 25
  }
}
```

Loader already has all cross-referenced data; this is computed at request time.

### Key files
- `data/philosophies/*.yaml` — 11 files, ready to serve
- `api.py` — add `GET /api/philosophies` endpoint
- `src/loader.py` — add `load_philosophies()` + join logic
- `frontend/src/App.tsx` — add `/philosophies` route
- `frontend/src/components/layout/Sidebar.tsx` — add nav item
- `frontend/src/pages/Philosophies.tsx` — new page (create)
- `frontend/src/api/philosophies.ts` — new API hook (create)

---

## 8. Expanded Benchmarks

**The idea:** More benchmark coverage — at minimum, everything in the Cell Standards. Currently `cell_standards.yaml` is never loaded by the API.

### What exists

Three files in `data/benchmarks/`:
- `strength_standards.yaml` — 7 benchmarks (squat, deadlift, press, bench, power clean, pull-ups, weighted pull-up)
- `conditioning_standards.yaml` — 4 benchmarks (3-mile run, SSST, 2km row, 1-mile run)
- `cell_standards.yaml` — ~30 standards across 8 domains (hips, push, pull, core, work_capacity, endurance, skill, benchmark WODs) — **never loaded by the API**

The API (`api.py:89`) reads only the first two files. `cell_standards.yaml` has an incompatible schema (Roman-numeral levels I–V, qualitative strings mixed with numerics, no `id` field) and is silently ignored.

The UI shows two tabs — Strength Standards and Conditioning Standards. A `'cell'` category already exists in `types.ts` but is never rendered.

### What's missing

**Cell Standards** — the biggest gap. The file exists but isn't exposed. Its schema needs to be converted to the standard list-of-objects format (adding `id`, mapping I→entry / III→intermediate / IV→advanced / V→elite).

**Missing benchmark families** (no data files yet):

| Category | Examples |
|---|---|
| Kettlebell pentathlon | Wildman 5-lift scoring (snatch, C&J, press, squat, pull) |
| Ruck standards | SFAS pace (40 lb / 12 mi / sub-3h), Horsemen PT Test |
| CrossFit Girls WODs | Fran (partial in cell), Grace, Helen, Diane, Isabel, Annie, Elizabeth |
| CrossFit Hero WODs | Murph, Cindy, DT |
| Horsemen PT Tests | PT Test I and II — referenced in notes but not extracted |
| Movement/skill | Turkish Get-Up standard, handstand hold |

**Schema gaps:**
- 5 Cell levels vs. 4-level hardcoded UI — need mapping or UI extension
- Female values exist in the data (`female_bw_pct`, `female_time`) but `_all_benchmarks()` reads only male values and there's no gender toggle in the UI
- New unit types in Cell data (`inches`, `metres`, `time_sec`) have no unit mapping and get dropped

### Implementation path

**Phase 1 — expose Cell Standards:**
1. Convert `cell_standards.yaml` to list-of-objects schema (~30 entries)
2. Add it to `_all_benchmarks()` loop in `api.py`; extend `_BENCHMARK_UNIT_MAP` for `inches`, `metres`, `time_sec`
3. Add "Cell Standards" tab to `ProfileBenchmarks.tsx` filtering on `category === 'cell'`

**Phase 2 — add missing benchmark families:**
- Create `ruck_standards.yaml`, `kettlebell_pentathlon.yaml`, `crossfit_wods.yaml` using existing list schema
- Add to `_all_benchmarks()` loop; add `'benchmark_wod'` category

**Phase 3 — female values + user PR tracking:**
- Extend `BenchmarkStandard` type with `female_standards`
- Add sex toggle to `ProfileBenchmarks.tsx`
- Wire `userValue` on each `LevelBar` (prop already exists, never passed)
- Add `performanceLogs: Record<string, number>` to `profileStore`

### Key files
- `data/benchmarks/cell_standards.yaml` — needs schema conversion
- `api.py:89` `_all_benchmarks()` — add files + unit mappings
- `frontend/src/pages/ProfileBenchmarks.tsx` — add Cell tab
- `frontend/src/api/types.ts` — `BenchmarkStandard` type, `'cell'` already present but unused

---

## Summary and Suggested Order

| # | Item | Type | Effort |
|---|------|------|--------|
| 3 | Carries filter bug | Bug fix | 1 line |
| 4 | Week nav capped at 4 | Bug fix | 1 line |
| 2 | Granular equipment selection | Feature | Small (frontend only) |
| 5 | Program overview / phase summary | Feature | Small–Medium |
| 8 | Cell Standards exposed in UI | Feature | Small–Medium |
| 7 | Philosophies page | Feature | Medium |
| 6 | Custom injury entry | Feature | Medium |
| 6 | Mid-program injury management | Feature | Medium |
| 8 | Full benchmark expansion | Feature | Medium |
| 1 | Multi-goal / custom goals | Feature | Medium–Large |
