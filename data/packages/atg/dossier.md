# ATG — source dossier

Engine shape: week templates (`src/week_template.py`). Ben Patrick publishes ATG as fixed
workouts, each a list of movements with their doses, done on set days of the week. Each
workout is one archetype as written (`archetypes/plan/`), in its own one-workout pool
(frameworks `atg_zero`, `atg_program` and `knee_ability_pro`). The record (sources, rules
with what enforces each, inventions) is `data/packages/atg/fidelity.yaml`; this page is its
prose, under the same ids. The status is the scorecard's (records/status.yaml).

## Sources

Read on 2026-10-22, all by Ben Patrick:

- ATG Zero, the ATG Online newsletter of 2023-08-06 (zero): the ten movements, their doses
  and the three days a week.
- ATG Program #1 & 2 (p12): Program #1's one workout, and Program #2's two workouts.
- ATG: Knee Ability Series 1, 2 and 3 of 10 on his Substack (2025) (kas). Part 3 lays out
  the Knee Ability Pro week.
- Knee Ability Series 4 (kas4): the lower legs, and the order of a workout.
- Minimalistic Full-Body Program (mfb): his own two workouts a week, "from the ground up".
- The ATG Longevity System (longevity), in part: its exercises are shown in images.
- Pain-Free Ability (pfa); Every Regression Counts, Simplified Step-ups for Knee Health and
  Updated ATG Ham Curl / Nordic System (regress); ATG Lower Body Basics on a Budget, Thrive
  With 5? and Mobility Made SIMPLE (budget).
- Not read: Knee Ability Zero, the 2021 book (no copy was found), and the ATG app's
  programs and Ability Protocols (behind the subscription).

## Rules and where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | ATG Zero's ten movements as written, three days a week, other exercise or sport on the days between (zero) | archetype `atg_zero`; track `zero`'s `week_templates`; source week `zero_week` |
| R2 | Program #2: two workouts, each once a week; "3 days of sport and 2 days of ATG" (p12) | archetypes `atg_p2_w1`, `atg_p2_w2`; track `program`; source week `program_week` |
| R3 | Knee Ability Pro: Monday and Thursday the heavy sled, lower legs and the bottom of the squat; Tuesday and Friday flexibility and the upper body (kas) | archetypes `atg_pro_mon`, `atg_pro_tue`, `atg_pro_thu`, `atg_pro_fri`; track `knee_ability_pro`; source week `pro_week` |
| R4 | From the ground up: the sled, the lower legs, the knee, the hamstrings and hips, the core, the upper body last (longevity, mfb, kas4, p12) | the order of every workout's slots |
| R5 | The sled leads, backward first; a resisted treadmill or walking backward replaces it, "You don't have to sled!" (mfb, zero, kas, pfa) | the sled slots' `exercise_ids: [sled_forward_backward, backward_walk]` |
| R6 | Every exercise scales by assistance, height, slope and range, and is trained at the pain-free level, never through pain (mfb, regress, pfa, kas) | each exercise's notes give its ladder; the workouts name the ladder ("Nordic progression") |
| R7 | No phases, deloads or tests: the same workouts, repeated (p12, zero, mfb) | one repeatable phase per track; no `deload_protocol` |

## Debt (rules nothing enforces yet)

None. R6 is enforced only as far as the athlete reads it: the engine does not know which
step of a ladder the athlete is on, and moving up is advice (I8).

## Open

- Knee Ability Zero (the 2021 book) and the ATG app's programs were not read.
- Knee Ability Pro's two-session version (Monday and Tuesday back to back, Thursday and
  Friday back to back) is not built, so the track needs four days.
- Program #1 (for children), the Minimalistic Full-Body Program, Thrive With 5? and Mobility
  Made SIMPLE were read but are not built as tracks. They agree with the three that are.
- An injury flag that rules out the knee movements rules out every workout, because each is
  run as written. Patrick: "I do not address conditions. I only address your pain-free
  ABILITY."
- Knee Ability Pro's jumping (a staff basketball game, a Vertec test) is the athlete's sport
  and is not programmed.

## Inventions

- I1: with no track named, the level picks one: novice Zero (where Patrick starts
  everyone), intermediate Program #2, advanced and elite Knee Ability Pro. The sources route
  by age and goal, not level.
- I2: Knee Ability Pro is for intermediate and up; Zero and Program #2 are for every level.
- I3: Zero's days fall on Monday, Wednesday and Friday, and Program #2's on Monday and
  Thursday. The sources ask only for days between.
- I4: four-week blocks, repeated. The sources give no length.
- I5: how the doses are read. Yards become metres (50 yd as 46 m, 100 as 91), each way one
  set. "Burnout" and "exhaustion" become max reps, and the L-sit's burnout a 30-second hold.
  "Up to" becomes the top of the range. A slant is written as a box for the step-ups. Each
  workout's minutes are estimated.
- I6: names are merged. Zero's piriformis push-up is the pigeon push-up. The wall tibialis
  raise and Knee Ability Pro's tibialis raise are one exercise. Zero's external rotation
  takes any light weight, so it needs no equipment.
- I7: each track needs its own training days (Zero 3, Program #2 2, Knee Ability Pro 4).
  There is no drop order for fewer.
- I8: assessment gating is advice, not a gate (the owner's call, 2026-10-22, as for Wildman's
  layoff). Each workout's first movement says to work at the step of each ladder owned
  without pain and to move up when ready; the call is the athlete's, and the step is not
  tracked. Patrick writes no pass marks ("no test or numeric standard"); his one check is
  his own "10 full pull-ups every week". The text is each category's `advice` in the
  frameworks.

## Removed in this review

The `joint_health` track (Range → Load → Maintain) on `atg_joint_health`, whose phases, six-week
deload, sessions per week and intensity split no ATG source writes. Also removed: the
knee-durability, range-work and rehab-protocol sessions, and the post-operative rehab ladder
that had been built from the design document rather than from Patrick (quad sets, heel
slides, ankle pumps, the shoulder-rehab sequence). The injury flags lost their ATG
substitution pairs, which named that ladder.

## Tests

Source weeks (`data/packages/atg/source_weeks.yaml`): the Zero week (R1), the Program #2 week
(R2) and the Knee Ability Pro week (R3).

test_week_template.py: `test_atg_runs_its_programs_as_written` (R1–R5, R7, I1, I2).
