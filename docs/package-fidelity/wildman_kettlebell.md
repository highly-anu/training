# Wildman Kettlebell — source dossier

Engine shape: training contract (`data/packages/wildman_kettlebell/training_contract.yaml`).
The record — sources, rules with what enforces each, inventions — is
`data/packages/wildman_kettlebell/fidelity.yaml`; this page is its prose, by the same
ids. The status is the scorecard's (status.yaml).

## Sources

- Nerd Math Kettlebell Swing Program, public PDF (r1.4, 11 October 2021; URL in the
  contract's `sources`) — read in full; its rules re-checked against the text on
  2026-10-21.
- wildmanathletica.com: /programming (Nerd Math, Tetris of Training) and /phases,
  quoted 2026-10-21.
- programs.wildmanathletica.com: /kettlebell-programs, /snatch, /tgu, /deck-squat,
  /swings — read for the October 2026 rebuild; the host did not resolve on 2026-10-21.
- His Clean & Press, Turkish Get-up, Snatch and Deck Squat programs are paid;
  their pages give structure (sessions a week, minutes, cycles, goals), not
  their workouts.
- IKMF, "IKMF Pentathlon" (ikmf-world.com) — the events, times and caps (Fedorenko's).

## Rules → where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | Phases are I Restore, II Build, III Explore; Phase II "you are never done with" (/phases) | General Practice is one repeatable phase, `build` ("Build" — the name is his Phase II's, without the numeral, which read as the program's second phase); `former_ids` keeps older stored weeks regenerating |
| R2 | Phase II programs: swing, clean & press, Turkish get-up, deck squat, snatch (/kettlebell-programs) | General Practice modules `swing`, `clean_press`, `getup`, `deck_squat`, `snatch` |
| R3 | Each program twice a week, never on consecutive days; stacked into a week as time allows (Tetris; PDF "How to use": two or three days) | `exposures_per_week: 2`, `min_spacing_days: 2`; get-up and deck squat `optional` + `may_share_day` |
| R4 | Swing: 10-min EMOM 6→20 reps (+2 a session), then 20-min EMOM, then start/stop in 10 and 20 rounds of 90 s; 16 weeks a bell; then a heavier bell (PDF approaches 1–4) | `swing` density cycle: `rounds` 10/20/10/20, `interval_sec` 60/60/90/90, `cues` start/stop |
| R5 | "If pressed for time … do the short version" (PDF) | A stage that does not fit the session takes the longest earlier stage that does (`_stage` budget) |
| R6 | Clean & press before the snatch (/snatch FAQ) | `snatch` is `when_mastered` on clean, press and snatch |
| R7 | Snatch goal: 200 snatches in 10 minutes, Classic protocol (/snatch) | `snatch` cycle ends its first stage at 10 × 20; the SSST count is a hand-entered standard |
| R8 | Deck squat: bodyweight first, then a kettlebell (/deck-squat) | `deck_squat` block `progresses` without a bell; goblet squat its declared substitute |
| R9 | No deload week in the programs; "lighter" is the next cycle at a heavier bell (PDF, /phases) | `kb_general_practice` has no `deload_protocol` |
| R10 | Self-paced; progress is each workout completed, tracked by date (PDF) | `confirmed_state`; the one-tap `POST /health/sessions/<key>/confirm` |
| R11 | Repeat workouts when training is interrupted for more than a week (PDF, "Tracking your progress") | the swing module's `advice`, said in every swing session's note and never enforced (I5) |
| R12 | The pentathlon's five events, six minutes each with five between, and the rep caps (IKMF) | the `pentathlon_events` module; the test protocol |
| R13 | The get-up's goal is a bodyweight ratio no session tests (/tgu) | the `turkish_get_up_bw_ratio` standard, entered by hand |

## Open (the source does not say, or it is paid)

- The hand-to-hand option ("Option C: alternating minutes of 2HS and H2H", the PDF's
  most common) — needs a block that alternates two movements minute by minute.
- Clean & press, get-up and deck-squat numbers: his own are in the paid programs.
- Bell sizes: the athlete chooses; the contract never infers a weight.
- The PDF allows two or three days a week; the contract runs the website's twice.

## Inventions

- I1: Pentathlon Prep (from kettlebell-sport practice, IKMF; sources in the contract).
- I2: Get-Up and Loaded Mobility (a Codex track).
- I3: Double-Bell Practice (a Codex track); double bells are his Phase III, which is
  deliberately non-repeating.
- I4: clean and press, get-up and deck-squat cycles follow the Nerd Math pattern; his
  own numbers are in the paid programs.
- I5: the repeat after a layoff (R11) is recommended, not enforced — decided by the
  owner on 2026-10-21: the athlete decides and takes responsibility.

## Measurement

Every practice track but the get-up's runs density cycles, so the lead measure
is the intervals completed (`interval_rounds`, R10); Pentathlon Prep leads with
cadence (R12), Get-Up and Loaded Mobility with technique minutes (I2). The snatch
goal (R7, 200 in ten minutes) is the SSST count and the get-up's bodyweight ratio
(R13) a standard, both entered by hand (`manual: true`): no session tests them.

## Tests

Source weeks (`data/packages/wildman_kettlebell/source_weeks.yaml`): one bell's
32 swing sessions from the PDF's progression table — reps, rounds and minutes (R4).

test_training_contract.py — `test_general_practice_runs_wildmans_phase_two`,
`test_source_cycle_retains_movements_and_spacing`,
`test_one_tap_confirmation_earns_the_exposure`, the pentathlon tests.
