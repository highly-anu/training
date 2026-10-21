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

1. **Source dossier and record.** The primary sources (the author's own
   pages, books, published PDFs — read in full, not summarised from memory),
   and every rule they state: weekly structure and frequency, the unit of
   prescription, progression, loads, deloads, tests, equipment and
   substitutes, levels and entry requirements, and what the source says to do
   with fewer days or less time. What the source leaves open is listed as
   open, never filled in. Two halves, by the same ids:
   - the **record**, `data/packages/<package>/fidelity.yaml`
     (docs/schemas/fidelity.schema.json): each source with how much of it was
     read and when; each rule (`R1`, `R2` …) with what it `cites` and what it
     is `enforced_by`; `open`; each invention (`I1` …) with where it is
     `implemented_by`; the track's `currency`; the shape. It lives in the
     package folder, so a new package touches nothing outside it;
   - the **dossier**, `docs/package-fidelity/<package>.md`: the same in
     prose, naming every rule and invention by its id.
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
3. **The source's own weeks, as data.** What the source *shows* — an example
   week, a progression table — goes into `data/packages/<package>/source_weeks.yaml`
   (docs/schemas/source_weeks.schema.json, src/source_weeks.py): the profile
   the source assumes, then its weeks day by day (`archetype`, `category`,
   `modality`, the exercises with the sets, reps and loads it gives), a week's
   sessions per modality where it counts rather than places them, or one
   field over successive sessions (`series`: Wildman's 6 → 20 swings, a
   squat's kilograms). The scorecard generates each and compares only what
   the entry writes: a field left out is the source's silence. Horsemen's
   sixteen example weeks, Wildman's 32 swing sessions, Starting Strength's
   A/B weeks, squat jumps and Texas Method week are written this way.
4. **Every rule into data.** Each rule is enforced by something the engine
   executes (a contract module, a template day, a phase key, a slot's load
   text), a fidelity `checks:` claim tools/check_fidelity.py tests, a source
   week the scorecard reproduces, or a test CI runs — its `enforced_by`:
   `data:<file>#<key path>`, `checks:<track>/<phase>.<key>`, `week:<id>`,
   `test:<file>::<function>`, every one resolved by the scorecard. A rule
   with none is debt; the scorecard counts it, nobody declares it.
   A claim, a contract, a week template, a hand-entered standard
   (`data:analytics.yaml#benchmarks.<id>`) or the lead measure counts only
   when a rule (or, for what the app adds, an invention) names it: a
   `max_archetype_share: 1.0` no source states is a number, not the method.
5. **No invented structure.** No phase the source does not name (one
   repeatable phase is the honest default), no ramp, RPE, deload or test it
   does not prescribe, loads as written. Where the athlete's constraints bend
   the program, the source's own answer is used (Wildman: the shorter version;
   Horsemen: which days go first) and the program says what changed.
6. **Inventions are a ledger, not a habit.** Anything the app adds that the
   source does not contain is an invention in the record (and so in the
   generated `status.yaml`), decided by the owner case by case — Pentathlon
   Prep is built from kettlebell-sport practice because Wildman publishes
   none. A track that is itself an invention awaiting a decision is named in
   `excluded_tracks` by its invention id.
7. **Protect the athlete's history.** A package change reaches athletes through
   a regenerate, which keeps every trained day (program_history.restore_elapsed);
   earned progression needs logging that can earn it (the one-tap "done as
   written", `POST /health/sessions/<key>/confirm`).

## The scorecard

How far a package is from its method, graded per package × track
(`tools/evaluate_packages.py`, the graders in `src/package_eval.py`, today's
grades in [scorecard.md](scorecard.md)). Six dimensions, each criterion pass
(✓), partial (◐) or fail (✗) — never a blended number, because a weighted sum
hides the one failure that matters. A dimension reads its worst criterion that
is not hygiene; the grades ratchet in `tools/scorecard_baseline.json` (a worse
grade fails CI, and so does a better one left unrecorded), and
`status.yaml` is written from the records and the grades
(`--update-baseline`) — a status is earned, never typed.

| Dim | | Criterion | ✓ | ◐ | ✗ |
|---|---|---|---|---|---|
| Source | S1 | A record with sources and rules, and a dossier | all | — | one missing |
| | S2 | The sources, as read | a primary read in full, or ≥3 read | fewer read | none read |
| | S3 | Rules nothing enforces (debt, computed); every `enforced_by` resolves | none | some debt | a reference to nothing, or no rules |
| | S4 | Every rule rests on a source read; every currency and excluded track names a rule or invention; the dossier names every id | all | — | any not, or no rules |
| | S5 | The track's own source weeks (`source_weeks.yaml` entries for it), generated and compared; a track that is itself an invention has none to reproduce | all reproduce | only numbers differ; or none, but a source test CI runs | the structure differs, or neither |
| | S6 *hygiene* | A review of the output against the dossier (`tools/print_package.py`) in `reviews` | recorded | none | — |
| Execution | E1 | Sessions delivered with slots empty | none | some slots | every slot |
| | E2 | Sessions another modality's for lack of their own (`substituted_for`), worst written-for profile | none | ≤25 % | more |
| | E3 | A level the track is not written for (contract levels, else the frameworks' `training_level`) | refused | — | served |
| | E4 | Most-used archetype's share of its modality, per phase (≥4 sessions; contracts and templated phases exempt; a phase's `max_archetype_share` is the method's own word when a rule cites it) | ≤40 % | ≤60 % | more |
| | E5 | Defining claims a rule (or invention) cites: phase `checks:`, a contract or a week template | declared, hold | none cited | broken (a declared volume band too) |
| | E6 | Fidelity findings (`check_fidelity`'s rules; a contract's equipment and injuries too) | none | warnings | errors |
| Robustness | R1 | No equipment, a kettlebell home, 45 and 30 minutes, three days, one bell, lumbar, shoulder and knee flags | method kept, or refused where one constraint lifted alone unblocks it (what the preview's Held back shows) | refused, nothing unblocks | served degraded (an empty session, >25 % substitutes, a claim broken, a fidelity error on that athlete — an exercise their equipment or injury rules out) |
| Data | D1 | Schema-valid, injury flags resolve | yes | — | no |
| | D2 | Catalog exercises no program reaches (counting borrowers), computed in the run | none | some | — |
| | D3 *hygiene* | Exercise media | ≥90 % | ≥50 % | less |
| | D4 *hygiene* | Empty movement patterns, archetypes without levels, inert `equipment_limited` | none | some | — |
| Measurement | M1 | The analytics lead = the record's `currency[track]`, which names the rule (or invention) it rests on | yes | — | no, not stated, or uncited |
| | M2 | The lead's fields are logged on both clients (`vocabulary.CAPTURE`) | logged or prescribed | optional, or a watch only | no lead |
| | M3 | Each declared standard has a scheduled test, a prescribed `derived_from` lift, or `manual: true` a rule cites | all | some | — |
| | M4 | Referenced standards exist | yes | — | no |
| Portability | X1 | String literals in `src/`, `api.py`, the web, the iOS and Apple Watch apps and the Garmin core that name the package (`tools/check_code_neutral.py`) | none | — | any |
| | X2 | Every step of the ideal program resolved to a watch screen, as the watches' payload resolves it (`src/watch_spec.py`) | the package's own | the generic screen for an unclaimed slot type | one the vocabulary cannot draw |

The execution criteria are the audit's findings made executable: E2 sees a
novice Gym Jones program that is half substitutes, E4 CrossFit's one AMRAP
template, E3 an intermediate handed Starting Strength's novice sessions, R1
a session with every slot empty. A track `excluded_tracks` names (an invention
awaiting the owner) is graded but does not count toward the status.

Portability is the second goal of every package: one the owner adds by
writing a folder, with no change to the server, the clients or the watches.
X1 and X2 grade it per package; `test_package_dropin.py` proves it end to end
— three packages copied under ids no code has seen, into a packages folder of
their own (`TRAINING_PACKAGES_DIR`), validated, generated, served by the API,
encoded for the watches with their screens, read by the analytics and the
scorecard, with nothing in the repository changed.

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
| `tools/check_package_status.py` | each record names its own tracks; `status.yaml` is what the records and the recorded scorecard write; this table matches the workflow |
| `test_watch_spec.py` | a package's `watch.yaml` resolves; the watches' generated tables are current; `garmin/core` names no package |
| `test_program_analytics.py` | a package's analytics, including one written to disk as a throwaway package, need no engine change |
| `test_source_weeks.py` | a source week against hand-built programs: what is structure, what is a number, what is never compared |
| `tools/check_code_neutral.py` | no string literal in the server, the web, the iOS and Apple Watch apps or the Garmin core names a package (X1, without a baseline) |
| `test_package_dropin.py` | three packages dropped in under new ids need no code change, end to end |
| the package's **source weeks** | the weeks as the source writes them, generated and compared in `evaluate_packages.py`'s pass (S5); a package's own tests (`test_training_contract.py`, `test_week_template.py`) pin what data cannot say, such as the log that earns a step |

## Working a package

1. Get the sources first; write the record (`fidelity.yaml`: sources, how much
   of each was read and when, every rule with what it cites) and the dossier;
   transcribe what the source shows into `source_weeks.yaml` before looking
   at what the package generates.
2. Print the program the package generates today under realistic profiles
   (`tools/print_package.py <package>`: the rules with what enforces each, the
   source weeks, then each track under the fidelity profiles — the ideal
   athlete, the lowest and highest days, a kettlebell home, bodyweight, 45
   minutes, two injuries) and list each difference.
3. Fix data first, engine second; a new engine feature is generic and
   documented (CLAUDE.md, docs/logic/).
4. Give each rule its `enforced_by` — the data, the cited phase claims
   (`checks:`), the source's own weeks, a test; set the track's `currency` on
   its rule; record what the app adds as inventions with their
   `implemented_by`.
5. Two independent reviews: the code, and the output against the dossier
   (step 2's printout) — each recorded in the record's `reviews` (kind, date,
   scope, what it found and where each finding went; S6).
6. `tools/evaluate_packages.py --update-baseline --report
   docs/package-fidelity/scorecard.md`: the grades, the orphans, the fidelity
   findings and `status.yaml` are written together, from what the package
   earns.
