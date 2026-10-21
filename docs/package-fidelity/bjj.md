# BJJ — source dossier

Engine shape: training contract (`data/packages/bjj/training_contract.yaml`, track
`mat_support`). The record — sources, rules with what enforces each, inventions — is
`data/packages/bjj/fidelity.yaml`; this page is its prose, by the same ids. The status
is the scorecard's (status.yaml).

## Sources

Re-read on 2026-10-21, each for the passages the rules below cite.

- StrengthLog (Andreas Abelsson), "Strength Training for BJJ", January 2025 — strength
  as support: two or three sessions a week for most, two beside four or five BJJ
  sessions, one at peak; three sets of three to six reps on compound lifts, adding
  weight when the reps are made; a deload week between two six-week halves. It
  prescribes reps and percentages, not RPE.
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

There is no single-author method: the package encodes the consensus these
sources share.

## Rules → where they live

| | Rule (sources) | Encoded as |
|---|---|---|
| R1 | Mat time first; classes outnumber S&C at every week size (Vitruve, BJJEE, StrengthLog) | `mat_class` `exposures_by_days` (2 at 3 days … 5 at 7); the phase's `checks: modality_outnumbers` |
| R2 | Strength supports the mat: two or three sessions a week, two beside four or five BJJ sessions, one at peak (StrengthLog) | `grappling_strength` and `grip_endurance` exposures — one up to four days, two from five (I5) |
| R3 | Low volume: about three sets of three to six reps on compound lifts (StrengthLog, Vitruve) | the strength blocks' sets and reps |
| R4 | A deload week between the two six-week halves of a strength block: 50–60 % of the weight, about ten reps, two sets (StrengthLog) | the strength modules' `deload`: every seventh week, two sets of ten with the weight in the note; source week `strengthlog_deload` |
| R5 | A competitor's conditioning: ten-minute rounds of short efforts; shuttle runs and takedown-entry drills in bursts (Juggernaut, Vitruve) | optional `competition_conditioning`: `may_share_day` with a strength day, `never_with: [mat_class]`, dropped on a deload |

## Debt (rules nothing enforces yet)

None.

## Open

- Competition preparation (a camp: its weeks, Vitruve's taper) is not modelled; the
  conditioning module is what a competitor adds in a normal week.
- How a class divides its minutes: the sources leave the class to the gym.

## Inventions

- I1: the class's blocks and minutes (warm-up, drilling, positional, rolling) are the
  shape of a typical class, not the coach's plan.
- I2: strength is prescribed by effort (an RPE target); the sources write reps and
  percentages of a one-rep max and add weight when the reps are made.
- I3: R4's deload repeats every seventh week, not only once inside a twelve-week
  block, and the competition conditioning deloads with the strength work beside it.
  The mat never deloads on a schedule — no source deloads it; an athlete who reports
  being overreached deloads everything, and the class then drops live rolling and
  keeps the drilling (the owner's decision, 2026-10-21).
- I4: declared substitutes for an injured athlete (positional or drilling for rolling,
  inverted rows for pull-ups), and supporting blocks named when left out.
- I5: up to four training days, one strength session beside the classes — the
  sources' two need five days.
- I6: competition conditioning is offered from intermediate up; the sources write it
  for competitors.
- I7: at six training days, four classes, each on a day of its own, beside two S&C
  sessions, where BJJEE's week has five (Saturday a class and the second S&C
  session) — the owner's decision, 2026-10-21.

## Tests

Source weeks (`data/packages/bjj/source_weeks.yaml`): BJJEE's six-day week (R1), its
two S&C sessions compared; its five classes are not — the package's four (I7) are
the owner's decision. StrengthLog's deload (R4): the pull-up's sets and reps over
eight weekly strength sessions, two of ten on the seventh.

test_training_contract.py — `test_bjj_mat_time_leads_the_week`,
`test_bjj_strength_deloads_on_the_seventh_week_and_the_mat_carries_on` (R4, I3),
`test_bjj_substitutes_are_declared_and_supporting_blocks_say_when_they_go` (I4),
`test_bjj_conditioning_is_optional_and_never_outnumbers_the_mat`.
