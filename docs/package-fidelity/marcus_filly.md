# Marcus Filly — source dossier

Engine shape: training contract (`data/packages/marcus_filly/training_contract.yaml`,
tracks `functional_bodybuilding` — Pump Condition 3x — and `pump_lift`). The record —
sources, rules with what enforces each, inventions — is
`data/packages/marcus_filly/fidelity.yaml`; this page is its prose, by the same ids. The
status is the scorecard's (status.yaml).

## Sources

Read on 2026-10-21. Functional Bodybuilding's Help Center, written for the method by its
staff, and Filly's own blog posts:

- The Persist sample weeks "Full Body PUMP CONDITION 3x/wk" and "Full Body PUMP LIFT 3x/wk"
  (Help Center, 2025-12-31; read from their images) — every day's sections, exercises,
  sets, reps, tempo and intervals.
- Help Center: "Persist: Track Summary", "How to Read TEMPO", "RPE: What does this mean?",
  "Choosing Loads", "Why does my program not start with Week 1, Day 1?", "What if I only
  have 3 or 4 days to train?", "What Equipment is Needed for Persist?".
- Marcus Filly, "Deload Week", "Workout Tempo", "5 Ways To Build Functional Muscle"
  (functional-bodybuilding.com); the Persist deload PDF (September 2022).
- The Base Camp product page (the eBook is sold, not read).

## Rules → where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | The 3x tracks train three days a week (tracks_hc, pc3) | `persist_session` `exposures_per_week: 3`; the framework's `sessions_per_week` |
| R2 | About an hour a session (pc3, basecamp) | the days' sections, 51–60 minutes |
| R3 | Warm-up, strength intensity, strength balance, conditioning or a finisher, cooldown (pc3, pl3) | each day's blocks in that order; source weeks `pump_condition_3x`, `pump_lift_3x` |
| R4 | Pump Lift: no conditioning, a finisher (tracks_hc, pl3) | the `pump_lift` track's days |
| R5 | Tempo down, hold, up, pause; X explosive (tempo_hc, tempo_blog) | each block's note; the track notes explain it |
| R6 | The 3x sample weeks as printed (pc3, pl3) | the variants `day_1`…`day_3` of each track |
| R7 | Loads are the athlete's: top of the reps, then a little more; RPE 7 is three in reserve (loads_hc, rpe_hc) | the track notes; `rpe_target` where the day writes one |
| R8 | Six-week cycles, the days the same within one (start_hc, days_hc) | the rotation; `periods` (two cycles) |
| R9 | A Bridge week after two cycles, every section at RPE 6–7 (deload_blog, deload_pdf) | the second period, `deload` with its `note`; the work is kept (`deload_keep: 1`) |
| R10 | First week: a set or two fewer, loads 10–20 lb lighter (start_hc) | the track notes |
| R11 | Movement patterns, unilateral work every session (basecamp, fmuscle_blog) | the sample days (tripod rows, lunges, split squats) |
| R12 | Barbell, dumbbells, pull-up bar, bench, bands; bike or rower (equip_hc) | `required_equipment` |

## Debt (rules nothing enforces yet)

None.

## Open

- The 4x and 5x tracks: one day of each is public, not a week.
- The progression inside a cycle (more sets in weeks 4–6; fewer reps in weeks 3 and 5 in
  the 4x sample) has no numbers to write, so the days repeat as printed.
- The Benchmark Week between cycles is not programmed.
- A novice track: Base Camp's sessions are sold.
- Podcasts, Revival Strength and the Healthy Shoulder Guide were not read.

## Inventions

- I1: the published week repeats every cycle (Persist changes its days each cycle).
- I2: reps the sample leaves to the program are said so — a working set a rep or two in
  reserve, recorded.
- I3: a section's minutes shared evenly by its exercises; rests inside an interval
  estimated.
- I4: the warm-up, cooldown and conditioning are one entry each, the day's content in its
  note.
- I5: the sample's "or" options as alternatives in its order; no leg press.
- I6: intermediate lifters and up; novices refused.
- I7: at four or five days, the three sessions on three of them.

## Removed in this review

The shoulder rehab session (from `docs/plan.md`, not a source), the bodyweight strength
session (Pavel, Ido Portal, Gym Jones), the mobility session, quotes attributed to Filly
that no source holds, RTS and Renaissance Periodization as sources, the 5-week deload,
"add 2.5–5 kg when RPE drops below 7", and the exercises only they used.

## Output review (2026-10-22)

Both 3x tracks' first fortnight and Functional Bodybuilding's Bridge week (week 13)
printed (`tools/print_package.py marcus_filly --profile ideal`). Every section, exercise,
set, rep, tempo, interval and pairing reads as the sample weeks print them (R3, R4, R6);
the week repeats within a cycle (R8, I1); the Bridge week puts every section at RPE 6–7
(R9). Nothing to fix. The first-week advice (R10) stands in the track's note every week,
since a note has no week of its own.

## Tests

Source weeks (`data/packages/marcus_filly/source_weeks.yaml`): both 3x sample weeks, each
day's sections in order with the sets and reps they print (R3, R4, R6, R11).

test_training_contract.py — `test_filly_runs_the_sample_weeks_in_cycles_and_a_bridge_week`
(R2–R4, R6, R8, R9, I5, I6).
