# Kelly Starrett — source dossier

Engine shape: week templates (`src/week_template.py`). The Starretts publish Built to Move's
program as a 21-day challenge written day by day, so each day is one archetype as written
(`archetypes/plan/btm_dNN`). The days form one pool taken in order (framework
`built_to_move`), and day 21 is then its own pool for the habits after. The record
(sources, rules with what enforces each, inventions) is
`data/packages/kelly_starrett/fidelity.yaml`; this page is its prose, under the same ids. The
status is the scorecard's (status.yaml).

## Sources

Read on 2026-10-22:

- Kelly and Juliet Starrett, the Built to Move 21-Day Challenge on The Ready State
  (btm21), Days #0–21, every day's text in full (the site refuses automated reads; read in
  the Wayback Machine's 2024 copies). The challenge is "taken directly from the Built To Move
  book". Its follow-along mobilizations are videos that the pages do not name, and they were
  not watched.
- Secondary (btm_reviews): MindBodyDad's account of the vital signs' tests, Marlo Yonocruz's
  book notes and Equinox's article. They give the tests' protocols, and the bands the book
  gives for some of them.
- Not read (no copy found): Built to Move (Knopf, 2023), Becoming a Supple Leopard (2nd ed.,
  2015), Ready to Run (2014).

## Rules and where they live

| | Rule (source) | Encoded as |
|---|---|---|
| R1 | The challenge as written: days 1–10 one vital sign each (its test, its practice, the day's mobilizations), days 11–21 the practices stacked (btm21) | 21 archetypes `btm_d01`–`btm_d21` in one pool, taken in order; source week `challenge_weeks` |
| R2 | Ten tests in the first ten days (btm21, btm_reviews) | the movement tests as slots (`test_*`); the counts (steps, food, sitting, sleep) in the day's notes |
| R3 | Practices stack: each day keeps the ones before (btm21) | floor sitting in every day; the later practices from their day on |
| R4 | Sit-stands from day 7, one more each day to 21 (btm21) | `sit_stands` reps = the day's number; source series `sit_stands` |
| R5 | Balance from day 8: the Y balance, balance play or the Old Man Balance Test, as each day names it (btm21) | the days' `balance` slots |
| R6 | The through-the-day practices (8,000–10,000 steps, nose-only breathing, 800 g of fruit and vegetables, protein, standing at work rising from 30 minutes to 2 h 30, sleep hygiene) go with each day (btm21) | each day's notes |
| R7 | After day 21 the habits are "to be mixed into each day for the rest of your days"; no deload (btm21) | the repeatable `habits` phase; no `deload_protocol` |

## Debt (rules nothing enforces yet)

None. R6 is said, not scheduled: the engine plans sessions, not a whole day.

## Open

- **Scoring the tests.** The ten tests are practised and logged, not scored. Every day's
  page sends the reader to the book for what a result means ("Refer to pp. 33-34 of Built to
  Move"), and the book was not read. With its bands, each test could become a standard.
  Some of the bands are known second-hand (btm_reviews). Retesting is recommended meanwhile
  (I6).
- The follow-along mobilizations are unnamed videos. Each day's session links its page and
  counts them (I2).
- Becoming a Supple Leopard and Ready to Run were not read, and their mobility prescriptions
  and standards are not built.
- The extra credit (mouth taping, rucking, Tabata squats, jump rope, the worm push-up) is in
  each day's notes, not scheduled.
- Eating and sleep are said in the day's notes. The engine plans training sessions, not
  meals or nights.

## Inventions

- I1: floor sitting is five minutes in the session. The challenge asks for it "throughout
  your day".
- I2: each mobilization counts as three minutes, a test as four and a balance practice as
  three, so a day runs 15–30 minutes. The pages give no times.
- I3: day 7, which introduces the sit-stands without a number, does seven. Day 8 does eight,
  one more each day.
- I4: after day 21, day 21 runs every day: its practices and its three mobilizations, the
  challenge's last stack.
- I5: seven days a week are required, and the challenge starts on a Monday.
- I6: assessment gating is advice, not a gate (the owner's call, 2026-10-22, as for Wildman's
  layoff). Every everyday-practice session (after day 21) says to retest the ten vital signs
  now and then and to keep at the practice of any found hard, the method's "test, practise,
  retest". It is never scheduled or scored, and how often is not written on the challenge's
  pages. The text is the `habits` category's `advice`.

## Removed in this review

The `supple_leopard` track (Restore → Load the Range → Maintain) on `kelly_starrett_mobility`.
No source was read for its phases, eight-week deload, sessions per week or intensity split.
Also removed: the banded joint restore, endurance, grappling, strength and joint-prep
mobility sessions, built from descriptions of Becoming a Supple Leopard rather than from the
book, and the 35 exercises only they used.

## Tests

Source weeks (`data/packages/kelly_starrett/source_weeks.yaml`): the challenge's 21 days
(R1), and the sit-stands one more each day (R4).

test_week_template.py: `test_kelly_starrett_runs_the_21_day_challenge_as_written` (R1, R3,
R7, I5).
