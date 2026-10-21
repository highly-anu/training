# Gym Jones — source dossier

Engine shape: week templates (`src/week_template.py`). Gym Jones writes its plans as
months, day by day, so each day is one workout as written, in its own one-workout pool
(frameworks `operator_fitness` and `soldier_of_steel`, archetypes `archetypes/plan/`).
The record (sources, rules with what enforces each, inventions) is
`data/packages/gym_jones/fidelity.yaml`; this page is its prose, under the same ids. The
status is the scorecard's (status.yaml).

## Sources

Read on 2026-10-21:

- Operator Fitness (Rob "Maximus" MacDonald, Gym Jones Training Plan), in full
  (`data/gym jones/operator fitness I - gym jones.pdf`): the introduction and all 28 days.
- Soldier of Steel (Gym Jones for the Army National Guard, 2013), in full
  (`data/gym jones/gym jones soldier of steel.pdf`): the introduction and all 28 days,
  with the beginner versions printed on the days.
- Operator Fitness II, in part: the repository's copy ends at day 17.
- Mark Twight's Gym Jones Knowledge articles on the Wayback Machine: Breathing Ladders,
  Endurance V.2, TNSTAAFL.
- Not read: Extreme Alpinism (2001) and the paywalled Knowledge articles from 2015 on.

## Rules and where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | A month, six days a week: three key workouts (strength, circuit, accumulation), two recovery, one endurance (of1) | `days_per_week_min: 6`; the `foundation` phase's `week_templates`; source week `operator_fitness_month` |
| R2 | A Foundation period, an even mix of strength, power endurance and endurance (of1) | the framework's categories |
| R3 | Done once or repeated a few times in a row (of1) | `repeatable: true` |
| R4 | Operator Fitness's 28 days as written (of1) | 24 day archetypes `gj_of_dNN`; source week `operator_fitness_month` |
| R5 | Single-leg and core strength emphasised (of1) | the days themselves |
| R6 | The endurance day: a 90–120 min hike with elevation under a 20–30 lb pack (of1) | category `endurance` |
| R7 | The breathing ladder, 1-20-1 kettlebell swings at 53 lb, resting standing (k_bl, of1 day 17) | category `breathing_ladder`; the watch counts rungs |
| R8 | Soldier of Steel: every hard day followed by a recovery day, one rest day a week (sos) | its phase's `week_templates`; source week `soldier_of_steel_month` |
| R9 | Soldier of Steel's 28 days as written, the beginner versions among them (sos) | 24 day archetypes `gj_sos_dNN`; source week `soldier_of_steel_month` |
| R10 | Soldier of Steel is for the newly training, mostly open space (sos) | `track_for_level: novice → soldier_of_steel` |
| R11 | Repeat as written, or less rest or more weight; strict form, full range, speed (sos) | the track's description |
| R12 | No deload week; the recovery days and the rest day are the recovery (of1, sos) | no `deload_protocol` |

## Debt (rules nothing enforces yet)

None.

## Open

- Operator Fitness II is not run: the repository's copy ends at day 17. The source says
  the two months are interchangeable.
- Extreme Alpinism and the paywalled Knowledge articles were not read.
- "300" is an invitation-only challenge, not a program, and is not programmed.
- The 2000 m row on Operator Fitness day 15 is run as the day writes it. No source makes it
  a block test, so it is not scheduled as one.

## Inventions

- I1: the days start on a Monday. Operator Fitness numbers days 1–28 without weekdays.
- I2: a range is read at its middle (60–90 min as 75, 90–120 as 105, 3–4 sets as 4, the note
  keeping the range), and each day's minutes are estimated.
- I3: a section is logged by its main movement (clean + front squat + hang clean as power
  cleans, the Six-Way complex as the barbell complex), and its note keeps the source's words.
- I4: six training days are required, since both plans write six. There is no drop order
  for fewer.
- I5: the pull-up's scapular-control prerequisite is met from novice (`level_seeds.yaml`).
  Both plans prescribe pull-ups from the first week.
- I6: Operator Fitness is for intermediate and up, Soldier of Steel for novices and
  intermediates. The plans name audiences, not levels.

## Removed in this review

The three-block periodization (accumulation, transmutation, realization) on
`block_periodization`, whose blocks, deloads, intensity split and sessions per week no source
writes. Also removed: the 2 km row as a block test, the generic operator-strength, EMOM-wave
and barbell-complex sessions, the TGU, circuit, row-interval and aerobic-recovery templates,
`avoid_with`, and the exercises only they used. The old package lives on as the modality
scheduler's test fixture (`test_packages/block_fixture`), never shipped.

## Tests

Source weeks (`data/packages/gym_jones/source_weeks.yaml`): the Operator Fitness month (R4)
and the Soldier of Steel month (R9).

test_week_template.py: `test_gym_jones_runs_its_two_months_as_written` (R4, R9, R10, R12).
