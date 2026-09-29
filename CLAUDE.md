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
  Bring the local DB up with `python run_migration.py <name>` for each file in `migrations/`
  (`--list` shows them; one migration per call, all `IF NOT EXISTS`).
- Frontend uses real API when `frontend/.env.local` contains `VITE_API_BASE_URL=http://localhost:8000/api`;
  falls back to MSW mock data otherwise. With `VITE_SUPABASE_URL` empty it skips login and
  runs as the same `local-dev-user`.

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
│   └── benchmarks/           # Strength + conditioning + cell standards
├── docs/plan.md              # Original design document (ontology reference)
└── frontend/                 # React app (see below)
```

## API Endpoints (api.py)

All prefixed `/api/`:

| Method | Path | Returns |
|--------|------|---------|
| GET | `/philosophies` | `Philosophy[]` |
| GET | `/analytics/specs` | every philosophy's analytics spec, described (`src/analytics/describe.py`) |
| GET | `/frameworks` | `Framework[]` |
| GET | `/exercises` | `Exercise[]` (198 total) |
| GET | `/modalities` | `Modality[]` |
| GET | `/archetypes` | `Archetype[]` |
| GET | `/ontology` | Lightweight projection with counts |
| GET | `/constraints/equipment-profiles` | `EquipmentProfile[]` |
| GET | `/constraints/injury-flags` | `InjuryFlag[]` |
| POST | `/programs/generate` | `GeneratedProgram` |
| POST | `/sessions/generate` | `Session` (single session regeneration) |

`POST /programs/generate` body: `{ philosophy_id: string, constraints: AthleteConstraints, num_weeks?: number }` or `{ philosophy_ids: string[], philosophy_weights: Record<string, number>, constraints: AthleteConstraints, num_weeks?: number }`

## Frontend (frontend/)

React 19 + Vite 8 + TypeScript, Tailwind CSS v4, shadcn/ui, Framer Motion, TanStack Query, Zustand, Recharts, MSW v2, React Router v7.

**Pages:** Dashboard, ProgramBuilder (3-step wizard), ProgramView (week calendar), SessionDetail, ExerciseCatalog, ProfileBenchmarks

**State:** `builderStore` (wizard state + constraints form), `profileStore` (persisted: level, equipment, injuries, perf logs), `uiStore` (sidebar, filters)

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
- **Web**: `docs/frontend-design.md`.

Shared iOS style primitives live in `AppAnimationSettings.swift`
(`AppAnimation`, `AppHaptics`, `AppMetrics`, `appTabStyle()`) and
`AppSubTabs.swift`. Tab selection lives in `AppRouter.swift`, so one screen can
send the user to a section of another (§6.9) — route through its methods, never
by assigning tab state at the call site. Put shared behaviour inside the
component rather than in instructions at the call site.

## Workout Import

Activities reach the `workouts` table from five places: a manual `.fit`/`.xml`/`.json`
upload (`POST /api/workouts/parse`), the Strava OAuth sync, the Connect IQ watch app,
the iOS Apple Health relay, and the Garmin Connect webhook.

- **One FIT parser** — `src/fit_import.py`, extracted from the upload handler so the
  Garmin webhook can parse the same format. `parse_fit(stream, source=...)` is pure:
  no Flask, no DB.
- **Deterministic ids** — `src/workout_ids.py`. The formula is mirrored in
  `frontend/src/lib/importParsers.ts` and `ios/.../WorkoutID.swift`. **Do not change
  it**: `workout_matches.imported_workout_id` references the ids it produces.
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
- **Profile writes merge.** `PUT /api/profile` overwrites only the keys the body
  carries. It used to rebuild the blob, which is why every iOS save wiped
  `activeGoalId`.

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
  comparison needs the parked `feat/program-history` branch.
- **Capture.** `OutcomeLogger` (web) writes `ExercisePerformance.rounds /
  durationSec / distanceKm` — the keys the tracker always read and nothing
  wrote; `ExerciseRow` dispatches on `slot_type`, not `load.sets`. Bodyweight
  is the benchmark series `bodyweight_kg`, which turns a logged est-1RM into
  the ×BW standards. `PUT /api/health/sessions/<key>/notes` now exists — the
  iOS app had been posting notes into a phantom key — and fatigue is folded to
  1–5 at the boundary (iOS sends 1–10).
- `GET /api/progression/review` keeps its shape for iOS but takes its
  `exercise_findings` from the engine.

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
```

Run these after touching engine code or package data:

```bash
.venv/bin/python tools/validate_entities.py --all -q     # YAML vs docs/schemas (125 files)
.venv/bin/python tools/check_provenance.py               # no package leaks; 11 philosophies x 3 profiles
.venv/bin/python tools/check_provenance.py --coverage    # coverage gaps + authoring problems
.venv/bin/python tools/check_styles.py                   # every philosophy x style generates
.venv/bin/python test_provenance.py                      # source-policy rules
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
```

## Known Gaps / Next Work

- Non-blocking scope gaps remain: some packages declare a modality in `scope` that
  their own frameworks never prescribe and that has no archetype (e.g. `power` and
  `relative_strength` in several packages). `check_provenance.py --coverage` lists
  them. These do not affect generation — nothing schedules them — so they are
  authoring backlog rather than bugs.
