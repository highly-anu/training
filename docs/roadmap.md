# Roadmap

The single backlog for this project. Last verified against the code and the
production database on 2026-09-30; the information-architecture items were added
from the functionality review of 2026-10-01 (`information-architecture.md`).
The Garmin items (1, 2 and 4) were added on 2026-10-05 from the Connect IQ
connection plan, after a read-only look at production.

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
| 1 | Connect IQ pairing-flow defects | P2 | S | watch, web |
| 2 | Garmin wellness via Connect IQ | P2 | L | watch, API, web, iOS |
| 3 | Exercise animation content (Lottie and SVG CSS files) | P2 | L | content |
| 4 | On-demand HRV capture on the watch | P3 | M | watch, API |

---

### 1. Connect IQ pairing-flow defects — P2 · S

Found while planning the Garmin wellness connection (2026-10-05). None of them
needs the watch to run anything new.

1. **The pairing QR is a dead link.** `Config.pairQrValue`
   (`garmin/TrainingCompanionCIQ/source/Config.mc:50-56`) encodes
   `<webBaseUrl>/pair?code=…`, but the web app has no `/pair` route (`App.tsx`
   falls through to `NotFound`), and `ProtectedRoute` → `/login` →
   `navigate('/')` (`LoginPage.tsx:23`) discards any return path, so a scanned
   link could not finish even with the route. `webBaseUrl` defaults to empty, so
   today the QR carries the bare code and only the typed-code path works
   (Settings ▸ Connections ▸ Devices). Either add `/pair` (read `?code=`,
   survive sign-in, claim) or drop the link and encode the bare code on
   purpose. The production web origin lives only in the `FRONTEND_URL` Fly
   secret, so a default would have to be written down.
2. **Every watch pairs as "Garmin Fenix 9"** (`SyncManager.mc:64`). Send
   `System.getDeviceSettings().partNumber` with `POST /devices/pair` and let the
   server name the model (item 2's `data/garmin_devices.json` is the lookup).
3. **The manifest lists two products** (`fenix943mm`, `fenix947mm`,
   `manifest.xml:21-24`); the SDK defines seven fēnix 9 products (`fenix943mm`,
   `fenix947mm`, `fenix9pro43mm`, `fenix9pro47mm`, `fenix9pro51mm`,
   `fenix9prosolar47mm`, `fenix9prosolar51mm`) and which watch the athlete wears
   is recorded nowhere. Add the real model's id and compile it
   (`DEVICE=<id> ./build.sh --device`).

The Devices card's Revoke button sends back the truncated token the list shows
and always 404s; that is fixed with the token-scope work in item 2, slice 2.

Acceptance: scanning the watch's QR with a phone signs in if needed and claims
the code (or the QR is the bare code and says so); the Devices card shows the
model's name; every manifest product compiles.

---

### 2. Garmin wellness via Connect IQ — P2 · L

Garmin's official Developer Program is enterprise-only (personal applications
are rejected, onboarding is paused), so the built but dormant code for it
(`src/garmin_connect.py`, `src/garmin_worker.py`, `migrations/004_garmin.sql`)
stays off. The open route is the Connect IQ SDK the watch app already uses: it
can read **resting HR, Body Battery history and recovery time** on the wrist
and post them with the paired `ciqdev_` token. It cannot read nightly HRV,
sleep or training readiness, so this does **not** close the HRV gap — HRV is 35
of readiness's 100 points and September has it on 6 of 25 days — and the Apple
Health relay keeps carrying those.

Decisions:

- A new `daily_wellness` side table (`migrations/009_wellness.sql`), not
  `daily_bio`: `upsert_daily_bio` overwrites a day wholesale and swallows every
  exception, so a watch post would wipe Apple's sleep and HRV for that date. No
  HRV columns in v1.
- Readiness scores resting HR from **one series**, never mixed across sources
  or methods (`src/wellness.merge_for_scoring`: the series with the most
  readings wins, ties go to `daily_bio`). Body Battery and recovery time are
  display-only, there are no new flags, the scoring functions are untouched,
  and the response gains `sources` saying where each component's data came from.
- The device token is scoped before the endpoint ships: today a claimed token
  is accepted on every authenticated route.
- A hardware spike gates every watch-side slice. The simulator fabricates
  `SensorHistory` and profile values, and the app has never run on a watch.

Slices. Each reverts alone. Merging to `master` deploys the API, so the
migration runs on production first, after `scripts/backup_prod.sh`.

0. `garmin/WellnessSpike/` — a throwaway app (own app id) that logs every
   candidate signal from the foreground and from a 15-minute background event
   into on-watch Storage. Its README is the checklist for five mornings: is
   `restingHeartRate` a daily value or a static setting; do `SensorHistory` and
   `ActivityMonitor` reads work from the background, within memory; is
   `timeToRecovery` non-null; does the event fire with the app closed and
   `makeWebRequest` finish inside 30 s; what is `wakeTime`; which `<iq:product>`
   the watch needs. **Gate 1**, the athlete's, about five minutes a day.
1. The migration, `src/wellness.py` (`validate`, `merge_for_scoring`) and
   `test_wellness.py`. The SQL suite makes its own throwaway database, not
   `training_test`.
2. A device-token allowlist (the four routes the watch calls today plus the new
   one, everything else 403) and the Revoke fix (the list shows a 14-character
   prefix and revoke deletes by the full token); a test enumerates every
   protected route.
3. `POST /api/health/wellness` (gated by the Garmin integration toggle,
   validated, idempotent, 503 on a failed write so the watch retries),
   `wellness_store.py`, one `_bio_for_scoring` loader at the four scoring sites,
   and the program-analytics digest hashing merged values (it hashes only bio
   *dates* today, so a changed same-date value never busts the cache).
4. `GET /api/health/wellness/latest`, `data/garmin_devices.json` (part number to
   model), a Devices-card line and a readiness footnote on web and iOS.
5. Watch: foreground-on-open sync; delete the dead `PUT /health/bio/{date}`
   chain (`SyncManager.mc:185-192`) and the TODO at `WorkoutController.mc:807`.
   **Gate 2** — a week of rows matching Connect's numbers.
6. Watch: the background service, a morning window (wake time + 30 min to + 6 h)
   and a once-a-day marker. **Gate 3** — at least 6 of 7 mornings sent without
   opening the app.

Kill criteria from the spike: the event never fires with the app closed → slice
5 only; `restingHeartRate` static and the `hr_min_8h` fallback implausible →
display-only, no readiness merge; both histories empty on the athlete's model →
stop and record it here.

Not in this item: switching on the Garmin Developer Program code (needs
approval); Strava, the other open API, which carries activities only — an
optional step that needs no code (`STRAVA_*` Fly secrets, then connect under
Settings ▸ Connections; whether its GPS survives the dedup merge into the
HR-only canonical row is unchecked); unofficial scrapers (terms of service, and
Garmin blocks datacentre IPs).

Acceptance: a morning snapshot reaches `daily_wellness` from the watch and the
Devices card shows when and what; readiness names the source of its resting HR
and is identical to today's when no wellness rows exist; a leaked device token
can call only the five routes.

---

### 3. Exercise animation content — P2 · L

Every exercise has a description, cue points and a muscle diagram; 79 have a
GIF sourced from free-exercise-db; the rest are `animation.type: none`.
The code half shipped on 2026-10-01: `@lottiefiles/dotlottie-react` is
installed and `ExerciseAnimationPanel` renders `<DotLottieReact>` for
`type: lottie`. What remains is content:

1. Lottie files at `frontend/public/animations/lottie/{exercise_id}.lottie`, in
   priority order: Kelly Starrett's top twenty mobility movements, Wildman
   kettlebell ballistics, Ido Portal locomotion (custom, After Effects or Rive).
2. SVG CSS loops at `frontend/public/animations/svg/` for the bridge and
   handstand progressions and the rehab movements with no Lottie match.
3. Point each package's `exercise_media.yaml` entry at the file.

Acceptance: Lottie renders in the drawer; ten Starrett movements, the two core
KB ballistics and five Portal locomotion patterns animate; `type: none` still
shows the category placeholder.

---

### 4. On-demand HRV capture on the watch — P3 · M

The open SDK has no nightly HRV, but `Toybox.Sensor.HeartRateData` (API 3.0.0,
through `Sensor.registerSensorDataListener`, needs the `Sensor` permission)
delivers beat-to-beat intervals. The app could take a short seated capture on
demand — a couple of minutes each morning — and compute RMSSD. That is a
*different measurement* from Apple Health's SDNN and from Garmin's overnight
value, so it gets its own `hrv_ms` / `hrv_method` columns (added to
`daily_wellness` additively) and its own baseline series; item 2's series rule
already treats `(source, method)` as a series identity, so methods are never
mixed in one baseline.

1. The `Sensor` permission and a capture view: start, progress, a motion and
   quality check, and a discarded window when too few intervals are clean.
2. `hrv_ms` / `hrv_method` through `validate`, the store and
   `merge_for_scoring`; `sources.hrv` names the series.
3. The readiness HRV component scores the watch series once it has the three
   readings in 14 days that `_score_hrv` already needs.

Needs item 2's slices 1–3 first. Acceptance: a capture reaches `daily_wellness`
with its method, readiness scores it from its own baseline and says so, and
Apple's SDNN series is untouched.

---

## Later

Larger items from the IA review. Each needs a backend step first; none is
scheduled ahead of the ranked list.

- **Push notifications** — local session reminders exist
  (`NotificationManager`); push would need a device-token table and a sender.
- **iOS Library tab** — the contextual exercise sheet exists
  (`ExerciseDetailSheet`, design-system §6.14); a tab only once there is
  content to browse rather than look up.

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

**Session logs (2026-10-04)**: production's `session_logs` never had
`exercise_timeline`, the column `health_store.upsert_session_log` has inserted
since 2026-04-04, so once that writer was live there its INSERT died on
`UndefinedColumn` and the swallowed error meant it stored no log at all, while
the PUT routes answered `{saved: ...}`. That was every completion, set log,
note and watch timeline either client sent through the server. The last `web`
or `manual` log in production is dated 2026-04-07; every later row, to
2026-06-10, is a `fit_file` or `watch` one — the sources the phone's own
PostgREST upserts wrote, which never named the column (`d38e401` removed them
on 2026-10-01). The column was added by hand after `scripts/backup_prod.sh`
(additive; the 46 rows untouched); `migrations/008_session_log_timeline.sql`
records it, `health_store._ensure_timeline_column` adds it on first use for any
deployment that is behind, and `test_program_history_sql.py` now builds its
`session_logs` without the column, which is why it had stayed green. Logs sent
while the column was missing are not on the server, and neither client keeps
one it could not save (both hold them in memory and replace them from the
server on load), so they have to be entered again.

**Match writes, and the Uphill replica (2026-10-02)**: `health_store.upsert_match`'s
stub insert violated `workouts.start_time NOT NULL` before Postgres ever
reached its `ON CONFLICT DO NOTHING`, and the swallowed error meant no match
was written in production from 2026-06-10 on — auto-matches on import and
confirms from both clients alike (suggestions, written without a stub, kept
working). Fixed, with `test_dedupe_sql.py` writing a match against the
production-shaped schema. The spring Uphill program, overwritten before
history existed, was reconstructed from the late-April generator and
recorded as a replica block (`source = 'replica'`, 2026-04-27 → 2026-09-20):
33 of its 35 surviving matches and 32 of 33 logs attributed, 6 later
workouts auto-matched, 30 queued as suggestions. The development document
now treats `effectiveTo` as the exclusive end it is.

**Workout metrics cache (2026-10-02)**: the readiness TSB component, the PMC,
the weekly load, the progression routes and the program analytics all read
every workout with its GPS track and HR series; with a year of watch
activities that was a 327 MB peak on a 256 MB worker, an OOM kill per Home
open, and a "CORS error" in the browser (Fly's proxy answers for the dead
worker without headers). `workouts.metrics` (migration 007) caches each
row's zone minutes and TRIMP per max HR and zone version;
`api._workouts_for_load` fills it a few rows per request from the HR series
alone; the program analytics read series only for matches inside the
program's span. Peak is 93 MB on the same data. `test_workout_metrics.py`.

**Development across programs (2026-10-01)**:

- *Server*: `GET /api/analytics/development` (`src/analytics/development.py`,
  pure over its inputs, cached in `progression_snapshots` on a digest of the
  activations, logs, matches, workouts and PRs it read; last 365 days by
  default, `from`/`to` optional). `blocks` is the activation timeline with
  each block's planned and completed sessions and completion %; `lifts` and
  `currencies` are every logged series across the whole span, each point
  keyed to its block through `session_uid`, with per-block first / last /
  best / Δ and a trend over non-deload points; `load` is weekly TRIMP with
  the week's block; `benchmarks` the level ladder per PR date.
  `test_development_analytics.py` runs it on a throwaway two-block history.
- *Web*: Analytics ▸ Development (`components/analytics/DevelopmentTab.tsx`,
  `lib/developmentShaping.ts` with its test): the block strip and cards, lifts
  across blocks with a picker, block bands (`ReferenceArea`) and the per-block
  table, weekly TRIMP coloured by block, standards over time; one block says
  so and points at Progress. Home's Development card links to it.
- *iOS*: Analytics ▸ Blocks (`Views/AnalyticsDevelopmentTab.swift`,
  `DevelopmentModels.swift`, Swift Charts) — the same document; "Blocks"
  because five segments truncate "Development" (design-system §6.20).
  `DevelopmentCodableTests` decodes a real response with a malformed lift.
- *Also*: `GET /health/sessions/recent` names each log from the
  `planned_sessions` row its `session_uid` resolves to, and the phone's
  Log ▸ Sessions shows earlier programs' logs by name — a planned date before
  the current program's start overrides a legacy key that resolves to the
  wrong session (`LogSessionsTests`).

**Follow-up tranche (2026-10-01)**:

- *Partial regenerates continue the numbering*: `POST /programs/generate`
  takes `week_in_program`, the `week_number` of the first generated week;
  `generator._build_phase_entries` numbers from it (the event-date schedule,
  which carries absolute weeks, is untouched). The web's three partial
  regenerates (injuries sheet, "from tomorrow onwards", the profile offer)
  and the phone's pass the kept head's length + 1, so a 4-week plan rebuilt
  from week 2 reads 1, 2, 3, 4 instead of 1, 1, 2, 3, and session keys stay
  unique. `test_week_numbering.py` and the client request tests pin it.
- *iOS Log tab*: the third tab, `LogView` — Workouts (the list that was
  Analytics ▸ Workouts, with the `.fit` importer), Suggestions (the full
  inbox, `SuggestionRowView` with Accept, Review and Dismiss, shared with
  Today's card) and Sessions (`LogSessions.rows`: what was logged against
  planned sessions, newest first, one line per exercise with content; a row
  that resolves opens the session). Analytics keeps Program · Overview ·
  Progress · Recovery. `router.showLog(_:)` and `trainingcompanion://log?section=…`.
  `LogSessionsTests` pins the ordering, the wording and the server's
  timestamp forms.
- *Web Settings page*: `/settings` (Connections · Account · Appearance ·
  Developer in dev builds), URL-driven like the phone's Settings screen.
  Connections (integration toggles, Garmin and Strava accounts, devices) and
  the account switcher and sign-out moved there from Profile, which keeps
  the athlete: six tabs again. The OAuth landing URL names Settings, and
  `/profile?tab=connections` redirects with its query intact. The theme list
  is one export (`THEMES`) shared by the sidebar toggle and
  Settings ▸ Appearance. `settings.test.tsx` pins the tabs and the redirect.
- *"About this methodology" on the phone*: Program ▸ Current shows the
  methodology the plan was generated from under the phase bar (a menu for a
  blend) and opens `PhilosophyDetailSheet` — extracted from the builder, where
  it was private, into its own file so the program can explain itself
  (design-system §6.18). `AppState.programMethodologies()` maps the envelope's
  source ids to catalog cards, skipping the `_blended` marker.
- *Regenerate from this week after a profile change*: both clients compare
  the profile (level, equipment, days per week from the schedule, injuries)
  with the active program's stored constraints — `lib/programConstraintsDiff.ts`
  and `ProgramConstraintsDiff.swift`, the same rules — and offer "Regenerate
  from week N" on the profile tabs that feed constraints (and, on the phone,
  in the Program settings sheet beside the full regenerate). The web goes
  through `useRegenerateFromWeek`; the phone gets `APIClient.generateProgramPreview`
  (generate without persisting), `Regeneration.splice` (kept head + new tail,
  the tail's goal/constraints/validation/coverage report, volume summary left
  to the server) and `AppState.regenerateFromCurrentWeek`, saved through the
  revision-checked PUT. `GenerateProgramRequest` now speaks blends
  (`philosophy_ids` + weights) and `periodization_week`. Until now the web
  offered this for injuries only and the phone only a full regenerate.
- *Phone session logging*: `ExerciseLogSheet` on every session row (leading
  swipe or context menu) — sets for sets × reps and hold slots, the slot's
  currency for the rest, through `SessionLogging` (the web's outcome-field
  table) and `AppState.logExercise` → `PUT /health/sessions/<key>` with
  `{exercises: {<id>: …}}`; the server merges per exercise, so no
  planned-sessions step was needed (it resolves the version id from the key
  itself). `GET /health/sessions/recent` now carries `exercises`;
  `ExercisePerformanceLog` is the web's shape. `trainingcompanion://session?key=…`
  opens the session (the widget's link finally does what it says).
  `SessionLoggingTests` pins the table, the payload and the read-back.
- *Simulator against the local API*: `APITarget` (environment, then the
  `apiBaseURLOverride` default, then the build's URL), a local target needs no
  sign-in (`AuthManager.applyTargetChange`, no bearer sent), an ATS exception
  for localhost, Settings ▸ API target, and `DeepLink` routes
  (`trainingcompanion://today|program|analytics?section=…|profile`) through the
  router. `LOCAL_API=1 ROUTE=… ./ios/run_sim.sh shot.png` builds, points the
  simulator at the local server, opens a section and screenshots it — the
  first way to look at a data screen on the phone without production.
- *iOS saves round-trip the envelope*: the phone's program models decoded only
  the keys they displayed, so every save from the phone (a move, a swap,
  marking a session complete) stripped the goal, constraints, validation,
  coverage report, each exercise's `slot` and every other unmodelled key, and
  sent a blend's weights as `[:]`. `JSONValue` extras on each struct carry the
  rest back untouched (integers stay integers), `ServerProgram` keeps
  `sourceGoalWeights` and unknown envelope keys, and every rebuild in
  `AppState` passes them through. The PUT handler's back-fill now covers
  `coverage_report` too, for older builds. `ProgramRoundTripTests` pins it.

**Adjust, swap, devices and the iOS "Later" tranche (2026-10-01)**:

- *Apply adjustment*: `POST /api/programs/adjust` applies one of the review's
  `adjustments[]` to the stored weeks from a week onward (default: the current
  calendar week) under the same revision check as PUT, and returns the saved
  envelope. `hold_load` freezes the kg at the start week; `reduce_volume_10pct`
  cuts sets and AMRAP rounds per *week* (one off nine weekly sets — 10 % of
  three sets per session rounds to nothing) and minutes/km ×0.9;
  `early_deload` flags the start week and applies the deload scalings;
  `increase_increment` adds the lift's `weekly_increment_kg` cumulatively after
  the start week. `rebuild_habit` is answered 422 — it is about the athlete, not
  the plan. The logic is `apply_adjustment_to_weeks`, pure and testable without
  a DB; the web renders the list on Analytics ▸ Progress with an "Apply from
  week N" button per appliable entry (`ProgressionTab`, `useApplyAdjustment`).
- *Exercise-level swap*: `POST /api/exercises/substitute` runs the selector's
  own filter and score for one archetype slot (`select_exercise(...,
  return_trace=True)`, the session's other exercises excluded) and returns
  ranked, complete assignments with the week's load and the reasons. The web
  shows a swap icon on every exercise row (`SessionPanel` → `SwapExerciseSheet`);
  picking one calls `programStore.replaceExercise` and saves through the
  revision-checked PUT. Nothing is persisted by the endpoint.
- *Web Devices card*: Profile ▸ Connections ▸ Devices lists paired Connect IQ
  watches, claims a pairing code and revokes (`api/devices.ts`,
  `DevicesCard`), against the routes the iOS Settings screen already used.
- *Program header names the stored program*: `ProgramView` read the builder's
  persisted selection for its title, so browsing a philosophy in the builder
  renamed the program the athlete is on; it now reads the envelope's
  `sourceGoalIds`.
- *iOS swap and apply*: `SwapExerciseSheet` (context menu or swipe on a session
  row) and `AdjustmentRow` on Analytics ▸ Progress use the two endpoints above
  through `AppState.replaceExercise` / `applyAdjustment`; a 409 surfaces as
  `programSaveConflict` and reloads. Models in `ProgramEditing.swift`.
- *iOS exercise reference*: `ExerciseDetailSheet` (design-system §6.14) —
  catalog entry, cues, prerequisites and `GET /exercises/<id>/media` — from
  any session row and from the swap list.
- *iOS FIT import through the server*: `FITImportSheet` posts to
  `POST /workouts/parse` (`APIClient.uploadFITFile`) and matches through
  `POST /health/matches`; the raw Supabase upserts `saveWorkoutDirect` /
  `saveMatchDirect` are gone, so a phone upload meets dedup and the matcher.
  (The watch path still bypasses them — ranked item 1.)
- *iOS load analytics from the server*: Analytics ▸ Overview reads
  `/health/load/pmc` and `/health/load/weekly`; the on-device engine is the
  fallback only, and the footnote says which was used.
- *iOS local notifications*: `NotificationManager` schedules one reminder per
  training day over a 14-day horizon from the stored program (completed
  sessions skipped, rescheduled on every program change); Settings ▸
  Notifications holds the toggle and time. `NotificationPlan` is pure and
  tested.
- *`LoadFormat`*: the one prescription formatter on iOS (§1.7 extraction),
  shared by the session, swap and exercise sheets.
- *Watch uploads through the server*: `WatchSessionManager` posted a finished
  watch workout, its match and a second session-log row straight into
  Supabase. The row never met `workout_dedupe` (a Garmin or Apple Health
  copy became a second workout), the match had no `session_uid`, elevation
  loss stayed 0, the GPS enrichment re-upload wiped the heart-rate samples
  and the session name, and the log upsert still targeted the pre-006
  primary key. It now posts `WatchUpload.workoutPayload` to
  `POST /api/health/workouts`, links through `POST /api/health/matches`
  against the listed (canonical) row, and re-sends the whole workout with
  the HealthKit route; `saveWatchWorkoutDirect` / `saveWatchMatchDirect` /
  `supabaseUpsert` are gone. `WatchUploadTests` pins the keys.
- *iOS program scorecard*: Analytics ▸ Program (first section) lays out
  `GET /analytics/program` — frame, scorecard, intensity, a section per
  methodology with a card per metric (status, coverage reason, exercise
  picker, actual-vs-expected chart, stall line, evidence; unlocks and
  benchmark-level bodies), movement balance and load. Tolerant models in
  `ProgramAnalyticsModels.swift` (a failed section is reported, not fatal);
  `AnalyticsStatusStyle` mirrors the web's status colours and copy;
  `AnalyticsCard` is the one card the three analytics sections share
  (design-system §6.15). `ProgramAnalyticsCodableTests` pins the shapes
  against a real response. The archetype table and the benchmark ladder stay
  web-only for now (benchmarks live under Profile on the phone).
- *iOS workout reads through the API*: the list, the matches and the PRs come
  from one `GET /health/snapshot` (`APIClient.HealthSnapshot`, lossy per row
  so one odd workout cannot blank the list), the detail from
  `GET /health/workouts/<id>`, the delete from `DELETE /health/workouts/<id>`.
  The phone's own `canonical_id` filter, the `SupabaseValue` column decoding
  and the JWT `userId` parsing are gone; nothing in the app speaks PostgREST
  now (auth stays with Supabase). `WorkoutHRData` reads 142 or 142.0 — the
  `hr_avg` columns are `real` — and a match confidence written as a number
  reads as a string. `WorkoutReadsCodableTests` pins the shapes.

**Content and engine tranche (2026-10-01)**:

- *Benchmark families*: four new list files under `data/benchmarks/` —
  `kettlebell_pentathlon.yaml` (the five 6-minute events, tiers from the
  archetype's RPM targets), `ruck_and_pt_standards.yaml` (12-mile ruck,
  Uphill's pack vertical pace, Horsemen PT Tests I and II),
  `crossfit_benchmark_wods.yaml` (seven Girls, Murph, Cindy, DT; community
  Rx distributions, flagged as such), `movement_skill_standards.yaml`
  (get-up ×BW, wall and free handstand holds). Entries may set `category`
  (kettlebell · tactical · benchmark_wod · skill) and `unit`;
  `benchmarks_data.BENCHMARK_FILES` is the one list the loader and the static
  dump read. Both web views group by the new categories; iOS grouped by
  category already. 47 standards, up from 21.
- *Cadence and load tables*: `scheduler._CADENCE_OPTIONS` and
  `progression._STARTING_LOADS` / `_LINEAR_INCREMENTS` are gone. Every lift
  already carried `starting_load_kg` / `weekly_increment_kg`, and every
  framework in the table already carried the same `cadence_options`, so only
  the orphaned `polarized_80_20` entry moved — into the four Uphill
  frameworks, which now rotate their weekly pattern as the table intended.
  Starting Strength, CrossFit and Wildman programs are byte-identical before
  and after.
- *Scope cleanup*: the modalities `check_provenance --coverage` listed as
  declared-but-unserved were dropped from nine packages' `scope`; the report
  is clean.
- *Consecutive-day relaxation*: a framework may declare
  `recovery.allow_consecutive` (+ `phases`); `scheduler.consecutive_allowances`
  feeds `_recovery_safe` and `_score_days`. Uphill's specific phase allows
  `[strength_endurance, strength_endurance]`, so at seven days its two ME
  days sit back to back (they were forced apart before); at five and six days
  the allocation holds one ME session, so nothing to relax. Base needs no
  block: aerobic_base has no recovery window, which is why the weekend pair
  was never blocked there.
- *Authoring API*: the six write routes validate against `docs/schemas/*`
  (422 with the error list), `PUT /api/frameworks/<id>` accepts `recovery`,
  and `DELETE /api/exercises/<id>` / `DELETE /api/archetypes/<id>` exist for
  the `custom` package only — authored packages stay YAML-edited.
- *Exercise animations, code half*: the Lottie player is installed and wired;
  the files are the open item above.

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
server (its production column only arrived on 2026-10-04, see Session logs);
watch modality colours match `modalityColors.ts`; program history on
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
