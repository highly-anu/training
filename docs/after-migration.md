# After Migration: Program Quality Improvements

## Status

### Completed
- **Vertical package migration** — `data/packages/`, `data/commons/`, per-package `exercises.yaml`, all 12 frameworks have `cadence_options`. `loader.py`, `selector.py`, `generator.py`, `api.py` updated. Verified: 198 exercises, 34 archetypes, 12 modalities, 11 philosophies.
- **Issue 7 (modality mismatch)** — `polarized_80_20.yaml` changed `max_strength: 1` → `strength_endurance: 1`. Verified: strength_endurance gets guaranteed session in base phase.
- **Issue 2 (missing threshold intervals in build)** — `ultra_endurance.yaml` build phase `priority_override` now includes `anaerobic_intervals: 0.10`. Verified: `threshold_intervals` archetype appears in build phase schedule.
- **Codex review P2** — single-session API path (`/api/session`) was missing `exercises_by_package` arg to `populate_session()`; fixed in `api.py`.

### Engine cleanup (low urgency, no behavior change)
- Delete `_CADENCE_OPTIONS` dict from `scheduler.py` — all 12 frameworks now carry `cadence_options` in YAML; the hardcoded fallback is dead code.
- Update `docs/architecture.md` and `docs/author-guide.md` — still reference old `data/exercises/`, `data/frameworks/`, `data/philosophies/` paths.

### Pending engine extensions (wiring only — YAML fields already defined)
- `_SESSIONS_PER_WEEK` per-exercise override: add `sessions_per_week_default` check in `progression.py:68` before dict fallback.
- `_time_to_task` phase multipliers: read `slot.get('phase_duration_multipliers')` before hardcoded dict in `progression.py:113-119`. Required for `weekly_long_effort` archetype (Issue 5).
- `_distance_slot` level multipliers: read `slot.get('level_distance_multipliers')` before hardcoded dict.
- Phase-aware `sessions_per_week` in frameworks + `min:` session floors: `allocate_sessions()` in `scheduler.py` gains `phase` param and `isinstance(v, dict)` check. Allows frameworks to vary modality mix by phase without goal-level overrides.

---

These changes require the vertical package structure to exist before implementation. Issues 1 and 3 use package domain scope as the filtering mechanism. Issue 5 introduces a new archetype that belongs in a specific package directory. Issue 6 extends goal phase definitions.

All changes here are independent of each other and can be done in any order after migration completes.

---

## Issue 1: Irrelevant Archetypes Appearing (BJJ, KB Pentathlon, Grappling Mobility)

### What's wrong

Archetype selection in `selector.py:154` filters candidates by: modality match → phase → training level → equipment → duration. There is no domain or goal-relevance filter. Any archetype matching the modality is eligible.

**Why specific bad selections happen for `ultra_endurance`:**

`grappling_mobility` (modality: `mobility`) wins mobility slots because:
- Equipment: only `open_space` → full equipment bonus (+6)
- Sources: "Kelly Starrett" — `kelly_starrett` is in `ultra_endurance.primary_sources` → source bonus +2
- Score: 8. `endurance_mobility` scores identically (also Kelly Starrett, also open_space). Selection is a coin flip between the two archetypes, and `grappling_mobility` wins half the time.

`kb_pentathlon_training` (modality: `strength_endurance`) wins strength slots because:
- Equipment: only `kettlebell` → if athlete has kettlebell, full +6 equipment bonus
- Sources: "Wildman", "RKC" — neither in `ultra_endurance.primary_sources` → 0 source bonus
- Score: 6. But it's competing against archetypes like `bodyweight_strength_session` (no equipment required → also +6). Selection falls to recency penalty, which rotates them in.

### Root cause in the scoring function

The source match bonus (`selector.py:226-232`) is insufficient as a domain signal:
- It's a soft bonus (+2) easily drowned by the equipment bonus (+6)
- It's a substring match on string content, not a semantic domain relationship
- An archetype from a completely irrelevant philosophy can score 6 (equipment match alone) while the correct archetype scores 8 (equipment + source) — a 2-point gap that recency can easily erase

### The fix: package domain filtering

After migration, each archetype has a `_package` annotation from its file path. Each philosophy package declares its domain in `philosophy.yaml`. Goals declare which domains are compatible.

**Step 1: Add `domain` to each `philosophy.yaml`**

```yaml
# packages/bjj/philosophy.yaml
id: bjj
domain: combat_sport
...

# packages/wildman_kettlebell/philosophy.yaml
id: wildman_kettlebell
domain: kettlebell_sport
...

# packages/uphill_athlete/philosophy.yaml
id: uphill_athlete
domain: endurance
...

# packages/horsemen_gpp/philosophy.yaml
id: horsemen_gpp
domain: gpp
...

# packages/kelly_starrett/philosophy.yaml
id: kelly_starrett
domain: mobility   # domain-agnostic packages can declare 'universal'
...
```

**Step 2: Add `compatible_domains` to goals that need domain restriction**

```yaml
# data/goals/ultra_endurance.yaml
compatible_domains:
  - endurance
  - gpp
  - mobility
  - universal
# Excluded by omission: combat_sport, kettlebell_sport, bjj
```

**Step 3: Update `select_archetype()` in `selector.py`**

Load the domain map at module startup (or pass it in from loader):

```python
# In loader.py — new function
def load_package_domains() -> dict[str, str]:
    """Return {package_id: domain} from all philosophy.yaml files."""
    result = {}
    for path in glob.glob(os.path.join(_PACKAGES_DIR, '*', 'philosophy.yaml')):
        p = _load_yaml(path)
        if 'domain' in p:
            result[p['id']] = p['domain']
    return result
```

In `select_archetype()`, after the existing equipment/phase/level/duration filters, add a domain gate:

```python
# After duration filter, before building candidates list:
compatible_domains = set(goal.get('compatible_domains', []))
pkg_domains = data.get('package_domains', {})  # passed in from load_all_data()

if compatible_domains:
    arch_pkg = arch.get('_package', '')
    arch_domain = pkg_domains.get(arch_pkg, 'universal')
    if arch_domain not in compatible_domains and arch_domain != 'universal':
        continue  # hard filter — not a candidate
```

Archetypes without a `_package` (or whose package has no `domain`) are treated as `universal` and always pass. This is backward compatible — all existing archetypes pass until packages are annotated.

**Step 4: `load_all_data()` includes package domains**

```python
def load_all_data() -> dict:
    exercises, exercises_by_package = load_all_exercises()
    return {
        'modalities': load_all_modalities(),
        'archetypes': load_all_archetypes(),
        'exercises': exercises,
        'exercises_by_package': exercises_by_package,
        'injury_flags': load_injury_flags(),
        'package_domains': load_package_domains(),   # NEW
    }
```

Pass `package_domains` through `generator.py` → `populate_session()` → `select_archetype()`.

### Expected result

For `ultra_endurance` with `compatible_domains: [endurance, gpp, mobility, universal]`:
- `grappling_mobility` (`_package: bjj`, domain: `combat_sport`) → **filtered out**
- `endurance_mobility` (`_package: kelly_starrett`, domain: `mobility`) → **passes** ✓
- `kb_pentathlon_training` (`_package: wildman_kettlebell`, domain: `kettlebell_sport`) → **filtered out**
- `bodyweight_strength_session` (`_package: crossfit` or `marcus_filly`, domain: `gpp`) → **passes** ✓

### Archetypes without `applicable_goal_domains`

Any archetype in a package with no `domain` declared, or any archetype not yet assigned to a package, is treated as `universal` and passes all domain filters. This provides full backward compatibility during the transition.

---

## Issue 3: Peak Phase Has No Running

### What's wrong

This is a downstream consequence of Issue 1 (domain mismatch) plus the allocation math gap (Issue 4, addressed during migration). With the domain filter from Issue 1 applied:

- `aerobic_base` sessions in peak phase will pick `long_zone_2` (domain: endurance) over any durability or grappling archetypes
- `ruck_session` has `modality: durability`, not `aerobic_base` — it cannot win an aerobic slot anyway. This may not be an actual conflict but a reporting error: if the user saw rucks filling what looked like running slots, it was likely the durability slots being displayed alongside aerobic slots

**If the issue persists after Issue 1 fix:** check whether `aerobic_base` sessions are actually being allocated in peak phase. With peak priorities `{aerobic_base: 0.60, durability: 0.25, mobility: 0.15}` and the phase-aware framework fix (done during migration), `aerobic_base` should get 3–4 sessions on 5 days.

**Diagnostic:**
```bash
python -c "
from src.scheduler import allocate_sessions, select_framework
from src import loader
goal = loader.load_goal('ultra_endurance')
fw = loader.load_framework('polarized_80_20')
peak_priorities = {'aerobic_base': 0.60, 'durability': 0.25, 'mobility': 0.15}
print('peak allocation:', allocate_sessions(peak_priorities, 5, fw))
"
```

**If aerobic_base is allocated but running archetypes aren't winning:**

Add `applicable_goal_domains: [endurance, gpp]` to `long_zone_2.yaml` (already in the endurance package after migration). Once domain filtering is active, `long_zone_2` competes only against other endurance/gpp aerobic archetypes.

### Source scoring fix (independent of domain filtering)

The scoring gap between `endurance_mobility` and `grappling_mobility` is only 0 points (both score identically for a Kelly Starrett goal). Add explicit anti-domain scoring: archetypes with zero source overlap AND from a non-compatible package take an additional penalty:

```python
# In _score_arch():
if compatible_domains and arch_domain not in compatible_domains:
    score -= 10   # effectively eliminates them if hard filter isn't applied
```

This is a fallback if hard filtering isn't implemented, or a belt-and-suspenders addition alongside it.

---

## Issue 5: No Long Run Differentiation

### What's wrong

All Zone 2 sessions use the same `long_zone_2` archetype with `duration_sec: 5400` (90 min). On a 5-session aerobic week, all five sessions are prescribed identically. Ultra endurance training requires one weekly session that is 2–4× longer (the "long run": 3–5h in build, up to 5h in peak).

`_time_to_task()` in `progression.py` applies the same base duration to every instance of an archetype in a week. There is no mechanism to designate one session as the long effort.

### The fix: a new archetype + selector "one per week" logic

**Step 1: Create `packages/uphill_athlete/archetypes/weekly_long_effort.yaml`**

```yaml
id: weekly_long_effort
name: "Weekly Long Effort (Endurance)"
modality: aerobic_base
category: conditioning
duration_estimate_minutes: 180
required_equipment: []
applicable_phases:
  - build
  - peak
sources:
  - "Uphill Athlete"
  - "CrossFit Endurance"
notes: >
  The single long aerobic session of the week. Duration 2–5 hours depending on phase
  and athlete level. Kept at Zone 1–2 throughout — the long run is a volume stimulus,
  not an intensity stimulus. Uphill Athlete: one long effort per week is the cornerstone
  of aerobic base development. The goal is time on feet, not pace.
  Modality: run preferred for mountain/trail goals; hike, bike, or row are valid
  substitutes. Consistent modality within a training block is preferred.

slots:
  - role: long_aerobic_effort
    slot_type: time_domain
    duration_sec: 10800     # 3 hours base; scales to 18000 (5h) in peak via _time_to_task
    intensity: zone2
    phase_duration_multipliers:
      base: 1.0             # 3h
      build: 1.33           # 4h
      peak: 1.67            # 5h
      taper: 0.50           # 90 min — leg freshening, not a real long run
    exercise_filter:
      category: aerobic
    notes: >
      Zone 1–2 throughout. Nasal breathing test: if you cannot breathe through
      the nose, slow down. Carry nutrition for efforts over 90 min. Practice
      race nutrition strategy in build and peak phase long runs.

scaling:
  deload:
    volume_multiplier: 0.5
    duration_estimate_minutes: 90
    notes: "Deload long run: cut to 90 min max. Intensity unchanged."
  time_limited:
    drop_slots: []
    notes: "Long effort cannot be meaningfully shortened below 90 min. If time is the constraint, use long_zone_2 instead."
  equipment_limited:
    substitutions:
      - missing_equipment: none
        substitute_approach: "Any continuous aerobic modality. Run > hike > cycle > row for mountain goals."
```

**Step 2: Add selector logic for "one long effort per week"**

In `populate_session()` in `selector.py`, track whether a `weekly_long_effort` archetype has already been selected this week. Pass a `week_arch_ids` set through the generator's day loop:

```python
# In generator.py — extend the day loop:
week_long_effort_used = False  # reset each week

for day in sorted(week_schedule.keys()):
    for session in sessions:
        populated = populate_session(
            session, goal, constraints, exercises, archetypes,
            injury_flags_data, phase, week_in_phase,
            recent_arch_ids, recent_ex_ids,
            collect_trace=include_trace,
            week_long_effort_used=week_long_effort_used,   # NEW
        )
        if populated.get('archetype', {}).get('id') == 'weekly_long_effort':
            week_long_effort_used = True
```

In `select_archetype()`, when `week_long_effort_used=True`, exclude `weekly_long_effort` from candidates:

```python
if week_long_effort_used and arch['id'] == 'weekly_long_effort':
    continue
```

This ensures the long effort archetype appears exactly once per week. All other `aerobic_base` sessions use `long_zone_2` (60–90 min).

**Step 3: Require the long effort in weeks with ≥ 3 aerobic sessions**

Alternatively, make the long effort the preferred archetype on the last aerobic day of the week (highest day number in the pool that has an aerobic session). This is simpler but harder to implement without restructuring the day loop.

The one-per-week flag approach (Step 2) is sufficient.

### `phase_duration_multipliers` wiring in progression.py

The `weekly_long_effort` archetype slot includes a `phase_duration_multipliers` field. This requires the 3-line change to `_time_to_task()` described in the vertical-philosophy-ontology.md code changes section:

```python
# progression.py — _time_to_task(), lines 113-119
phase_mult = slot.get('phase_duration_multipliers') or {
    'base': 1.0, 'build': 1.25, 'peak': 1.40,
    'taper': 0.60, 'deload': 0.60, 'maintenance': 1.0,
}
target_sec = int(base_sec * phase_mult.get(phase, 1.0))
```

Without this change, `weekly_long_effort` gets the default `_time_to_task` phase multipliers (1.25× in build, 1.40× in peak), which still gives 3.75h and 4.5h — reasonable but not the intended 4h/5h. The wiring is needed for precise control but the archetype is useful even without it.

### Expected result

A build-phase week with 3 aerobic sessions:
- Session 1 (Mon): `long_zone_2` → 90 min Zone 2
- Session 2 (Wed): `long_zone_2` → 90 min Zone 2
- Session 3 (Sat): `weekly_long_effort` → 4h Zone 2

Clear differentiation. The weekly long run appears exactly once.

---

## Issue 6: No Back-to-Back Long Days in Build

### What's wrong

`_recovery_safe()` in `scheduler.py:210-226` actively prevents consecutive sessions for the same modality and prevents two high-cost modalities within 48 hours. This is correct for most goals but directly contradicts the ultra endurance build phase prescription:

> "Introduce back-to-back long days (Friday/Saturday) for glycogen depletion adaptation."

The recovery system will never place two `aerobic_base` sessions on consecutive days, even when the goal explicitly requires it.

### The fix: phase-level recovery override in goal YAML

**Step 1: Extend the phase definition schema in `ultra_endurance.yaml`**

```yaml
  - phase: build
    weeks: 8
    focus: >
      ...
    priority_override:
      aerobic_base: 0.50
      durability: 0.20
      anaerobic_intervals: 0.10
      strength_endurance: 0.10
      mobility: 0.10
    back_to_back:
      enabled: true
      modalities: [aerobic_base]
      preferred_day_pairs: [[5, 6]]    # Friday + Saturday (1=Mon … 7=Sun)
      max_pairs_per_week: 1
```

**Step 2: Pass phase config through the scheduler**

In `schedule_week()`, extract the back-to-back config for the current phase:

```python
def schedule_week(goal, constraints, data, phase, week_number, collect_trace=False):
    ...
    # Extract back-to-back config for this phase
    btb_config = None
    for phase_entry in goal.get('phase_sequence', []):
        if phase_entry['phase'] == phase:
            btb_config = phase_entry.get('back_to_back')
            break
```

**Step 3: Modify `_recovery_safe()` to accept a relaxation set**

```python
def _recovery_safe(day, modality, mod_data, schedule, modalities,
                   back_to_back_modalities=None) -> bool:
    """Return True if placing modality on day respects recovery windows.
    
    back_to_back_modalities: set of modality IDs for which consecutive-day
    placement is explicitly permitted (overrides the 48h high-cost rule).
    """
    btb_allowed = set(back_to_back_modalities or [])
    recovery_needed = mod_data.get('recovery_hours_min', 24)
    my_cost = _RECOVERY_COST_RANK.get(mod_data.get('recovery_cost', 'low'), 1)

    for prev_day in range(max(1, day - 3), day):
        hours = (day - prev_day) * 24
        for prev_mod in schedule.get(prev_day, []):
            if prev_mod == modality and hours < recovery_needed:
                if modality in btb_allowed:
                    continue   # back-to-back explicitly permitted for this modality
                return False
            pm_cost = _recovery_cost_rank(prev_mod, modalities)
            if my_cost == 3 and pm_cost == 3 and hours < 48:
                if modality in btb_allowed:
                    continue   # high-cost consecutive day permitted
                return False
    return True
```

**Step 4: Preferred day-pair enforcement**

When `back_to_back.preferred_day_pairs` is set, `_build_day_pool()` should bias toward including those day pairs. The simplest approach: if the day pool doesn't include both days of a preferred pair, force the second day in:

```python
# In _build_day_pool(), after computing desired:
if btb_config and btb_config.get('enabled'):
    for pair in btb_config.get('preferred_day_pairs', []):
        d1, d2 = pair
        if d1 in desired or d1 in forced_workout:
            desired.add(d2)  # guarantee the back-to-back day is in pool
```

**Step 5: Pass `btb_config` through `assign_to_days()`**

```python
raw = assign_to_days(
    allocation, data['modalities'], len(pool), pool,
    back_to_back_modalities=set(btb_config.get('modalities', [])) if btb_config else None
)
```

### Expected result

In the build phase on a week where the pool includes days 5 (Fri) and 6 (Sat):
- Two `aerobic_base` sessions can be placed on days 5 and 6
- The normal recovery gate is relaxed only for `aerobic_base`, only in the build phase
- All other modalities (strength, durability) still respect standard recovery windows
- Other phases (base, peak, taper) are unaffected — the back_to_back config is phase-scoped

### Scope note

The `back_to_back` field in the phase definition is a general schema addition. Any goal can use it:
- `alpine_climbing` could add consecutive ruck days in peak phase
- `sof_operator` could allow consecutive high-intensity days in build
- `bjj_competitor` could allow back-to-back BJJ sessions when `allow_split_sessions: true`

The recovery relaxation is surgical — it only applies to the modalities listed, only in the phase that declares it.

---

## Implementation Order

These four issues are independent. Suggested order after migration:

1. **Issue 1 (domain filtering)** `[ ]` — highest impact, fixes the most visible bad output. Requires: `domain` on 11 philosophy YAMLs, `compatible_domains` on relevant goal YAMLs, `load_package_domains()` in loader, domain gate in `select_archetype()`, pass-through in generator/selector.

2. **Issue 3 (peak running)** `[ ]` — verify it's resolved by Issue 1 fix first. If not, add anti-domain scoring penalty and check the phase-aware framework allocation math.

3. **Issue 5 (long run differentiation)** `[ ]` — self-contained. One new archetype YAML + `week_long_effort_used` flag in generator + `phase_duration_multipliers` wiring in progression.py.

4. **Issue 6 (back-to-back days)** `[ ]` — self-contained. YAML schema extension + `_recovery_safe()` relaxation + `_build_day_pool()` pair enforcement.
