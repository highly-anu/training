# Goal-Specific Secondary Session Archetypes

## Problem

Secondary sessions (the short mobility/skill work added after primary sessions or on rest days) are not goal-aware. `_add_split_sessions` in `scheduler.py` always picks `mobility` first, then the archetype selector picks the only mobility archetype — the generic `joint_prep_circuit` (sources: Ido Portal, Kelly Starrett) — for every goal.

An ultra-endurance athlete needs foot/ankle prep and thoracic rotation. A strength athlete needs hip flexors, thoracic extension, and shoulder prep. A climber needs wrist, shoulder, and hip mobility. None of this is currently expressed.

---

## How selection works (no changes needed)

`select_archetype(modality='mobility', ...)` in `src/selector.py`:
1. Filters archetypes by modality, phase, equipment, level
2. Scores each candidate: **+2 for each source string** that matches any of the goal's `primary_sources` (after normalising underscores → spaces)
3. Returns the highest-scoring archetype

Source matching:
```python
key = ps.replace('_gpp', '').replace('_', ' ').lower()  # 'uphill_athlete' → 'uphill athlete'
if key in src_lower:
    score += 2
```

An archetype with `sources: ["Uphill Athlete", "Kelly Starrett"]` scores **+4** for `ultra_endurance` (primary_sources: uphill_athlete, kelly_starrett), beating the generic `joint_prep_circuit` which scores +2 (kelly_starrett only).

**This means adding goal-specific archetypes with the right sources is sufficient — no Python or TypeScript changes needed.**

---

## Implementation — 3 new YAML files

All files go in `data/archetypes/movement_skill/`.

### `endurance_mobility.yaml`
**Wins for:** ultra_endurance (+4), alpine_climbing (+4)
**Sources:** "Uphill Athlete", "Kelly Starrett"
**Duration:** 20 min
**Focus:** foot/ankle, calf/achilles, hip flexor, thoracic rotation

| Slot | Duration | Purpose |
|------|----------|---------|
| `foot_ankle_prep` | 6 min | Ankle circles, calf stretch, soleus — ATG approach, direct injury prevention for high-mileage athletes |
| `hip_flexor_release` | 6 min | Couch stretch, hip flexor stretch, hip 90/90 — addresses shortening from running volume |
| `thoracic_rotation` | 5 min | Thoracic rotation, world greatest stretch — counters forward-lean fatigue posture |
| `activation_cooldown` | 3 min | Hip circles, pigeon pose — parasympathetic cool-down |

### `strength_mobility.yaml`
**Wins for:** max_strength_focus (+4), sof_operator (+4)
**Sources:** "Starting Strength", "Gym Jones"
**Duration:** 20 min
**Focus:** hip flexors, thoracic extension, shoulder, ankle dorsiflexion for squat depth

| Slot | Duration | Purpose |
|------|----------|---------|
| `hip_flexor_prep` | 6 min | Couch stretch, hip flexor stretch, hip 90/90 — anterior chain tightness from heavy squats/deadlifts |
| `thoracic_shoulder` | 7 min | Thoracic extension foam roll, thoracic rotation, shoulder circle, band pull-apart — overhead position restoration |
| `ankle_squat_prep` | 4 min | Ankle circles, squat clinic — ankle dorsiflexion for squat depth |
| `upper_prep` | 3 min | Wrist circles, scapula mobilization — pressing and pulling readiness |

### `grappling_mobility.yaml`
**Wins for:** bjj_competitor (+4)
**Sources:** "Ido Portal", "Kelly Starrett"
**Duration:** 20 min
**Focus:** hip rotation, shoulder, wrist, neck — grappling-specific demands

| Slot | Duration | Purpose |
|------|----------|---------|
| `hip_rotation_prep` | 6 min | Hip 90/90, pigeon pose, hip circle — ground-fighting hip mobility |
| `shoulder_wrist_prep` | 6 min | Shoulder circle, scapula mobilization, wrist circles, wrist flexion/extension — joint protection for grips and underhooks |
| `thoracic_neck` | 5 min | Thoracic rotation, neck rotation (if no injury flag) — cervical safety under collar chokes |
| `hip_flexor_cooldown` | 3 min | Couch stretch, world greatest stretch |

---

## Goal → archetype mapping after change

| Goal | primary_sources | Selected archetype | Score |
|------|----------------|-------------------|-------|
| ultra_endurance | uphill_athlete, kelly_starrett | endurance_mobility | +4 |
| alpine_climbing | uphill_athlete, kelly_starrett | endurance_mobility | +4 |
| max_strength_focus | starting_strength, gym_jones | strength_mobility | +4 |
| sof_operator | gym_jones, horsemen_gpp, starting_strength | strength_mobility | +4 |
| bjj_competitor | ido_portal, kelly_starrett | grappling_mobility | +4 |
| general_gpp | horsemen_gpp, crossfit, kelly_starrett | joint_prep_circuit | +2 (generic — appropriate) |
| injury_rehab | kelly_starrett, atg | joint_prep_circuit | +2 (generic — appropriate) |

---

## Files to create

| File | Status |
|------|--------|
| `data/archetypes/movement_skill/endurance_mobility.yaml` | TODO |
| `data/archetypes/movement_skill/strength_mobility.yaml` | TODO |
| `data/archetypes/movement_skill/grappling_mobility.yaml` | TODO |

No Python, no TypeScript changes required.

---

## Verification

1. Generate `ultra_endurance` with secondary sessions enabled → inspect session archetype IDs; secondary sessions should be `endurance_mobility`, not `joint_prep_circuit`
2. Generate `max_strength_focus` + secondaries → archetype should be `strength_mobility`
3. Generate `general_gpp` + secondaries → archetype should still be `joint_prep_circuit`
4. Confirm via generation trace: `archetype.selected_id` in the secondary session trace entries
