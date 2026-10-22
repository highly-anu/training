# Uphill Athlete — source dossier

Engine shape: training contract (`data/packages/uphill_athlete/training_contract.yaml`,
track `full_program`), with the `weekly_volume` model (docs/logic/training_contracts.md).
The record — sources, rules with what enforces each, inventions — is
`data/packages/uphill_athlete/fidelity.yaml`; this page is its prose, by the same ids.
The status is the scorecard's (status.yaml).

## Sources

Read on 2026-10-21. The books — *Training for the Uphill Athlete* (2019) and *Training
for the New Alpinism* (2014) — could not be read, so nothing rests on them; the package
is Uphill Athlete's own public material:

- Steve House, "Training for Mountaineering", uphillathlete.com, March 2021 (full) — the
  week, the starting hours, the long day, the build and recovery weeks, the pack, when
  intensity and muscular endurance come, the taper.
- "The General Strength Routine" (PDF from *Training for the New Alpinism*, full) — the
  circuit and its eight weeks of laps.
- "Uphill Athlete Muscular Endurance Workout" (PDF, full) — the ten workouts.
- "When and How to Add High-Intensity Training: The 10 Percent Test" (full); "Aerobic
  Deficiency" (2018, full); "Heart Rate Drift Test" (full) — thresholds and when
  intensity may enter.
- The 2023 podcasts on training for mountaineering — base, the specific period,
  strength (transcripts, partially); "Making the Most of Your UA Training Plan", the
  16-week plan's page and "Muscular Endurance Training for Mountain Athletes" (2016)
  (partially).

## Rules → where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | Transition, Base, Specific, Taper; eight weeks at least (plan page, mtn) | the track's phases; `expectations.min_weeks: 8` |
| R2 | Six days: four aerobic, two strength, one off (mtn) | the frameworks' six-day cadence; the modules' exposures; source week `uphill_week` |
| R3 | The long day is half the week's aerobic time (mtn) | `long_day` `progression.share: 0.5` |
| R4 | Three build weeks, then an easy week at half the hardest (mtn) | `weekly_volume`: `build_weeks: 3`, `recovery_pct: 50`; the frameworks' deload every fourth week |
| R5 | About 10 % a week (plan_use) | `ramp_pct: 10`; Base's `volume_change_per_week` claims |
| R6 | First week: about 5 h untrained, 7 lean and active, 8–10 for someone who jogs 10 miles, strength included (mtn) | `start_minutes` by level (I3) |
| R7 | No pack for four weeks, then 5, 10, 15 % of bodyweight; none heavy on the long day (mtn) | `pack_pct` on the easy days; the long day's note |
| R8 | No intensity for eight to twelve weeks; the first in week 13 (mtn, podcast) | Transition's and Base's `max_zone: 2`; Zone 3 runs from Base with Zone 3 (week 13) |
| R9 | Zone 3 only once AeT is within 10 % of AnT (aerobic deficiency) (ads, ten) | the Zone 3 and ME notes (I10) |
| R10 | Zone 3 at about 5 % of the week, one session then two, 48 h apart (ten) | `zone_3` `share: 0.05`, `exposures_by_phase`, `min_spacing_days: 2` |
| R11 | The General Strength circuit, twice a week, one lap to four over eight weeks (gs_pdf) | `general_strength` `periods` and variants `gs_1`…`gs_4`; source week `general_strength_laps` |
| R12 | Strength: general, then max, then muscular endurance (podcast, me16) | the modules' `phases` |
| R13 | Max strength: three or four reps at 90–95 %, never past twice bodyweight (podcast, mtn) | the lifts' `load_note` |
| R14 | The ME workout's ten workouts as written (me_pdf) | `muscular_endurance` variants `me_1`…`me_10`, `rotation_holds`; source week `me_progression` |
| R15 | ME once a week when the rest of the load is high (me_pdf, me16) | `exposures_per_week: 1` |
| R16 | ME in the last weeks — about week 16 of 24, six to ten workouts over six to eight weeks (mtn, me16) | `phases: [specific]`, eight weeks |
| R17 | Specific: two Zone 3, maintenance strength, volume not rising (podcast) | `exposures_by_phase`; `ramp_phases` stops the ramp at the end of Base; source week `specific_week` |
| R18 | Base at least twelve weeks; Specific two to eight (podcast) | Base 4 + 8 weeks, Specific 8 |
| R19 | A one-week taper halving the time, for a two- or three-day climb (mtn) | Taper, one week, a deload phase: half the held volume |

## Debt (rules nothing enforces yet)

None.

## Open

- The books could not be read.
- Hill muscular endurance (water carried up, dumped at the top) is not programmed; the
  gym workout is.
- The heart-rate drift test is not scheduled; the zones are the app's heart-rate zones.
- Back-to-back long days in Specific are not placed next to each other.
- Pack weight past 15 % of bodyweight does not progress (up to 25 % on aerobic hikes).
- More Transition for an aerobically deficient athlete is not modelled.
- A novice track: Beginner Mountain Fitness is sold, not published; the next step.

## Inventions

- I1: a 29-week plan — Transition 8 (the 24-week plan's), Base 4 without intensity and 8
  with one Zone 3 session, Specific 8, Taper 1.
- I2: each block starts one step above the last; the ramp holds from Specific on, its
  recovery weeks still at half. Peak about 11.4 hours (the plans: about 11).
- I3: the first week's aerobic minutes by level — intermediate 5.5 h, advanced 7,
  elite 8.5 (R6 less about 1.5 h of strength); no novice.
- I4: a session longer than the athlete's longest day is capped there, and said.
- I5: the max-strength session's sets (four), lifts (squat and deadlift alternating,
  weighted pull-ups) and the core routine.
- I6: the General Strength reps ("up to ten") and minutes; the ME minutes; the goblet
  squat to press and swing take each later workout's set count.
- I7: recovery weeks — the General Strength laps run as written; max strength and ME keep
  half their sets, and the ME workout repeats.
- I8: in Specific the one easy day takes what the long day and Zone 3 leave, the second
  of back-to-back long days.
- I9: a Zone 3 session's 15-minute warm-up and 10-minute cool-down.
- I10: the aerobic-deficiency gate is said, never enforced (the owner's rule for Wildman).
- I11: six training days required; at seven, the same six sessions.

## Tests

Source weeks (`data/packages/uphill_athlete/source_weeks.yaml`): the week's four aerobic
and two strength sessions (R2); the General Strength laps over Transition (R11); the ME
workouts' first sets and rests (R14); the Specific week (R17).

test_training_contract.py — `test_uphill_volume_ramps_recovers_and_holds` (R3–R5, R7,
R8, R10, R17, R19, I2), `test_uphill_strength_goes_general_max_then_muscular_endurance`
(R11, R12, R14), `test_uphill_caps_the_long_day_and_refuses_what_it_is_not_for` (I4, R2).
