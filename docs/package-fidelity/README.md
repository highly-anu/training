# Package fidelity: how a package is checked and improved

The goal of every package is a program the method's author would recognise:
the package's own contents, built into weeks as the method prescribes them,
under the athlete's days, minutes, equipment, injuries and level. This is the
method for getting a package there and keeping it there. It came out of
rebuilding Wildman, BJJ, Horsemen and Starting Strength (October 2026);
`status.yaml` says where every package stands.

## What went wrong before

Almost every defect was **content the source does not contain**, not an engine
bug: Horsemen's Fan Dance, second track and deload weeks; Wildman's three phases
whose content never differed; BJJ's strength work taking mat days; ramps,
RPE targets and deloads where the source writes none. Each was fixed by going
back to a primary source. The engine's part was that it could only express
"sessions of a modality per week", so packages bent their method into it.

## The method

1. **Source dossier** (`docs/package-fidelity/<package>.md`). The primary
   sources (the author's own pages, books, published PDFs — read in full, not
   summarised from memory), and every rule they state: weekly structure and
   frequency, the unit of prescription, progression, loads, deloads, tests,
   equipment and substitutes, levels and entry requirements, and what the
   source says to do with fewer days or less time. Each rule cites its source.
   What the source leaves open is listed as open, never filled in.
2. **Choose the engine shape the method has.** The unit of prescription decides:
   - fixed modules progressed by cycles (Wildman, BJJ's strength work) →
     a training contract (`training_contract.yaml`, docs/logic/training_contracts.md);
   - the source's own week, day by day, from lists of named workouts
     (Horsemen) → week templates and category pools (`week_templates`,
     `categories`, `as_written`; src/week_template.py);
   - load added session to session (Starting Strength) → a contract with load
     per confirmed exposure (`load_per_exposure`);
   - skills earned by assessment (Ido Portal, ATG, Kelly Starrett) →
     assessment gating (not built yet);
   - otherwise the modality scheduler, with the framework's
     `sessions_per_week`, `cadence_options` and the phase `checks:`.
3. **Every rule into data.** Each dossier rule is either something the engine
   executes (a contract module, a template day, a phase key, a slot's load
   text) or a fidelity `checks:` entry that tools/check_fidelity.py tests. A
   rule left only in prose is listed in the dossier as debt.
4. **No invented structure.** No phase the source does not name (one
   repeatable phase is the honest default), no ramp, RPE, deload or test it
   does not prescribe, loads as written. Where the athlete's constraints bend
   the program, the source's own answer is used (Wildman: the shorter version;
   Horsemen: which days go first) and the program says what changed.
5. **Inventions are a ledger, not a habit.** Anything the app adds that the
   source does not contain is listed in the dossier and in `status.yaml`
   (`inventions:`), decided by the owner case by case — Pentathlon Prep is
   built from kettlebell-sport practice because Wildman publishes none.
6. **Protect the athlete's history.** A package change reaches athletes through
   a regenerate, which keeps every trained day (program_history.restore_elapsed);
   earned progression needs logging that can earn it (the one-tap "done as
   written", `POST /health/sessions/<key>/confirm`).

## The scorecard

How far a package is from its method, graded per package × track
(`tools/evaluate_packages.py`, the graders in `src/package_eval.py`, today's
grades in [scorecard.md](scorecard.md)). Five dimensions, each criterion pass
(✓), partial (◐) or fail (✗) — never a blended number, because a weighted sum
hides the one failure that matters. A dimension reads its worst criterion that
is not hygiene; the grades ratchet in `tools/scorecard_baseline.json` (a worse
grade fails CI), and `status` in `status.yaml` is derived from them.

| Dim | | Criterion | ✓ | ◐ | ✗ |
|---|---|---|---|---|---|
| Source | S1 | Dossier has Sources, Rules, Open, Inventions and Tests | all | — | one missing |
| | S2 | `sources_kind` | primary, or a consensus of ≥3 | secondary | not stated |
| | S3 | Rules only in prose (`debt:`) | none | some, or not stated | — |
| | S4 | `inventions` in status.yaml = the dossier's | equal | — | differ |
| | S5 | A source test CI runs | ≥1 | — | none |
| Execution | E1 | Sessions delivered with every slot empty | none | — | any |
| | E2 | Sessions another modality's for lack of their own (`substituted_for`), worst written-for profile | none | ≤25 % | more |
| | E3 | A level the track is not written for (contract levels, else the frameworks' `training_level`) | refused | — | served |
| | E4 | Most-used archetype's share of its modality, per phase (≥4 sessions; contracts and templated phases exempt; a phase's `max_archetype_share` is the method's own word) | ≤40 % | ≤60 % | more |
| | E5 | Defining claims: phase `checks:`, a contract or a week template | declared, hold | none declared | broken |
| | E6 | Fidelity findings (`check_fidelity`'s rules) | none | warnings | errors |
| Robustness | R1 | No equipment, a kettlebell home, 45 and 30 minutes, three days, one bell, lumbar, shoulder and knee flags | method kept, or refused where one constraint lifted alone unblocks it | refused, nothing unblocks | served degraded (an empty session, >25 % substitutes, a claim broken) |
| Data | D1 | Schema-valid, injury flags resolve | yes | — | no |
| | D2 | Catalog exercises no program reaches (counting borrowers) | none | some | — |
| | D3 *hygiene* | Exercise media | ≥90 % | ≥50 % | less |
| | D4 *hygiene* | Empty movement patterns, archetypes without levels, inert `equipment_limited` | none | some | — |
| Measurement | M1 | The analytics lead = `currency[track]` in status.yaml | yes | — | no, or not stated |
| | M2 | The lead's fields are logged on both clients (`vocabulary.CAPTURE`) | logged or prescribed | optional, or a watch only | no lead |
| | M3 | Each declared standard has a scheduled test, a prescribed `derived_from` lift, or `manual: true` | all | some | — |
| | M4 | Referenced standards exist | yes | — | no |

The execution criteria are the audit's findings made executable: E2 sees a
novice Gym Jones program that is half substitutes, E4 CrossFit's one AMRAP
template, E3 an intermediate handed Starting Strength's novice sessions, R1
a session with every slot empty. A track `excluded_tracks` names (an invention
awaiting the owner) is graded but does not count toward the status.

## The gates

Run on every change to the engine, the data, the schemas, the tools, the tests or
the watch code (.github/workflows/training-contract.yml). Every command in the
first column runs there; `tools/check_package_status.py` fails when the table
and the workflow part.

| Gate | What it holds |
|---|---|
| `tools/validate_entities.py --all` | every file against its schema; template, pool and test wiring; injury-flag ids resolve, each substitution pair inside one package |
| `tools/check_provenance.py` | no package draws on another it does not declare |
| `tools/check_provenance.py --coverage` | coverage gaps and authoring problems, watch specs included |
| `tools/check_styles.py` | every philosophy × track × phase generates on its own framework |
| `tools/evaluate_packages.py` | the scorecard may not get worse, `status` is the one it earns, every fidelity finding is in the baseline (`check_fidelity.gate`, in the same pass) and every catalog exercise reaches a program (`check_exercise_coverage`, in the same pass); a baseline that a change has made stale fails until it is updated in that change |
| `tools/check_analytics.py` | every declared measure applies somewhere |
| `tools/check_package_status.py` | `status.yaml` lists every package, names real files and tracks, and declares the status the recorded scorecard earns; this table matches the workflow |
| `test_watch_spec.py` | a package's `watch.yaml` resolves; the watches' generated tables are current; `garmin/core` names no package |
| `test_program_analytics.py` | a package's analytics, including one written to disk as a throwaway package, need no engine change |
| the package's **source test** | the week as the source writes it, pinned (e.g. `test_training_contract.py`'s Wildman Phase II and BJJ tests, `test_week_template.py`'s Horsemen macro) |

## Working a package

1. Write or update the dossier; get the sources first.
2. Print the program the package generates today under realistic profiles
   (3–6 days, 30–90 minutes, home and gym equipment, a common injury, each
   level) beside the dossier's rules, and list each difference.
3. Fix data first, engine second; a new engine feature is generic and
   documented (CLAUDE.md, docs/logic/).
4. Add or extend the package's source test; declare the phase's defining
   claims (`checks:`), the track's `currency`, `sources_kind` and `debt`;
   shrink the baselines (`--update-baseline` on `evaluate_packages.py` and
   `check_exercise_coverage.py`).
5. Two independent reviews: the code, and the output against the dossier.
6. Set the package's `status` in `status.yaml` to the one the scorecard earns.
