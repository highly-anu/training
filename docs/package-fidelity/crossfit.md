# CrossFit — source dossier

Engine shape: week templates (`src/week_template.py`): the template's day types as
category pools of named workouts, each as written (framework `crossfit_template`). The
record — sources, rules with what enforces each, inventions — is
`data/packages/crossfit/fidelity.yaml`; this page is its prose, by the same ids. The status
is the scorecard's (status.yaml).

## Sources

Read on 2026-10-21:

- Greg Glassman, "A Theoretical Template for CrossFit's Programming" (CrossFit Journal,
  February 2003) — the three-on, one-off and five-on, two-off cycles, the M/G/W day types,
  their priorities and Table 4's twelve workouts.
- Glassman, "What Is Fitness?" (2002), "Foundations" (2002), "Benchmark Workouts" (2003);
  "The New Girls" (2004); crossfit.com's benchmark pages.
- The crossfit.com Workout of the Day archive, July-December 2005 (184 days).
- The CrossFit Level 1 Training Guide (2020), in part: scaling, responsible training, the
  nine foundational movements.

## Rules → where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | Three on, one off (tmpl03, wif02, wod05) | the `constantly_varied` phase's `week_templates`: the twelve-day cycle laid on twelve weeks, a rest every fourth day |
| R2 | Five on, two off for fixed weekdays (tmpl03) | the `five_on_two_off` track's three weeks |
| R3 | The day cycle M, GW, MGW, off, G, WM, GWM, off, W, MG, WMG, off (tmpl03 Table 1) | the templates' day types; source weeks `table4_cycle`, `five_two_week` |
| R4 | The elements' movements (tmpl03 Table 2) | the categories' workouts |
| R5 | One-element days: long slow distance, a single skill, a single heavy lift (tmpl03) | categories `m`, `g`, `w` |
| R6 | Couplets, 3–5 rounds for time (tmpl03) | categories `gw`, `wm`, `mg` |
| R7 | Triplets for 20 minutes, scored by rounds (tmpl03) | category `triplet` |
| R8 | Table 4's twelve days as written (tmpl03) | the pools' first workouts; source week `table4_cycle` |
| R9 | Everything varies; no set routine (wif02, found02) | each day takes the next workout of its pool |
| R10 | Benchmarks recur irregularly to measure progress (bench03, wod05) | the Girls in the pools, each a selectable test of its standard |
| R11 | The Girls and the Heroes read, as written (bench03, newgirls04, bm, wod05) | their archetypes, Rx loads in the slot notes |
| R12 | Heavy days at descending or repeated low reps (tmpl03, wod05) | category `w` |
| R13 | No deload; the off day is the rest (tmpl03, wif02) | no `deload_protocol` |
| R14 | About an hour a session (found02) | `ideal_session_minutes: 60` |

## Debt (rules nothing enforces yet)

None.

## Open

- Grace, Isabel and Karen fit none of the template's day types and are not placed.
- A scaled novice track (the Level 1 guide's scaling) is not built.
- The rest of the 2005 archive is not transcribed.
- Today's crossfit.com is not strictly three on, one off.

## Inventions

- I1: workouts are filed by their elements; every workout of three or more as a triplet.
- I2: the pools' order (Table 4 first, then the Girls and the 2005 days); the next one
  the athlete can do, passing over one used in the last week.
- I3: another couplet or triplet when none of the day's type fits.
- I4: the drop order at five days.
- I5: intermediate and up; novices refused.
- I6: estimated minutes; pounds as written, kilograms beside.

## Removed in this review

The single 20-minute squat/pull/push AMRAP that was every conditioning day, the Tabata and
bodyweight-circuit sessions, the benchmark test every fourth week, the Zone 2 warm-ups,
Fran's 12-minute cap, `avoid_with: [max_strength, aerobic_base]`, the CrossFit Endurance
claims, and the exercises only they used.

## Tests

Source weeks (`data/packages/crossfit/source_weeks.yaml`): Table 4's cycle (R1, R3, R8);
the five-on, two-off week (R2).

test_week_template.py — `test_crossfit_runs_glassmans_cycle_and_the_girls_as_written`
(R1, R3, R8, R9, R11, R13); test_standard_tests.py —
`test_crossfit_benchmarks_recur_in_its_pools` (R10).
