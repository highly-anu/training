# BJJ — source dossier

Status: **partial** (2026-10-20): the week is right; five catalog exercises are
never prescribed. Engine shape: training contract
(`data/packages/bjj/training_contract.yaml`, track `mat_support`).

## Sources

- StrengthLog, "Strength training for BJJ" — strength as support, by effort, low volume.
- BJJEE, the training-mix article — the weekly ratio of mat time to strength and conditioning.
- TrainHeroic, Relentless Grappler team plan — session shapes for grappling strength.

There is no single-author method: the package encodes the consensus these
sources share. Each is cited in the contract.

## Rules → where they live

| Rule | Encoded as |
|---|---|
| Mat time first; classes outnumber S&C at every week size | `mat_class` `exposures_by_days` (2 at 3 days … 5 at 7); strength one session up to four days, two from five |
| Classes are the gym's; drilling before live work | `mat_class` blocks: warm-up, drilling, positional, rolling — minutes are a typical class, not instructions to the coach |
| Strength by effort, not fixed kg; a hard mat week lowers it | `sets_reps` blocks with `rpe_target`; the note says to choose the load that meets it |
| Deloads drop live rolling, keep drilling | per-block `deload_keep` (rolling 0, positional 0.5) |
| Injured athletes keep training around the injury | declared `alternatives` (positional or drilling for rolling, inverted row for pull-ups); `optional` supporting blocks named when left out |

## Open

- Five catalog exercises (bear crawl, shuttle sprint, sprawl intervals,
  takedown practice, wall sit) reach no program: wire them into a module the
  sources support (conditioning for competitors?) or drop them.
- Competition preparation (a camp) is not modelled.

## Tests

test_training_contract.py — `test_bjj_mat_time_leads_the_week`,
`test_bjj_deload_drops_rolling_and_keeps_drilling`,
`test_bjj_substitutes_are_declared_and_supporting_blocks_say_when_they_go`.
