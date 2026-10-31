# BJJ — source dossier

Engine shape: training contract (`data/packages/bjj/training_contract.yaml`, track
`mat_support`). The record — sources, rules with what enforces each, inventions — is
`data/packages/bjj/fidelity.yaml`; this page is its prose, by the same ids. The status
is the scorecard's (records/status.yaml).

## Sources

Re-read on 2026-10-21, each for the passages the rules below cite.

- StrengthLog (Andreas Abelsson), "Strength Training for BJJ", January 2025 — the
  strength program the package runs (the owner's decision, 2026-10-21): two
  full-body workouts a week over twelve weeks, six of strength and hypertrophy, a
  deload week, five of power; three or four sets, rests of two to four minutes on
  the compound lifts and one to two on the rest; add weight once every set makes its
  reps. The article prints one week of each block; the week-by-week loads are in
  StrengthLog's app.
- BJJEE (Guillaume Huni), the training-mix article, 20 June 2017 — five classes to two
  S&C sessions in the author's best weeks (a hard one midweek, a medium one Saturday).
- Vitruve (Iker Zubizarreta), "BJJ Strength and Conditioning Program", May 2025 —
  "BJJ technique is priority number one"; the pre-competition phase's functional
  circuits (shuttle runs of 30–40 m) and partner drills for takedown entries in short
  bursts; a taper "reducing volume about 1–2 weeks out".
- Chad Wesley Smith (Juggernaut), "Jiu Jitsu Conditioning Circuits", on jiujitsu.com,
  October 2015 — ten-minute rounds of 15–30 s efforts with sprints or animal movements
  between.
- TrainHeroic, Relentless Grappler team plan — the page answered 404 on 2026-10-21;
  nothing rests on it.

There is no single-author method for the week: the mat comes from the consensus these
sources share, and the strength work is StrengthLog's program as written.

## Rules → where they live

| | Rule (sources) | Encoded as |
|---|---|---|
| R1 | Mat time first; classes outnumber S&C at every week size (Vitruve, BJJEE, StrengthLog) | `mat_class` `exposures_by_days` (2 at 3 days … 5 at 7); the phase's `checks: modality_outnumbers` |
| R2 | Two full-body workouts a week beside the classes (StrengthLog) | `grappling_strength` `exposures_by_days`: both from five days, one up to four (I5) |
| R3 | Three or four sets; 5–15 reps in the strength block, 3–8 in the power block, 3–6 on the compound lifts (StrengthLog, Vitruve) | the variants' sets and reps; source week `strengthlog_cycle` |
| R4 | Week 7 is a deload: two light days at 50–60 % of the weight, about ten reps, two sets, its own exercises (StrengthLog) | `periods` (the second, `deload: true`) and the variants `deload_1`, `deload_2`, run as written |
| R5 | A competitor's conditioning: ten-minute rounds of short efforts; shuttle runs and takedown-entry drills in bursts (Juggernaut, Vitruve) | optional `competition_conditioning`: `may_share_day` with a strength day, `never_with: [mat_class]`, cut in the deload week |
| R6 | Twelve weeks: six of strength and hypertrophy, the deload week, five of power, each with its Workout 1 and Workout 2 (StrengthLog) | `grappling_strength` `periods` and its six `variants`; source week `strengthlog_cycle` (every lift's sets and reps through the twelve weeks) |
| R7 | Add weight or a rep each workout; once every set makes its reps, add weight next time (StrengthLog) | each strength-block lift's `load_note` |
| R8 | Power: up to 75 % of the one-rep max, every rep explosive, the set ends when the weight slows (StrengthLog) | the power variants' `load_note` |
| R9 | Two to four minutes' rest on the compound lifts, one to two on the rest (StrengthLog) | each block's `rest_sec` (the short end, I8) |

## Debt (rules nothing enforces yet)

None.

## Open

- StrengthLog's week-by-week loads within a block are in its app; the article prints one
  week of each block, and the contract repeats it.
- Competition preparation (a camp: its weeks, Vitruve's taper) is not modelled; the
  conditioning module is what a competitor adds in a normal week.
- How a class divides its minutes: the sources leave the class to the gym.

## Inventions

- I1: the class's blocks and minutes (warm-up, drilling, positional, rolling) are the
  shape of a typical class, not the coach's plan.
- I2: the weights are the athlete's — each lift carries StrengthLog's rule in its note
  and the athlete records what they lift; the app prescribes no kilogram, because the
  article gives no starting weights or increments.
- I3: StrengthLog writes one twelve-week program; it repeats here, its deload the
  seventh week of every twelve, and the competition conditioning deloads with the
  strength. The mat never deloads on a schedule — no source deloads it; an athlete who
  reports being overreached deloads everything, and the class then drops live rolling
  and keeps the drilling (the owner's decision, 2026-10-21).
- I4: declared substitutes — positional work or drilling for rolling under an injury,
  inverted rows for pull-ups and the barbell row, Bulgarian split squats for the front
  squat, a dead hang for the plate pinch, a hollow hold for the plank. A lift an injury
  rules out with no substitute is left out and said, the rest of the workout kept (the
  owner's decision, 2026-10-21); a lift missing its equipment refuses, naming it.
- I5: up to four training days, one of the two workouts a week, alternating week to
  week — StrengthLog's two need five days.
- I6: competition conditioning is offered from intermediate up; the sources write it
  for competitors.
- I7: at six training days, four classes, each on a day of its own, beside two S&C
  sessions, where BJJEE's week has five (Saturday a class and the second S&C
  session) — the owner's decision, 2026-10-21.
- I8: the rests are the short end of StrengthLog's ranges (two minutes and one), so a
  workout is about fifty minutes; "max reps" pull-ups are sets to failure, a 20–30 s
  pinch a 30 s hold, the weighted plank carries a plate, the carry is with dumbbells;
  the deload notes add an easier pull-up and a lower box.

## Output review (2026-10-22)

Eight weeks at five days printed (`tools/print_package.py bjj --profile ideal --weeks 8`):
three classes and two StrengthLog workouts a week, every lift's sets, reps and holds as
R4 and R6 write them through the strength block, the deload week and the first power week.
Fixed: the competitor's conditioning, which has no room beside 60-minute strength days in
the build weeks, appeared in the deload week alone, because the lighter workouts freed the
time — optional work is now offered by the last build week's minutes, so a deload never
adds a session (`training_contract`, every contract package); the track's note said "sets
of five to eight" where R3 runs five to fifteen.

## Tests

Source weeks (`data/packages/bjj/source_weeks.yaml`): BJJEE's six-day week (R1), its
two S&C sessions compared; its five classes are not — the package's four (I7) are
the owner's decision. StrengthLog's cycle (R6): every lift's sets and reps over twelve
weeks at five days.

test_training_contract.py — `test_bjj_mat_time_leads_the_week`,
`test_bjj_strength_runs_strengthlogs_cycle_and_the_mat_carries_on` (R4, R6–R8, I3),
`test_bjj_substitutes_are_declared_and_refusals_name_the_way_out` (I4),
`test_bjj_conditioning_is_optional_and_never_outnumbers_the_mat`.
