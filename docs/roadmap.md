# Roadmap

The single backlog for this project. Last verified against the code and the
production database on 2026-09-30; the information-architecture items were added
from the functionality review of 2026-10-01 (`information-architecture.md`).

This replaces the phased build roadmap (phases 0–8, all complete), and absorbs
`next_features.md` (March), `model-generalization-gaps.md` (April),
`programming-improvements.md` (April) and `ios/docs/phone-app-plan.md` (the
unbuilt four-tab iOS plan), all of which are deleted — their shipped items are
listed under *Done* below and their open items are ranked here. Three planning
documents remain because they carry rationale, not backlog:
`frontend-fix-plan.md` (design decisions, plus the *Explicitly not doing* table),
`program-history-release.md` (the release runbook) and
`information-architecture.md` (the target layout of both clients and why).

## How items are ranked

**Priority** is what it costs to leave the item alone:

- **P1** — wrong data, or a gap that lets wrong data in. Do next.
- **P2** — a feature or platform gap a user can see.
- **P3** — engine generality and authoring backlog. Nothing schedules it, nothing breaks.

**Complexity** is the size of the change, not the value: **S** under a day,
**M** a few days, **L** a week or more of mostly content work.

Within a priority band, cheaper items come first. The information-architecture
restructure of 2026-10-01 is complete on both clients (see *Done*); what it
deferred is under *Later*.

## Ranked backlog

| # | Item | Priority | Complexity | Area |
|---|------|----------|------------|------|
| 1 | Missing benchmark families | P2 | M | data |
| 2 | Exercise animations (Lottie + SVG CSS) | P2 | L | web / content |
| 3 | Finish moving cadence and load tables from Python into YAML | P3 | S | engine |
| 4 | Scope declares modalities nothing schedules | P3 | S | packages |
| 5 | Configurable back-to-back recovery relaxation | P3 | M | engine |
| 6 | Authoring API completeness | P3 | M | api / web |

---

### 1. Missing benchmark families — P2 · M

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

### 2. Exercise animations — P2 · L

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

### 3. Cadence and load tables still in Python — P3 · S

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

### 4. Scope declares modalities nothing schedules — P3 · S per package

Several packages declare `power` or `relative_strength` in `scope` with no
framework that prescribes them and no archetype that serves them.
`tools/check_provenance.py --coverage` lists each. Nothing schedules them, so
generation is unaffected; either author the archetype and a framework line, or
drop the modality from `scope`. One package per change.

### 5. Configurable back-to-back recovery relaxation — P3 · M

The scheduler's recovery rules forbid consecutive long days. Endurance build
phases want them — Uphill Athlete's weekend back-to-back is a defining feature
of the base phase. There is no framework or phase field to relax the rule; the
only knobs are `sessions_per_week` and `modality_priority`. Add a per-framework
`recovery` block (which modality pairs may sit on consecutive days, in which
phases), read it in `allocate_sessions`, and make Uphill's base and specific
phases use it. Verify with `check_styles.py` and by generating Uphill at five
and six days.

### 6. Authoring API completeness — P3 · M

Six authoring routes exist — `POST/PUT /api/exercises`, `POST/PUT
/api/archetypes`, `POST /api/modalities`, `PUT /api/frameworks/<id>` — and
since 2026-10-01 they require a signed-in user and `AUTHORING_ENABLED` (local
development gets both for free). None validates against `docs/schemas/`, and
there is no DELETE for any entity; packages are edited as YAML and validated
with `tools/validate_entities.py`. Since the per-package restructure this is a
reasonable steady state — a new package with its own `analytics.yaml` needs no
engine change. If in-app authoring (Dev Lab) is revived, the order from the
April analysis still holds: schema validation on the existing routes first,
then modality creation, then edit and delete for exercises and archetypes.

---

## Later

Larger items from the IA review. Each needs a backend step first; none is
scheduled ahead of the ranked list.

- **Phone session logging** — `PUT /health/sessions/<key>` and the `by-uid`
  writer exist; needs `session_uid` from `GET /programs/planned-sessions` for
  unambiguous keys; reuse the watch `SetLoggerSheetView` slot views. Then
  promote iOS Analytics ▸ Workouts to a Log tab.
- **Notifications** — local `UNUserNotificationCenter` scheduling from
  `WidgetDataStore` needs no backend (daily session, deload week, program
  complete); push would need a device-token table.
- **Apply adjustment** — `suggest_adjustments` (`src/progression_tracker.py`)
  emits `hold_load`, `reduce_volume_10pct`, `rebuild_habit`, `early_deload`,
  `increase_increment` and nothing applies them. Either `POST /api/programs/adjust`
  under the revision check, or map `early_deload` onto regenerate-from-week with
  `fatigue_state: overreached`.
- **Exercise-level swap** — `POST /sessions/generate` is session-level; needs
  `POST /api/exercises/substitute` over `selector.py` scoring.
- **iOS server-side analytics** — replace `AnalyticsEngine`'s local PMC with
  `/health/load/pmc` and add `/analytics/program`, or the two platforms disagree.
- **iOS FIT import through `POST /workouts/parse`** — gets server dedup and the
  matcher instead of a raw Supabase upsert.
- **`/settings` and a web Devices UI** — `GET /api/devices` exists; only when
  Profile's sub-tab row overflows.
- **iOS Library tab** — after a contextual exercise sheet exists and has content
  to promote; needs `GET /exercises/<id>/media`.

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

**Wrong-data and cheap P2 tranche (2026-10-01)**:

- *FIT dates are the athlete's day.* `fit_import.local_date` reads the FIT
  activity message's `local_timestamp − timestamp`, else the profile's new
  `timezone` key, else UTC; the Garmin webhook passes
  `startTimeOffsetInSeconds`; Strava uses `start_date_local` on the server
  and in the browser parser. `startTime` and the deterministic id stay UTC.
  `test_fit_import.py` pins it. Profile ▸ Athlete sets the zone (one click
  for the browser's); iOS fills it from the device when unset.
- *iOS interactive design steps 4 and 6*: `AppRefresh.perform` carries the
  pull-to-refresh contract (light haptic, 600 ms minimum, success haptic) for
  all seven sites; zero `ForEach(id: \.offset)` remain, with layout animation
  where rows change with data.
- *FIX-5*: `EmptyState` gained a `compact` size; the six chart zero-data views,
  Analytics ▸ Load's period empty state and Recovery's sleep card use it, with
  an Import action where one resolves the state. The slot-sized day cell,
  decorative dashed outlines and informational "not configured" cards stay, as
  the fix plan sanctions. Eight orphan components deleted.
- *FIX-6*: every cursor fill, the "all philosophies" radar reference series
  and the ontology graph labels read tokens; marks are untouched.
- *Female benchmark standards*: `GET /api/benchmarks?sex=`; the web hook
  queries it from the profile's sex (bundled male JSON as the offline
  fallback) and Benchmarks says which tables it shows; iOS has a Sex picker
  and passes it. Multi-standard WODs and the other families are item 1.

**Information-architecture restructure (2026-10-01)** — the layout in
`information-architecture.md`, on both clients:

- *Web*: grouped sidebar (Train / Insight / Library / You / Dev); the builder is
  the flow `/program/new`; Log (`pages/Log.tsx`: Workouts with filters ·
  Suggestions; Import as a sheet through `api/workouts.ts`, no hand-made auth
  header, no manual start-date field); Analytics is Program · Progress · Load ·
  Recovery with URL tabs (Bio Log folded into Recovery, the Dashboard's
  Progress tab moved, Activity and Overview folded into Load); Home has no
  sub-tabs and a compact `ProgressionWidget`; Program has Calendar · Overview ·
  History tabs with "New program", the priority mix beside the phases and
  methodology / standards links into Explore; Explore has a Standards topic,
  "Build with this" on every philosophy (`components/explore/PhilosophyPanel.tsx`)
  and framework (`builderStore.prefillFrom…`), and resolves exercise deep links
  from a session row's "Open in Explore"; Profile has an Athlete tab (level,
  date of birth, sex, bodyweight, account) and the API a writable `sex` key.
  Old paths redirect (`LegacyRedirect`), unknown paths get a 404 page. One
  `SessionPanel` serves the session page and the Home side panel; one
  `WorkoutRow` serves every workout list; `lib/sessionKeys.ts` is the only
  session-key parser; `ExerciseCatalog`, `Philosophies`, `BioLog`,
  `WorkoutImport`, `ProgramHistory` (page), `ExerciseSearch`, `ExerciseDrawer`,
  `PhaseTimeline` and `VolumeBar` are deleted.
- *iOS*: four tabs (Today · Program · Analytics · Profile); the Sync tab
  dissolved into Settings pushed from Profile (`Views/SettingsView.swift`), its
  hidden `resetProgramStartToToday` mutation deleted; Profile ▸ Athlete (level,
  DOB, bodyweight, editable HR zones); Analytics ▸ Progress hosts the
  progression review; Today has a Suggestions card (`GET /health/matches/
  suggestions`, dismiss, review through `WorkoutDetailView`) and a "Generate a
  Program" empty-state button; `ContentView` routes through
  `router.show(.dashboard)`. Defects fixed: settings-sheet init, debounced
  notes, fatigue 1–5, stable sheet identity, check-in notes sent, undo-complete
  through the new `DELETE /api/health/sessions/<key>/completion`, and a visible
  banner on a 409 `stale_revision`. Dead code deleted: `LogView.swift`,
  `DevicesView.swift`, `SyncStatusView.swift`, `ProgramStore.swift`, the stale
  `ios/TrainingCompanionWatch/` folder, and the watch's unreferenced
  `SettingsView` / `SessionOverviewView`.
- *Docs*: `frontend-design.md` §13.2 / §17.8 / §17.9, `ios/docs/design-system.md`
  §6.13, `ios/README.md` rewritten, `CLAUDE.md` updated.

**Functionality & IA review, P1 tranche (2026-10-01)** — the five findings
that were wrong data or let wrong data in, from `information-architecture.md`:

- The iOS builder could not generate a program: step 1 fetched `GET /api/goals`,
  removed on 2026-04-25 (`d079ace`), so the grid never populated and Next stayed
  disabled — for five months. It now picks a methodology from
  `GET /api/philosophies` with a detail sheet per card; the settings sheet's
  picker, the Today header's goal name and `GenerateProgramRequest.philosophyId`
  follow. The settings sheet also got its title and Cancel button, which were
  attached to the `NavigationStack` instead of its content and never rendered.
- iOS PRs were silently lost: Benchmarks appended to `profile.performanceLogs`
  and sent it with the profile, whose server whitelist drops the key. They go
  through `POST /api/health/performance` now, then re-read the series.
- The web could not log rounds, minutes or kilometres: `OutcomeLogger` was
  written in `2e84772` and never mounted. `ExerciseRow` dispatches on
  `slot_type` through `lib/outcomeFields.ts`; `ExerciseRow.test.tsx` pins it.
- Server match suggestions (Garmin webhook, iOS relay) were written and shown
  nowhere. `HealthDataProvider` merges `GET /api/health/matches/suggestions`
  into `bioStore.pendingMatches`; a Home card and an Import ▸ Suggestions tab
  (`SuggestionRow`) let the athlete review or dismiss; `lib/sessionKeys.ts` and
  `lib/activityType.ts` are the first shared helpers of item 12.
- Six unauthenticated YAML-writing authoring routes and a Dev Lab in end-user
  navigation: the routes require `require_auth` + `AUTHORING_ENABLED`
  (`_authoring_enabled()` in `api.py`); Dev Lab's route and nav entry exist only
  in dev builds (`src/lib/featureFlags.ts`, `VITE_DEVLAB=1` to opt a production
  build in).

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

**From `ios/docs/phone-app-plan.md`**: the Today, Program and Profile tabs,
`SessionDetailView` shared between Today and Program, the builder sheet, the
bio check-in, pull-to-refresh and background refresh, and the Apple Health
relay. Its Library tab, phone session logging and notifications are under
*Later*; its four-tab structure is superseded by `information-architecture.md`.

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

**Dependabot**: the 64 open alerts on 2026-09-30 (29 high) were all in
`frontend/package-lock.json`, sixteen packages, every one fixable inside the
ranges `package.json` already declared. Cleared by a lockfile-only update;
`npm audit` reports zero. Of the runtime-scoped ones, only React Router's
open redirect through a backslash in `<Link>` and `useNavigate` was reachable
from a browser SPA; `ws`, `form-data` and `follow-redirects` are the Node
adapters of Supabase and axios and never ship in the bundle.

**Program history**: migrations 005 and 006 applied to production; archiving on
read and write; the union matcher index; `session_uid` on every match writer.
The backfill was run in dry-run mode against production on 2026-09-30 and
attributed nothing, correctly: all 46 matches and 46 logs belong to one athlete
and are dated 2026-03-29 to 2026-06-10, while that athlete's only surviving
program starts 2026-09-21. The blocks they belonged to were overwritten before
history existed and are unrecoverable; the script refuses to fabricate them. Those
rows keep working through the legacy key path, and `need merging` is 0, so 006
being applied first cost nothing. Nothing further to do.
