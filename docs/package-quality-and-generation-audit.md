# Historical package evaluation and generator root-cause investigation

Recovered from the user's pasted conversation on 2026-10-18 for branch
`codex/wildman-generation-contract`.

## How to read this archive

This preserves the substantive original audit, all 11 package inventories and
rankings, both importance/urgency matrices, and the ten-part generator investigation.
Tables were converted from tab-separated pasted text to Markdown and UI timestamps
were removed. The original findings and judgments have not been silently rewritten.

**These are historical, pre-contract findings, not a fresh evaluation of the current
branch.** The original audit reported 22 default-track, 12-week programs. Its
inventory and Wildman counts precede the four added tracks and other branch fixes.
Original source-link labels without URLs remain as supplied; historical code line
numbers may have shifted. The research and numeric claims below were recovered
from the conversation, not independently rerun during this documentation task.

For the present implementation, validation and unresolved boundaries, read
[wildman-generation-branch-handoff.md](wildman-generation-branch-handoff.md).
Current Wildman generated reachability is 20/20 across six tracks; that does not
upgrade the historical execution score automatically or establish fidelity of
app-authored prescriptions. No new all-package ranking has been performed.

## Original audit and conversation

The main quality gap is between what packages say in their notes and what the generator actually prescribes. Several packages contain recognizable exercises and good explanatory text, but lose essential parts of their methodology during generation.
I audited all 11 packages, researched their methodologies using primary sources, and generated 22 programs: novice and intermediate, 12 weeks each, all equipment available, no injury restrictions.
No source files were changed during this audit. Results use the current working tree, including my earlier uncommitted selector changes.

## Original package inventory

“Modalities” counts distinct modalities represented by a package’s session templates. “Media” counts exercise-media records; it does not certify their accuracy.

| Package | Exercises | Frameworks | Session templates | Modalities | Tracks | Phase entries | Media |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ATG | 32 | 1 | 3 | 3 | 1 | 3 | 25 |
| BJJ | 26 | 1 | 5 | 4 | 1 | 1 | 0 |
| CrossFit | 54 | 1 | 6 | 3 | 1 | 1 | 46 |
| Gym Jones | 61 | 1 | 10 | 7 | 1 | 3 | 39 |
| Horsemen GPP | 85 | 2 | 8 | 5 | 2 | 5 | 46 |
| Ido Portal | 42 | 1 | 3 | 2 | 1 | 3 | 30 |
| Kelly Starrett | 45 | 1 | 5 | 2 | 1 | 3 | 45 |
| Marcus Filly | 46 | 1 | 5 | 5 | 1 | 1 | 28 |
| Starting Strength | 13 | 1 | 4 | 1 | 1 | 1 | 5 |
| Uphill Athlete | 14 | 4 | 13 | 6 | 1 | 4 | 13 |
| Wildman Kettlebell | 20 | 2 | 7 | 6 | 2 | 6 | 18 |
| Total package declarations | 438 | 16 | 69 | — | 13 | 31 | 355 |



There are 345 globally unique exercise IDs, because packages share some exercises. All 11 packages have analytics specifications; four have watch specifications. CrossFit alone declares package-specific level seeds.
A large catalog is not inherently better: Starting Strength should be narrow. Conversely, 85 exercises cannot compensate for inaccurate workout definitions.

## Original generated-program comparison

I used each default framework’s ideal days and session duration. Counts include warm-ups, mobility, benchmarks, and complementary work.
N / I means novice / intermediate. Substitutions count sessions whose planned modality was replaced. Gaps count unfilled exercise assignments, excluding intentional structural slots.

| Package | Days × minutes | Unique exercises N / I | Session substitutions N / I | Exercise gaps N / I |
| --- | --- | --- | --- | --- |
| ATG | 4 × 45 | 31 / 31 | 0 / 0 | 0 / 0 |
| BJJ | 5 × 60 | 23 / 23 | 0 / 0 | 0 / 0 |
| CrossFit | 4 × 60 | 30 / 38 | 0 / 0 | 0 / 0 |
| Gym Jones | 5 × 90 | 24 / 39 | 28 / 0 | 0 / 0 |
| Horsemen GPP | 5 × 90 | 35 / 47 | 24 / 0 | 6 / 0 |
| Ido Portal | 6 × 90 | 33 / 34 | 0 / 0 | 0 / 0 |
| Kelly Starrett | 6 × 30 | 44 / 44 | 0 / 0 | 0 / 0 |
| Marcus Filly | 5 × 75 | 13 / 28 | 36 / 0 | 0 / 0 |
| Starting Strength | 3 × 75 | 5 / 8 | 0 / 0 | 0 / 0 |
| Uphill Athlete | 6 × 90 | 8 / 11 | 16 / 0 | 0 / 8* |
| Wildman Kettlebell | 4 × 60 | 19 / 20 | 24 / 0 | 0 / 0 |



No run used exercises outside its own package catalog under the current stricter selector.
* Uphill exposes a problem with my earlier change: it intentionally borrows barbell exercises from Starting Strength. Restricting every session to its archetype’s own catalog blocks that declared borrowing. I verified this in memory using the original selector: intermediate gaps fell from eight to zero, using borrowed back squats and front squats. The eventual rule should respect explicitly declared borrowing.
These are default-track samples, not exhaustive validation. Twelve weeks does not cover all phases of longer tracks, such as Uphill’s 31-week program, or alternate tracks.

## Original methodology fidelity ranking

These are qualitative engineering judgments, not measured percentages. I separated authored description from generated execution:
- 5: close representation, including defining progression and scheduling rules.
- 4: strong representation with material omissions.
- 3: recognizable but simplified.
- 2: major defining elements absent or contradicted.
- 1: largely unrelated.
Packages with equal scores are tied.

| Rank | Package | Description /5 | Execution /5 | Assessment and improvement needed |
| --- | --- | --- | --- | --- |
| 1= | Starting Strength | 4 | 3 | Novice A/B sessions correctly preserve five core lifts and basic set/rep schemes. However, generated loads advance by week and estimated frequency rather than actual completed exposures. Intermediate output alternates HLM and 5×5 templates inside a novice LP track; HLM day modifiers are described in prose without corresponding scheduling logic. Separate novice and intermediate tracks and implement actual exposure-based progression. Official novice programming |
| 1= | Gym Jones | 4 | 3 | Broad physical preparation, strength, power, recovery, and outcome-oriented blocks are represented. Intermediate output is substantially stronger than novice output: 28/60 novice sessions are substituted, leaving 40 aerobic-recovery sessions. Define a genuine foundation track or explicitly restrict the current track’s audience. Gym Jones itself emphasizes foundations across power through endurance and individualized outcomes. Official training description |
| 3 | Uphill Athlete | 4 | 2 | The strongest phase architecture: transition, base, specificity, taper, with aerobic work, strength, and muscular endurance. Execution loses novice durability and muscular-endurance sessions; the novice run produces 56 recovery-jog sessions out of 72. Restore declared borrowing and create scaled mountain-specific novice sessions. Its official program explicitly identifies aerobic base, periodized strength, and specific muscular endurance as three pillars. Official mountaineering plan |
| 4= | ATG | 3 | 3 | Good coverage of backward sledding, tibialis work, split squats, posterior-chain work, and range-first principles. The framework uses RPE autoregulation while the defining range and pain-free progression criteria mainly remain prose. The generic range/load/maintenance track also compresses the more specific Zero/Dense/Standards progression. Encode regressions and measurable advancement criteria before expanding the catalog. ATG’s published principles |
| 4= | Ido Portal | 3 | 3 | Isolation, integration, expression, joint preparation, and movement practice are recognizable. Three templates provide limited representation of a much broader, exploratory practice; novice and intermediate programs use almost identical catalogs. Add concrete practice tasks, constraints, partner/reactive work, and observable mastery criteria. Public material supports the broad principles, but does not establish one canonical 24-week program. Movement Culture, Portal on isolation and integration |
| 4= | Kelly Starrett | 3 | 3 | Strong mobility catalog and relevant tissue, positional, breathing, and banded work. However, rotating through 44/45 exercises does not demonstrate assessment-led targeting. The package needs an explicit assessment → intervention → retest loop, with short routines attached to the athlete’s actual limitations and training. The Ready State’s assessment approach |
| 7= | CrossFit | 3 | 2 | Recognizable conditioning, scaling, and benchmark workouts, but the default program is heavily narrowed to one AMRAP template and bodyweight circuits. Novices get 36 AMRAP + 12 bodyweight sessions; intermediate benchmarks replace only three AMRAP sessions. Missing dedicated heavy days, broader workout structures, and systematic variation across time domains. CrossFit’s own template includes metabolic conditioning, gymnastics, and weightlifting in one-, two-, and three-element workouts. Official programming template |
| 7= | Marcus Filly | 3 | 2 | Tempo, controlled movement, RPE, and shoulder work appear in the descriptions. However, the default framework omits conditioning from its weekly mix despite having a conditioning template. Novice output becomes 48 mobility + 12 bodyweight sessions. Build integrated warm-up/strength/accessory/conditioning sessions, structured tempo and supersets, and a suitable beginner track—or clearly reject unsupported novice requests. Official FBB pillars, Base Camp |
| 7= | Wildman Kettlebell | 3 | 2 | Useful movement ladder, timed practice, and kettlebell coverage. However, the general framework emphasizes generic complexity progression and mixes in pentathlon training. It does not explicitly encode Wildman’s defining volume/density cycles and modular Tetris scheduling. Novice output substitutes half its sessions. Separate general Nerd Math practice from pentathlon-specific preparation. Wildman’s own programming explanation |
| 7= | BJJ | 3 | 2 | Correctly states that mat time is indispensable and includes drilling, positional sparring, and rolling. Yet the generated 60-session program contains only 12 actual BJJ classes. Another 12 sessions labeled combat_sport are gym S&C, allowing support work to occupy the same category as mat practice. Protect actual coached mat sessions separately. BJJ has multiple schools; Gracie’s published curriculum is a useful primary example, not a universal prescription. Gracie University’s curriculum |
| 11 | Horsemen GPP | 2 | 2 | The macro structure and equipment are recognizable, but there are concrete source discrepancies. The package calls strength numbers prerequisites; the source introduction presents them as program goals. “Russian Aggression” is described as a kettlebell/bodyweight couplet, while the source prescribes front-squat work followed by deadlifts, sled work, and other movements. Named workouts are collapsed into a generic exercise slot, losing their protocols. Re-extract and verify the source before adding content. |



Horsemen’s comparison used the repository’s original source document, particularly its introduction and named-workout definitions: data/horsemen/horsemen.pdf

## Original package improvement matrix

Here, importance means preserving a methodology’s defining training stimulus. Urgency means the current default output materially misrepresents it, omits essential work, or contains a verified source error. This prioritization does not assume anything about package popularity.

| Importance / urgency | Urgent: correct current defaults | Less urgent: improve depth and progression |
| --- | --- | --- |
| High importance | DO FIRST — Horsemen: correct source errors and encode named protocols. BJJ: protect mat classes from S&C substitution. Marcus Filly: restore appropriate strength and conditioning structure. CrossFit: broaden workout formats and strength exposure. Uphill: restore declared borrowing and scaled novice specificity. | SCHEDULE — Starting Strength: exposure-based loading and separate intermediate tracks. Gym Jones: foundation/novice track. Wildman: Nerd Math cycles and Tetris scheduling. ATG: measurable range/regression gates. Ido Portal: mastery criteria and richer practice tasks. Kelly Starrett: assessment-driven prescription and retesting. |
| Lower importance | BATCH / DELEGATE LATER — Fix misleading diagnostics: BJJ’s intentional structural slots are reported as “skipped”; Horsemen receives advice to add loaded_carry as equipment. These obscure the audit but are secondary to the training errors above. | DEFER — More exercise variants, additional media, watch customization, and cosmetic framework expansion until defining methodology rules work reliably. |



My recommended order is Horsemen → BJJ → Marcus Filly → CrossFit → Uphill, followed by progression work across the remaining packages.
Before implementation, I would turn each package’s defining claims into a small set of generation checks—for example, “BJJ mat sessions cannot be satisfied by gym S&C” or “CrossFit must include more than repeated AMRAP/bodyweight templates.” Any edits should start on a new Git branch, as you requested.

  







I agree with you conclusions, but I would like to start with Mark Wildman, since I'm on week 1 of a MW program right now. Before we work on the package data itself - you mentioned:
"The main quality gap is between what packages say in their notes and what the generator actually prescribes. Several packages contain recognizable exercises and good explanatory text, but lose essential parts of their methodology during generation."
this is of the uttermost imporance. it seems no matter how good our package data and structure is, we won't get to where we want if important parts are missed or dropped during program generation. do a deep investigation to the root causes of your statement above, and create a similar matrix with your suggested fixes. 
















Your concern is justified. The generator currently preserves exercise identity more reliably than it preserves training intent. It can produce a complete-looking program while changing the progression, session structure, or practice requirements that make it a Wildman program.
This is an engine-contract problem as well as a package-data problem. Improving package descriptions alone will not resolve it.
I traced the generation pipeline, generated both full Wildman tracks, ran the existing fidelity checker, and performed controlled experiments entirely in memory. No files were edited. These are reproductions from the current code; I have not inspected your saved week-one program.
The methodological reference was Wildman’s own description of Nerd Math progression, repeated practice of fundamentals, and modular Tetris scheduling. Wildman Athletica programming
The strongest evidence is in the generated output.

| Reproduction | What happened | Why it matters |
| --- | --- | --- |
| Change framework progression from complexity to rpe_autoregulation | Exercise prescriptions remained identical | A seemingly authoritative package field does not govern generation |
| Intermediate General Practice, week 1 | “Double KB Strength” selected a single-arm press, prescribed 3×5 at 12.5 kg | Session identity, equipment assumptions, and loading diverged |
| Novice General Practice | All 20 exercises passed prerequisite unlocking before phase exclusions | Eligibility is being treated as acquired proficiency |
| Novice week 7 | Snatches and single/double jerks appeared immediately when exclusions ended | Advancing the calendar substitutes for demonstrating readiness |
| General Practice | Pentathlon training appeared in the noncompetition track | Package ownership does not establish track suitability |
| Deload movement-skill session | Header: 17 minutes; prescribed blocks: 31 minutes | Displayed deload and actual workload disagree |
| Request 30-minute sessions | Ballistic session labeled 30 minutes contained 45 minutes of timed blocks; pentathlon session contained 50 | The time limit changes the label without ensuring the work fits |
| Add an explicit forbidden-archetype check | Generation still returned that archetype; the separate checker detected it | A known-invalid result can still be returned |
| Run the existing Wildman fidelity command | Exit success: 108 warnings, all already baselined | Passing the gate does not currently mean methodological fidelity |



Below are the root causes, ordered roughly by how directly they undermine trust in generation.
1. There is no complete executable contract between package authoring and generation.
   Important rules exist in prose: “increase only after clean repetitions,” “practice this movement twice weekly,” “six-minute sets,” or “double-bell work.” Some have structured equivalents; others do not.
   The engine does not interpret those sentences, and there is no capability check telling the author which promises it can actually execute. A package can therefore describe a richer methodology than the engine supports.
   Fix: Give every essential methodological rule a supported structured representation, an implementation owner, and an output check. If a required capability is unsupported, generation should report that explicitly. Descriptive text should explain the executable prescription.
   This separation is explicit in [phase handling (line 158)](../src/phases.py#L158): phase text is carried for display, while a limited set of structured fields drives behavior.
2. Progression ownership is ambiguous, and several model names do not implement distinct progression.
   Generation chooses:
   framework modality override → shared modality model → linear-load fallback
   It does not ordinarily use the framework’s progression_model.
   My mutation experiment confirmed this: changing Wildman’s framework model changed nothing; adding an explicit modality override changed the loads.
   There is a second problem inside the dispatcher. For sets_reps:
   - linear_load, density, and volume_block invoke the same linear-loading calculation.
   - Several other accepted models return plain sets and reps.
   - Timed slots use generic duration logic irrespective of the named progression model.
   Thus a valid model name is not proof that the advertised progression exists. [Model selection (line 634)](../src/generator.py#L634), [prescription dispatcher (line 342)](../src/progression.py#L342)
   Fix: Define one explicit resolution order, record the resolved policy on each prescription, and validate supported model × slot-type combinations. Unsupported combinations must produce an explicit failure instead of a generic prescription.
   Simply making every framework model override every slot would introduce a different class of errors; progression needs an explicit scope.
3. Progression is primarily calendar arithmetic, without the athlete state needed to apply conditional advancement.
   Linear loading uses:
   starting load + (week − 1) × assumed weekly exposures × increment
   The generator receives no completed-session history, successful exposure count, current bell inventory, or demonstrated movement mastery. Phase transitions reset the week counter used by that calculation.
   Wildman’s “advance when the current work is owned” cannot be implemented from a week number alone.
   There are progression-review and manually applied adjustment features elsewhere. They do not form an automatic, methodology-specific advancement loop inside generation. [Loading calculation (line 42)](../src/progression.py#L42), [generation inputs (line 383)](../src/generator.py#L383), [existing adjustment mechanisms (line 2512)](../api.py#L2512)
   Fix: Maintain progression state per training module: current bell/load, cycle position, successful exposures, quality criteria, and hold/advance/reset decisions. Future weeks can remain conditional forecasts until results justify advancement.
4. Prerequisite resolution confuses “can be selected” with “has been mastered.”
   The prerequisite resolver repeatedly unlocks exercises whose prerequisites are already unlocked. This correctly finds reachable movements, but does not establish that an athlete has learned them.
   For Wildman, that process made 20/20 movements eligible for a novice. Phase exclusions temporarily remove some; their expiry then opens them without a mastery decision. [Prerequisite resolver (line 76)](../src/selector.py#L76)
   Fix: Separate:
   - eligibility to begin learning;
   - permission to practice a regression;
   - demonstrated proficiency;
   - permission to load or progress.
   Calendar phase changes should not manufacture proficiency.
5. Selection preserves broad modality labels, but lacks enough training-purpose constraints.
   Archetypes are selected by modality, phase kind, level, equipment, duration, and scoring. They are not explicitly restricted to a selected track’s permitted session families.
   Exercises are selected using broad filters and recency scoring. Consequently:
   - General Practice can select the package’s pentathlon template.
   - A double-bell session can select a single-arm exercise.
   - Variety can win over repeated practice of a deliberately stable movement.
   Some declared filters are also unimplemented: my direct tests showed that bilateral: true and equipment_required did not constrain _matches_slot_filter. [Archetype selection (line 246)](../src/selector.py#L246), [exercise filters (line 124)](../src/selector.py#L124), [recency scoring (line 451)](../src/selector.py#L451)
   Fix: Add explicit track/session-family membership, movement continuity rules, and equipment quantity/loading semantics. Repetition versus variation must be a methodology policy.
6. The scheduler reduces methodologies to modality proportions, losing module identity.
   The scheduler largely turns weekly ratios into whole-session allocations across available days. Its split-session support mainly adds secondary mobility/skill work; it is not a general system for composing independently progressing training modules.
   That is insufficient for Wildman’s Tetris approach, where modules have their own identity, runtime, exposure frequency, and spacing rules.
   Separately, missing session types can be replaced with another modality through generic fallback logic. The replacement is reported, but generation continues even when the defining training stimulus has changed. [Allocation (line 240)](../src/scheduler.py#L240), [split sessions (line 678)](../src/scheduler.py#L678), [fallback substitutions (line 133)](../src/generator.py#L133)
   Fix: Schedule identifiable modules with minimum exposure and spacing requirements. Let the package declare which substitutions preserve intent and which make the requested program unsupported.
7. Workload adaptation operates on disconnected representations.
   Session headers, timed blocks, sets/reps, deload flags, and generic phase multipliers are calculated separately.
   Specific failures include:
   - Capping the session’s displayed duration without fitting its contents.
   - Capping individual timed blocks rather than the session total.
   - Leaving skill-practice duration unchanged on a deload.
   - Applying shared phase multipliers to timed work without a package-specific progression decision.
   The result can be internally contradictory even before presentation. [Duration rewriting (line 1017)](../src/selector.py#L1017), [timed prescriptions (line 163)](../src/progression.py#L163)
   Fix: Build one executable session structure, then calculate its full workload—including work, rest, repeated blocks, and transitions. Adapt that structure according to declared rules and derive the displayed duration afterward.
8. Schema validity is stronger than runtime support in some places, and weaker in others.
   Examples I verified:
   - The schema accepts filters that the selector ignores.
   - Changing intensity_pct_1rm did not change the calculated load.
   - rpe_target is read by progression code but rejected by the archetype slot schema.
   - Schema-accepted model names can fall through to generic behavior.
   Fix: Add capability and cross-field validation, with a test for each executable field. A field should be implemented, explicitly informational, or rejected—not silently accepted without effect.
9. Fidelity checks are detached from the production success decision.
   The existing checker is useful, but generation does not invoke it as a final acceptance gate. The API performs feasibility validation and adds some coverage warnings; that is narrower than validating the completed prescription.
   The current Wildman checker profiles also use intermediate athletes only, so the novice substitution problem is outside that matrix. Baselines permit existing warnings, and the checked-in deployment workflows do not run the backend fidelity gate. Some checks reuse selector helpers, so they can inherit the selector’s blind spots.
   Fix: Run independent post-generation invariants before accepting or saving a program. Test every supported level and full track. Keep legacy baselines for migration tracking, while making essential contract violations blocking. [Fidelity checker (line 243)](../src/fidelity.py#L243), [profile selection (line 72)](../tools/check_fidelity.py#L72), [API generation flow (line 1120)](../api.py#L1120)
10. Output and analytics can reinterpret the prescription again.
    This is not a blanket loss of all notes: the API and interactive clients preserve meaningful coaching text, and the watch receives structured RPM.
    However, Markdown skips structural blocks and reduces session notes to their first sentence. Progression analysis also independently resolves modality models, which can disagree with framework overrides used during generation.
    Fix: Preserve a versioned prescription and its resolved policy through every client and analytics path. Each client should either represent its required instructions faithfully or declare the unsupported feature. [Markdown rendering (line 67)](../src/output.py#L67), [analytics model inference (line 1104)](../src/progression_tracker.py#L1104)
The common architectural cause is that multiple stages independently approximate the method, with no final proof that the combined result still fulfills its essential rules.
My proposed importance × urgency matrix is:

| Importance / urgency | Urgent: prevents trustworthy generation now | Less urgent: needed for faithful long-term behavior |
| --- | --- | --- |
| High importance | DO FIRST — A. Block essential post-generation contract violations. B. Resolve progression explicitly and reject unsupported model/slot combinations. C. Implement or reject ignored executable fields. D. Enforce track identity and approved substitutions. E. Fit and validate actual session workload, including deloads. | SCHEDULE NEXT — F. Add module-specific progression state and outcome-driven advancement. G. Separate eligibility from mastery. H. Implement module composition and spacing for Tetris scheduling. I. Preserve resolved prescription semantics across regeneration, analytics, API, phone, and watch. |
| Lower importance | BATCH ALONGSIDE — Correct misleading duration labels and diagnostics; expose which rule produced each prescription. These improve visibility but cannot substitute for A–E. | DEFER — More exercise variants, longer prose, more media, visual polish, and additional methodology packages until the execution contract works. |



For Wildman, I recommend a narrow engine-first sequence.
1. Define a small executable contract for one specific Wildman program. Establish required modules, movement continuity, cycle variables, advancement conditions, equipment constraints, and permitted adaptations from its source.
2. Make today’s failures fail tests. Cover novice and intermediate users, both tracks, normal and deload weeks, shortened sessions, missed sessions, and regeneration.
3. Repair A–E using that contract. This establishes that supported rules are honored and unsupported requests are explicit.
4. Add F–H for actual Wildman progression. Track the athlete’s cycle and completed exposures rather than substituting generic weekly increases.
5. Then revise the package data to use the supported contract.
The acceptance standard should be concrete: every essential rule must either be fulfilled in the generated prescription or produce an explicit unresolved requirement. A familiar session title, filled exercise slots, and a passing warning baseline are insufficient.
Before applying this to your ongoing program, we should audit its exact saved prescription and preserve your completed week-one work. Any implementation edits should begin on a new Git branch.

## Re-measured and extended, 2026-10-19

Added after the contract work was committed (`wildman-contract`) and the Dev Lab's
constraint-impact route existed (`dev_lab`). The plan that follows from it is
`docs/roadmap.md` item 9; this section is its evidence.

### The sample, re-run

The same 22 programs (each package's primary track, novice and intermediate, 12
weeks, the first framework's ideal days and minutes, all equipment, no injuries),
generated on the current code:

| Package | Novice | Intermediate |
| --- | --- | --- |
| Wildman | contract: fixed modules, 0 substitutions | contract |
| Gym Jones | 28 of 60 substituted, 40 aerobic recovery | as written |
| Horsemen GPP | 24 substituted, 6 empty slots, 36 of 60 aerobic base | as written |
| Marcus Filly | 36 substituted, 48 of 60 positional mobility | as written |
| Uphill Athlete | 16 substituted, 44 of 60 recovery jogs | 20 of 60 recovery jogs |
| CrossFit | 36 of 48 the same AMRAP template | 33 of 48 |
| BJJ | 12 of 60 are mat classes | the same |
| Starting Strength | 3×5 A/B, as written | HLM and 5×5 inside the novice LP track |
| ATG, Ido Portal, Kelly Starrett | as before: no substitutions, the depth findings stand | |

Every non-contract number is the audit's own: nothing outside Wildman has moved.
The fidelity gate does not see these failures. Of its 228 baselined findings, 184
are `intensity_split`; none says that a novice program is two-thirds recovery
jogs, that CrossFit repeats one template, or that BJJ trains the mat once a week
in five. "0 errors" is not evidence of fidelity yet.

### The root causes, for the ten packages on the old generator

| Audit cause (matrix letter) | Contract (Wildman) | Old generator (ten packages) |
| --- | --- | --- |
| No executable contract, no output gate (1, A) | `verify` + phase rules; 422 before saving | No acceptance gate: `fidelity` is a separate tool |
| Progression ownership (2, B) | explicit policy per module | No framework sets `prescription_policy`; `linear_load`, `volume_block` and `density` still share one calculation |
| Calendar progression (3, F) | confirmed state from clean logged work | `starting load + weeks × increment` |
| Eligibility vs mastery (4, G) | `requires_mastery`, level seeds | prerequisite closure only |
| Track identity (5, D) | fixed modules per track | selection by modality, phase kind and level; no track scope |
| Module scheduling (6, H) | placement with spacing; optional modules | modality ratios; fallback substitutes another modality |
| Workload (7, E) | budget of actual blocks and rests | labels capped apart from contents; deloads keep 60–85 % (roadmap 9.4 before this) |
| Schema vs runtime (8, C) | contract schema = capabilities | `intensity_pct_1rm` sets no load; 44 archetypes declare `scaling.equipment_limited` that nothing executes |
| Output reinterpretation (10, I) | resolved metadata through clients and watches | as before |

Two data findings the audit did not have, both from the Dev Lab work:

- **Injury data is mostly inert.** 55 of the 63 `modified_exercises` pairs in
  `injury_flags.yaml` name an exercise no package declares, so no substitute is ever
  given (Uphill with a knee flag empties its running slots instead of biking); 94 of
  the 143 `excluded_exercises` name nothing either, so protection rests on movement
  patterns alone.
- **Constraints degrade silently.** Starting Strength with no equipment returns
  sessions whose every slot is empty, under a warning that "equipment-limited
  scaling" will be used; an intermediate on its novice track gets other sessions
  with only a `LEVEL_MISMATCH` warning. The constraint-impact route now shows both;
  the generator should not produce them.

### What the methods prescribe for the open questions (web research)

The audit's per-package fixes left two kinds of decision open: whether a package
should serve novices at all, and what structure its contract must express.

| Package | Finding | Consequence |
| --- | --- | --- |
| Uphill Athlete | Publishes an 8-week *Beginner Mountain Fitness* plan for people with no prior experience: hikes or walks plus beginner strength ([plan](https://uphillathlete.com/training-plans/8-week-beginner-mountaineering-training-plan/)) | Write a novice track; do not refuse |
| Marcus Filly | *Base Camp* is his beginner program: 8 weeks, three 60-minute sessions, each warm-up + strength by movement pattern + conditioning, in barbell, dumbbell or kettlebell versions ([Rogue listing](https://www.roguefitness.com/apo/functional-bodybuilding-base-camp)) | Write a novice track on that shape |
| Gym Jones | *Foundation* is for people with a training background; true beginners are sent to the coached *Basecamp* class ([Gym Jones HQ](https://gymjones.com/headquarters/), [Foundation listing](https://marketplace.trainheroic.com/workout-plan/program/williams-program-1638632182)) | Refuse novices with that explanation |
| Starting Strength | Novice LP until session-to-session progress stops; intermediates move to weekly progression — Texas Method (volume, light, intensity day) or Heavy-Light-Medium ([Barbell Logic](https://barbell-logic.com/?p=4520), [Texas Method](https://fitnessvolt.com/strength-gains-texas-method/)) | Add an intermediate track; stop serving intermediates HLM inside novice LP |
| CrossFit | The template: three days on, one off; metabolic, gymnastic and weightlifting elements as singlets, couplets and triplets; time domains rotated ([CrossFit Journal template](https://library.crossfit.com/free/pdf/06_03_CF_Template.pdf)) | Needs a contract policy for *variation within declared families*, not fixed movements |
| BJJ | Mat time first; two or three strength sessions of 30–60 minutes on lighter mat days, scaled to how often the athlete rolls ([StrengthLog](https://www.strengthlog.com/strength-training-for-bjj/), [BJJEE](https://www.bjjee.com/articles/your-training-mix-how-to-find-your-optimum-bjj-training-strength-conditioning-weekly-ratio/)) | Protected mat sessions, S&C counted from them |
| ATG | Zero → Dense Strength → Standards, advancing by performance markers; the official markers are not public ([overview](https://exercisewithstyle.com/knees-over-toes-program/)) | Tracks with gates once markers are sourced |
| Kelly Starrett | 10–15 minutes of daily maintenance; a self-assessment of trunk, shoulders, hips and ankles drives the work ([Outside](https://www.outsideonline.com/health/training-performance/how-can-i-increase-my-training-and-stay-injury-free/)) | Assessment-driven selection; needs athlete input |
| Horsemen GPP | The audit's source errors stand (`data/horsemen/horsemen.pdf`) | Re-extract the source before deciding anything else |
| Wildman | Pentathlon rebuilt from kettlebell-sport practice (handoff, 2026-10-19) | Done; the handoff's review items remain |

Most of these are vendor or practitioner pages, not primary texts; where a primary
program is paid (Base Camp, ATG, Texas Method's book), only its public structure is
used and the track says it is an adaptation.

### The contract has to grow before it fits every package

Fixed modules fit Wildman, Starting Strength, Horsemen's named workouts and
Uphill's strength. The other methods need policies the compiler does not have yet:

| Policy | Needed by | Exists |
| --- | --- | --- |
| Fixed modules, spacing, refusal, verification | all | yes |
| Optional modules on free days | Pentathlon runs; BJJ open mats | yes (2026-10-19) |
| Load per confirmed exposure (add weight after a completed session) | Starting Strength novice, Horsemen strength | no — confirmed state exists, the model does not |
| Weekly ramp that restarts after a deload | Uphill base, Gym Jones | no |
| Protected external sessions (attendance, not exercises) | BJJ classes | no |
| Variation within declared families and time domains | CrossFit, Gym Jones, Filly conditioning | no |
| Assessment-gated selection and advancement | Kelly Starrett, ATG | no |

So "move every package to a contract" is right as a direction, but each package
waits for the policies it needs; the shared fixes below help all of them now.
