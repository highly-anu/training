# Deep Analysis: Training Program Generator Shortcomings



## Context



The user generated an ultra endurance (50km trail run) program using the `ultra_endurance` goal with the `polarized_80_20` framework. The generated plan has several systematic problems. This analysis traces each issue to its root cause in the code and proposes general fixes that would benefit all goals, not just ultra endurance.



---



## Issue 1: Irrelevant Archetypes Selected (BJJ, Grappling Mobility, KB Pentathlon)



### Root Cause

**Archetype selection is purely modality-based with no domain/goal filtering** (`src/selector.py:181-214`).



The selection pipeline filters by: modality match -> phase -> training level -> equipment -> duration. There is zero filtering by goal domain, goal ID, or goal relevance. Any archetype whose `modality` field matches a modality in the goal's priority vector is eligible.



**Why specific bad selections happen:**

- **Grappling Mobility**: modality=`mobility`, applicable to all phases. Ultra endurance allocates mobility slots. Grappling mobility competes with endurance mobility and may win on scoring tiebreakers (equipment availability, source matching, recency).

- **BJJ Class**: modality=`combat_sport`. Appears if `combat_sport` somehow gets allocated, or if the scheduler fallback assigns it.

- **KB Pentathlon**: modality=`strength_endurance`. Ultra endurance allocates `strength_endurance: 0.10` for structural durability, but KB Pentathlon (a kettlebell sport archetype) matches the same modality and can outscore relevant alternatives via equipment bonus (+6).



**The source matching bonus (+2 per keyword match, `selector.py:226-232`) is insufficient** because:

- Sources like "Kelly Starrett" appear in both ultra endurance (mobility context) and BJJ (grappling context)

- The +2 bonus is easily overridden by the +6 equipment bonus

- Niche archetypes with no source overlap still win if they're the only candidate



### Suggested Fix (General)

Add an **archetype tagging / domain system** — applicable across all goals:



**Option A: `applicable_domains` on archetypes** (most general)

- Add a field like `applicable_domains: [endurance, gpp]` to each archetype YAML

- Goals would declare their domain(s): `domain: endurance`

- Selector filters candidates to matching domains before scoring

- Archetypes without domains remain universal (backward compatible)



**Option B: `excluded_archetypes` / `preferred_archetypes` on goals** (simpler)

- Goals list archetype IDs to exclude or prefer per modality

- e.g., ultra_endurance excludes `bjj_class`, `kb_pentathlon_training`, `grappling_mobility`

- Less general but immediately effective



**Option C: Stronger source-matching weight** (minimal change)

- Increase source match bonus from +2 to +8 (outweighs equipment bonus)

- Add negative scoring for archetypes with zero source overlap with the goal (-4)

- Least disruptive but least precise



**Files to modify:**

- `src/selector.py:181-243` — add domain filtering or strengthen scoring

- Archetype YAMLs — add `applicable_domains` field

- Goal YAMLs — add `domain` field



---



## Issue 2: No Threshold Intervals in Build Phase



### Root Cause

**The build phase `priority_override` in `ultra_endurance.yaml` doesn't include `anaerobic_intervals`**, and the scheduler filters out framework modalities with zero priority weight.



Code path (`src/scheduler.py:163-165`):

```python

active_fw = {mod: cnt for mod, cnt in fw_sessions.items()

             if priorities.get(mod, 0) > 0}

```



The `polarized_80_20` framework defines `anaerobic_intervals: 1` session/week. But when build phase priorities are loaded (`scheduler.py:16-21` via `get_phase_priorities()`), the override is:

```yaml

# ultra_endurance.yaml, build phase

priority_override:

  aerobic_base: 0.55

  durability: 0.25

  strength_endurance: 0.10

  mobility: 0.10

```

`anaerobic_intervals` has implicit weight 0 -> filtered out -> zero sessions allocated.



### Suggested Fix (General)

Two complementary approaches:



**Option A: Fix the data** (immediate, goal-specific)

- Add `anaerobic_intervals: 0.05` to the build phase `priority_override` in `ultra_endurance.yaml`

- Same pattern applies to any goal that needs phase-specific modality introduction



**Option B: Phase-aware framework sessions** (general, architectural)

- Extend framework YAML to support per-phase `sessions_per_week`:

  ```yaml

  sessions_per_week:

    base: { aerobic_base: 5, max_strength: 1 }

    build: { aerobic_base: 4, anaerobic_intervals: 1, max_strength: 1 }

    peak:  { aerobic_base: 5, anaerobic_intervals: 1 }

  ```

- `allocate_sessions()` would read phase-specific counts instead of a single static map

- Benefits ALL goals using any framework — each framework can define how its modality mix evolves



**Option C: `phase_modalities` field on goals** (general)

- Allow goals to specify modalities to ADD in specific phases:

  ```yaml

  phase_modalities:

    build: { anaerobic_intervals: 0.05 }

  ```

- Merged into `priority_override` by `get_phase_priorities()`



**Files to modify:**

- `data/goals/ultra_endurance.yaml` — add anaerobic_intervals to build priority_override

- `src/scheduler.py:16-21` — extend `get_phase_priorities()` for Option B or C

- `data/frameworks/polarized_80_20.yaml` — phase-aware sessions_per_week for Option B



---



## Issue 3: Peak Phase Has No Running



### Root Cause

**Same mechanism as Issue 2**, but in reverse. The peak phase `priority_override` includes `aerobic_base: 0.60`, so aerobic sessions SHOULD be allocated. However, the generated output shows only ruck, loaded carry, and mobility.



The likely cause is that `aerobic_base` sessions are being allocated but the **archetype selected for aerobic_base in peak phase is `ruck_session`** (modality overlap) or the long_zone_2 archetype is being outscored by ruck/carry archetypes.



Alternatively, if the user's displayed output is from a specific run, the scheduler may have allocated aerobic_base slots that were then filled with ruck_session (which has modality `durability`, not `aerobic_base`) through a fallback path.



**Another contributing factor**: The `long_zone_2` archetype's `applicable_phases` list (`conditioning/long_zone_2.yaml:7-11`) includes `base, build, peak, taper, maintenance` — so it SHOULD be eligible. If it's not appearing, the issue may be in the scoring/selection where ruck_session outcompetes it, or in how the scheduler counts are distributed.



### Suggested Fix

- Investigate the exact session allocation for peak phase with logging/debug output

- If it's a scoring issue, the domain-based fix from Issue 1 would help (ruck shouldn't replace running in peak)

- Ensure `aerobic_base` modality sessions can only be filled by aerobic archetypes, not durability archetypes



**Files to investigate:**

- `src/scheduler.py:152-197` — trace allocation for peak phase priorities

- `src/selector.py:181-243` — check what candidates exist for aerobic_base in peak



---



## Issue 4: Zone 2 Volume Too Low (~3/week vs 5-6/week)



### Root Cause

**Mathematical consequence of the allocation algorithm** (`src/scheduler.py:152-197`).



With 5 days/week and base priorities `{aerobic_base: 0.60, durability: 0.20, strength_endurance: 0.10, mobility: 0.10}`:



1. Framework `active_fw` = `{aerobic_base: 4}` (only aerobic_base overlaps with priorities)

2. `fw_covered_prio` = 0.60, `goal_only_prio` = 0.40

3. `fw_slots` = 5 * (0.60/1.0) = **3.0**

4. `goal_only_slots` = 5 * (0.40/1.0) = 2.0

5. After rounding: aerobic_base=3, durability=1, strength_endurance/mobility share 1



The framework says `aerobic_base: 4` but the allocation algorithm scales it DOWN based on the goal's priority share. The framework's intent (4 Z2 sessions) is overridden by the proportional math.



**The core tension**: The framework says "4 aerobic sessions" but the goal only gives aerobic 60% of priority, so on 5 days the math yields 3. The framework's absolute count is treated as a RATIO, not a MINIMUM.



### Suggested Fix (General)

**Option A: Framework minimums** (recommended)

- Add `min_sessions` per modality to frameworks:

  ```yaml

  sessions_per_week:

    aerobic_base: { target: 4, min: 4 }

    anaerobic_intervals: { target: 1, min: 0 }

  ```

- `allocate_sessions()` would enforce minimums before proportional allocation

- Remaining slots distributed by priority

- Benefits all frameworks — ensures their core prescription isn't diluted



**Option B: Increase days_per_week**

- The ultra endurance goal expects 4-6 days/week. At 6 days: aerobic_base would get ~3.6 -> 4 sessions

- This is user-side but still doesn't reach 5-6 Z2 sessions



**Option C: Allow multiple sessions per day**

- Ultra runners often do AM easy run + PM mobility

- The scheduler currently assigns one primary session per day

- Adding secondary session slots would allow 5-6 Z2 on 5 training days



**Files to modify:**

- `src/scheduler.py:152-197` — implement minimum session counts

- `data/frameworks/polarized_80_20.yaml` — add min_sessions

- Potentially `src/scheduler.py` day assignment — allow multi-session days



---



## Issue 5: No Long Run Differentiation



### Root Cause

**The system has no concept of a "long run" vs "regular run"** — all Zone 2 sessions use the same archetype (`long_zone_2`) with the same base duration (90 min).



In `src/progression.py:108-133`, `_time_to_task()` applies the SAME duration to every instance of the archetype within a week. There's no mechanism to say "one of these 3 weekly Z2 sessions should be 2-3x longer."



The archetype `long_zone_2.yaml` has a single slot with `duration_sec: 5400` (90 min). Every Z2 session gets this same prescription.



### Suggested Fix (General)

**Option A: Weekly long run archetype** (cleanest)

- Create a new archetype: `weekly_long_run` with modality `aerobic_base`

- Duration: 180-300 min (3-5h), scaling by phase

- Scheduler allocates exactly 1 per week when `aerobic_base` sessions >= 3

- Regular Z2 sessions use `long_zone_2` (60-90 min), the long run uses the new archetype

- This pattern (regular + long) is universal across endurance sports



**Option B: Slot-level duration variation**

- Extend the selector to tag one session per week as "long effort" and multiply its duration

- `_time_to_task()` would accept a `long_effort_multiplier` parameter

- Less clean but requires no new archetypes



**Option C: Archetype variants**

- Create `zone2_easy` (60 min) and `zone2_long` (180+ min) as separate archetypes

- Selector picks a mix based on goal configuration



**Files to modify:**

- New archetype YAML: `data/archetypes/conditioning/weekly_long_run.yaml`

- `src/selector.py` — logic to allocate 1 long run per week

- `src/progression.py:108-133` — different base durations per archetype variant



---



## Issue 6: No Back-to-Back Long Days in Build



### Root Cause

**The recovery system actively PREVENTS consecutive hard days** (`src/scheduler.py:210-226`).



```python

def _recovery_safe(day, mod, ..., recovery_windows):

    # Enforces minimum recovery hours between same modality

    # Prevents two high-cost modalities within 48 hours

```



This is correct for most training but directly contradicts the ultra endurance build phase prescription of consecutive long days (glycogen depletion training).



### Suggested Fix (General)

- Add a **`back_to_back_allowed` flag** to phase definitions or goal configuration:

  ```yaml

  # In goal phase definition:

  build:

    back_to_back_days: true

    back_to_back_modalities: [aerobic_base]

  ```

- When this flag is active, `_recovery_safe()` relaxes constraints for the specified modalities

- General enough to apply to any goal needing consecutive-day training blocks



**Files to modify:**

- `src/scheduler.py:210-226` — conditional recovery relaxation

- `data/goals/ultra_endurance.yaml` — add back_to_back config to build phase



---



## Issue 7: Low Strength Volume



### Root Cause

**`strength_endurance: 0.10` priority + 5 days/week = ~0.5 sessions/week**, which rounds to 0-1 sessions. Additionally, the framework `polarized_80_20` defines `max_strength: 1` but this is filtered out because the goal doesn't include `max_strength` in its priorities (it uses `strength_endurance` instead, which is NOT in the framework's `sessions_per_week`).



So strength ends up as a "goal-only" modality getting leftover slots after framework modalities are allocated. With 0.10 priority, it gets very few sessions.



### Suggested Fix

- **Align modality naming**: Either the goal should use `max_strength` (matching the framework) or the framework should list `strength_endurance`

- **Minimum sessions**: Same as Issue 4 — allow goals/frameworks to specify floor counts

- **Structural strength archetype**: Ensure a simple single-leg archetype (SL deadlift, split squat, step-up) exists and scores well for endurance goals



**Files to modify:**

- `data/goals/ultra_endurance.yaml` — consider using `max_strength` or adding it alongside `strength_endurance`

- `data/frameworks/polarized_80_20.yaml` — add `strength_endurance` to sessions_per_week

- `src/scheduler.py:152-197` — minimum session enforcement



---



## Summary: Most Impactful General Fixes



| Priority | Fix | Scope | Files |

|----------|-----|-------|-------|

| **1** | Phase-aware `sessions_per_week` in frameworks | All goals/frameworks | `scheduler.py`, framework YAMLs |

| **2** | Domain/tag filtering for archetypes | All goals | `selector.py`, archetype YAMLs, goal YAMLs |

| **3** | Framework minimum session counts | All frameworks | `scheduler.py`, framework YAMLs |

| **4** | Long run archetype (weekly long effort) | All endurance goals | New archetype, `selector.py` |

| **5** | Configurable recovery relaxation for back-to-back days | Endurance/peaking goals | `scheduler.py`, goal YAMLs |

| **6** | Framework/goal modality alignment | All goals | Goal + framework YAMLs |



## Verification



After any fixes:

1. Run `python main.py` with `ultra_endurance` goal — verify threshold intervals appear in build, Z2 sessions increase, no BJJ/grappling archetypes

2. Run with `bjj_competitor` goal — verify BJJ archetypes still appear (regression check)

3. Run with `general_gpp` — verify no unintended archetype filtering

4. Check all 7 goal profiles produce reasonable programs

5. API: `POST /api/programs/generate` with `{goal_id: "ultra_endurance", constraints: {days_per_week: 5}}` — inspect output JSON


