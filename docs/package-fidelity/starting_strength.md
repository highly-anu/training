# Starting Strength — source dossier

Both tracks run as the sources write them, and the load follows what the athlete
confirms lifting. Engine shape: training contract
(`data/packages/starting_strength/training_contract.yaml`) with the
`load_per_exposure` model and alternating variants (docs/logic/training_contracts.md).
The record — sources, rules with what enforces each, inventions — is
`data/packages/starting_strength/fidelity.yaml`; this page is its prose, by the same ids.
The status is the scorecard's (status.yaml).

## Sources

- Mark Rippetoe, "Who Wants to Be a Novice? You Do", startingstrength.com, 2 May 2013
  (read in full via the Wayback Machine; the site refuses scripted fetches) — the
  novice program.
- Mark Rippetoe, "The Texas Method", startingstrength.com, 1 May 2013 (first on
  T-Nation, 2010; read in full) — the intermediate week.
- Rori Alter, DPT, SSC, "The Reset: Why and How", startingstrength.com, 3 October 2018
  (read in full) — what a stalled novice lift does; written by a Starting Strength
  coach, citing *Starting Strength: Basic Barbell Training* and *Practical Programming*.
- *Starting Strength: Basic Barbell Training* (3rd ed.) and *Practical Programming for
  Strength Training* — the books the articles summarise; not read for this dossier, and
  nothing below rests on them alone.

## Rules → where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | Two workouts alternate, A-B-A one week and B-A-B the next (Rippetoe 2013) | `novice_lp` `variants` a, b and `rotation: [a, b]`; the cursor counts attended sessions |
| R2 | A: squat 3×5 across, press 3×5 across, deadlift 1×5, chin-ups 3 sets to failure, 5 min between (Rippetoe 2013) | variant `a` blocks; chin-ups `to_failure` |
| R3 | B: squat 3×5, bench 3×5, power clean 5×3 across; rows are not a substitute (Rippetoe 2013) | variant `b` blocks; no alternatives declared |
| R4 | Three days, 48–72 hours apart (Rippetoe 2013) | `exposures_per_week: 3`, `min_spacing_days: 2`; fewer days refuse |
| R5 | Every lift goes up every workout (Rippetoe 2013) | `load_per_exposure`: a made exposure adds the lift's increment |
| R6 | First session: empty bar, sets of five, small jumps to a heavy weight that keeps form, two more sets there (Rippetoe 2013) | `work_up` prescription for a lift with no weight; the logged weight becomes its start |
| R7 | Squat +10 lb for two weeks, then +5; deadlift +15 at first, then 5; press, bench, clean +5, then 1–3 (Rippetoe 2013, 2013 TM) | `lifts.*.increments_kg` / `first_exposures`, in kg rounded to 1.25 kg plates |
| R8 | Missed reps once: repeat the weight; missed at one weight twice in a row: reset 5 % and climb in smaller jumps (Alter 2018) | `stall: {failures: 2, reset_pct: 5}`; a step down `increments_kg` after a reset |
| R9 | Stalled again after the adjustments: that lift is intermediate; the others carry on (Alter 2018) | `stall.resets: 1`: the lift holds, `stalled`, and its note sends it to the Texas Method |
| R10 | Novice ends when progress stops session to session; intermediates progress weekly (Rippetoe 2013) | `track_for_level`: novice → Linear Progression, intermediate → Texas Method; the novice track refuses an intermediate, naming the Texas Method |
| R11 | Monday: squat 5×5 across at ~90 % of 5RM (up to 8–10 min rest); press or bench 5×5 at ~90 %, alternating Mondays; one heavy set of five deadlifts, up every week (Rippetoe, TM) | `texas_method` variants `volume_press` / `volume_bench`; `pct: 0.9`; the deadlift advances |
| R12 | Wednesday: squat 2×5 at 80 % of Monday; the other press for three lighter sets; chin-ups 3×failure (Rippetoe, TM) | `light_*` variants, squat `pct: 0.72` (80 % of 90 %) |
| R13 | Friday: a new 5RM (within 2 %) on the squat and the press; power cleans 5×3 (Rippetoe, TM) | `intensity_*` variants; the advancing blocks |
| R14 | No conditioning beyond "don't do much"; no deload week | no conditioning module; `linear_progression` and `texas_method` declare no `deload_protocol` |

## Open

- Which press Friday intensifies: the article says "the squat and the press or bench";
  the contract reads it as Monday's press (Monday's volume becomes Friday's max).
- The book's earlier novice phase (deadlifts on both days before the power clean) —
  the 2013 article programs the clean from the start, and so does the contract.
- Two-day weeks and sessions under an hour: no source writes a shorter version, so
  the contract refuses them (a 45-minute day names the 60 minutes Workout A needs).
- Curls (Rippetoe: "if you must", on B) and the Texas Method's back extensions
  (optional in the article) are not programmed.
- A Texas Method Friday that stalls has no rule in the article; the contract repeats
  the weight.

## Debt (rules nothing enforces yet)

- R15: after a first stall, a light squat day (80 % of the first day's squat, 2×5)
  joins the week; after a second, the lift switches to 5×3 (Alter 2018). The contract
  resets 5 % and steps the increment down, then flags the lift.
- R16: layoffs — a week off repeats the last workout; longer resets 5 % under 40, 10 %
  over; three to four weeks resets 10 % (Alter 2018).

## Inventions

- I1: chin-ups are left out, and said so, when there is no pull-up bar; the article
  lists them in Workout A.
- I2: the Texas Method's weekly increments (2.5 kg squat and deadlift, 1.25 kg presses
  and clean): the article gives none.
- I3: the light day's press shares (bench 85 %, press 87.5 % of the five-rep max): the
  article says "a little lighter than the last 5×5" and "a little heavier relative to
  5RM" for the press.

## Tests

Source weeks (`data/packages/starting_strength/source_weeks.yaml`): two novice weeks,
A-B-A and B-A-B with each workout's sets and reps (R1); the squat's jumps over nine
sessions (R7); a Texas Method week from given five-rep maxes (R11).

test_training_contract.py — `test_ss_alternates_a_and_b_across_weeks`,
`test_ss_adds_weight_each_confirmed_session`, `test_ss_stall_repeats_then_resets`,
`test_ss_first_session_works_up`, `test_ss_refuses_with_the_unblocking_constraint`,
`test_ss_intermediate_routes_to_texas_method`, `test_texas_method_volume_light_intensity_week`,
`test_confirm_route_records_each_lift`, `test_legacy_ss_program_seeds_loads`.
