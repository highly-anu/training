# Package fidelity: how a package is checked and improved

The goal of every package is a program the method's author would recognise:
the package's own contents, built into weeks as the method prescribes them,
under the athlete's days, minutes, equipment, injuries and level. This is the
method for getting a package there and keeping it there. It came out of
rebuilding Wildman, BJJ and Horsemen (October 2026); `status.yaml` says where
every package stands.

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
     per confirmed exposure (not built yet);
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

## The gates

Run on every change to `src/**` or `data/**` (.github/workflows/training-contract.yml):

| Gate | What it holds |
|---|---|
| `tools/validate_entities.py --all` | every file against its schema; template, pool and test wiring |
| `tools/check_provenance.py` (`--coverage`) | no package draws on another it does not declare; coverage gaps |
| `tools/check_styles.py` | every philosophy × track × phase generates on its own framework |
| `tools/check_fidelity.py` | every philosophy × track × profile against its package; findings may only shrink |
| `tools/check_analytics.py` | every declared measure applies somewhere |
| `tools/check_exercise_coverage.py` | every catalog exercise reaches a program; orphans may only shrink |
| `tools/check_package_status.py` | `status.yaml` lists every package; an audited one has its dossier, a source test CI runs, no fidelity finding and no orphan |
| the package's **source test** | the week as the source writes it, pinned (e.g. `test_training_contract.py`'s Wildman Phase II and BJJ tests, `test_week_template.py`'s Horsemen macro) |

## Working a package

1. Write or update the dossier; get the sources first.
2. Print the program the package generates today under realistic profiles
   (3–6 days, 30–90 minutes, home and gym equipment, a common injury, each
   level) beside the dossier's rules, and list each difference.
3. Fix data first, engine second; a new engine feature is generic and
   documented (CLAUDE.md, docs/logic/).
4. Add or extend the package's source test; shrink the baselines
   (`--update-baseline` on both tools).
5. Two independent reviews: the code, and the output against the dossier.
6. Set the package's `status` in `status.yaml`.
