# Before Migration: Data Fixes

Two bugs causing bad output in the currently working system. Both are pure YAML edits — no code changes. Fix these before touching the package reorganization so the baseline is correct.

---

## Issue 7: Modality Naming Mismatch (Strength Gets No Sessions)

### What's wrong

`ultra_endurance.yaml` uses `strength_endurance: 0.10` in its priorities. `polarized_80_20.yaml` lists `max_strength: 1` in `sessions_per_week`. These are different modality IDs.

`allocate_sessions()` in `scheduler.py:164` filters framework modalities to only those the goal prioritises:

```python
active_fw = {mod: cnt for mod, cnt in fw_sessions.items()
             if priorities.get(mod, 0) > 0}
```

`max_strength` has zero priority weight in `ultra_endurance` → gets filtered out. `strength_endurance` is a "goal-only" modality with no framework backing → competes for leftover slots after aerobic sessions are allocated. On 5 days with `strength_endurance: 0.10` priority it gets 0–1 sessions, and often 0 after rounding.

### The fix

**Two changes, one to each file.**

**`data/frameworks/polarized_80_20.yaml`** — replace `max_strength: 1` with `strength_endurance: 1`:

```yaml
# Current:
sessions_per_week:
  aerobic_base: 4
  anaerobic_intervals: 1
  max_strength: 1

# Fixed:
sessions_per_week:
  aerobic_base: 4
  anaerobic_intervals: 1
  strength_endurance: 1
```

Rationale: the Uphill Athlete supplementary strength prescription is explicitly structural and muscular endurance-focused (single-leg deadlift, split squat, step-up) — not maximal strength work. `strength_endurance` is the correct modality. `max_strength` belongs to the barbell-primary philosophies (starting_strength, gym_jones).

**`data/goals/ultra_endurance.yaml`** — no change needed to priorities (already uses `strength_endurance: 0.10`). The framework fix above makes the engine see that modality as framework-backed, elevating it from leftover-slot competition to a guaranteed slot.

### Expected result after fix

With 5 days/week, base priorities `{aerobic_base: 0.60, durability: 0.20, strength_endurance: 0.10, mobility: 0.10}`:

- `strength_endurance` is now in `active_fw` (framework ratio: 1/6)
- Framework-covered priority = 0.60 + 0.10 + 0.10 = 0.80 (aerobic + strength_end + anaerobic — but anaerobic_intervals is 0 in base, so effectively 0.70)

Wait — base phase has no `priority_override` so all modalities use root priorities. `anaerobic_intervals` isn't in root priorities → still filtered. But `strength_endurance` now IS in the framework and IS in priorities → guaranteed at least 1 session.

On 5 days: strength_endurance gets 1 session (from its 1/5 framework share within covered modalities). Correct.

### Verify

```bash
python -c "
from src.scheduler import allocate_sessions
from src import loader
fw = loader.load_framework('polarized_80_20')
priorities = {'aerobic_base': 0.60, 'durability': 0.20, 'strength_endurance': 0.10, 'mobility': 0.10}
print(allocate_sessions(priorities, 5, fw))
# Expect: aerobic_base=3, durability=1, strength_endurance=1 or similar
# Before fix: strength_endurance=0 or 1 (volatile), strength_endurance often 0
"
```

---

## Issue 2: Missing Threshold Intervals in Build Phase

### What's wrong

`ultra_endurance.yaml` build phase `priority_override` does not include `anaerobic_intervals`:

```yaml
# Current build phase:
priority_override:
  aerobic_base: 0.55
  durability: 0.25
  strength_endurance: 0.10
  mobility: 0.10
```

`polarized_80_20.yaml` defines `anaerobic_intervals: 1` in `sessions_per_week`. But because `anaerobic_intervals` has zero weight in the build phase override, `allocate_sessions()` filters it out entirely:

```python
active_fw = {mod: cnt for mod, cnt in fw_sessions.items()
             if priorities.get(mod, 0) > 0}   # anaerobic_intervals: 0 → excluded
```

Zero threshold sessions in the build phase. The goal's own focus text says "Add 1×/week threshold intervals" in build — the data contradicts the stated intent.

### The fix

**`data/goals/ultra_endurance.yaml`** — add `anaerobic_intervals` to the build phase `priority_override`, and renormalise weights to sum to 1.0:

```yaml
# Current:
  - phase: build
    weeks: 8
    focus: >
      Extend long efforts toward race simulation distance. Introduce
      back-to-back long days (Friday/Saturday) for glycogen depletion
      adaptation. Add 1×/week threshold intervals. Strength shifts to
      maintenance (1×/week). Ruck and loaded carry training for expedition goals.
      Increase total weekly vertical gain.
    priority_override:
      aerobic_base: 0.55
      durability: 0.25
      strength_endurance: 0.10
      mobility: 0.10

# Fixed:
  - phase: build
    weeks: 8
    focus: >
      Extend long efforts toward race simulation distance. Introduce
      back-to-back long days (Friday/Saturday) for glycogen depletion
      adaptation. Add 1×/week threshold intervals. Strength shifts to
      maintenance (1×/week). Ruck and loaded carry training for expedition goals.
      Increase total weekly vertical gain.
    priority_override:
      aerobic_base: 0.50
      durability: 0.20
      anaerobic_intervals: 0.10
      strength_endurance: 0.10
      mobility: 0.10
```

Weight rationale:
- `aerobic_base` drops from 0.55 → 0.50: one slot is now carved out for intervals
- `durability` drops from 0.25 → 0.20: slightly less ruck/carry emphasis in build to make room
- `anaerobic_intervals: 0.10`: gives it enough weight to survive `_proportional_round` and land 1 session on 5 days
- `strength_endurance` and `mobility` unchanged at 0.10 each
- Total: 1.00 ✓

### What this means for session allocation

On 5 days in build phase with framework `polarized_80_20`:

- `active_fw` now includes `aerobic_base: 4`, `anaerobic_intervals: 1`, `strength_endurance: 1` (all have priority weight > 0)
- `active_total` = 6
- `fw_covered_prio` = 0.50 + 0.10 + 0.10 = 0.70
- `fw_slots` = 5 × 0.70 = 3.5
- `aerobic_base` raw = (4/6) × 3.5 = 2.33
- `anaerobic_intervals` raw = (1/6) × 3.5 = 0.58
- `strength_endurance` raw = (1/6) × 3.5 = 0.58
- `durability` and `mobility` split the remaining 1.5 goal-only slots
- After `_proportional_round` to 5: likely `aerobic_base=2, durability=1, anaerobic_intervals=1, strength_endurance=1`

One threshold session per week. Matches the stated training intent.

### What archetype gets picked for anaerobic_intervals?

The selector will look for archetypes with `modality: anaerobic_intervals`. The existing `threshold_intervals` archetype (`data/archetypes/conditioning/threshold_intervals.yaml`) has:
- `modality: anaerobic_intervals` ✓
- `applicable_phases: [build, peak]` ✓
- `sources: ["Uphill Athlete", "CrossFit Endurance", "Gym Jones"]`

`uphill_athlete` is in `ultra_endurance.primary_sources` → source match bonus +2. This archetype will win.

### Verify

```bash
python -c "
from src.scheduler import allocate_sessions
from src import loader
fw = loader.load_framework('polarized_80_20')
build_priorities = {
    'aerobic_base': 0.50, 'durability': 0.20,
    'anaerobic_intervals': 0.10, 'strength_endurance': 0.10, 'mobility': 0.10
}
print(allocate_sessions(build_priorities, 5, fw))
# Expect: anaerobic_intervals=1 is present
"

python main.py  # or POST /api/programs/generate with ultra_endurance, build phase
# Check: threshold_intervals archetype appears in week schedule
```

---

## Applying Both Fixes Together

`data/goals/ultra_endurance.yaml` receives one edit (build phase priority_override). `data/frameworks/polarized_80_20.yaml` receives one edit (sessions_per_week). No code changes. Run the full generator after both edits and check all four phases still produce valid output.

Regression check: run `bjj_competitor`, `general_gpp`, and `alpine_climbing` goals — the framework change to `polarized_80_20` only affects goals that use it (`ultra_endurance` is the primary user). The `bjj_performance` and `concurrent_training` frameworks are unaffected.
