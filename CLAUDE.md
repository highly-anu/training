# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A training logic system that algorithmically generates periodized training programs from philosophies (training methodologies), constraints, and weighted priorities. Sources: Starting Strength, Uphill Athlete, CrossFit, Wildman Kettlebell, Ido Portal, Horsemen GPP, Gym Jones, Marcus Filly, ATG, BJJ, Kelly Starrett.

## Current State

**Fully functional end-to-end.** Python backend generates programs; Flask API serves them; React frontend connects to the API.

- To run: `python api.py` (port 8000) + `cd frontend && npm run dev` (port 5173)
- **Env layering.** `.env` is the production-shaped config (`op inject -i .env.template -o .env`);
  `.env.local` (from `.env.local.template`, no secrets) layers over it with `override=True`
  and points local dev at the local `training_test` Postgres with Supabase unset, so the
  API runs as `local-dev-user` and `FRONTEND_URL=http://localhost:5173` for CORS. Fly gets
  its config from `fly secrets`; neither file is committed or copied into the image.
  The YAML authoring routes (`POST/PUT/DELETE /api/exercises`, `/api/archetypes`,
  `POST /api/modalities`, `PUT /api/frameworks/<id>`) require a signed-in user and
  `AUTHORING_ENABLED=1`; an empty `SUPABASE_URL` (local dev) enables them without it. They
  validate against `docs/schemas/*.schema.json` (422 with the error list) and DELETE only
  touches the `custom` package.
  Bring the local DB up with `python run_migration.py <name>` for each file in `migrations/`
  (`--list` shows them; one migration per call, all `IF NOT EXISTS`).
- Frontend uses real API when `frontend/.env.local` contains `VITE_API_BASE_URL=http://localhost:8000/api`;
  falls back to MSW mock data otherwise. With `VITE_SUPABASE_URL` empty it skips login and
  runs as the same `local-dev-user`.
- **npm 11.4.2 cannot rebuild this lockfile's ideal tree** (`npm update`, `npm audit fix`
  and plain `npm install <pkg>` die with `Cannot read properties of null (reading 'edgesOut')`
  in arborist's peer-set loader). `npm ci`, `npm ls` and `npm audit` are fine. To change
  dependencies, run the command through a newer npm without changing the global one:
  `npx -y npm@12 update <pkg…>`. Dependabot's alerts all point at `frontend/package-lock.json`
  and are cleared by bumping within the ranges package.json already declares.

## Repository Structure

```
training/
├── api.py                    # Flask REST API (port 8000)
├── main.py                   # CLI entry point
├── requirements.txt          # pyyaml, flask, flask-cors
├── src/
│   ├── generator.py          # Orchestrates full program generation
│   ├── goals.py              # Builds the synthetic goal from a philosophy
│   ├── provenance.py         # Which packages a goal may draw from
│   ├── scheduler.py          # Assigns modalities to days (recovery-aware)
│   ├── selector.py           # Selects archetypes and exercises per slot
│   ├── progression.py        # Calculates loads (linear, RPE, time-domain)
│   ├── validator.py          # Pre-flight feasibility checks
│   ├── loader.py             # YAML data loading
│   ├── output.py             # Markdown formatter
│   └── summary.py            # Volume summary computation
├── tools/
│   ├── check_provenance.py   # Asserts no package leaks; --coverage reports gaps
│   ├── check_styles.py       # Every philosophy x style validates and generates
│   └── validate_entities.py  # YAML against docs/schemas/
├── data/
│   ├── packages/             # 11 self-contained philosophy packages
│   │   └── <philosophy_id>/
│   │       ├── philosophy.yaml      # beliefs, scope, framework_groups,
│   │       │                        #   self_contained, borrows_from
│   │       ├── frameworks/          # the training styles it offers
│   │       ├── archetypes/          # session shapes, one subdir per modality
│   │       ├── exercises.yaml       # the movements it owns
│   │       ├── exercise_media.yaml  # demo links
│   │       └── level_seeds.yaml     # optional; per-level assumed knowledge
│   ├── commons/              # shared, owned by no philosophy
│   │   ├── modalities/              # 12 modality definitions
│   │   ├── movement_patterns.yaml   # slot-filter aliases (press, hinge, carry…)
│   │   └── constraints/
│   │       ├── injury_flags.yaml    # 12 flags with patterns + substitutions
│   │       └── equipment_profiles.yaml
│   └── benchmarks/           # Six list files (strength, conditioning, kettlebell
│                             #   pentathlon, ruck & PT tests, benchmark WODs, skill)
│                             #   + the Cell standards; `benchmarks_data.BENCHMARK_FILES`
├── docs/plan.md              # Original design document (ontology reference)
└── frontend/                 # React app (see below)
```

## API Endpoints (api.py)

All prefixed `/api/`:

| Method | Path | Returns |
|--------|------|---------|
| GET | `/philosophies` | `Philosophy[]` |
| GET | `/analytics/specs` | every philosophy's analytics spec, described (`src/analytics/describe.py`) |
| GET | `/analytics/development?from=&to=&fresh=1` | development across programs — blocks, lifts and currencies across the span, load by block, standards over time (`src/analytics/development.py`); last 365 days by default, cached on a digest |
| GET | `/frameworks` | `Framework[]` |
| GET | `/exercises` | `Exercise[]` (198 total) |
| GET | `/benchmarks?sex=` | `BenchmarkStandard[]` (47; female or male tables) |
| GET | `/modalities` | `Modality[]` |
| GET | `/archetypes` | `Archetype[]` |
| GET | `/ontology` | Lightweight projection with counts |
| GET | `/constraints/equipment-profiles` | `EquipmentProfile[]` |
| GET | `/constraints/injury-flags` | `InjuryFlag[]` |
| POST | `/programs/generate` | `GeneratedProgram` (`week_in_program` numbers a partial regenerate's tail from the kept head's length + 1) |
| POST | `/sessions/generate` | `Session` (single session regeneration) |
| POST | `/exercises/substitute` | `{alternatives: [{assignment, score, reasons}]}` — ranked swaps for one slot, selector-scored, loads for the week; 422 when nothing fits |
| POST | `/programs/adjust` | applies one `suggest_adjustments` entry (`hold_load`, `reduce_volume_10pct`, `early_deload`, `increase_increment`) to the stored weeks from a week onward under the revision check; returns the saved envelope; `rebuild_habit` is 422 (advice) |
| GET/POST/DELETE | `/devices`, `/devices/claim`, `/devices/<token>` | Connect IQ watch pairing: list, claim a code, revoke (web: Profile ▸ Connections ▸ Devices; iOS: Settings) |

`POST /programs/generate` body: `{ philosophy_id: string, constraints: AthleteConstraints, num_weeks?: number }` or `{ philosophy_ids: string[], philosophy_weights: Record<string, number>, constraints: AthleteConstraints, num_weeks?: number }`

**Adjust and swap edit the stored program, never regenerate it.** `POST /programs/adjust`
mutates `weeks[start:]` in place (`apply_adjustment_to_weeks`, pure, tested without a DB):
`hold_load` freezes each lift at the start week's kg; `reduce_volume_10pct` cuts discrete
quantities *per week* (one set off nine weekly sets — 10 % of three sets per session rounds
back to three and would never change anything) and continuous ones ×0.9; `early_deload`
flags the start week and its sessions and applies the deload scalings; `increase_increment`
adds the exercise's `weekly_increment_kg` per week cumulatively after the start week. Targets
are the tracker's display strings (`all`, `schedule`, or comma-joined exercise names) matched
against id and name. Loads and slots are outside the version skeleton hash, so an adjustment
never mints a program version; it bumps the revision like a PUT. `POST /exercises/substitute`
runs `selector.select_exercise(..., return_trace=True)` for one slot with the session's other
exercises excluded and returns complete assignments with `calculate_load` for the week; the
client replaces the entry (`programStore.replaceExercise`) and saves through the
revision-checked PUT — nothing is persisted by the endpoint.

## Frontend (frontend/)

React 19 + Vite 8 + TypeScript, Tailwind CSS v4, shadcn/ui, Framer Motion, TanStack Query, Zustand, Recharts, MSW v2, React Router v7.

**Pages (grouped sidebar, `components/layout/Sidebar.tsx`):** Train — Home `/`
(`pages/Dashboard.tsx`, no sub-tabs, side panel), Program `/program` (Calendar · Overview ·
History via `?tab=`; the builder is the flow `/program/new`), Log `/log` (Workouts ·
Suggestions, Import as a sheet; `/log/:workoutId` is WorkoutDetail). Insight — Analytics
`/analytics` (Program · Progress · Load · Recovery via `?tab=`). Library — Explore
`/explore` (Philosophies · Frameworks · Modalities · Archetypes · Exercises · Standards,
with "Build with this" CTAs into the builder). You — Profile `/profile` (Athlete · Equipment ·
Injuries · Schedule · Benchmarks · Heart Rate) and Settings `/settings` (Connections · Account ·
Appearance · Developer in dev builds). The Garmin and Strava OAuth callbacks land on
`/profile?tab=connections`, which redirects to `/settings?tab=connections` with the query
intact — the server keeps naming the old URL because `FRONTEND_URL` may pin a deployment
that predates Settings. Dev Lab `/dev` exists in dev
builds only (`src/lib/featureFlags.ts`). Old paths (`/builder`, `/import`, `/bio`,
`/exercises`, `/philosophies`, `/program/history`) redirect through
`components/layout/LegacyRedirect.tsx`; unknown paths render `pages/NotFound.tsx`.
Session detail (page and Home side panel) renders one `components/session/SessionPanel.tsx`;
recorded-workout lists render one `components/workout/WorkoutRow.tsx`; session keys are
parsed by `lib/sessionKeys.ts` only.

**State:** `builderStore` (wizard state; persisted), `uiStore` (selected week; persisted),
`programStore` (server-backed, `revision` 409 protocol), `profileStore` (server-synced
through `PUT /api/profile`), `bioStore` (hydrated by `HealthDataProvider` from
`/api/health/snapshot` plus `/api/health/matches/suggestions`), `authStore`.

**Information architecture:** the target layout for both clients, the connectivity map and
the reasoning are in `docs/information-architecture.md`; the work is ranked in
`docs/roadmap.md` (items tagged *IA*).

**API hooks:** `src/api/` — goals.ts, exercises.ts, programs.ts, constraints.ts, modalities.ts, benchmarks.ts

## System Architecture

```
Philosophy → Framework Groups → Frameworks → Modalities → Archetypes → Exercises → Progression → Constraints → Program
```

1. **Philosophy** — training methodology with framework_groups (sequential or alternatives)
2. **Framework groups** — organize frameworks as sequential phases (e.g., base→build→peak) or alternative approaches
3. **Synthetic goal** — generated from philosophy priorities + phase sequence; allows philosophy blending
4. **Scheduler** — maps priorities + framework → session slots per day (recovery-aware)
5. **Selector** — picks best archetype per slot; fills archetype slots with exercises (injury/equipment/level filtered)
6. **Progression** — calculates load prescription per slot type (linear_load, rpe_autoregulation, time_to_task, distance, density)
7. **Validator** — pre-flight checks on equipment, days, session time, injury conflicts, phase validity
8. **API** — transforms integer day keys → day names; wraps in `{ goal, constraints, validation, weeks, volume_summary }`

## Key Engine Behaviors

- **Injury flags**: excluded_movement_patterns blocks exercises by movement pattern; contraindicated_with blocks specific exercises. Slots whose required pattern is fully excluded show as `injury_skip` (not an error).
- **Session time cap**: `_time_to_task` progression is capped at `session_time_minutes` — Zone 2 duration never exceeds the athlete's session limit even in build phase.
- **Package provenance**: a program may only use its philosophy's own package, plus any package that philosophy declares in `borrows_from` (`src/provenance.py`). Enforcement is per philosophy via `self_contained: true` — all 11 are on. `api.py` and `generator.py` share one `SourcePolicy`, so validation and generation can never check different libraries. Borrowed sessions carry a `provenance` tag and are badged "via X" in the UI.
- **Coverage gaps, not substitutions**: when a package cannot fill a slot, the slot is left empty and marked `coverage_gap` (the same way `injury_skip` marks an injury-blocked slot) rather than filled from another philosophy. Programs carry a `coverage_report` listing unfilled sessions, unfilled slots and borrowed sessions; `validate()` warns `PACKAGE_COVERAGE_GAP` per uncovered modality and only errors when every top-2 priority is uncoverable.
- **Archetype fallback**: sessions whose modality has no valid archetype for the phase fall back within the allowed packages (equipment filter relaxed first, then `aerobic_base` → `durability` → `mobility`).
- **Prerequisites**: `requires` is resolved transitively — a requirement is met if it is a concept the training level knows or an exercise that is itself unlocked. A package may declare `level_seeds.yaml` for concepts its own athletes arrive with.
- **Exercise scoring**: prefers exercises with defined movement_patterns (+0.5) and forward-unlocking exercises (+0.5); penalizes recently used (-2 per recent use). AMRAP/for_time slots exclude `mobility` and `rehab` category exercises.
- **Deload**: auto-triggered every N weeks (per framework) or when `fatigue_state: overreached`.
- **Cadence, loads and recovery live in YAML.** A framework's `cadence_options`
  (keyed by days per week, several patterns rotating week to week) is the only source of
  day patterns; an exercise's `starting_load_kg` / `weekly_increment_kg` the only source of
  loads (`progression._DEFAULT_INCREMENT_KG` is the sole code default). A framework may
  declare `recovery.allow_consecutive: [[a, b], …]` (+ `phases`) to let a modality pair sit
  on back-to-back days despite the recovery windows — Uphill's specific phase does, for
  its two ME long days (`scheduler.consecutive_allowances`).
- **Framework expectations**: Every framework defines required `expectations` (min/ideal weeks, days/week, session minutes, split-day support). UI derives "Ideal for this goal" banners from framework expectations (or weighted blend when combining frameworks). Philosophy-specific, not goal-generic.
- **Phased frameworks**: Philosophies can specify different frameworks for each phase using `framework_groups` with `type: sequential`. Each group contains a `canonical_phase_sequence` with `framework_id` per phase. Framework selection priority: 1) phase-specific override, 2) API request override (`forced_framework`), 3) goal framework alternatives, 4) default framework. Uphill Athlete uses this for transition→base→specific→taper progression.
- **Framework groups**: Philosophy `framework_groups[]` defines how frameworks are organized. Type `sequential` creates phased programs (UI shows "Full Program" button covering all phases). Type `alternatives` offers multiple styles/approaches (UI shows framework picker to choose one). Uphill Athlete has sequential phases; Wildman/Horsemen have alternatives.

## Design

Before building or changing UI, read the design system for that platform — it
is the source of the patterns, not the neighbouring screen:

- **iOS / watchOS**: `ios/docs/design-system.md`. Colour, typography, spacing,
  motion, and the component patterns in §6. §1.7 covers the governing rule:
  when two screens need the same component, extract it and convert both in the
  same change, then document it in §6. Profile and Analytics each grew their
  own sub-tab selector before that rule existed; both now use
  `AppSubTabs.swift` (§6.8).
- **Web**: `docs/frontend-design.md` (§13.2 the grouped sidebar, §17.8 every page's header).
- **iOS tabs**: Today · Program · Log · Analytics · Profile (`AppRouter.Tab`); Settings
  (connections, devices & sync, notifications, appearance, account) is pushed from
  Profile's gear, never a tab — design-system §6.13. The exercise reference on the phone
  is `ExerciseDetailSheet` (§6.14), presented from any session row and from the swap
  list; prescriptions are formatted by `LoadFormat` only. Local session reminders come
  from `NotificationManager` (`NotificationPlan` is pure and tested); there is no push.

Shared iOS style primitives live in `AppAnimationSettings.swift`
(`AppAnimation`, `AppHaptics`, `AppMetrics`, `appTabStyle()`) and
`AppSubTabs.swift`. Tab selection lives in `AppRouter.swift`, so one screen can
send the user to a section of another (§6.9) — route through its methods, never
by assigning tab state at the call site. Put shared behaviour inside the
component rather than in instructions at the call site.

## Workout Import

Activities reach the `workouts` table from five places: a manual `.fit`/`.xml`/`.json`
upload (`POST /api/workouts/parse`, from the web Log page and the iOS `FITImportSheet`
alike), the Strava OAuth sync, the Connect IQ watch app, the iOS Apple Health relay, and
the Garmin Connect webhook. The Apple Watch companion posts through the same two routes
(`WatchUpload` builds the payloads; `WatchUploadTests` pins the keys): no client writes a
workout or a match to Supabase directly any more, so every copy meets dedup, the matcher
and `session_uid` resolution. The phone reads them back through `GET /health/snapshot`
and `GET /health/workouts/<id>` too — nothing in the iOS app speaks PostgREST for
training data; only sign-in goes to Supabase.

- **One FIT parser** — `src/fit_import.py`, extracted from the upload handler so the
  Garmin webhook can parse the same format. `parse_fit(stream, source=...)` is pure:
  no Flask, no DB.
- **Deterministic ids** — `src/workout_ids.py`. The formula is mirrored in
  `frontend/src/lib/importParsers.ts` and `ios/.../WorkoutID.swift`. **Do not change
  it**: `workout_matches.imported_workout_id` references the ids it produces.
- **Dates are the athlete's day, ids stay UTC.** `fit_import.local_date` derives a
  workout's `date` from the FIT activity message's local timestamp, else the profile's
  `timezone` (IANA; Profile ▸ Athlete on the web, filled from the device on iOS), else
  UTC; the Garmin webhook passes `startTimeOffsetInSeconds`, Strava uses
  `start_date_local`. `startTime` and the deterministic id never move.
- **Cross-source dedup** — because the id embeds the source, one activity arriving
  four ways makes four ids. `src/workout_dedupe.py` decides whether two records are the
  same activity (±5 min start, duration within 3 min or 10%, same modality family) and
  merges into the row already there. The canonical row's id never changes; duplicates
  are kept, marked `canonical_id` and hidden from reads. Sources rank by richness:
  `fit_file > garmin > apple_watch_live > apple_health > strava > manual`.
- **Matching** — `src/workout_matcher.py` (server) and
  `frontend/src/lib/workoutMatcher.ts` (browser) share `data/matching_rules.json` and
  the golden fixtures in `data/matcher_fixtures.json`. Change scoring in the JSON, not
  in either implementation, and run both suites. Weak matches go to
  `workout_match_suggestions`, never to `workout_matches` with a 'pending' confidence —
  a dozen readers treat "row that isn't 'rejected'" as "is matched".
- **Settings** — `profile_data['integrations']`: a master switch plus per-source
  toggles, gated server-side via `api.integration_allows(user_id, source)`. Enforcing
  it only in the UI would leave it decorative for webhook traffic.
- **Garmin webhook** — unauthenticated by necessity. Defended by a shared secret in
  the URL, identity taken only as a `garmin_user_id` looked up against an existing
  registration, and the activity fetched from Garmin with our own token after the
  callback host/port is checked against `GARMIN_API_BASE` (without which the endpoint
  is an SSRF primitive). Always answers 200 except on a bad secret — Garmin disables
  endpoints that keep erroring. Work happens on a worker thread against the durable
  `garmin_webhook_events` queue, because gunicorn runs `--workers 1`.
- **A match write must not touch a NOT NULL column it does not fill.**
  `health_store.upsert_match` first inserts a stub `workouts` row `ON CONFLICT
  DO NOTHING` so the FK holds. Postgres checks NOT NULL constraints *before*
  conflict resolution, so a stub that left `start_time`, `end_time` and
  `duration_minutes` NULL raised on every call — and the writer's `except`
  swallowed it. Production wrote no match between 2026-06-10 and 2026-10-02
  while the suggestions table (no stub) kept filling; every auto-match on
  import and every confirm from either client was lost. The stub now fills
  every NOT NULL column; `test_dedupe_sql.py` writes a match against the
  production-shaped schema. When a store writer swallows exceptions, test it
  against a schema with the real constraints.
- **Load maths never reads a series.** `workouts.metrics`
  (`migrations/007_workout_metrics.sql`, lazily added by
  `health_store._ensure_metrics_column`) caches `zones.compute_metrics` — zone
  minutes and TRIMP at one max HR and one zone-edge version — per row.
  `api._workouts_for_load` serves readiness (TSB), the PMC, the weekly load
  and the development document from summaries, reading the HR series
  (`get_workouts_with_hr`, never the GPS track) only for rows whose cache is
  missing or stale, 40 per call, newest first, and writing them back; a
  re-import that changes the series drops the row's cache. Before this the
  TSB component of readiness read every workout with its GPS track on every
  Home open — ~40 MB of JSON, a 327 MB peak once parsed — and OOM-killed the
  256 MB worker, which the browser reports as a CORS error because Fly's
  proxy answers the dead worker with a header-less 502. The program analytics
  read full rows only for matches dated inside the program's own span
  (`_matched_ids_in_window`); the progression routes read summaries.
  `test_workout_metrics.py` pins all three.
- **Profile writes merge.** `PUT /api/profile` overwrites only the keys the body
  carries. It used to rebuild the blob, which is why every iOS save wiped
  `activeGoalId`. `performanceLogs` is not a profile key: PRs and the
  `bodyweight_kg` series go through `POST /api/health/performance` on both
  clients (iOS used to send them with the profile, where the whitelist dropped
  them).
- **iOS builds from philosophies.** `GET /api/goals` was removed on 2026-04-25;
  the iOS builder and settings sheet pick a methodology from
  `GET /api/philosophies` and send it as `philosophy_id`.

## Program Analytics

`GET /api/analytics/program` answers "how is the athlete doing against what the
active program is *for*" — per methodology, in that methodology's own currency.
The engine is `src/analytics/`; the web Program tab (`components/analytics/`)
only lays the document out. Analytics used to be goal-blind on every platform
(TRIMP, PMC and readiness with no idea what the program was), and the one
tracker that could have been goal-aware analysed every program as
`linear_load` because it read a `goal.progression_model` that `goals.py` never
writes.

- **The spec is shown before it is run.** `GET /api/analytics/specs`
  (`src/analytics/describe.py`) describes every package's composed spec —
  declared or default, ids resolved to names, `expected` normalised, and the
  capture requirements unioned from `src/analytics/vocabulary.py`, the one
  place the twelve primitives are put into words. The Explore tab's
  philosophy detail renders it beside the phase spine and weekly shape
  (`components/explore/`), and the framework, modality and archetype details
  list the signals that name them. Static, no user, no program.
- **Packages own their analytics.** A methodology declares what progress means
  for it in `data/packages/<id>/analytics.yaml` (schema
  `docs/schemas/analytics.schema.json`; validated by `validate_entities.py`,
  provenance-checked by `check_provenance.py`, loaded by
  `loader.load_analytics_specs`). A package that ships none gets a spec
  synthesised from its frameworks (`src/analytics/spec.py`). **Nothing in
  `src/` names a philosophy** — a new package with an `analytics.yaml` gets its
  own section with no engine change, and `test_program_analytics.py` proves it
  with a throwaway package.
- **The engine's vocabulary is twelve primitives** (`src/analytics/primitives/`):
  `set_load`, `load_at_rpe`, `rounds`, `duration`, `distance`, `hold_seconds`,
  `rate`, `zone_minutes`, `aerobic_efficiency`, `unlocks`, `benchmark_level`,
  `session_completion`. A spec entry names one, scopes it (modalities,
  archetypes, frameworks, slot types, roles, exercises, patterns) and says where
  its expectation comes from. Every result carries **coverage** — the share of
  completed in-scope sessions that produced the metric, with a reason code
  when it is zero — so a methodology whose currency is not captured yet says
  "not measurable — log rounds" instead of showing nothing.
- **Expected values come from the stored prescription, never a generator
  re-run.** `api._clean_exercise_assignment` strips the slot, and generation
  used `week_in_phase` where the old tracker replayed with `week_number`; the
  old "expected trajectory" was a recomputation against a bare slot with the
  wrong week. Read `ea.load`; for load, expect last achieved + the exercise's
  increment.
- **The framework's `progression_model` never drove a prescription** —
  `generator.py` reads the modality yaml's. Default primitives key on
  `(modality.progression_model, slot_type)`; the framework's model informs
  only the intensity section.
- **Slot roles are free-form (144 strings).** Never scope by guessing a role
  name; the default `set_load` scope is `slot_types: [sets_reps]` plus
  `exclude_slot_roles` for warm-up/accessory/prep. Starting Strength's own
  roles are `primary_squat`, `upper_press`, `secondary_compound`.
- **One HR-zone definition, one family map.** `data/commons/hr_zones.json`
  (edges near the aerobic threshold, with a `version` cached workout metrics
  key on) is read by `src/analytics/zones.py`, `_calc_workout_trimp` and
  `lib/hrZones.ts`; `data/commons/modality_families.json` replaced five
  divergent copies. Under the old Friel 60/70/80/90 edges honest Zone 2 at 72%
  counted as Z3, inverting Uphill's 80/20 diagnostic. Server max HR is now
  DOB-aware like the clients.
- **The scorecard headline is a gate, not a weighted sum**: Σ priority ×
  completion is arithmetically plain compliance (priorities *are* the session
  shares). Committed-tier completion < 70% is `off_plan` regardless.
- **A strength session contributes to `max_effort` whether or not it wore a
  strap** — never to the HR buckets as well. Sessions with neither HR nor a
  strength modality are `unclassified`, counted not dropped.
- **Trend** is a least-squares slope over non-deload points (`trend.py`),
  ±1 %/point; stall for load is per *session*, over the package's declared
  window. A deload week — flagged, or a taper — is never a stall.
- **Window.** Session logs, matches and workouts are keyed program-relatively
  and a regenerate leaves the last block's rows under the same keys, so
  `context.py` filters every input to the program's own date span. Cross-block
  comparison is what the Program History tables (below) exist for, and
  `GET /api/analytics/development` (`src/analytics/development.py`) is where
  they are read: `blocks` (the activation timeline with each block's planned
  and completed sessions), `lifts` and `currencies` (every logged series over
  the whole span, keyed to its block through `session_uid`, with per-block
  first / last / best / Δ and a trend), `load` (weekly TRIMP with the week's
  block) and `benchmarks` (the level ladder per PR date). Pure over its
  inputs — `test_development_analytics.py` runs it on a throwaway two-block
  history — and cached in `progression_snapshots` on a digest of everything
  it read. The web's Analytics ▸ Development and the phone's Analytics ▸
  Blocks lay it out; the Program tab stays the current block.
- **Capture.** `OutcomeLogger` (web) writes `ExercisePerformance.rounds /
  durationSec / distanceKm` — the keys the tracker always read and nothing
  wrote. `ExerciseRow` dispatches on `slot_type` through `lib/outcomeFields.ts`
  (sets × reps → `PerformanceLogger`, anything with a currency →
  `OutcomeLogger`); `ExerciseRow.test.tsx` pins it, because the logger was once
  written and never mounted, which left every rounds/duration/distance
  primitive at zero coverage. The phone logs from the session detail
  (`ExerciseLogSheet`, design-system §6.16) with the same dispatch
  (`SessionLogging`) and the same payload; `GET /health/sessions/recent`
  carries `exercises` so it can read back. Bodyweight
  is the benchmark series `bodyweight_kg`, which turns a logged est-1RM into
  the ×BW standards. `PUT /api/health/sessions/<key>/notes` now exists — the
  iOS app had been posting notes into a phantom key — and fatigue is folded to
  1–5 at the boundary (iOS sends 1–10).
- `GET /api/progression/review` keeps its shape for iOS but takes its
  `exercise_findings` from the engine.
- **iOS load charts are server-side.** Analytics ▸ Overview reads
  `/health/load/pmc` and `/health/load/weekly`; `AnalyticsEngine` is the
  fallback when the request fails, and the footnote says which was used, so
  the phone and the web cannot quietly disagree. Analytics ▸ Program
  (`Views/AnalyticsProgramTab.swift`) lays out the same `/analytics/program`
  document the web does; `ProgramAnalyticsModels.swift` decodes every section
  on its own, and `AnalyticsStatusStyle` is the phone's copy of
  `components/analytics/status.ts`. Analytics ▸ Blocks
  (`Views/AnalyticsDevelopmentTab.swift`, `DevelopmentModels.swift`) lays out
  `/analytics/development` the same way; the section is called Blocks because
  five segments truncate "Development".
- **Earlier programs' logs are named by the server.** `GET /health/sessions/recent`
  resolves each log's `session_uid` through `planned_sessions`
  (`program_history.planned_rows_for_uids`) and adds `planned_name`,
  `planned_modality`, `planned_date`, `program_version_id`, `week_index` and
  `day_name`. The phone's Log ▸ Sessions uses them for logs whose legacy key
  resolves to nothing — or to the wrong session: "3-Friday-0" exists in the
  current program too, so a planned date before the current program's start
  overrides the key lookup (`LogSessions.rows`).

## Program History

`user_programs` holds **one row per athlete** and `save_user_program` upserts it,
so generating a program used to destroy the previous one outright. Nothing
recorded what had been planned, and a planned session's only identity was the
program-relative string `"{week_number}-{DayName}-{idx}"`, which references
nothing. Three consequences, all fixed here: a workout dated inside a finished
block was dropped by the matcher and could never be matched; a stored match
silently re-pointed at whatever now occupied that (week, day, index); and
`session_logs`, keyed on the same string, **merged** one block's set data into
another's row.

- **Three tables** (`migrations/005_program_history.sql`), because three things
  were conflated: `program_versions` is the content (an immutable snapshot,
  deduplicated by skeleton hash), `program_activations` is the timeline
  (append-only, DATE-valued intervals), `planned_sessions` is the geometry (one
  row per planned session per version, on the calendar day it fell on).
- **`session_uid` is keyed on the week's ARRAY INDEX**, never on `week_number`.
  `src/generator.py` numbers weeks from `week_in_program` and, with an event
  date, `phase_calendar.build_remaining_schedule` starts that at the athlete's
  *absolute* week — so a 16-week generate legitimately yields weeks[0..15]
  numbered 16..31, and a partial regenerate splices that onto the kept head. One
  `week_number` then sits at two array indices. (Without an event date a partial
  regenerate used to number its tail from 1 again, so a program read 1, 1, 2, 3;
  since 2026-10-01 the three regenerate paths pass `week_in_program` = kept head
  length + 1 and the tail continues the numbering.) `legacy_key` ('3-Monday-0') is
  descriptive and **not unique**; resolve it as `(user_id, legacy_key, date)`.
- **Dates come from `workout_matcher.session_calendar_date`**, called rather
  than reimplemented: `PUT /api/user/program` does not Monday-align (only
  generate does) so non-Monday starts are real, and both paths must agree.
- **The skeleton hash covers only plan-defining content** — start date, and per
  week index the number, phase, deload flag and each day's (modality, archetype
  id, exercise ids), with days iterated in `DAY_NAMES` order. Everything the
  three self-healing re-saves in `GET /api/user/program` rebuild is excluded, or
  every app open would mint a version; so is every load and slot, because iOS
  re-encodes `reps` through `AnyCodable` and `8` comes back as `8.0`. Days are
  iterated in fixed order because Swift re-encodes the schedule dictionary
  arbitrarily. `content_hash` is separate: same skeleton, different content means
  the snapshot is stale, and it is refreshed in place — but only by a copy at
  least as *rich*, because an iOS save used to strip `goal` and every `slot`.
  Since 2026-10-01 the phone round-trips every key it does not model
  (`JSONValue` extras on each program struct in `WatchModels.swift`, pinned by
  `ProgramRoundTripTests`) and echoes the blend's weights; the richness guard and
  the PUT handler's goal/constraints/validation/coverage_report back-fill stay
  for older builds.
- **Intervals are DATEs computed in Python**, never `activated_at::date` — that
  cast uses the server's TimeZone (UTC on fly.io) and is a day out every evening
  west of Greenwich. The **first** activation runs from the program's own
  `start_date`, which is what lets the program archived on first read own its
  already-elapsed weeks; later ones start the day they are activated. Intervals
  must stay disjoint: two candidate sets on one date inflate the `unambiguous`
  count in `auto_match_indexed` and silently demote auto-matches to suggestions.
- **Archiving is idempotent and happens on read as well as on write.** `PUT`,
  the `persist` branch of generate, and `GET /api/user/program` all call
  `record_version`; the GET path is guarded by `source_revision` so the common
  case is one indexed lookup, not hashing a ~1 MB envelope. Archiving on *read*
  is what captures the pre-strip copy.
- **The matcher's index is a union** (`workout_matcher.history_aware_index`):
  the current program first, history overwriting any date it covers. Strictly
  additive — history is empty on a fresh deploy and in local dev with no
  `DATABASE_URL`, and indexing it alone would stop all auto-matching.
- **`session_uid` is resolved in `health_store`, not in the matcher**, so all
  five match writers get it. Resolve it **before** opening a connection:
  `get_conn()` hands out one process-global connection and a nested `with` on it
  returns nothing while swallowing the reason.
- **`session_logs` is scoped to a version** (`migrations/006_session_log_scope.sql`):
  `log_key` is `COALESCE(session_uid, session_key)` and the primary key moved to
  `(user_id, log_key)`. Existing rows keep their old key, so nothing breaks.
  `get_session_logs` answers "this program's log for that key" and hides other
  versions' rows; `get_session_logs_by_uid` is the cross-program reader the
  progression endpoints use.
- **Run `005` before deploying the code.** `src/program_history._ensure_tables`
  is a fallback for a deploy that got ahead of its migration, and it creates the
  tables with row security enabled but *no policy* (deny-by-default) because a
  test database has no `auth` schema. The migration is what adds the real
  per-user policies — these tables live in `public`, which Supabase exposes
  through PostgREST.
- **The Uphill block of 2026-04-27 → 2026-09-20 is a replica** (activation
  `source = 'replica'`, `backups/uphill_replica_2026-04-27.json`). The plan
  trained on in spring was overwritten on 2026-09-28, before history existed;
  on 2026-10-02 it was regenerated from the late-April generator (commit
  `557fa98`, a 0.7/0.3 Uphill + Horsemen blend, event date 2026-08-16, the
  weekly schedule Mon short+mobility · Tue short+mobility · Wed short+long ·
  Thu short · Fri short · Sat long · Sun long+mobility) chosen because it
  reproduces 34 of the 35 session keys the surviving matches carry. Its
  exercises and loads are the generator's, not the athlete's; its sessions,
  dates and the matches and logs attributed to it are real.
- **History starts at deploy.** Programs already overwritten are unrecoverable.
  `scripts/backfill_program_history.py` archives each athlete's current program
  and attributes existing matches and logs where a key resolves unambiguously on
  the workout's own date. It does **not** infer a start date from
  `(workout.date, session_key)`: that is wrong by
  `(week_number - 1 - week_index) * 7` days — fifteen weeks in the absolute-week
  case — and undefined when a week number repeats.

## Running the iOS App

**Every iOS change ends in the simulator.** A green `xcodebuild` says the code
compiles, not that the screen still works — so after touching anything under
`ios/`, rebuild, reinstall and relaunch the app before reporting the work done,
and look at a screenshot of the screen you changed:

```bash
./ios/run_sim.sh                      # build + install + relaunch on a booted sim
./ios/run_sim.sh /tmp/after.png       # …and screenshot the result
```

The script boots `iPhone 17 Pro` (override with `SIM_DEVICE=`) if nothing is
booted, and always terminates the old copy first so the running app is the code
that was just built.

**Point the simulator at the local API to see screens with data.** The build
talks to production unless told otherwise, and production is not always
reachable; the local Flask server has the local dev program and needs no
account. The target is the app's `apiBaseURLOverride` default (`APITarget.swift`;
`API_BASE_URL` in the launch environment wins for one launch), and it persists
in the simulator until cleared. Deep links open any section without tapping —
the Simulator window is not scriptable:

```bash
LOCAL_API=1 ./ios/run_sim.sh /tmp/today.png                                            # local API, Today
LOCAL_API=1 ROUTE='trainingcompanion://analytics?section=program' ./ios/run_sim.sh /tmp/p.png
LOCAL_API=0 ./ios/run_sim.sh                                                            # back to production
```

Routes: `today`, `program`, `analytics?section=program|overview|workouts|progress|
recovery`, `profile` (`DeepLink.swift`, routed through `AppRouter`). The route travels
in the launch environment (`SIMCTL_CHILD_TC_ROUTE`), because `simctl openurl` makes
iOS ask "Open in Training Companion?" and nothing can tap that. Screens behind a tap
(the swap sheet, the exercise sheet) are still out of reach; test their models.
Settings ▸ API target shows the current target and, in debug builds, the switch.
Never generate, adjust or swap from a simulator pointed at production.

The unit tests live in `ios/TrainingCompanionTests/`, a synchronized folder on
the `TrainingCompanionTests` target, so a new test file needs no project edit:

```bash
./ios/run_tests.sh                        # the whole bundle, same simulator rules
./ios/run_tests.sh ProgramCodableTests    # one class, or Class/testMethod
```

A test that lets an `AppState` go out of scope must be `async`: the class is
`@MainActor`, its deinit is isolated, and the Xcode 26.2 runtime aborts an
isolated deinit that runs outside a Task — which is where a synchronous XCTest
method runs. `CurrentWeekIndexTests.swift` explains it at the top.

To drive the UI, the simulator maps device points to screen coordinates through
`group 1 of window 1` — its AX position is the top-left of the device screen and
its size is the screen in points (a screenshot's pixels ÷ the device scale):

```bash
osascript -e 'tell application "System Events" to tell process "Simulator" \
    to get {position, size} of group 1 of window 1'    # e.g. 1812, 105, 402, 874
osascript -e 'tell application "System Events" to click at {1812, 105}'
```

## Checks

Run this after touching analytics, a package's `analytics.yaml`, the matcher's
zone edges or the session-log path (needs `SUPABASE_URL=''` for the routing checks):

```bash
SUPABASE_URL='' .venv/bin/python test_program_analytics.py   # engine, specs, primitives, routing (no DB)
.venv/bin/python test_development_analytics.py               # development across programs, on a throwaway history (no DB)
SUPABASE_URL='' .venv/bin/python test_workout_metrics.py     # the per-workout metrics cache and the load routes' reader (no DB)
```

Before anything that changes production structure (a migration, a backfill):

```bash
scripts/backup_prod.sh                    # pg_dump 17 + restore-test + row-count compare; exits 1 on mismatch
```

Run these after touching engine code or package data:

```bash
.venv/bin/python tools/validate_entities.py --all -q     # YAML vs docs/schemas (125 files)
.venv/bin/python tools/check_provenance.py               # no package leaks; 11 philosophies x 3 profiles
.venv/bin/python tools/check_provenance.py --coverage    # coverage gaps + authoring problems
.venv/bin/python tools/check_styles.py                   # every philosophy x style generates
.venv/bin/python test_provenance.py                      # source-policy rules
SUPABASE_URL='' .venv/bin/python test_week_numbering.py  # a partial regenerate's tail continues the numbering
```

Run this after touching anything under `ios/` (in addition to the simulator):

```bash
./ios/run_tests.sh                         # TrainingCompanionTests on the booted sim
```

Run these after touching program history, the matcher or the session-log path:

```bash
.venv/bin/python test_program_history.py      # hashing, flattening, intervals (no DB)
.venv/bin/python test_workout_matcher.py      # the cross-language parity contract
```

Run these after touching the workout import pipeline:

```bash
.venv/bin/python test_fit_import.py        # FIT parser + the deterministic id formula
.venv/bin/python test_profile_merge.py     # profile blob merges; auto-import settings
.venv/bin/python test_workout_matcher.py   # matcher, against the shared fixtures
.venv/bin/python test_workout_dedupe.py    # cross-source dedup decisions (pure logic)
cd frontend && npx vitest run              # incl. the TS half of the matcher parity suite
```

Two suites need a local PostgreSQL and skip cleanly (exit 0) without one:

```bash
brew services start postgresql@14 && createdb training_test
.venv/bin/python test_dedupe_sql.py        # dedup SQL: merge, canonical_id, visibility
.venv/bin/python test_garmin_webhook.py    # the whole webhook path, no Garmin account needed
.venv/bin/python test_program_history_sql.py  # the timeline, and matching inside a finished block
```

## Known Gaps / Next Work

The ranked backlog is `docs/roadmap.md` — one document, priority and complexity
per item, verified against production on 2026-09-30. Read it before planning
work; add new items there rather than to a fresh planning doc.
