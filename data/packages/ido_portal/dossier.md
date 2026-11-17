# Ido Portal — source dossier

Engine shape: week templates (`src/week_template.py`). Ido Portal's Floreio Routines are a set
of named routines, each written for beginners, intermediates and the advanced. Each version
is one archetype as written (`archetypes/plan/`), all in one pool in the PDF's order
(framework `floreio_routines`), and the athlete's level picks the version (`training_levels`).
The record (sources, rules with what enforces each, inventions) is
`data/packages/ido_portal/fidelity.yaml`; this page is its prose, under the same ids. The
status is the scorecard's (records/status.yaml).

## Sources

Read on 2026-10-22:

- Ido Portal, Floreio Routines (`data/portal/Ido Portal Floreio Routines.pdf`), all 16 pages:
  thirteen routines, nearly all at three levels. The PDF's links (the demonstration videos,
  and the posts that describe the wrists, squat clinic, shoulder and scapula routines) were
  not read.
- Not read: Ido's wider method (the camps, the online coaching, the handstand and rings
  programs).

## Rules and where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | Thirteen routines as written: exercises, reps, holds, distances, sets, rests (floreio pp. 1–16) | 35 archetypes `ido_*` in the pool `floreio`; source week `floreio_weeks` |
| R2 | Each routine written for beginners, intermediates and the advanced; the athlete does their level's (floreio) | each archetype's `training_levels` |
| R3 | The preparation opens every routine (jump rope or joint mobility, wrists, squat clinic, shoulders); prehab closes most (floreio) | the routines' first and last slots |
| R4 | Polish single movements, then sequence them, then role work, improvised at the advanced level (floreio) | "Singular Movement Polish", "Sequence Work" and role slots |
| R5 | "The variation you are capable of": where a routine writes "or", the written movement first and its alternative after (floreio) | ordered `exercise_ids` |
| R6 | No phases or deloads; the routines repeat (floreio) | one repeatable phase; no `deload_protocol` |

## Debt (rules nothing enforces yet)

None.

## Open

- The routines the sessions name (wrists, squat clinic, shoulder ROM and stabilization,
  scapula mobilization) and every movement are linked videos and posts that were not read.
  The exercise notes describe the movements, not Ido's cues.
- Ido's wider method was not read; only these routines are built.
- A routine that opens with the jump rope has no written alternative, so without a rope it is
  passed over.

## Inventions

- I1: six training days a week with Sunday rest, and fewer days drop from the end of the
  week. The PDF names no frequency.
- I2: the routines run in the PDF's order, each training day taking the next one written for
  the athlete's level.
- I3: the PDF's beginner is novice, intermediate is intermediate, and advanced covers
  advanced and elite.
- I4: how the doses are read. A range is taken at its middle, with the note keeping the
  range. A pyramid is written as "10/8/6" reps. A circuit or tri-set becomes each exercise's
  sets, with the circuit in the notes. A routine's first pass counts as three minutes and a
  repeat as two. Each routine's minutes are estimated.
- I5: the second "Explosive Leg Workout – beginner/intermediate" (p. 15: front and back flips,
  the advanced shrimp) is read as the advanced version.
- I6: assessment gating is advice, not a gate (the owner's call, 2026-10-22, as for Wildman's
  layoff). Each session's first movement says, at beginner and intermediate, to set the next
  level in the profile once the athlete owns their version of the routines; the engine never
  moves the level. The PDF gives no criterion beyond "if you can already" and "the variation
  you are capable of". The text is the category's `advice`, per level.

## Removed in this review

The `movement_practice` track (Isolation → Integration → Spontaneous Expression) on
`high_frequency_skill`, whose phases, six-week deload, sessions per week, intensity split and
cadence no source writes. Also removed: the joint-prep, movement-flow and skill-ladder
sessions that summarised the routines rather than running them; the exercise prerequisites
that locked the handstand walk and the L-sit behind movements no level granted (`requires`
naming `push_up`, `wrist_prep`, `dip_ring` and others the package did not have); and the
exercises only they used.

## Tests

Source weeks (`data/packages/ido_portal/source_weeks.yaml`): a beginner's first fortnight
(R1, R2).

test_week_template.py: `test_ido_portal_runs_the_floreio_routines_at_each_level` (R1, R2, R3,
R6, I2).
