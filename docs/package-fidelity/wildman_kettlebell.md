# Wildman Kettlebell — source dossier

Status: **audited** (2026-10-20). Engine shape: training contract
(`data/packages/wildman_kettlebell/training_contract.yaml`).

## Sources

- Nerd Math Kettlebell Swing Program, public PDF (r1.3/1.4; URL in the
  contract's `sources`) — read in full.
- wildmanathletica.com: /programming (Nerd Math, Tetris of Training), /phases,
  /swings, /snatch, /deck-squat, /kettlebell-programs.
- His Clean & Press, Turkish Get-up, Snatch and Deck Squat programs are paid;
  their pages give structure (sessions a week, minutes, cycles, goals), not
  their workouts.

## Rules → where they live

| Rule (source) | Encoded as |
|---|---|
| Phases are I Restore, II Build, III Explore; Phase II "you are never done with" (/phases) | General Practice is one repeatable phase, `build` ("Build" — the name is his Phase II's, without the numeral, which read as the program's second phase); `former_ids` keeps older stored weeks regenerating |
| Phase II programs: swing, clean & press, Turkish get-up, deck squat, snatch (/kettlebell-programs) | General Practice modules `swing`, `clean_press`, `getup`, `deck_squat`, `snatch` |
| Each program twice a week, never on consecutive days; stacked into a week as time allows (Tetris; PDF "How to use") | `exposures_per_week: 2`, `min_spacing_days: 2`; get-up and deck squat `optional` + `may_share_day` |
| Swing: 10-min EMOM 6→20 reps (+2 a session), then 20-min EMOM, then start/stop in 10 and 20 rounds of 90 s; 16 weeks a bell; then a heavier bell (PDF approaches 1–4) | `swing` density cycle: `rounds` 10/20/10/20, `interval_sec` 60/60/90/90, `cues` start/stop |
| "If pressed for time … do the short version" (PDF tips) | A stage that does not fit the session takes the longest earlier stage that does (`_stage` budget) |
| Clean & press before the snatch (/snatch FAQ) | `snatch` is `when_mastered` on clean, press and snatch |
| Snatch goal: 200 snatches in 10 minutes, Classic protocol (/snatch) | `snatch` cycle ends its first stage at 10 × 20 |
| Deck squat: bodyweight first, then a kettlebell (/deck-squat) | `deck_squat` block `progresses` without a bell; goblet squat its declared substitute |
| No deload week in the programs; "lighter" is the next cycle at a heavier bell (PDF, /swings) | `kb_general_practice` has no `deload_protocol` |
| Advance by completed sessions, not by the calendar | `confirmed_state`; the one-tap `POST /health/sessions/<key>/confirm` |

## Open (the source does not say, or it is paid)

- The hand-to-hand option ("Option C: alternating minutes of 2HS and H2H") —
  needs a block that alternates two movements minute by minute.
- Clean & press, get-up and deck-squat numbers: the cycles use the Nerd Math
  pattern; his own are in the paid programs.
- Bell sizes: the athlete chooses; the contract never infers a weight.

## Inventions (see status.yaml)

- Pentathlon Prep (from kettlebell-sport practice, IKMF; sources in the contract).
- Get-Up and Loaded Mobility, Double-Bell Practice (Codex tracks); double bells
  are his Phase III, which is deliberately non-repeating.
- Clean and press, get-up and deck-squat cycles follow the Nerd Math pattern;
  his own numbers are in the paid programs.

## Measurement

Every practice track but the get-up's runs density cycles, so the lead measure
is the intervals completed (`interval_rounds`); Pentathlon Prep leads with
cadence, Get-Up and Loaded Mobility with technique minutes. The snatch goal
(200 in ten minutes) is the SSST count and the get-up's bodyweight ratio a
standard, both entered by hand (`manual: true`): no session tests them.

## Tests

test_training_contract.py — `test_general_practice_runs_wildmans_phase_two`,
`test_source_cycle_retains_movements_and_spacing`,
`test_one_tap_confirmation_earns_the_exposure`, the pentathlon tests;
tools/check_exercise_coverage.py (no orphans).
