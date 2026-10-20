# Executable training contracts

Wildman was the first opt-in package; BJJ and Starting Strength followed. `training_contract.yaml` is validated against
`docs/schemas/training_contract.schema.json` before it becomes part of a goal.
Other packages retain their legacy generator while their contracts are authored.

## Contract guarantees

- Fixed movement sequences, independent module cursors, required weekly exposures,
  cyclic recovery spacing, injury restrictions and actual elapsed-time budgets.
- Supported density, timed-set and technique-hold policies, with no silent model fallback.
- Phase changes never earn proficiency, reset a cycle or authorize a heavier bell.
- No cross-track template substitution, generic accessory injection or implicit blend.
- Exact scored pentathlon events; practice reductions do not rescale test protocols.
- Post-generation verification rejects unfulfilled contracts. The API returns 422
  and never persists that response. Generic session/exercise swaps cannot bypass it.

## Optional modules and placement

A module marked `optional: true` is supplementary work the method lets the athlete
skip — Pentathlon Prep's easy runs. It is placed after the essential modules, only
on days none of them uses, and never after the track's test module in the week;
when no such day is free, or an injury, avoided movement or missing equipment
rules its movement out, it is left out and the week and the program's compromises
say why. It is never a reason to refuse the request.

Essential modules are placed by searching every valid placement (exposures,
spacing, budget) and keeping the first that (1) puts the test module's session
last in the week, so a test week differs from its twin only by the test and the
test closes it; (2) gives no module a shared day it does not need; and (3) fits
the most optional sessions. Recovery spacing holds across week boundaries too.

A block that progresses without a bell says `progresses: true` (an easy run's
minutes follow its timed cycle); `intensity: zone2` writes the zone band onto the
load, so the analytics count that block's heart rate. A scored test is verified
against its own protocol's minutes, which need not equal the module's weekly
ceiling (Pentathlon's practice sets stop at four minutes, the events run six), and
it carries the protocol's hand switch for the watches.

An optional module may name modules it `never_with` shares a day: BJJ's
competition conditioning joins a strength day with the minutes for it, never a
class day.

## Alternating sessions and load per confirmed exposure (Starting Strength)

A module may declare `variants` and a `rotation`: the rotation names the variant
each exposure runs, so Starting Strength's `rotation: [a, b]` runs A-B-A one week
and B-A-B the next, and the Texas Method's six variants (volume, light and
intensity days, the press and bench swapping) run over two weeks. A session
carries its variant (`modules[].variant`), its archetype and its name ("Workout
A"); `verify` holds the order.

`progression.model: load_per_exposure` prescribes kilograms from what the athlete
made. Each lift in `module_state[mid].lifts` keeps `next_kg` (what its next
progressing exposure lifts), `kg` (the last made), `exposures`, `failures`,
`resets` and `stalled`:

- a made exposure adds the lift's increment (`lifts.<id>.increments_kg`: the
  first `first_exposures` at the larger step, a step smaller after that and after
  each reset), rounded to `round_kg`;
- a miss repeats the weight; `stall.failures` misses in a row reset it by
  `stall.reset_pct`; a lift that stalls again after `stall.resets` resets holds,
  `stalled`, and its note sends it to the next track;
- a block with `pct` (the Texas Method's Monday at 90 %) reads its lift's last
  made weight and does not move it; a block at full weight does;
- a lift with no weight works up on the day (`load.work_up`), unless the builder
  sent `starting_loads_kg` (the last weight made); an athlete whose program this
  contract did not write starts from the last logged sets (`seed_lifts`).

Future sessions are forecasts that assume every lift is made (`conditional`).
The confirmed state counts attended sessions, so the rotation moves on a missed
lift, and moves each lift on its own outcome: the one-tap confirm takes `lifts`
— {exercise id: {made, weightKg}} for the ones that went otherwise than written —
and a session's logged sets say the same. `verify` recomputes every weight.

A philosophy's `track_for_level` gives a request that names no track the one
written for the athlete's level (Starting Strength: novice → Linear Progression,
intermediate → Texas Method); a track refuses another level by naming the track
that fits.

## Wildman's Phase II and sources

General Practice is Wildman's Phase II on the Tetris of Training: his programs,
each twice a week on nonconsecutive days, stacked as the session time holds. The
swing module runs the public Nerd Math swing program's four approaches in order —
6 to 20 swings a minute (two more a session) over a 10-minute EMOM, then a
20-minute one, then start/stop swings in ten and twenty 90-second rounds — sixteen
weeks at two a week, then a heavier bell. A density cycle's `interval_sec` and
`cues` express the stages; a stage that does not fit the session falls back to the
longest earlier one that does, at the same interval first ("if pressed for time, do
the short version"). Clean and press stays essential; the Turkish get-up and the
deck squat are `optional` modules that `may_share_day`, taking a day beside the
essential work when its minutes allow; the snatch is `when_mastered`, joining only
once confirmed (it is then no entry requirement). The program has no deload week
and one repeatable phase, `build`; `former_ids` lets a stored week that names
foundations, ladder or practice still regenerate.

Sources are recorded in the package contract, including
https://www.wildmanathletica.com/programming and the public swing-program FAQ.

## Confirmed state versus forecast

`module_state` records confirmed completed exposures and an optional selected
`weight_kg`, keyed by module id. `load` records the resolved model, module id,
forecast step, conditional status, elapsed seconds and prescription version.
Future exposures are conditional forecasts. Only chronologically ordered,
completed sessions with all required outcomes, clean mechanics and RPE at or below
the module ceiling advance confirmed state. Missing, failed, out-of-order, deload
and scored-test sessions do not. Existing active-program log scoping is reused.

An API regeneration automatically recovers that state from the current program
and its logs when the contract identity/version matches. An explicit
`constraints.module_progression_state` starts or resumes a chosen cycle. A new bell
requires explicitly starting a new cycle; no fractional or level-derived bell is
invented. `kettlebell_weights_kg` optionally restricts choices to actual inventory.
Pentathlon requires `mastered_exercises` listing all five event movements.

Web and phone expose clean completion, actual bell weight and RPE for module
outcomes. API and phone/watch descriptions retain repetitions per interval.
Unknown phone model fields survive its existing Codable extras mechanism.

Timed blocks are rounded up to whole minutes for existing phone/watch support;
the compiler budgets the rounded work, including prescribed rests. A shorter
session request fails if its required work cannot fit; only the label is never cut.

## Verification

Run `python test_training_contract.py`, the selection/phase/standard regression
scripts, entity validation and `tools/check_fidelity.py --package wildman_kettlebell`.
Contract profiles cover every supported level. Unsupported home/injury/time
profiles are explicit refusals; ideal profiles and malformed contracts fail the gate.
The GitHub workflow runs these checks before changes reach the default branch.

## Catalog reachability

Wildman now also offers separate squat, snatch, get-up/mobility and double-bell
practice tracks. Their prescriptions are explicit app adaptations. See
[wildman_catalog_coverage.md](wildman_catalog_coverage.md) for the evidence, exact
counts and limits. `tools/check_exercise_coverage.py` enforces package-wide
generated reachability rather than demanding variety inside each track. Web and
phone builders expose the proficiency and matching-bell entry confirmations.
