# Wildman generation fidelity — branch handoff

Recorded: 2026-10-18. Branch: `codex/wildman-generation-contract`, committed and rebased onto master as `wildman-contract` on 2026-10-19.
Repository: this one (the branch was first built in the main checkout).

This is a conversation and implementation handoff, not a second project backlog.
`docs/roadmap.md` remains the central backlog. The implementation is local and
uncommitted at this checkpoint, including new untracked files. No merge, push or
production deployment was performed. Do not discard the working tree when resuming.

## User intent and decisions

1. Programs must use exercises declared by their owning package's `exercises.yaml`.
   Explicitly declared borrowing remains supported; accidental cross-package or
   cross-track selection does not.
2. The initial comparison request was CrossFit: catalog size versus unique
   exercises used in generated 12-week novice and intermediate programs, with all
   equipment available. The wider discussion then requested raw package inventory,
   methodology research, fidelity rankings and an Eisenhower-style improvement matrix.
3. The user chose Wildman first because they were on week 1 of a Wildman program.
   The central concern was: good package data is insufficient if generation drops
   the methodology's essential rules.
4. Initially the user prohibited edits and required a new branch before any later
   editing. They subsequently authorized implementation, including package files,
   and confirmed that regeneration would be safe for their completed work.
5. The user challenged the small matrix relative to the severity of the findings.
   Explanation: the matrix grouped multiple serious symptoms under shared causes;
   fewer rows did not mean minor defects.
6. The user requested serving the branch on standard localhost for manual testing.
7. The first Wildman exercise-count comparison found only 20–35% per-track coverage.
   The assistant initially overclaimed fidelity after fixing progression. That was
   corrected explicitly: executable progression alone does not establish that a
   few selected modules represent the full Wildman methodology.
8. The user clarified the desired coverage policy: focused General Practice and
   Pentathlon tracks are acceptable. Do not inflate variety inside them. Add
   appropriate tracks so exercises are not permanent unused catalog entries.
9. The resulting policy is **package-wide generated reachability**, distinct from
   per-track breadth and from methodology fidelity. Reaching 100% is not proof of
   an official or complete Wildman program.

The user subsequently supplied the earlier all-package evaluation and generator
investigation. Their full substantive contents are now preserved in
[package-quality-and-generation-audit.md](package-quality-and-generation-audit.md),
including both matrices, package inventories, generated counts and fidelity rankings.
Those are historical pre-contract results, not current branch measurements. The
original CrossFit sample used 30/54 novice and 38/54 intermediate exercises; it is
separate from the later Wildman full-track comparison.

## Root causes and the implemented response

| Root cause / symptom | Implemented response | Boundary |
|---|---|---|
| Methodology exists in prose but is not executable | Validated, opt-in `training_contract.yaml` and compiler | Wildman is the first opted-in package |
| Modality defaults override framework intent | Shared resolver with explicit framework policy support | Legacy packages still need individual audits |
| Templates and exercises drift across owners or tracks | Owner-scoped selection, explicit borrowing, fixed contract modules | No implicit contract blending |
| Calendar weeks imply skill or load advancement | Independent module state, clean-outcome advancement, conditional forecasts | No automatic skill promotion or heavier bell |
| Session labels fit while real work exceeds time | Budget actual timed work, intervals and explicit recovery | Infeasible requests fail rather than trim essential work |
| Standards lose event structure or are rescaled | Exact scored Pentathlon protocol, explicit event recovery and test placement | Preparation ramp is an app adaptation |
| Invalid output can be saved | Independent output/phase acceptance checks and HTTP 422 before persistence | Generic replacement/swap routes reject contract bypasses |
| Logs and clients drop prescription semantics | Web/iOS outcome inputs, EMOM descriptions, contract metadata retained | More device-level manual testing remains useful |
| Analytics measure obsolete prescriptions | Wildman analytics rescaled to actual practice, intervals, time and events | Completion alone is not mastery |
| Exercise catalog contains unreachable movements | Four additional tracks plus generated coverage gate | Adaptation boundaries remain explicit |

The expected benefit is substantial improvement in **prescription fidelity and
continuity through regeneration**. No percentage improvement in physiological
training outcomes was claimed or measured.

## Architecture and generation behavior

Primary implementation: `src/training_contract.py`.

- `src/goals.py` loads a validated package contract for the selected track.
- `src/generator.py` compiles opted-in contracts; other packages retain the legacy
  generator. Shared selector fixes still apply to legacy generation.
- Supported policies are `density_cycle`, `timed_cycle` and `skill_hold`.
- Each module has fixed exercises, frequency, minimum recovery spacing, workload
  policy, supported levels and any explicit proficiency requirements.
- Same-module exposures are nonconsecutive, including across week boundaries.
- Modules can share a session if their required work fits. Essential movements
  are not replaced by generic accessories or another track's templates.
- Injury restrictions, phase exclusions and equipment availability are enforced.
- Deloads reduce executable work and hold the progression cursor. Scored tests do
  not advance it. An overreached athlete does not receive a scored test.
- Timed work is rounded up to whole minutes for current phone/watch clients; the
  actual rounded time is budgeted. Inter-event rest is an explicit meta block.
- Output is checked for exercise sequence, frequency, spacing, progression,
  per-exercise completion requirements, duration and declared phase rules.
- Failed compilation/preflight returns HTTP 422 and does not persist a program.
- Generic session generation/replacement and exercise swaps cannot bypass the
  contract. Exercise swap controls are hidden for contract assignments.
- `src/output.py` preserves block notes and prescription details in Markdown.
- `src/fidelity.py` uses contract-specific verification for contract programs.

### Confirmed work versus a forecast

`module_state` stores confirmed completed exposures and an optional selected
`weight_kg`. Future generated exposures forecast successful completion; they do
not grant earned progression in advance.

On regeneration, `api.py` recovers confirmed state from the matching active
program's scoped logs. It also handles a client submitting the unchanged old
state snapshot. Contract identity includes package, track and version.

Advancement requires completed attendance plus all required exercise outcomes:
clean technique, RPE within the module ceiling, and the prescribed rounds or
practice-window duration. Missing, failed, out-of-order and replayed older
exposures do not grant additional progress. Per-exercise requirements avoid
counting a short get-up window as completion of a longer one.

- An explicit changed `module_progression_state` can start/resume/reset a cycle.
- An actual logged bell can be retained; a different bell midcycle does not
  silently count as continuing the old cycle.
- No fractional bell, level-derived working weight or automatic bell increase.
- Optional `kettlebell_weights_kg` restricts selection to real inventory.
- `mastered_exercises` records entry proficiency confirmations.
- `kettlebell_count >= 2` explicitly confirms matching bells for the double track;
  selected/logged weight is **per bell**.
- `src/progression_tracker.py` reports contract module positions rather than
  applying legacy shared weight/round stall heuristics.

## Package contents and program counts

`data/packages/wildman_kettlebell/exercises.yaml` contains **20 entries with 20
unique IDs**. No catalog entries were deleted to improve the coverage number.

Measured by actually generating full default tracks: all catalog equipment,
four available days, a 90-minute session budget, required mastery explicitly
confirmed, and two matching bells for the double-bell track. Unique counts include
preparation, main work and recovery exercises. Rest-only meta blocks do not count.

| Track | Weeks | Novice | Intermediate | Advanced | Elite | Sessions in supported full run |
|---|---:|---:|---:|---:|---:|---:|
| General Practice | 16 | 4 | 6 | 6 | 6 | 64 |
| Pentathlon Prep | 12 | unsupported | 7 | 7 | 7 | 24 |
| Squat Practice | 12 | 3 | 3 | 3 | 3 | 24 |
| Snatch Practice | 12 | unsupported | 4 | 4 | 4 | 24 |
| Get-Up and Loaded Mobility | 12 | unsupported | 5 | 5 | 5 | 24 |
| Double-Bell Practice | 12 | unsupported | 6 | 6 | 6 | 48 |

Before the four additional tracks, General Practice covered 20% (novice) or 30%
(intermediate–elite) and Pentathlon covered 35%. Their union was 10/20 IDs.
Their individual sets remain unchanged. With the new tracks the package-wide
union is **20/20**, with no foreign IDs and no orphan catalog exercises.
Intermediate, advanced and elite currently share movement sets within each track;
those level labels do not independently introduce additional movement complexity.

### Exact movement sets

| Track / level | Prescribed unique movements |
|---|---|
| General Practice novice | Deadlift, halo, two-hand swing, Turkish get-up |
| General Practice intermediate–elite | Novice set plus single-arm clean and strict press |
| Pentathlon intermediate–elite | Deadlift, halo, single-arm clean, long cycle press, single-arm jerk, half snatch, single-arm push press |
| Squat Practice | Deadlift, halo, goblet squat |
| Snatch Practice | Deadlift, halo, single-arm swing, full snatch |
| Get-Up and Loaded Mobility | Halo, Turkish get-up, windmill, rack carry, overhead carry |
| Double-Bell Practice | Halo, deadlift, double clean, double press, double front squat, double jerk |

### Track prescription boundaries

- **General Practice:** two swing and two complementary module exposures weekly.
  Public swing-cycle progression is preserved: repetitions increase within fixed
  minute intervals, then volume increases at the same bell. Novices have hinge
  and unloaded get-up practice; intermediate+ clean/press entry assumptions remain
  explicit. No calendar-based introduction of snatches, jerks or doubles.
- **Pentathlon:** five fixed sport events, twice weekly, with explicit five-minute
  rests between events. Practice duration ramps are an app adaptation. Full test
  events remain six minutes each and the final test uses the last scheduled
  exposure of its declared week. Novice entry is rejected.
- **Squat Practice:** separate goblet squat density practice. This is not a
  reproduction of Wildman's Deck Squat program.
- **Snatch Practice:** qualified single-arm swing/snatch practice; the low-rep EMOM
  is an app adaptation, not the purchased snatch timing protocol.
- **Get-Up and Loaded Mobility:** fixed, repeated technique windows. Windows
  include short efforts and rest; they do not prescribe continuous multi-minute
  overhead carries. Requires proficiency in the loaded movements.
- **Double-Bell Practice:** independent double strength and jerk technique modules.
  Requires two appropriate matching bells and declared movement proficiency.
  The double-jerk block is an **app-authored extension**, not a verified official
  Wildman jerk cycle or an IKMF Pentathlon event.

Twelve weeks on the added tracks is an app practice horizon, not a claim that an
official paid Wildman program ends then. These tracks are labelled adaptations.
Do not erase that distinction in future UI copy or fidelity assessments.

## 2026-10-19: Pentathlon Prep rebuilt from kettlebell-sport practice

Committed and rebased onto master, the contract cut Pentathlon Prep to two event
sessions a week, while master had meanwhile given the track's antiglycolic
session a heart-rate rest. Asked which mirrors a real program, a search found:
Wildman publishes no pentathlon or antiglycolic program (his catalog is swing,
clean & press, get-ups, snatch, deck squat, clubs, bodyweight); IKMF publishes
the event rules only; practitioners prepare with three sessions a week of volume
toward a full pentathlon and at least one full practice pentathlon per cycle
(RazeBells), the mini pentathlon as a frequent predictor (Kettlebell Nation),
repeats and intervals (Girya Garage), and easy steady runs as skippable general
preparation (Breaking Muscle, Clemente); kettlebell sport needs its glycolytic
capacity (Girevoy Sport Science). The user chose to follow that:

- Three essential event modules a week — volume (five events, 3 → 4 minutes,
  five-minute rests), repeats (5 × 3 minutes slightly faster than competition
  pace, four-minute rests), minute intervals on the four fast events (6 → 10
  reps, 4 → 6 rounds) — and an optional easy run, up to twice a week on free days.
- A full practice pentathlon ends Timed Sets (week 10); the test ends Competition.
- No antiglycolic work in Pentathlon; the archetype stays, credited to StrongFirst.
- The track and framework say it is an IKMF / kettlebell-sport adaptation.

Sources: [IKMF rules](https://ikmf-world.com/disciplines/ikmf-pentathlon),
[RazeBells](https://www.razebells.com/post/valery-fedorenko-gave-us-gold),
[Kettlebell Nation](https://kettlebellnation.com/the-kettlebell-pentathalon/),
[Girya Garage](http://www.giryagarage.com/powerbyparker/2022/8/10/kettlebell-sport-training-styles),
[Breaking Muscle](https://breakingmuscle.com/a-12-week-gpp-programme-for-kettlebell-sport-athletes/),
[Girevoy Sport Science](https://www.gsscience.com.au/anti-glycolytic-musings-part-1/),
[Wildman programs](https://www.wildmanathletica.com/all-programs). No official
IKMF or Fedorenko training program is public; RazeBells' full program is paid.

## Research and confidence

Sources used during the discussion, with narrower claims than marketing promises:

- [Wildman programming / Nerd Math and Tetris](https://www.wildmanathletica.com/programming):
  repetition, non-linear advancement, themed blocks and nonconsecutive exposures.
- [Official kettlebell program catalog](https://programs.wildmanathletica.com/kettlebell-programs):
  separate movement programs and foundational movement families.
- [Public swing program PDF](https://s3.amazonaws.com/kajabi-storefronts-production/sites/2147529643/themes/2148964886/downloads/wm1OoAfESN6SsE7bdmR9_NerdMath_SwingProgram_211011_r1.4.pdf):
  the source used for the swing repetition/volume cycle.
- [Get-up program](https://programs.wildmanathletica.com/tgu) and
  [public get-up guide](https://s3.amazonaws.com/kajabi-storefronts-production/sites/2147529643/themes/2151832023/downloads/xlOFB2RgSg2I2ZXpR9y9_ProgramGuide_TGU_v01.pdf):
  separate get-up focus and six foundational movement patterns.
- [Snatch program](https://programs.wildmanathletica.com/snatch): separate snatch
  training and learning/working protocol distinctions.
- [Double-bell discussion](https://programs.wildmanathletica.com/blog/the-benefits-of-double-kettlebell-training):
  double clean, press, squat and carry movement families.
- [Wildman's windmill demonstration](https://www.youtube.com/watch?v=LpFZMjh80nM):
  direct movement evidence, not evidence for our exact practice-window prescription.

Public evidence does not establish that all app-authored cycles reproduce official
Wildman plans. Exact double-jerk methodology remains unverified. Neither full
catalog reachability nor a clean automated fidelity report resolves that question.

## Clients, analytics and tooling

- Web and iOS expose clean completion, RPE and actual bell weight for module work.
- EMOM descriptions retain repetitions per round and the selected bell; watch
  descriptions were updated too. Forecast prescriptions are labelled conditional.
- `/api/philosophies` exposes track entry requirements, including skills by athlete
  level and matching-bell count. Builders present confirmations rather than silently
  granting mastery. Novice General Practice does not require clean/press mastery.
- iOS generation encodes proficiency/count fields and retains saved readiness when
  opening program settings. New types have a decoding/encoding regression test.
- Wildman analytics now measures practice consistency, swing intervals, technique
  time, Pentathlon event cadence and event duration; obsolete double-bell weight
  and ballistic-time scopes were removed. Practice consistency covers added tracks.
- `tools/check_exercise_coverage.py` generates every supported track/level and fails
  for failed/empty programs, foreign exercise IDs or an orphan catalog entry.
- Schema validation discovers `training_contract.yaml`; schemas cover contracts,
  constraints, archetype RPE targets and explicit framework prescription policy.
- Fidelity checks qualify fixture athletes explicitly, test supported contract
  levels and reject ideal-profile generation failures. Baselines may shrink, not grow.
- `.github/workflows/training-contract.yml` runs contract, catalog coverage,
  selection, phase, standard and fidelity checks. It is local/uncommitted too.

## Validation checkpoint

Latest successful checks recorded in this conversation:

- 16 contract behavioral tests, including regeneration from saved clean work,
  actual bell retention, refusal without mastery/pairs and per-exercise durations.
- 272 web tests; production frontend build successful; lint had zero errors and
  six existing warnings in unrelated files.
- 225 iOS tests; simulator rebuilt and launched against read-only fixture data.
- 167/167 entity files valid.
- All philosophy/track/phase style checks passed, including four new tracks.
- Wildman analytics measures apply in their intended tracks.
- Wildman fidelity: zero errors, zero warnings, 20 informational findings.
- Full fidelity baseline remained 228 known findings after updating
  `docs/fidelity-report.md` and `tools/fidelity_baseline.json`. That number is not
  a claim that remaining legacy package issues have been fixed.
- Provenance: zero foreign sessions out of 608 and zero foreign exercises out of
  3,142 in its standard profiles. Coverage/authoring: zero blocking gaps and no
  authoring problems. Static level/phase reporting still lists 17 gaps, including
  intentional novice-ineligible Wildman Pentathlon/double-bell frameworks.
- Passed scripts: `test_phases.py`, `test_provenance.py`, `test_week_numbering.py`,
  `test_today_session.py`, `test_last_time.py`, `test_fidelity.py`,
  `test_selection.py`, `test_phase_summary.py`, `test_standard_tests.py`,
  `test_program_analytics.py`, `test_development_analytics.py`,
  `test_workout_metrics.py`, `test_workout_analysis.py`, `test_load_summary.py`.
- Earlier program-envelope SQL tests skipped because local PostgreSQL was not
  available to that test process; do not claim end-to-end database validation.
- `git diff --check` passed.

A verification pitfall: older tests create/remove `_zz_test` inside `data/packages`.
Running catalog scanners concurrently with these mutating tests caused transient
missing-file/no-track errors. Affected contract/provenance checks passed when
rerun after those tests finished. Keep those operations sequential when resuming.
Some read-only tests emit local PostgreSQL sandbox warnings while still passing.

## Local runtime and saved-data safety

At the checkpoint, branch code is served by the normal dev processes:

- Frontend: `http://localhost:5173` from `frontend/`.
- API: `http://localhost:8000/api` from the repository root.
- Vite proxies `/api` to port 8000; frontend local config uses the real local API.
- Both services returned HTTP 200. The live philosophy endpoint was read back and
  showed all six Wildman tracks with entry requirements.
- The repository's local environment layer targets the local `training_test`
  database and local-dev identity. Never copy production secrets into this document.

If servers have stopped, use the existing local environment and start
`.venv/bin/python api.py` and, in `frontend/`, `npm run dev`. Check existing listeners before starting
another copy. Recheck the branch and local environment before any persistence.

No real saved program was regenerated or replaced for this verification. The user
can choose to generate through localhost for their own manual testing.

A separate read-only fixture server was left running on `127.0.0.1:18080` from
`/private/tmp/wildman-preview.py`. The iOS Simulator API override points there,
**not to port 8000 or production**. The fixture is not the real local API and does
not expose the latest enriched readiness response. Do not confuse the fixture's
four-week sample with the full default sixteen-week General Practice track.

Latest simulator screenshot: `/private/tmp/wildman-tracks-preview.png`.
Earlier screenshot: `/private/tmp/wildman-program-preview.png`.
The fixture and screenshots are temporary, not committed artifacts. If resuming
phone testing, inspect the override and choose the intended local server explicitly;
never regenerate against production as a verification step.

## Resume checklist and remaining review questions

This is a checkpoint of limitations and decisions to revisit, not evidence that
all of them are defects or a separate ranked backlog:

1. Review the four new adaptations for coaching quality, especially the double-jerk
   extension. Reachability is solved mechanically; exact methodological fidelity
   still needs stronger source evidence and/or a deliberate product decision.
2. Manually exercise new-track selection and readiness in web and phone builders,
   generation, logging, regeneration and both watch presentations. The simulator
   screenshot verified rendering of the fixture calendar, not every readiness control.
3. Intermediate, advanced and elite share movement choices. Decide whether explicit
   athlete-selected module/proficiency paths should distinguish them further.
4. The placer uses conservative uniform duration estimates and checks day-specific
   caps after placement. It can refuse a tight schedule that a better search might
   fit; it must never accept an over-budget program to improve coverage.
5. Starting a heavier-bell cycle is supported by explicit API module state, but
   dedicated user-facing cycle reset / bell-selection controls remain limited.
6. Review program-settings track changes separately from fresh builder entry;
   ensure new requirements can be confirmed and saved readiness is preserved.
7. Generic swaps are blocked. Review manual session moves and other editing paths
   for ways they might violate spacing after generation.
8. Additional packages still need their own executable contracts and renewed
   methodology audits. Shared schema/selector improvements do not imply all-package
   fidelity. Generalizing the reachability rule to every package is not yet done.
9. The original CrossFit comparison and all-package quality matrix can be revisited
   with reproducible generated artifacts rather than relying on conversational totals.
10. Inspect the full working-tree diff, including untracked files, before committing.
    No commit, PR, push or deployment has been requested/performed here.

Useful entry points:

- `docs/logic/training_contracts.md` — contract semantics.
- `docs/logic/wildman_catalog_coverage.md` — counts and evidence boundaries.
- `src/training_contract.py` — compiler, state recovery and verification.
- `data/packages/wildman_kettlebell/training_contract.yaml` — executable tracks.
- `data/packages/wildman_kettlebell/philosophy.yaml` — track/phase descriptions.
- `test_training_contract.py` — behavior tests.
- `tools/check_exercise_coverage.py` — generated catalog reachability gate.
- `docs/fidelity-report.md` — generated multi-package fidelity findings.

Core reproducible checks (run package-mutating tests separately from scanners):

```sh
.venv/bin/python -B test_training_contract.py
.venv/bin/python -B tools/check_exercise_coverage.py
.venv/bin/python -B tools/validate_entities.py --all -q
.venv/bin/python -B tools/check_fidelity.py --package wildman_kettlebell
.venv/bin/python -B tools/check_styles.py
.venv/bin/python -B tools/check_analytics.py -p wildman_kettlebell
.venv/bin/python -B tools/check_provenance.py
.venv/bin/python -B tools/check_provenance.py --coverage
```

Follow repository instructions for broader checks, iOS build/test/preview and any
future baseline update. Consult `docs/roadmap.md` before promoting these review
questions into new project work.

## Recovered historical audit: interpretation at this checkpoint

The attached [historical evaluation](package-quality-and-generation-audit.md)
completes this handoff's earlier missing package-wide evidence. It includes:

- Inventory of all 11 packages: 438 package exercise declarations, 345 globally
  unique IDs, 16 frameworks, 69 session templates, 13 tracks, 31 phase entries and
  355 media records **at the time of that audit**.
- All 22 sampled novice/intermediate 12-week outputs, with session substitutions
  and unfilled exercise assignments.
- Description/execution scores and methodology-specific recommendations for every
  package, plus the original package-level importance/urgency matrix.
- Controlled Wildman reproductions, ten generator root causes, the engine-level
  matrix and proposed implementation sequence.

The original tied ranking was: Starting Strength and Gym Jones first; Uphill
Athlete third; ATG, Ido Portal and Kelly Starrett fourth; CrossFit, Marcus Filly,
Wildman and BJJ seventh; Horsemen eleventh. The underlying scores are preserved
in the archive; these are qualitative engineering judgments, not percentages.

The user's choice to start with Wildman superseded the original recommended
implementation order (Horsemen, BJJ, Marcus Filly, CrossFit, Uphill). It did not
mean the other packages' findings were resolved.

Status mapping against the historical investigation:

| Historical finding | Branch response / remaining boundary |
|---|---|
| No executable methodology contract | Implemented for Wildman; other packages retain legacy generation |
| Ambiguous progression ownership and unsupported model behavior | Wildman uses explicit supported contract policies; shared resolver supports opt-in ownership; accepted legacy models have not all been repaired |
| Calendar progression without successful-exposure state | Wildman module state and outcome-driven regeneration implemented; not a universal progression replacement |
| Eligibility mistaken for mastery | Wildman explicit entry proficiency and fixed modules; generic prerequisite closure is not a mastery system |
| Wrong track/template/filter selection | Wildman module identity, swap guards, shared bilateral/equipment filters and owner/declared-borrowing scoping implemented |
| Modality allocation loses Tetris identity | Wildman independent module composition, frequency and spacing implemented; not a general multi-method composition engine |
| Displayed and executable workload disagree | Wildman budgets actual blocks and rests and derives duration; legacy workload paths require separate audits |
| Schema/runtime mismatch | Contract schema and implemented capabilities validated; legacy percentage-of-1RM and every accepted model/filter combination are not globally certified |
| Fidelity detached from production success | Wildman output/phase gate blocks saving failed contracts, level profiles expanded and CI added; existing legacy baselines remain |
| Clients/analytics reinterpret prescriptions | Wildman resolved metadata, outcome logging, EMOM descriptions, Markdown structural work and contract progression review updated; complete device parity remains a review item |

The original strict-selector experiment incorrectly blocked Uphill's intentional
Starting Strength exercise borrowing. Branch scoping now respects declared
borrowing; passing provenance checks must not be interpreted as requiring every
borrowed exercise to be redeclared in the borrowing package.

Do not carry the original 19/20 Wildman default-track sample or its 108 baselined
warnings forward as current results. The current six-track counts and latest
Wildman fidelity check are recorded above. A new methodology ranking would require
a fresh evaluation, especially for the explicitly app-authored new tracks.
