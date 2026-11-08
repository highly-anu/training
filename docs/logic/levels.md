# Levels: written for one athlete, done by every athlete

A package writes its sessions as its source does, for the athlete the source
writes for: CrossFit's Rx, Fran at 43 kg, 21-15-9. This framework lets the
same package serve every training level (novice, intermediate, advanced,
elite: `data/commons/training_levels.yaml`) in three layers, each data, none
naming a package (`tools/check_code_neutral.py`).

Since 2026-11-07. Pilot: CrossFit. The other packages convert one change at a
time (`docs/roadmap.md`, item 18).

## 1. Which movements: suitability

An exercise's lowest suitable level is **computed**, never tagged:
`src/level_suitability.py` asks `selector._get_unlocked` at each level, on the
package's own copies (`provenance.scope`'s order: the package, then what it
borrows). That reads

- the exercise's `requires` chain, resolved to a fixed point;
- the commons' level concepts (`data/commons/level_concepts.yaml`) and the
  package's seeds (`level_seeds.yaml`, a training contract track's
  `level_seeds`);
- an exercise's optional `min_level`, for a movement no chain locks (a full
  snatch): below it the exercise is locked whatever is known.

`/api/explore/links` serves the table as `exerciseLevels`
(`{package: {exercise: {minLevel, scalesTo}}}`), and Explore's exercise page
says "Suits Intermediate and up". Without `requires` or `min_level` an
exercise suits a novice: a package that converts says which of its movements
do not.

**A movement out of reach is scaled.** In a slot of a `scaling_eligible`
archetype that names its movement, a written movement the athlete cannot do
(locked at the level, or no equipment for it) is replaced by the first
doable of its `scaling_down` list, nearest first (breadth first:
`selector._scaled_slot`). The assignment says `scaled_from` (+ `_name`) and
`scale_cause` (`level` or `constraint`). Only a slot whose movement nothing
scales still empties, and a named workout that cannot be done is passed over
as before (`generator._fits_as_written`). Scales are the package's own
exercises, usually `named_only`, so adding one never changes an open slot.

## 2. How much: dose

A track opts in with `authored_level` (`philosophy.yaml`). Below it, a
session whose archetype is `scaling_eligible` is done at a share of what is
written, per dimension:

| Dimension | Scales | Never |
|-----------|--------|-------|
| `load` | a slot's `load_kg` (a number, or `{male, female}` by the athlete's `sex`) | a % of 1RM or of bodyweight, RPE: already the athlete's own |
| `volume` | the sets where there are several, else the reps, `rep_scheme`, reps a round — once, never both; a rep ladder ("25-20-15-10-5", one rung a set) rung by rung, its sets kept | rounds of a for-time piece (its structure) |
| `time` | an AMRAP's or a cap's minutes, a block's minutes, holds; an interval's rounds (and its minutes with them) | an interval's length (every 30 s stays every 30 s), rest |
| `distance` | metres, kilometres | |

The share is the track's own `level_scaling.<level>.<dimension>` where its
source says (CrossFit's Level 1 guide: half for a newcomer), else the
commons' (`training_levels.yaml` `scaling`, relative to the authored level:
novice 0.5, intermediate 0.7, advanced 0.85 of an elite prescription), never
more than written. Counts round half up and never go under one; seconds to
5 s, metres to 10 m, kilograms to 2.5 kg (1 kg under 20 kg: dumbbells and
balls; 4 kg for a kettlebell). Converted: CrossFit (Rx elite, the Level 1
guide's half for a novice), Gym Jones (Operator Fitness elite, Soldier of
Steel the novice's own, never scaled), Horsemen (every workout elite,
novices taken in, the hardest movements kept for intermediates and up).

`src/level_scaling.scale_prescription` is the one function, called by
`progression.calculate_load` (the generator, `POST /sessions/generate`,
`/exercises/substitute`; a single-session route finds the track by the week's
phase) and on a structural slot's load. The scaled load keeps each written
value under `rx` and says `level_scaled: {level, from, shares, sources}`;
`load_note` reads "15 kg · Rx 95 lb (43 kg); women 65 lb (30 kg)". Both
clients word it (web `lib/levelScaling.ts`, iOS `LoadFormat.scaledText`):
"Scaled for Novice · Rx 21-15-9 reps · 30 kg", "In place of Pull-Up".

**A scaled benchmark is not its standard's result.** A named workout that is
a selectable test (Fran) done below the authored level carries no `standard`
on its scored slot (`scaled_standard` names it), so no suggestion places a
scaled time on the Rx ladder. A test a phase places (a protocol) is never
scaled.

**Precedence.** A version the source wrote for the level wins: an archetype
or track whose `training_levels` include it and which is not
`scaling_eligible` runs as written (Ido's routines, Starting Strength's LP
and Texas Method, Gym Jones's Soldier of Steel, ATG's programs). Then the
track's `level_scaling`, then the commons' shares.

**Not yet:** training contracts (`training_contract._assignment` and its
`verify`) do not scale; a contract track's modules carry their own per-level
volume (`start_minutes`). A contract package converts with its own change,
which adds the hook and its mirror in `verify`. An exercise's
`starting_load_kg` stays per level as authored (no elite × share fallback
yet).

## 3. The elite target: standards

`analytics.yaml` names `elite_standards`: the standards whose elite rung the
authored prescriptions are for (CrossFit: the benchmark workouts).
`tools/check_analytics.py` fails a package with a scaled track and none;
`tools/check_provenance.py` checks the ids. Each level trains toward its own
rung (`standard_rung`: novice → entry, the rest by name): a standard's
"intermediate" is roughly where a novice program ends, so the ladders are not
one-to-one. Standards stay measures: the engine never moves a level.

## Fidelity

Scaling the source does not state is the app's. `package_fidelity.unrecorded_scaling`
(in the S3 references) fails a package whose track takes the commons' shares
without a rule or invention naming `tracks.<id>.authored_level`, or whose own
`level_scaling.<level>` no rule cites. The scorecard and the fidelity gate read
a scaled track's ideal athlete at its authored level (`check_fidelity._track_ranges`);
its `eval-level-*` profiles read the levels below. `test_single_lane_golden.py`
pins a scaled track at its authored level too.

## Converting a package

1. Set each track's `authored_level`; write `level_scaling` where the source
   says, and record the rest as an invention.
2. Give fixed loads `load_kg`; leave relative loads as text.
3. Mark the archetypes the levels below reach by scaling `scaling_eligible`
   and widen their `training_levels`; leave source-written versions alone.
4. Give the hardest movements `min_level` or a `requires` chain, and every
   movement that may be out of reach a `scaling_down` the package owns.
5. Name `elite_standards`.
6. Re-record: `test_single_lane_golden.py --record --package <id>`,
   `tools/evaluate_packages.py --package <id> --update-baseline`; review the
   output at the lowest level and the authored one.
