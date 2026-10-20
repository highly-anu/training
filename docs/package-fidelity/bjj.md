# BJJ — source dossier

Status: **audited** (2026-10-20). Engine shape: training contract
(`data/packages/bjj/training_contract.yaml`, track `mat_support`).

## Sources

- StrengthLog, "Strength training for BJJ" — strength as support, by effort, low volume;
  two sessions a week for active competitors or four to five mat sessions, one at peak.
- BJJEE, the training-mix article — the weekly ratio of mat time to strength and
  conditioning (five classes to two S&C sessions in the author's best weeks).
- TrainHeroic, Relentless Grappler team plan — session shapes for grappling strength.
- Vitruve (Iker Zubizarreta), "BJJ Strength and Conditioning Program" — the
  pre-competition phase's functional circuits (shuttle runs of 30–40 m) and partner
  drills for takedown entries in short bursts; "BJJ technique is priority number one".
- Chad Wesley Smith (Juggernaut), "Jiu Jitsu Conditioning Circuits" — ten-minute rounds
  of 15–30 s efforts with sprints or animal movements between.

There is no single-author method: the package encodes the consensus these
sources share. Each is cited in the contract.

## Rules → where they live

| Rule | Encoded as |
|---|---|
| Mat time first; classes outnumber S&C at every week size | `mat_class` `exposures_by_days` (2 at 3 days … 5 at 7); strength one session up to four days, two from five; the phase's `checks: modality_outnumbers` |
| Classes are the gym's; drilling before live work | `mat_class` blocks: warm-up, drilling, positional, rolling — minutes are a typical class, not instructions to the coach |
| Strength by effort, not fixed kg; a hard mat week lowers it | `sets_reps` blocks with `rpe_target`; the note says to choose the load that meets it |
| Deloads drop live rolling, keep drilling | per-block `deload_keep` (rolling 0, positional 0.5) |
| Injured athletes keep training around the injury | declared `alternatives` (positional or drilling for rolling, inverted row for pull-ups); `optional` supporting blocks named when left out |
| A competitor's conditioning beside the strength work, never at the mat's expense | optional `competition_conditioning`: takedown entries, sprawl intervals, shuttle sprints, bear crawls; `may_share_day` with a strength day, `never_with: [mat_class]`, dropped on a deload |

## Open

- Competition preparation (a camp: its weeks, the taper) is not modelled; the
  conditioning module is what a competitor adds in a normal week.

## Inventions (see status.yaml)

- Class minutes are the shape of a typical class, not the coach's plan.
- Competition conditioning is offered from intermediate up: the sources write it for
  competitors, and the app reads a novice's mat time as their conditioning.

## Tests

test_training_contract.py — `test_bjj_mat_time_leads_the_week`,
`test_bjj_deload_drops_rolling_and_keeps_drilling`,
`test_bjj_substitutes_are_declared_and_supporting_blocks_say_when_they_go`,
`test_bjj_conditioning_is_optional_and_never_outnumbers_the_mat`.
