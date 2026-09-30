# Roadmap

The single backlog for this project. Last verified against the code and the
production database on 2026-09-30.

This replaces the phased build roadmap (phases 0–8, all complete), and absorbs
`next_features.md` (March), `model-generalization-gaps.md` (April) and
`programming-improvements.md` (April), all of which are deleted — their shipped
items are listed under *Done* below and their open items are ranked here. Two
planning documents remain because they carry rationale, not backlog:
`frontend-fix-plan.md` (design decisions, plus the *Explicitly not doing* table)
and `program-history-release.md` (the release runbook).

## How items are ranked

**Priority** is what it costs to leave the item alone:

- **P1** — wrong data, or a gap that lets wrong data in. Do next.
- **P2** — a feature or platform gap a user can see.
- **P3** — engine generality and authoring backlog. Nothing schedules it, nothing breaks.

**Complexity** is the size of the change, not the value: **S** under a day,
**M** a few days, **L** a week or more of mostly content work.

Within a priority band, cheaper items come first.

## Ranked backlog

| # | Item | Priority | Complexity | Area |
|---|------|----------|------------|------|
| 1 | FIT import dates workouts from UTC; no user timezone | P1 | M | import |
| 2 | iOS interactive design: refreshable min-time and stable ForEach ids | P2 | S | ios |
| 3 | Twenty hand-rolled empty states bypass `EmptyState` (FIX-5) | P2 | S | web |
| 4 | Chart chrome partially hardcoded (FIX-6) | P2 | S | web |
| 5 | Female benchmark values served, never shown | P2 | S–M | web / api |
| 6 | Missing benchmark families | P2 | M | data |
| 7 | Exercise animations (Lottie + SVG CSS) | P2 | L | web / content |
| 8 | Finish moving cadence and load tables from Python into YAML | P3 | S | engine |
| 9 | Scope declares modalities nothing schedules | P3 | S | packages |
| 10 | Configurable back-to-back recovery relaxation | P3 | M | engine |
| 11 | Authoring API completeness | P3 | M | api / web |

---

### 1. FIT import dates workouts from UTC; no user timezone — P1 · M

`src/fit_import.py` takes the session `start_time` as a UTC-naive datetime and
derives the workout's date from it, so an evening workout west of Greenwich is
dated a day late. No source stores a user timezone. `resolve_session` has a
±1-day widening used only when displaying an existing match, never for scoring,
because the matcher's golden fixtures pin that behaviour.

Do: read the FIT `activity` message's `local_timestamp` where present and
derive the date from it; add a `timezone` field to the profile blob for the
other sources (Strava and Apple Health carry their own offsets; Garmin's
summary carries `startTimeOffsetInSeconds`). Any change to the date a workout
carries must keep `test_workout_matcher.py` and the vitest half green — change
`data/matcher_fixtures.json` deliberately if the contract moves.

### 2. iOS interactive design, remaining steps — P2 · S

Of the six steps in the interactive design plan, steps 1, 2, 3 and 5 shipped:
named `AppAnimation` springs, velocity-aware swipe commit, `AppHaptics` in 14
files, `appTabStyle()` on every tab root. Two remain:

- **Step 4** — `.refreshable` with a light haptic on trigger, a 600 ms minimum
  display time so the spinner does not flash, and a success haptic on
  completion. No call site has the minimum-time pattern yet.
- **Step 6** — seven `ForEach(... id: \.offset)` sites remain. Offset identity
  makes SwiftUI recreate rows instead of animating them. Use the day name,
  session key or phase as the id, and add `.animation(AppAnimation.layoutChange,
  value:)` where the layout changes with data.

Per `CLAUDE.md`, each change ends in the simulator with a screenshot.

### 3. Hand-rolled empty states (FIX-5) — P2 · S

Eight screens use the shared `EmptyState` component; twenty more render their
own "No … yet" markup. Real UX cost: the hand-rolled ones lack the icon, the
action slot and the consistent spacing. Sweep and convert. Rationale and
the component contract are in `frontend-fix-plan.md` under FIX-5.

### 4. Chart chrome partially hardcoded (FIX-6) — P2 · S

Marks (bars, lines, cells) are correctly hardcoded to a §8 colour system. Some
chrome — axis ticks, grid lines, tooltip surface, cursor fill, reference
lines — is still a hex literal and reads wrong in the Military and Zen themes.
The token table is under FIX-6 in `frontend-fix-plan.md`. Opportunistic: do it
when touching a chart. `WorkoutAnalytics.tsx` defines series colours inline; new
series there should read `MODALITY_COLORS` or `ZONE_COLORS`.

### 5. Female benchmark values served, never shown — P2 · S–M

`_all_benchmarks()` in `api.py` now carries the female values and the metric
metadata; `ProfileBenchmarks.tsx` has no sex toggle and never reads them. Add
the toggle, read the athlete's sex from the profile as the default, and pass the
logged value to each `LevelBar` (the `userValue` prop exists and is never
passed).

### 6. Missing benchmark families — P2 · M

Three files exist under `data/benchmarks/`: strength, conditioning and the
Cell standards. Families referenced in the packages with no data behind them:

| Family | Contents |
|---|---|
| Kettlebell pentathlon | Wildman five-lift scoring (snatch, clean and jerk, press, squat, pull) |
| Ruck standards | SFAS pace (40 lb / 12 mi / sub-3 h), Horsemen PT Tests I and II |
| CrossFit benchmark WODs | Girls (Fran, Grace, Helen, Diane, Isabel, Annie, Elizabeth) and Heroes (Murph, Cindy, DT) |
| Movement and skill | Turkish get-up standard, handstand hold |

Each is a YAML file in the existing list-of-objects schema plus one entry in the
`_all_benchmarks()` loop and, for WODs, a `benchmark_wod` category. Content
work; the sources are in `data/` and `docs/extracted/`.

### 7. Exercise animations — P2 · L

Every exercise has a description, cue points and a muscle diagram; 79 have a
GIF sourced from free-exercise-db; the rest are `animation.type: none`.
`ExerciseAnimationPanel` already dispatches on `gif | lottie | svg_css | none`,
so what remains is content and one dependency:

1. `npm install @lottiefiles/dotlottie-react` and swap the placeholder branch
   for `<DotLottieReact src=… loop autoplay />`.
2. Lottie files at `frontend/public/animations/lottie/{exercise_id}.lottie`, in
   priority order: Kelly Starrett's top twenty mobility movements, Wildman
   kettlebell ballistics, Ido Portal locomotion (custom, After Effects or Rive).
3. SVG CSS loops at `frontend/public/animations/svg/` for the bridge and
   handstand progressions and the rehab movements with no Lottie match.
4. Point each package's `exercise_media.yaml` entry at the file.

Acceptance: Lottie renders in the drawer; ten Starrett movements, the two core
KB ballistics and five Portal locomotion patterns animate; `type: none` still
shows the category placeholder.

### 8. Cadence and load tables still in Python — P3 · S

Two of the three "knowledge in code" tables identified in April are half
migrated:

- `_CADENCE_OPTIONS` in `scheduler.py`: the framework yaml's `cadence_options`
  is read first and the Python dict is the fallback. Move the remaining entries
  into their frameworks, delete the dict.
- `_STARTING_LOADS` and `_LINEAR_INCREMENTS` in `progression.py`: the exercise
  yaml's `starting_load_kg` and `weekly_increment_kg` are read first and the
  dicts are the fallback. Same treatment; the schema already has the fields.

The third table, movement-pattern aliases, is done: `selector.py` loads
`data/commons/movement_patterns.yaml`.

### 9. Scope declares modalities nothing schedules — P3 · S per package

Several packages declare `power` or `relative_strength` in `scope` with no
framework that prescribes them and no archetype that serves them.
`tools/check_provenance.py --coverage` lists each. Nothing schedules them, so
generation is unaffected; either author the archetype and a framework line, or
drop the modality from `scope`. One package per change.

### 10. Configurable back-to-back recovery relaxation — P3 · M

The scheduler's recovery rules forbid consecutive long days. Endurance build
phases want them — Uphill Athlete's weekend back-to-back is a defining feature
of the base phase. There is no framework or phase field to relax the rule; the
only knobs are `sessions_per_week` and `modality_priority`. Add a per-framework
`recovery` block (which modality pairs may sit on consecutive days, in which
phases), read it in `allocate_sessions`, and make Uphill's base and specific
phases use it. Verify with `check_styles.py` and by generating Uphill at five
and six days.

### 11. Authoring API completeness — P3 · M

There are no POST, PUT or DELETE routes for any entity: packages are edited as
YAML and validated with `tools/validate_entities.py`. Since the per-package
restructure this is a reasonable steady state — a new package with its own
`analytics.yaml` needs no engine change. If in-app authoring (DevLab) is
revived, the order from the April analysis still holds: modality creation
first, then goal creation, then edit and delete for exercises and archetypes,
each behind the same schema validation the CLI uses.

---

## Parked

Enhancements noted as real opportunities but not gaps against the current spec.
Track here so they are not lost; do not schedule ahead of anything above.

- Container queries for the card grids; `layoutId` shared-element transitions;
  list virtualization for the exercise catalog; `color-mix()` for the alpha
  variants now hand-authored per theme.
- Multiple event dates in a blended program: the primary goal's periodization
  should suppress the secondary's peak and taper. Today the nearest event
  governs and the rest is background.
- Per-phase weight adjustment for blended philosophies.
- Custom injury `side` is stored but applied symmetrically; `severity` does not
  yet force a phase.

## Explicitly not doing

Decided and closed; do not re-open without a defect motivating it. The
reasoning for each is in `frontend-fix-plan.md`.

- Changing modality or phase hex values (mirrored by hand into two Swift files).
- Making Dashboard drop its tab header; converting Explore's wrapped header to
  one row; splitting the two-row headers on ExerciseCatalog and ProgramView.
- Unifying HR-zone colours with modality colours (different semantic axes).
- Conditional loading of theme web fonts (FIX-9, left as-is).

## Done

Shipped items from the absorbed documents, so nobody re-plans them.

**Build phases 0–8** (original roadmap): source extraction, schemas, data
population, logic design, MVP generator, validation, KB-only strength
archetypes, exercise variety scoring, methodology review, phase automation from
an event date.

**From `next_features.md`**: multi-goal blending (`philosophy_ids` with
weights); granular equipment picker (grouped checkboxes, profile quick-picks);
carries filter and week-navigation bugs; `ProgramOverview` with phase prose and
volume progression; custom injury flags merged at the API boundary; the
Philosophies page, since grown into the Explore tab; Cell standards exposed.

**From `model-generalization-gaps.md`**: modality drop-in via YAML; exercise
`starting_load_kg` and `weekly_increment_kg`; movement-pattern aliases in
`data/commons/movement_patterns.yaml`; the philosophy endpoint and analytics
spec description.

**From `programming-improvements.md`**: phase-aware `sessions_per_week` (each
Uphill phase is its own framework); archetype leakage across methodologies
(solved structurally by package provenance, `self_contained: true` on all 11);
long-run differentiation (`long_zone_2`, `long_mountain_day`); framework and
goal modality alignment (`check_provenance.py --coverage`).

**From `frontend-fix-plan.md`**: FIX-1 (WCAG AA light-mode text, with a
contrast regression guard in CI), FIX-2 (reduced motion), FIX-3 (theme-aware
basemap), FIX-4 (one HR-zone colour source), FIX-7 (page transitions), FIX-8
(accessible names on icon buttons).

**iOS tests**: `TrainingCompanionTests` is a real unit-test target as of
2026-09-30, hosted by the app, backed by a synchronized folder so new test
files need no project edit, and wired into the shared scheme's test action.
`ios/run_tests.sh` runs it; all 22 tests pass. Two of the three pre-existing
files had drifted: `UserProgramSavePayload` had gained `baseRevision`, and every
test that let an `AppState` go out of scope from a synchronous test method
aborted in the Swift runtime's isolated-deinit path (Xcode 26.2). Those tests
are `async` now, with the reason in the file.

**Watch and iOS**: the full watch bio and GPS pipeline — `CLLocationManager`
and `HKWorkoutRouteBuilder` on the watch, HR sample arrays, per-set
`startOffset`, `transferFile` for large payloads, `exercise_timeline` on the
server; watch modality colours match `modalityColors.ts`; program history on
the Program tab; `AppAnimation`, `AppHaptics`, `AppMetrics`, `appTabStyle()`,
`AppSubTabs`.

**Program history**: migrations 005 and 006 applied to production; archiving on
read and write; the union matcher index; `session_uid` on every match writer.
The backfill was run in dry-run mode against production on 2026-09-30 and
attributed nothing, correctly: all 46 matches and 46 logs belong to one athlete
and are dated 2026-03-29 to 2026-06-10, while that athlete's only surviving
program starts 2026-09-21. The blocks they belonged to were overwritten before
history existed and are unrecoverable; the script refuses to fabricate them. Those
rows keep working through the legacy key path, and `need merging` is 0, so 006
being applied first cost nothing. Nothing further to do.
