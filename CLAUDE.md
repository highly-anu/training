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
- **Production serves on four threads in one process** (Dockerfile: gunicorn
  `gthread --threads 4`, 256 MB machine). `src/db.get_conn()` is per thread;
  `api._bound_send` fails a send that makes no progress for 30 s and `api._gzip`
  compresses large JSON (never for a `ciqdev_` watch request). With the old single
  sync worker, a phone that stopped reading mid-download of `/user/program` held
  it until the 120 s kill, again and again overnight on 2026-10-12, and the
  watch's morning sync queued behind it (`test_worker_stalls.py`).
- **Reference routes are built into the image** (since 2026-10-27, `api.static_json`). The
  package-data routes (`/philosophies`, `/frameworks`, `/archetypes`, `/exercises`, the
  Explore documents, `/analytics/specs`, `/similarity`…) are pure functions of the YAML: the
  Docker build answers every one into `STATIC_BUILD_DIR` (`tools/build_static_cache.py` →
  `api.build_static`, JSON + gzip + ETag each; a route that fails fails the build), and the
  worker serves those bytes (a revisit is a 304). What the build did not answer — local dev,
  tests, an unusual query, everything after a successful authoring write — is built once per
  process, one at a time (`_BUILD_LOCK`). YAML is parsed with libyaml (`loader.safe_load`,
  10× the pure-Python parser, identical on every file — `test_static_cache.py`). Before, each
  request re-parsed the packages, and on 2026-10-27 Explore's concurrent calls held four copies
  at once: the worker passed 140 MB and was OOM-killed — the browser showed CORS errors and
  "timeout of 30000ms" because no answer came back at all. A new route that reads only
  package data takes `@static_json` and goes in `_static_paths`; one that reads the user must not.
- **The app runs beside its database** (Fly `cdg`, Supabase `aws-1-eu-west-3`, both
  Paris, since 2026-10-17). In `sjc` every query crossed the Atlantic (~150 ms), and
  Log ▸ Linking took 17 s; keep `primary_region` with the database. Reads that may
  nest in a `with get_conn()` block take `db.read_conn()` (reused per thread), never
  a fresh `new_conn()` — that is for transactions.
- **Accounts start on either client, by Apple.** The iOS app signs up and in
  through supabase-swift's `Auth` module (the project's only Swift package;
  session in the Keychain, refreshed by the SDK) with Sign in with Apple — a native
  ID token, so no secret, no email sent and no domain — and with password for
  web-made accounts. The web's "Continue with Apple" (`authStore.signInWithApple`)
  is Supabase's OAuth redirect through the Services ID
  `haerdsoft.TrainingCompanion.web`, whose domain and return URL are the Supabase
  project's own, not the web host. It needs a **client secret Apple caps at six
  months**: `scripts/apple_client_secret.py` signs one from the .p8 key (in
  1Password) for Supabase ▸ Apple ▸ Secret Key; when it lapses only the web's
  Apple sign-in stops. An emailed code waits for outgoing mail and passkeys for a
  permanent web domain (`docs/roadmap.md` item 11). `DELETE /api/account`
  (`src/account.py`) empties every `public` table with a `user_id` column,
  children first, in one transaction, then deletes the Supabase user with
  `SUPABASE_SERVICE_ROLE_KEY` (503 and nothing removed without it; 409 for
  `local-dev-user`).
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
│   ├── goals.py              # Builds the synthetic goal from one track of a philosophy
│   ├── phases.py             # Tracks, phases, kinds; start-phase resolution
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
│   ├── check_styles.py       # Every philosophy x track x phase generates on its framework
│   └── validate_entities.py  # YAML against docs/schemas/
├── data/
│   ├── packages/             # 11 self-contained philosophy packages
│   │   └── <philosophy_id>/
│   │       ├── philosophy.yaml      # beliefs, scope, tracks (its own phases),
│   │       │                        #   self_contained, borrows_from
│   │       ├── frameworks/          # the training styles it offers
│   │       ├── archetypes/          # session shapes, one subdir per modality
│   │       ├── exercises.yaml       # the movements it owns
│   │       ├── exercise_media.yaml  # demo links
│   │       └── level_seeds.yaml     # optional; per-level assumed knowledge
│   ├── commons/              # shared, owned by no philosophy
│   │   ├── phase_kinds.yaml         # the phase kinds the engine keys on
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
| GET | `/explore/links` | Explore's lineage: the movements (patterns exercises declare) and every link between neighbouring levels — philosophy→framework (by track and phase), framework→modality, modality→archetype, archetype→exercise (the selector's slot rule: `exercise_ids`, else the pattern filter, within the package), exercise→movement, and the exercise progression (`requires` ∪ `unlocks`); `equipment` — what each exercise and archetype needs as the generator reads it (all of it, open space free), for Explore ▸ Equipment, pinned to `selector._equipment_ok` and the archetype filter by `test_explore_links.py` (`src/explore_links.py`); static, built once |
| GET | `/philosophies/glance` | Every philosophy's comparable facts — weeks, days, minutes, levels, equipment, modality mix, intensity, what progress is and the standards, counts, and each track and phase in numbers (a template phase's seven days as modalities) — the same keys for every philosophy (`explore_philosophy.glance`; `glance` on the describe document too): Explore's landing cards and the page's header, and the shape a comparison will read; static |
| GET | `/philosophies/<id>/describe` | Explore ▸ Philosophies' page as the package writes it (`src/explore_philosophy.py`): each track's phases with their words, tests and the week from what builds it — a training contract's modules, the phase's `week_templates` days, else the framework's sessions per week — the modality mix (a track's weighted by phase weeks), the rules, inventions and open questions of `fidelity.yaml`, every session grouped (template category, contract module, modality, tests) with each slot's exercises by the selector's rule (`explore_links.slot_exercises`); static, built once per process. The web page (`components/explore/philosophy/`) only lays it out |
| GET | `/analytics/vocabulary` | the analytics words: primitives, what each needs logged, and the `terms` (`vocabulary.TERMS`: load, recovery, completion, intensity, mix…) for the phone's About sections; static, no sign-in |
| GET | `/analytics/development?from=&to=&fresh=1` | development across programs — blocks, lifts and currencies across the span, load by block, standards over time (`src/analytics/development.py`); last 365 days by default, cached on a digest |
| GET | `/frameworks` | `Framework[]` |
| GET | `/exercises` | `Exercise[]` (198 total) |
| GET | `/standards?sex=` | `BenchmarkStandard[]` (48; female or male tables, each with `categoryName`, `standardsText`, `inputHint`); `/benchmarks` is the old name, kept for installed builds |
| GET | `/standards/results` | the athlete's results: per standard `current` (latest) and `best`, each placed on its ladder with its text, and every entry with its day, source, note and block; `blocks`; bodyweight with its entries (`src/standards.py`) |
| POST | `/standards/results` | one result: typed `text` ("4:58"), a `value`, or for a ×BW standard `kg` + `reps` (÷ the bodyweight that day; Epley past one rep); `loggedOn` (the athlete's day, today by default), `note`. 422 when it cannot be a result, 503 when the write fails. `/health/performance` is the old name |
| PATCH / DELETE | `/standards/results/<id>` | correct one result (value, day, note — a load is re-read on its new day's bodyweight) or delete one; 404 when it is not the athlete's |
| GET | `/standards/suggestions` | results logged sessions suggest, pending, each in the server's words — value, level, what it would follow, `isBest`, `replacesText`, the session's name (`src/standard_results.py`) |
| POST | `/standards/suggestions/<id>/confirm\|dismiss\|reopen` | save one as a result (the body may correct it: `text`, `value`, `kg`), "Not a test", or undo that; 404 when it is not the athlete's or not in a state that allows it, 503 when the write fails |
| GET | `/modalities` | `Modality[]` |
| GET | `/archetypes` | `Archetype[]` |
| GET | `/ontology` | Lightweight projection with counts |
| GET | `/constraints/equipment-profiles` | `EquipmentProfile[]` |
| GET | `/constraints/injury-flags` | `InjuryFlag[]` |
| POST | `/programs/generate` | `GeneratedProgram` (`week_in_program` numbers a partial regenerate's tail from the kept head's length + 1) |
| POST | `/sessions/generate` | `Session` (single session regeneration). `add: true`: a session the athlete adds on the fly to today or a later day — any package (a borrowed one carries `provenance`), named workouts included, the ones that fit as written within the session's time, one at random (`current_archetype_id` asks for another); never refused by a training contract or a template day; the answer is marked `added` |
| POST | `/dev/constraint-impact` | For the Dev Lab (no screen calls it yet): generate's body run against a reference with nothing in the way (the packages' equipment, no injuries, the framework's level, a training contract's mastery and bell pair for that level) and once per constraint lifted alone (equipment, injury, level, proficiency); every changed session or slot with what was planned, its `causes`, why, `knock_on` when an earlier direct change moved the rotation, and the equipment that would restore the most changes (`src/constraint_impact.py`). A refused request (200, no weeks) answers `feasible: false` and `unblocked_by`: the one constraint, or the framework's ideal days and minutes, that alone lets it generate, else `combined`; a reference that cannot generate answers `reference_generates: false`. At most 12 weeks and seven generations; local dev or `AUTHORING_ENABLED` only |
| GET | `/dev/portability` | For Dev Lab ▸ Model Interactions: per package its engine shape per track, the files it carries, the records it still needs outside its folder (scorecard, coverage, status, golden hashes, dossier), any id the commons do not define, and ids two packages declare (which copy the loader keeps); with `tools/portability_gaps.json`, what no package can bring in its folder yet, each gap anchored in the code (`src/portability.py`, `test_portability.py`). Local dev or `AUTHORING_ENABLED` only |
| POST | `/exercises/substitute` | `{alternatives: [{assignment, score, reasons}]}` — ranked swaps for one slot, selector-scored, loads for the week; 422 when nothing fits |
| POST | `/programs/impact` | The preview's Held back: `/dev/constraint-impact`'s answer for any signed-in athlete (`api._constraint_impact`, shared); ≤ 7 generations, 12 weeks; one run in the process at a time and one per athlete — a taken gate answers 429 `busy` at once, never waiting (the clients retry); small answers cached ten minutes per body and day. Clients send the draft's own first phase and length (`impactParams`, `impactRequest(for:)`), never its event date |
| POST | `/programs/constraint-change` | Does a profile change change the program? The regenerate body (`constraints` = the profile's) + `baseline_constraints` (the program's): both generated, diffed by `constraint_impact.diff_programs` (exercises *and* each slot's numbers, so a level change that moves only loads is affected) → `{affected, sessions, first_week_number, changes, program?}` (`program`, the new tail, only when affected); same gate as impact, never cached on the server |
| PATCH | `/user/program/constraints` | Adopt an unaffected change: merges `equipment`, `training_level`, `injury_flags`, `days_per_week` (+ `custom_injury_flags`) into the stored program's constraints under `baseRevision` (409 `stale_revision`); mints no version |
| POST | `/programs/adjust` | applies one `suggest_adjustments` entry (`hold_load`, `reduce_volume_10pct`, `early_deload`, `increase_increment`) to the stored weeks from a week onward under the revision check; returns the saved envelope; `rebuild_habit` is 422 (advice) |
| GET/POST/DELETE | `/devices`, `/devices/claim`, `/devices/<token>` | Connect IQ watch pairing: list, claim a code, revoke by the display id the list shows (web: Profile ▸ Connections ▸ Devices; iOS: Settings) |
| POST | `/health/wellness` | one day's watch reading into `daily_wellness`; 422 invalid, 503 on a failed write (the watch retries), 200 `stored: false` when the Garmin toggle is off |
| GET | `/health/wellness/latest` | the newest watch reading, with the model named from its part number |
| GET | `/health/workouts/<id>` | one workout with its series and `analysis` — zones, TRIMP, training effect, recovery, decoupling, best efforts (`src/analytics/workout_analysis.py`) |
| GET | `/health/linking?today=&dismissed=` | Log ▸ Linking's day cards for the phone — workouts beside each day's planned sessions across programs, links, same-day suggestions (`src/linking.py`, the server's copy of `lib/linking.ts`; change both) |
| GET | `/health/load/summary?period=&today=` | Analytics ▸ Load's totals vs the prior period, modality/activity mix, 12-week consistency, zone minutes, 28-day focus (`src/analytics/load_summary.py`) |

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

**Added sessions are extras.** An athlete may add a session on the fly to today or a later
day (web: Today's rest card and the calendar's rest days, `ReplaceSessionSheet` in add mode;
iOS: the long-press menu on Today's cards and the calendar's day rows, `Views/SessionActions.swift`
— which also holds Move, Replace and Remove, so no card or detail screen shows them —
`ReplaceWorkoutSheet` in add mode; → `programStore.addSession` / `AppState.addSession` →
the revision-checked PUT). It is marked `added`, appended after the day's others (indices
already on the day keep their place), and only an added session can be removed. It counts
**only once done** — logged complete or matched: `analytics.context.Context.sessions` (and
through it the scorecard, completion and every primitive), the watch's week counts
(`_watch_progress`), Today's week-done and the week dots leave an undone one out, and
`phase_summary` and a program's own standards never include one. Adding to today or later
keeps the block (`record_version` → `continued`); a past day would switch it, so neither
client offers one (`test_added_sessions.py`).

**A generated program is a draft until it is started** (Program ▸ Preview, since 2026-10-20).
The builder's last step generates (`useGenerateDraft`, never a store write) and opens
`/program/preview` (`pages/ProgramPreview.tsx`, draft in the in-memory `previewStore`):
Overview · Calendar · Held back. Held back is `/programs/impact` — what equipment, injuries,
level and proficiency change against the program with nothing in the way, and "Add barbell ·
restores 33" actions that re-preview; a refused draft shows what alone would let it build.
Adjust (equipment, injuries, level) re-previews; swaps and replaced sessions edit the draft
only (the swap sheets' `onPick` / `onReplace`). "Start this program" asks before replacing an
active program, offers the draft's extra equipment to the profile, and saves through
`commitProgram` (the revision-checked PUT, with `keepDaysBehind`: a rebuild of the same block
keeps the days already behind the athlete, as generate's persist branch does — the PUT answers
`keptDays` and the client reads the program again); an infeasible draft never commits, and on
iOS the draft becomes the program only once the save succeeded. The held-back count is the
server's (`held_back` on every generate, `src/blockers.held_back`, never stored). Slots say why
they are empty (`blocked_by`: `{cause, exercise, needs | flags | requires}`, from
`selector._explain_unfilled`'s lifted run, no extra generation), sessions why they stand in
(`substitution_cause`) or run scaled (`equipment_scaled`); `lib/heldBack.ts` words them for
the session card and sheet. **The Profile offers a regenerate only when it changes the
program**: `RegenerateFromWeekBanner` debounces the profile, asks `/programs/constraint-change`,
adopts an unaffected change (PATCH, "Your program doesn't change with these settings"), and
for an affected one says how many sessions from which week, with Preview changes
(`?mode=regenerate`, the changed sessions marked) and Apply (`commitRegeneratedTail`; an
infeasible tail is refused, it used to splice `weeks: []` over the rest). The phone
has the same (`Views/ProgramPreviewView.swift`, design-system §6.39; the offer card §6.17):
the builder and the settings sheet's full regenerate preview a `persist: false` draft
(nothing in the app persists a generate any more), and `RegenerateOfferCard` asks
`AppState.checkConstraintChange`, adopts or offers. `/constraint-change` answers
`comparable: false` (always `affected`) when the program's own constraints no longer
build it, so nothing is adopted unchecked. Debug builds open the preview on launch with
`SIMCTL_CHILD_TC_PREVIEW=<philosophy id>` (+ `TC_PREVIEW_TAB=heldback`).

## Frontend (frontend/)

React 19 + Vite 8 + TypeScript, Tailwind CSS v4, shadcn/ui, Framer Motion, TanStack Query, Zustand, Recharts, MSW v2, React Router v7.

**Pages (grouped sidebar, `components/layout/Sidebar.tsx`):** the same items and sections,
in the same order, as the iOS tabs (`docs/information-architecture.md` §2 — rename or move
a section on both clients in one change). Train — Today `/`
(`pages/Dashboard.tsx`, no sub-tabs, side panel), Program `/program` (Overview · Calendar ·
History via `?tab=`, Overview first since 2026-10-17; the builder is the flow `/program/new`), Analytics `/analytics`
(Progress · Blocks · Load · Recovery via `?tab=`; `development` aliases Blocks and `program`
Progress — Program and Progress merged on 2026-10-23, `components/analytics/ProgressTab.tsx`;
before Log since 2026-10-16, which folded the old Insight group into Train), Log `/log` (Activity ·
Linking, Import as a sheet; Activity is recorded workouts and logged sessions in one
list with an All · Workouts · Sessions filter (`?show=`; the old `?tab=workouts|sessions`
land on it), Workouts and Sessions until 2026-10-20 — `components/log/ActivityTab.tsx`,
`lib/logSessions.mergeLogEntries`, iOS `LogActivityTab` + `WorkoutListFilter.entries`; Linking is one card per day, workouts beside
sessions, suggestions scored within the day only, drag a workout onto any session to
link across days — `lib/linking.ts`, `components/log/LinkingTab.tsx`; `?tab=suggestions`
aliases it. Earlier programs' days come from `GET /programs/planned-sessions` back to the
oldest workout, and a date an earlier program has rows on is that program's day, as in
the server matcher's index. Every link sends `sessionUid` (the server keeps a given uid
only if it is planned for the athlete, else resolves the key on the workout's date, which
finds nothing across days), and one into an earlier program skips the completion
side effects, whose key would tick this program's session of that name; `/log/:workoutId` is WorkoutDetail). Library — Explore
`/explore` (Philosophies · Frameworks · Modalities · Archetypes · Exercises · Movements · Equipment · Standards,
with "Build with this" CTAs into the builder). You — Profile `/profile` (Athlete, with the
heart-rate zones · Equipment · Injuries · Schedule · Benchmarks; `heartrate` aliases Athlete)
and Settings `/settings` (Connections · Appearance · Account · Developer in dev builds and for `dev` users). The Garmin and Strava OAuth callbacks land on
`/profile?tab=connections`, which redirects to `/settings?tab=connections` with the query
intact — the server keeps naming the old URL because `FRONTEND_URL` may pin a deployment
that predates Settings. Dev Lab `/dev` exists in dev
builds and, in production, for users whose Supabase `app_metadata.roles` holds `dev`
(`featureFlags.useDevLabEnabled`; set it with the admin API and the service-role key — the
user cannot write app_metadata — and it takes effect at their next token refresh). It is
lazy-loaded, and the authoring routes it calls stay behind the server's own gate. `/pair?code=…` (`pages/PairDevice.tsx`) is the
watch QR's target, outside the sidebar: it claims on a tap, never on load, and sign-in
returns to it (`ProtectedRoute` passes the path, `lib/returnPath.safeReturnPath` keeps
it in-app). Old paths (`/builder`, `/import`, `/bio`,
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
Philosophy → Tracks → Phases → Frameworks → Modalities → Archetypes → Exercises → Progression → Constraints → Program
```

1. **Philosophy** — training methodology; declares one or more tracks
2. **Tracks and phases** — a track is one way to follow the philosophy, an ordered list of its own phases; each phase names its framework and a shared kind
3. **Synthetic goal** — built from one track (its phases become `phase_sequence`) + priorities; several tracks compose one program (*Compositions*)
4. **Scheduler** — maps priorities + framework → session slots per day (recovery-aware)
5. **Selector** — picks best archetype per slot; fills archetype slots with exercises (injury/equipment/level filtered)
6. **Progression** — calculates load prescription per slot type (linear_load, rpe_autoregulation, time_to_task, distance, density)
7. **Validator** — pre-flight checks on equipment, days, session time, injury conflicts, phase validity
8. **API** — transforms integer day keys → day names; wraps in `{ goal, constraints, validation, weeks, volume_summary }`

## Standards

**One name.** Everything a person reads says *standard* (the ladder), *result* (one dated
value), *best* (the best result ever), *est.* (derived from training sets). Stored and
wire identifiers keep *benchmark* — `performance_logs.benchmark_id`, `benchmarkId`, the
`benchmark_level` primitive, `data/benchmarks/`, `/api/benchmarks` — because renaming them
would break stored rows and installed builds. "Benchmark workouts" is only the CrossFit
group's name.

- **The server places every value.** `benchmarks_data.level_of` (the level; `None` is
  below entry), `format_value` ("4:58", "3:20:00", "1.62×BW", "45 s") and `parse_input`
  (its inverse, so a field takes what it shows) are the only copies; no client computes a
  level or formats a result. Thresholds go out as `standardsText`, results as `valueText`.
- **One ladder, coloured by modality.** Every standard's `domain` is a modality id, and
  web `components/standards/StandardLadder.tsx` / iOS `Views/StandardLadder.swift` fill
  the rungs in that modality's colour; a level has no colour of its own (frontend-design
  §8.1, design-system §6.31). Traffic-light colours only for a declared target.
- **Current is the latest, best the best.** `src/standards.summarise`; every result is kept,
  and each can be corrected or deleted on its own (Standard detail on both clients: web
  `components/standards/StandardDetailSheet.tsx` at `/profile?tab=standards&standard=<id>`,
  iOS `Views/StandardDetailSheet.swift`, deep link `profile?section=standards&standard=<id>`).
- **A result counts for the athlete's day** — `performance_logs.logged_on`
  (`migrations/011_standard_results.sql`, lazily added by `src/standards_store.py`, which
  raises on a failed write), never `logged_at::date`; a row from before 011 reads its
  timestamp's day in the profile timezone (`standards.day_of`) until
  `scripts/backfill_performance_logged_on.py` fills it. Run 011 and the backfill after
  `scripts/backup_prod.sh`. Each result is placed in the block in force that day (its test
  session's when it has a `session_uid`). `analytics.benchmarks.standing` is the one reading
  of a standard (latest result, else the estimate from logged sets) the program ladder and
  `benchmark_level` share.
- **Only a program's own standards lead.** `analytics.benchmarks.program_standards(goal,
  weeks, specs)` — measured by a test the program schedules (a slot's or session's
  `standard`: `tested`), or estimated from a lift it schedules (the standard's
  `derived_from`: `linked`) — is the one answer for Progress (the only rows it sends,
  each `primary`), Profile ▸ Standards' *This program* (`programStandards` on
  `/standards/results`) and Blocks (`inCurrentProgram`, sorted first). A package's
  `analytics.yaml` naming a standard (`declared`) is a label beside those, never enough
  alone (until 2026-10-23 it was, so Starting Strength led with the power clean before
  any was scheduled). Same domain, cites the philosophy or merely has a result: Profile's
  *Your results*; "More standards" is gone. `validate_entities` fails a `derived_from` id
  no package has (three did). A result alone used to make a standard primary. Progress rows carry `atBlockStart`,
  `levelChange` and `blockHistory` (the block's results, its starting standing first).
- **The Cell maps by its own words:** II entry, III intermediate, IV advanced, V elite
  (until 2026-10-17 I–IV, which made Cell's "Advanced" the app's elite).
- Cached analytics documents key on `api._ANALYTICS_SHAPE` and on every result's
  value and date (`standards.digest_key`), not on how many there are.
- **Programs test their standards** (`src/standard_tests.py`). A package marks an archetype
  `test:` and points each scored slot at a commons standard (`standard: <id>` or
  `{id, result}`); a phase's `tests:` says when (`week: first|last|<n>` or `every: <n>`, a
  rotation of `archetypes:`, `in_place_of`, `on_deload`). The generator
  (`_plan_week_tests`) puts the test in place of one session of the week — same day, same
  count — when the athlete can do it as written (level, equipment, the time within 1.1×,
  every movement of the scored piece fillable), else the week records `tests_skipped` with
  why. The session it stands in for is still selected, so the rest of the program is exactly
  what it would have been, and recorded as `test.instead_of` (archetype, minutes, intensity
  minutes) so fidelity and the phase summary count the test as that session. A scored slot
  is prescribed as written (`protocol_load`: no ramp, level, phase or deload scaling;
  `load.test`); adjust and swap leave it alone; selection never picks a test-only
  archetype. Sessions carry `test`, scored assignments `standard` (outside `slot`, so it
  survives storage); the skeleton hash ignores both. Tests today: Wildman's pentathlon
  (competition, last week), Horsemen's PT test (start of strength, end of maintenance);
  the phase `tests:` path on the modality scheduler is tested on `block_fixture` (old
  Gym Jones, `test_packages/`, staged by `fixture_packages.use()`, never shipped), whose
  2 km row tests the first week of accumulation and the last of realization. CrossFit's
  Girls are `test: {selectable: true}` workouts in its template pools: picked as any
  other day's workout, their scored slot still carries its standard, and a test's
  written `load` reaches its prescription (`protocol_load`). A standard's `derived_from` (its YAML) names the
  lifts whose sets estimate it. Both clients badge a test session, list its standards with
  the number to beat, and Today says "Test today".
- **Sessions suggest results; the athlete confirms** (`src/standard_results.py`). Both
  session-log PUTs store the log (`health_store.upsert_session_log` now returns the merged
  row, and the route answers **503** when the write fails — it used to say "saved"), then
  read it: a test slot's logged outcome (`read_result` per result kind — a for-time clock,
  rounds with the partial round kept, reps summed over a timed slot, the longest hold) and
  a completed single on a `derived_from` lift that beats the current result (÷ the
  bodyweight that day) become rows in `standard_result_suggestions`
  (`migrations/012_standard_suggestions.sql`, lazily created by `standards_store`). A
  pending suggestion is **never a result** — the `workout_match_suggestions` lesson —
  until `POST /standards/suggestions/<id>/confirm` writes it to `performance_logs` (source
  `session`, or `garmin` / `apple_watch` for a watch-logged session; the test's
  `session_uid`) in one transaction. A re-logged value reopens a confirmed suggestion
  (`replacesText`; the confirm corrects that result); a dismissal sticks; deleting a
  confirmed result dismisses its suggestion. The gate is cheap: only a log of a test
  archetype (`planned_sessions.archetype_id`) or of a derived lift loads a snapshot. A
  day-level web key ("3-Monday") finds the day's test through `planned_rows_for_key`;
  Garmin's name-keyed logs are matched by id → name → case-folded name → slot role, never
  a name two slots share. The PUT answers `standards: {pending, confirmed, skipped,
  problems, error}`, and takes `standardResults: {id: {decision: save|dismiss, text?}}`
  — honoured only for a standard that session tests, so the device-token route reaches no
  further. UI: one row on both clients (web `components/standards/SuggestionRow.tsx`, iOS
  `Views/StandardSuggestionRow.swift`, design-system §6.34) — Save result · Correct · Not a
  test — on Profile ▸ Standards' *To confirm*, Today and under the test standard. A
  for-time slot logs a clock (`time`, m:ss) on both clients, never prefilled from its cap,
  and a test slot asks first for its standard's number (`outcomeFieldsFor(…, standard)`,
  `SessionLogging.outcomeFields(…, standardResult:)`). Both watches show a test step's
  best and next-level number and ask Save results / Not a test at the end (see *Watch
  Screens*).
- **Imported runs suggest run results** (`standard_results.after_workouts_import`, after
  `upsert_workouts` on the FIT upload, `POST /health/workouts` and the Garmin worker). A
  standard's YAML `best_effort` (`km`, `label`, `sports`) names its distance — the 1, 3
  and 5-mile runs today. A workout whose track carries **recorded speed** (FIT: an upload
  or Garmin Connect; never positions alone — GPS jitter would invent records) is read by
  `workout_analysis.fastest_seconds`, which, unlike the workout screen's `best_efforts`
  (windows may fall 5 % short), covers the whole distance. Suggested (`origin:
  best_effort`, `source: workout`, keyed on the canonical workout) when the run is
  matched to a session testing that standard — never overwriting what was logged for it
  (`onlyNew`) — or when it beats the best on a standard the athlete tracks (has a result,
  or is this program's: `current_program_standards`). Apple Health and live watch runs
  carry no speed; the Standard detail says so on both clients.
- `test_standards.py`, `test_standard_results_sql.py` (a production-shaped table in a scratch
  database), `test_standard_tests.py`, `test_standard_suggestions.py` (pure, then the routes
  on a scratch database); plan and later phases: `docs/roadmap.md` item 12.

## Key Engine Behaviors

- **Injury flags**: excluded_movement_patterns blocks exercises by movement pattern; contraindicated_with blocks specific exercises. Slots whose required pattern is fully excluded show as `injury_skip` (not an error).
- **Session time cap**: `_time_to_task` progression is capped at `session_time_minutes` — Zone 2 duration never exceeds the athlete's session limit even in build phase.
- **Package provenance**: a program may only use its philosophy's own package, plus any package that philosophy declares in `borrows_from` (`src/provenance.py`). Enforcement is per philosophy via `self_contained: true` — all 11 are on. `api.py` and `generator.py` share one `SourcePolicy`, so validation and generation can never check different libraries. Borrowed sessions carry a `provenance` tag and are badged "via X" in the UI.
- **Coverage gaps, not substitutions**: when a package cannot fill a slot, the slot is left empty and marked `coverage_gap` (the same way `injury_skip` marks an injury-blocked slot) rather than filled from another philosophy. Programs carry a `coverage_report` listing unfilled sessions, unfilled slots and borrowed sessions; `validate()` warns `PACKAGE_COVERAGE_GAP` per uncovered modality and only errors when every top-2 priority is uncoverable.
- **Archetype fallback**: sessions whose modality has no valid archetype for the phase fall back within the allowed packages (equipment filter relaxed first, then `aerobic_base` → `durability` → `mobility`). A cross-modality swap is recorded (since 2026-10-16; it used to change the modality and leave no trace): the session carries `substituted_for`, the compromises say it once per modality, `coverage_report.substituted_sessions` lists each, and when the athlete's level is the cause (no archetype for it written for that level) generate adds a `LEVEL_COVERAGE_GAP` warning naming the substitute (`validator.check_level_coverage`, run on what was actually substituted). `check_provenance.py --coverage` lists the static level/phase gaps (reported, not failed): all novice — Horsemen, Marcus Filly, Uphill, Wildman.
- **Prerequisites**: `requires` is resolved transitively — a requirement is met if it is a concept the training level knows or an exercise that is itself unlocked. A package may declare `level_seeds.yaml` for concepts its own athletes arrive with.
- **Training contracts space their programs** (`training_contract._spacing`, since
  2026-10-26): of the placements that close a test week and fit the optional work,
  the one with the fewest same-modality days back to back, then the fewest
  same-modality neighbours among the training days (wrapping into next week), then
  each module's sessions furthest apart. The first valid placement used to win, so
  Wildman's General Practice ran swing, swing, press, press; it now runs his example
  week (swings Mon/Thu, clean and press Wed/Sat).
- **Regional recovery** (`src/recovery_regions.py`, `data/commons/recovery_regions.yaml`,
  since 2026-10-26): where a session's work lands — lower, upper push, upper pull, trunk,
  cardio — derived, never tagged: each exercise's movement patterns weighted by region,
  each working slot's intensity, the modality's recovery cost (an archetype whose slots
  name no exercise may write `regional_load`; only `bjj_class` does). 0.5 and over is
  heavy. It is a soft rule only where the app chooses: the archetype picker scores −2 per
  region a session 24 h earlier loaded heavily, −1 at 48 h, capped at −4
  (`select_archetype`'s `regional` term, in the Dev Lab trace), and a contract's placement
  ranks it after the spacing terms. Fidelity reads a region loaded heavily on consecutive
  days as `region_back_to_back` (info, never gated). A source's own week is never
  rearranged for it. **Where scoring runs at all:** every shipped package places its
  sessions by its own `week_templates` or a training contract, so the archetype picker
  (and the scheduler) run only for blends a contract philosophy leads, for packages
  without either, and for a single-session regenerate.
- **Exercise scoring**: prefers exercises with defined movement_patterns (+0.5) and forward-unlocking exercises (+0.5); penalizes recently used (-2 per recent use). AMRAP/for_time slots exclude `mobility` and `rehab` category exercises.
- **Deload**: every `deload_protocol.frequency_weeks` (a framework without a protocol never
  deloads on schedule) or when `fatigue_state: overreached`; `volume_reduction_pct` is the
  share of volume the week **keeps**. In a kind that is itself the deload (taper) it is the
  total, not a second cut on top of the kind's multiplier. A training contract's module
  may run its own cycle instead (`periods`: weeks, a rotation of its variants, `deload`;
  `training_contract.period_of`, `module_deload`): BJJ's strength is StrengthLog's
  program — six weeks of strength, a deload week of its own workouts run as written, five
  of power, repeating — and the classes never deload on a schedule. Uphill's aerobic
  modules ramp by `weekly_volume` (three build weeks of 10 %, a recovery week at half, the
  ramp holding from Specific on); its modules run in named `phases`, and in a phase a
  module may sit beside another (`adjacent_to_by_phase`: Specific's back-to-back long
  days). A period's `note` leads every block's note in its weeks (Persist's Bridge week:
  RPE 6–7, the work kept). Optional modules are offered by the last build week's minutes,
  so a deload never adds a session (BJJ's conditioning once appeared in week 7 alone).
- **Theory fidelity** (`src/fidelity.py`, `tools/check_fidelity.py`): a generated program
  is read against its package — `sessions_per_week`, `intensity_distribution`,
  `deload_protocol`, archetype level and phase, recovery windows, equipment and injuries,
  and a phase's optional `checks:` block in `philosophy.yaml` (the prose's numbers made
  testable; the generator never reads it). Three phase keys the generator does read:
  `exclude_exercises` (a lift the method has not reached), `rotate_main_lifts`, and `tests`
  (when the phase tests its standards — see *Standards*). Main-lift
  slots (`selector.is_main_lift_slot`) keep one exercise per phase unless a phase rotates;
  ties go to the least recently used, then first authored, archetype or exercise. An empty
  slot always says why (`injury_skip`, `equipment_gap`, `gap_reason`), and an injury flag's
  `modified_exercises` substitute fills it when both ids resolve.
- **Phase summary** (`src/phase_summary.py`): `currentProgram.phase_summary` — each phase's
  weekly shape, minutes, intensity, archetypes/exercises marked new or continued, dropped
  ones, lifts and plain `changes` lines — is built on generate and on every
  `GET /user/program`, and `db.save_user_program` strips it. `PUT /user/program` answers with
  `phaseSummary` of the weeks it saved and `POST /programs/adjust` returns its envelope with
  one, so an edit never leaves a stale summary; both clients apply it. Program ▸ Overview on
  both clients lays it out (web `program/PhaseChanges.tsx`, iOS `PhaseSummaryModels.swift`).
- **Single-session routes take the week's phase.** `POST /sessions/generate` and
  `/exercises/substitute` accept `phase_id` + `framework_id` (both clients send them) and
  apply that phase's `exclude_exercises` and the framework's deload share
  (`api._week_phase_rules`, `phases.phase_rules`); without them they behave as before.
- **Weeks the source writes day by day** (`src/week_template.py`, since 2026-10-19). A
  phase may declare `week_templates` (seven days per week of the phase: `rest`, a day
  category, several, or `{categories, warm_up, light}`) and `drop_order` (which days go with
  fewer training days); its framework declares `categories` — pools of named-workout
  archetypes (`pool_only: true`, never picked by modality) with a `fallback` order — and a
  `warm_up_category`. Each day takes the next workout of its pool the athlete can do **as
  written** (level, every item of `required_equipment` — open space assumed — every movement
  fillable, the day's minutes), passing a workout used in the last week of picks while another
  fits; the warm-up opens it and both become one session (`category`, `pieces`, `warm_up` on
  the session). Days keep their template positions (the source's rest day), honouring
  preferred and forced-rest days. Loads are `progression_model: as_written`: the slot's `load`
  text ("75% of today's 1RM", "24 kg (53 lb)", "1.25x bodyweight"), no ramp, level, phase or
  deload scaling. The slot that carries a for-time or AMRAP piece's rounds or minutes is a
  movement too: its own `reps_per_round` or `distance_m` reaches the load
  (`progression._parent_count`; Cindy's 5 pull-ups); a count that changes round by round
  is the slot's `rep_scheme` (Fran's [21, 15, 9], `progression.round_count`), shown as the
  source writes it by every client and round by round on both watches. A slot's `exercise_filter.ordered` takes the written movement first and the
  source's declared substitutes after it; a workout's movements are `named_only` exercises,
  so adding them never changes what an open slot picks. Rotation resumes where a regenerate's
  first week stands (the elapsed template weeks are replayed, `prior_entries`); a test may
  take a templated day nothing fitted; a program in which nothing fits is `TEMPLATE_UNFILLED`.
  Long-day categories (`long_day`) take the athlete's longest days. A category's `advice`
  (per level when it differs, `advice_for`) closes each piece's first movement's note: the
  method's recommendation where the source writes no pass mark — ATG's ladders, Ido's next
  version, Built to Move's retests — never acted on, as a contract module's `advice`. A composed slot's role
  names its source (`warm_up__<id>__<role>`, `<id>__<role>`; `source_slot`) so a swap finds
  it; `POST /sessions/generate` on a templated framework picks another workout of the day's
  category (`category`, else inferred from the modality; `regenerate_day`). Fidelity reads a templated phase
  against its template (`_check_template`), not `sessions_per_week`. Horsemen's 4-Month Macro
  uses it (~190 named workouts, the PT test on the first and last hard job-specific days), and
  CrossFit (since 2026-10-21): Glassman's three-on, one-off cycle laid on twelve weeks, its day
  types (one element, couplets, triplets) as pools of Table 4's workouts, the Girls and the 2005
  workouts read; Gym Jones (same day): Operator Fitness and Soldier of Steel, months the
  source writes day by day, each day a one-workout pool; ATG (2026-10-22): Ben Patrick's
  ATG Zero, Program #2 and Knee Ability Pro weeks, each workout its own pool; Kelly
  Starrett (same day): the Built to Move 21-Day Challenge, its days one pool taken in order;
  and Ido Portal (same day): the Floreio Routines, one pool whose versions the athlete's
  level picks (`training_levels`). No shipped package runs on the modality scheduler any
  more; its tests use `test_packages/block_fixture` (`test_week_template.py`).
- **A training contract's progress is earned by confirmed sessions.** A module advances
  (`confirmed_state`, read when the program is regenerated) only on a completed session
  whose progressing exercises are logged clean at or below the module's RPE. A
  watch-recorded or linked workout logs no per-exercise outcome, so both clients ask "done
  as written?" on a finished contract session — web `session/ModuleProgress.tsx`, iOS
  `SessionDetailView` Progress — and `POST /health/sessions/<key>/confirm` {clean, rpe}
  writes each progressing exercise's prescribed rounds or seconds with the answer, merged
  into the log (`training_contract.confirmation_outcomes`). Until then the plan forecasts
  each exposure as clean; a regenerate starts every unconfirmed cycle again.
- **Cadence, loads and recovery live in YAML.** A framework's `cadence_options`
  (keyed by days per week, several patterns rotating week to week) is the only source of
  day patterns; an exercise's `starting_load_kg` / `weekly_increment_kg` the only source of
  loads (`progression._DEFAULT_INCREMENT_KG` is the sole code default). A framework may
  declare `recovery.allow_consecutive: [[a, b], …]` (+ `phases`) to let a modality pair sit
  on back-to-back days despite the recovery windows — Uphill's specific phase does, for
  its two ME long days (`scheduler.consecutive_allowances`). The windows
  (`scheduler.recovery_window`: a modality's `recovery_hours_min` from itself; between two
  high-cost modalities the larger of theirs, never under 48 h; fidelity audits by the same
  function) are checked
  against days before **and after** (modalities are placed hardest first, not in day
  order) and against the previous week's last days (`scheduler._neighbours`, since
  2026-10-26); a session the week has no safe day for is still placed and the compromises
  say so. A day's sessions are ordered by their modalities' `session_position` (first,
  any/standalone, last). Only weeks the scheduler builds are checked: a source's own week
  (`week_templates`) and a training contract place their sessions themselves.
- **Compositions: several tracks, one program** (`src/composition.py`, since 2026-10-27).
  `POST /programs/generate` takes `lanes: [{philosophy_id, track_id?, weight, start_phase?,
  periodization_week?}]` — tracks of different philosophies or two of one; the old blend shape
  (`philosophy_ids` + weights + one `track_id`) is read the same way, the named track its
  owner's, the others the level's. One lane is the single-track request, untouched
  (`test_single_lane_golden.py` hashes 131 programs). Every track runs its own phases on its
  own engine — a contract its modules, spacing and earned state (`training_contract.start`,
  week by week), a template its named workouts (`generator.start`). Each week the contracts
  place first (lightest first, on the days each keeps: `reserve_days`, a contract the most
  evenly spaced), then the templates, each into the minutes the others left (`day_room`);
  a placement avoids another track's days and a body region it loads heavily (`others`). A
  week that cannot fit gives way cheapest first, for the whole program, and each cut is a
  compromise naming the track: optional work, one weekly session of the module with the
  fewest minutes, the weekly volume (a uniform scale, so ramps keep their shape); a cut
  that breaks a track's own phase rules is undone and never made again; a template none of
  whose days filled gets another day; a track that cannot run alone is refused as such at
  once. Weeks carry `lanes` (each track's phase, framework, deload — the week's own fields
  are the lead track's, `is_deload` only when every track deloads); sessions their
  `lane_key`, `phase`, `phase_id`, `framework`; the program `composition` (shares, kept
  days, cuts, each contract's id and module state) and, on read, `lane_phase_summary`.
  Contract state carries on per track from a stored composition or a stored one-track
  program (`composition.lane_view`); swaps and session regenerates are refused only on a
  contract track's session (`_stored_contract(lane_key, package)`). Both clients build them
  (web `LanePicker`, `CompositionTracks`, `TrackBadge`; iOS `LaneSections`,
  `CompositionTracks`, `TrackBadge`) and regenerate every track from its own phase.
- **Framework expectations**: Every framework defines required `expectations` (min/ideal weeks, days/week, session minutes, split-day support). UI derives "Ideal for this goal" banners from framework expectations (or weighted blend when combining frameworks). Philosophy-specific, not goal-generic.
- **Philosophies own their phases** (`src/phases.py`). `philosophy.yaml` declares
  `tracks`; each track is an ordered list of the philosophy's own phases — id, name,
  `kind`, weeks, the `framework_id` that builds its weeks, and its words (`focus`,
  `description`, `adaptations`, `intensity`, `repeatable`). A **framework** is how a
  week is built; a **phase** is a block of weeks. Uphill runs one track of four
  phases on four frameworks; Wildman offers two tracks (General Practice, Pentathlon
  Prep); single-block methods have one repeatable phase. There is no default
  sequence: a philosophy without tracks cannot become a goal.
  - **The engine reads the kind, never the words.** `data/commons/phase_kinds.yaml`
    is the vocabulary: archetype `applicable_phases`, the time/distance multipliers,
    cadence spreading, the taper max-effort filter and the analytics deload reading
    all key on it. Phase text reaches the clients only from the program's own goal
    (`goal.phase_sequence`, `goal.track`); the web's overview used to describe every
    phase from one map written from Uphill and Gym Jones.
  - **Every week runs its phase's framework.** Weeks carry `phase` (the kind),
    `phase_id`, `phase_name`, `track_id` and `framework`. `phases.week_entry` is the
    one constructor the plain generate path and the event-date calendar share — the
    calendar used to drop the framework, so Uphill's specific and taper weeks ran
    its base framework.
  - **Start phase.** `start_phase` (a phase id) or the legacy `training_phase` (a kind:
    mapped to the first phase of that kind, or the first phase with a
    `PHASE_KIND_NOT_IN_TRACK` warning; older iOS builds send it, and the current one
    sends it beside `start_phase` on a tail regenerate). Neither → the track's first phase; the API
    no longer defaults to `'base'`. An unknown `start_phase` is infeasible.
  - **Picks.** `track_id` picks a track (otherwise the one `track_for_level` names, else
    the primary). Several tracks are a composition (below); the old blend shape's `track_id`
    is its owner's track there. The legacy `framework_id` maps to the track and
    phase that run it (`goals.owner_track_for_framework`) — it used to sit in
    constraints as `forced_framework`, where the phase's framework overrode it.
  - **Regenerates** send the target week's `track_id`, `start_phase` and
    `periodization_week` (web `lib/programSource.tailResume`, iOS
    `ProgramConstraintsDiff.merged`), so a tail resumes in its own track and phase.
  - **iOS** decodes `PhilosophyCard.tracks`, reads `phase_id` / `phase_name` /
    `track_id` off each week's round-tripped extras (`ProgramWeek.phaseLabel`), colours
    by kind through `PhaseStyle`, and picks tracks and start phases with
    `TrackPhaseList` / `StartPhasePicker` (design-system §3.2, §6.22;
    `PhaseTrackTests`).
  - `tools/check_styles.py` generates every phase of every track and fails if a week
    runs another framework, and generates a phase that tests at full length and fails
    unless every declared test is placed; `check_provenance.py --coverage` fails if a phase's
    framework schedules a modality no package archetype applies to for its kind;
    `validate_entities.py` checks track/phase ids and framework ownership;
    `test_phases.py` covers the rest.

## Design

Before building or changing UI, read the design system for that platform — it
is the source of the patterns, not the neighbouring screen:

- **iOS / watchOS**: `ios/docs/design-system.md`. Colour, typography, spacing,
  motion, and the component patterns in §6. §1.7 covers the governing rule:
  when two screens need the same component, extract it and convert both in the
  same change, then document it in §6. Profile and Analytics each grew their
  own sub-tab selector before that rule existed; both now use
  `AppSubTabs.swift` (§6.8).
- **Custom icons** (what SF Symbols lacks, e.g. `kettlebell`): `ios/docs/custom-icons.md`
  — the drawing rules, `ios/tools/make_*_symbol.py` + `preview_symbol.swift`, and
  `Image(symbol:)`, without which a custom name draws nothing.
- **Session icons** (since 2026-10-22): a session leads with a workout icon for its main
  exercise, tinted with its modality colour, the same on the web, phone, widgets and both
  watches. `src/session_icon.py` derives `icon` on every read (archetype or exercise `icon:`,
  else the lead exercise's category, `data/commons/workout_icons.json`) and the save and the
  content hash strip it, like `phase_summary`. One icon so far: `kettlebell`. Web
  `WorkoutIcon` (glyphs generated by `tools/icons/gen_workout_icons.py`), iOS
  `SessionIcon` + `Image(symbol:)`, Garmin `Icons.forSession`; design-system §6.40,
  frontend-design §15.4, `test_session_icon.py`.
- **Web**: `docs/frontend-design.md` (§13.2 the grouped sidebar, §17.8 every page's header).
- **iOS tabs**: Today · Program · Analytics · Log · Profile (`AppRouter.Tab`); Settings
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
  against a schema with the real constraints. Session logs fell into the same
  hole from the other side: production's `session_logs` never got
  `exercise_timeline` (`migrations/008`, `health_store._ensure_timeline_column`),
  so once the writer that names it was live there, every log sent through the
  server — the web's and the phone's alike — died on it until the column was
  added on 2026-10-04, and `test_program_history_sql.py` stayed green because
  its own DDL declared the column. Keep a test schema to what production has
  and let the lazy ensure add the rest.
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
- **Watch wellness is a side table, merged only to score.** The Connect IQ app
  posts resting HR, its 7-day average, the heart-rate low, Body Battery and
  recovery time to `POST /api/health/wellness` (`src/wellness.py` validates,
  `src/wellness_store.py` writes `daily_wellness`, `migrations/009_wellness.sql`).
  Not `daily_bio`: `upsert_daily_bio` overwrites a day wholesale and would wipe
  the Apple relay's sleep and HRV. A repeat post of a day merges per column —
  lows keep the lowest, the Body Battery high the highest, the rest the newest
  by `read_at` — because the watch's heart-rate history holds only six hours.
  Readiness, the program analytics and the progression review all read
  `api._bio_for_scoring`, which takes resting HR from **one** series (the one
  with more readings, ties to `daily_bio`; `wellness.merge_for_scoring`) and
  never mixes methods day by day. Readiness says which in `sources`. With no
  watch rows every score is what it was. **Body Battery and recovery time
  are scored** (since 2026-10-15, `api._score_watch_recovery`): with no HRV —
  Garmin does not pass it to Apple Health — the morning's Body Battery peak
  and the recovery hours left carry HRV's 35 points instead of a neutral 17,
  and recovery left caps the score at `100 − hours` (min 10, flag
  `recovery_pending`), counted down from `recovery_read_at` — the post the
  hours came from (`migrations/010`, lazily added by `wellness_store`; the
  row's `read_at` moves on with a later post that carries none). Only a
  reading taken in the last 36 hours counts — by its age, not its date, since
  the server's UTC date runs ahead of the athlete's every evening west of
  Greenwich. The program analytics digest keys on these readings
  (`api._watch_digest`). Production read 67 against Garmin's 17
  with 68 h of recovery left; it now reads 32. The response carries `watch`
  and `sources.recovery` (`test_wellness.py`), and `parts` — each component's
  label, points and maximum — with `cappedAt` when recovery left capped it, for
  the phone's readiness screen. The watch's series is its
  heart-rate low `hr_min`, **never** `resting_hr`: the SDK's
  `UserProfile.restingHeartRate` is the zone setting (46 on three mornings
  while the watch showed 46, 45, 49). Garmin's exact daily resting HR reaches
  `daily_bio` through Garmin Connect → Apple Health → the iOS relay, which is
  why `daily_bio` wins ties.
- **A device token reaches five routes.** `auth.DEVICE_ROUTES` lists the
  (method, rule) pairs a `ciqdev_` token may call — today's session,
  readiness, workouts, session logs, wellness; every other protected route
  answers it 403 before the token is looked up. A new watch route goes in that
  list; `test_device_scope.py` sends a device token to every `@require_auth`
  view and fails on any other that answers.
- **Profile writes merge.** `PUT /api/profile` overwrites only the keys the body
  carries. It used to rebuild the blob, which is why every iOS save wiped
  `activeGoalId`. `performanceLogs` is not a profile key: PRs and the
  `bodyweight_kg` series go through `POST /api/health/performance` on both
  clients (iOS used to send them with the profile, where the whitelist dropped
  them).
- **iOS builds from philosophies.** `GET /api/goals` was removed on 2026-04-25;
  the iOS builder and settings sheet pick a methodology from
  `GET /api/philosophies` and send it as `philosophy_id` — or several as `lanes`
  (a composition, `ProgramComposition.swift`).

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
- **Packages own their analytics.** Every shipped package declares one (since
  2026-10-16; the synthesised default is the fallback for a new package). A
  methodology declares what progress means
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
- **An entry that no session of the program is in scope for does not apply**
  (`applies: false`, `appliesIn` names the tracks that schedule it). It is left out
  of "N of M measurable" (`methodologies[].applicable`) and of the headline, which
  falls to the running framework's `progression_model` primitive, then the
  philosophy's (`document._lead_entry`): Wildman leads with completed intervals in
  its density-cycle tracks, cadence in Pentathlon Prep and technique minutes in
  Get-Up and Loaded Mobility. "Now available" in `unlocks` is
  what practice opened beyond `selector._get_unlocked` at the athlete's level.
- **The framework's `progression_model` never drove a prescription** —
  `generator.py` reads the modality yaml's, unless the week's framework
  declares `progression_overrides` (modality → model; no shipped framework does since
  Marcus Filly's package became a training contract on 2026-10-21, its RPE targets
  written per block). Default primitives key on
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
- **Heart rate counts only where an exercise prescribes zones**
  (`src/analytics/hr_plan.py`, since 2026-10-17), never by modality family.
  An exercise's prescription is its slot's `intensity` (`zone2`, `low`, `high`
  — `progression._INTENSITY_ZONES` — prescribe zones; `heavy`, `max_effort`,
  `bodyweight`, `progressing` load or effort), else the band its load carries
  (`zone_lower`/`zone_upper`). `hr_plan.attribute` is the one reading, for the
  intensity split, the `zone_minutes` buckets and one workout's screen: every
  prescription a zone → the whole recording counts (`whole`); zones mixed with
  load (Fran's Zone 2 warm-up) → only the minutes the watch timed on the zoned
  exercises (`timeline`, from the session log's `exerciseTimeline` — each
  step's window, sent by the Garmin app and the Apple Watch — or the sets'
  offsets) and the rest of the session is `max_effort`; untimed, nothing counts
  in zones (`untimed`); no zone → `max_effort`, strap or not. Planned minutes
  are counted for the same exercises only. An archetype may say `heart_rate:
  track | ignore`; a session stored without slots falls back to the family.
  `GET /health/workouts/<id>` adds `analysis.planned` — the attribution with
  each slot's prescription, planned and timed minutes — on the athlete's own
  edges; both clients lay it out (web `bio/ZonePlanComparison.tsx` +
  `lib/zonePlan.ts`, iOS `ZonePlanComparison.swift`, design-system §6.35).
  Fidelity's planning-side split still uses the family rule (roadmap 13).
- **One chart, every series** (`src/analytics/exercise_series.py`, since 2026-10-23).
  `exerciseSeries` on `/analytics/program` is every exercise of the program session by
  session — elapsed or not — with the stored prescription and, once logged, what was done,
  read set by set (top set with its own reps, sets, total reps, volume, est. 1RM, RPE;
  time, hold, rounds and distance from the log, else the matched workout for the session's
  endurance exercise), plus `doneText` / `prescribedText` in the server's words. A lift's
  `duration_minutes` is its time budget: only a prescription naming no reps prescribes
  time. `measures` names the progress entries the chart also draws (not `benchmark_level`).
  Every expected point carries `date` (`primitives.expected_point`; weekly series take
  `Context.week_date`). Both clients' Progress tab draws one chart from it (web
  `analytics/ProgressChart` + `lib/progressChart.ts`, iOS `ProgressChartView` +
  `ProgressChartModel`, design-system §6.41); the per-measure charts and the exercise
  cards it replaced read `/progression/exercises`, which stays for installed builds.
- **Each measure says what it is.** Every `progress` entry carries `about`
  (`vocabulary.about`: what it measures, what to log and where, the package's
  `notes`), which ends the phone's measure screen (design-system §6.37); the
  cards keep to numbers. Evidence lines word a status ("on track", "not
  enough data yet"), never the engine's code.
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
  block, and each block's weeks, average a week and peak — `byBlock`) and `benchmarks` (the level ladder per PR date). Pure over its
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
  carries `exercises` so it can read back. A skill-practice row on both
  clients has a **Clean** toggle (`exercises[id].clean`: every rep owned); an
  `unlocks` entry with `require_clean: true` (Ido) earns a movement
  only by clean sessions and says `clean_not_logged` until one is ticked. Bodyweight
  is the benchmark series `bodyweight_kg`, which turns a logged est-1RM into
  the ×BW standards. `PUT /api/health/sessions/<key>/notes` now exists — the
  iOS app had been posting notes into a phantom key — and fatigue is folded to
  1–5 at the boundary (iOS sends 1–10).
- `GET /api/progression/review` keeps its shape for iOS but takes its
  `exercise_findings` from the engine, and its `compliance_pct` from the
  scorecard (`completion=`), so Progress, Today and the Program tab show one
  number. Its own count read this version's logs only, and moving a single
  session mints a version: on 2026-10-16 Progress read 0 % beside 2 of 2.
  `src/analytics/review.py` then rescores and explains it. **The score is the
  trends alone** (since 2026-10-16): the mean status points of the findings
  that have a trend; with none, no score (`basis: collecting`). Completion is
  context beside it (`compliance_pct`, `scope_label`), never part of it — at
  `0.4 × completion + 0.6 × trends` the score *was* completion until a trend
  existed, the number Today's Adherence card already shows. The review
  carries the band and why, each measure behind it, and the measures still
  waiting for data, so both clients show the server's words
  (`test_progression_review.py`).
- **iOS load charts are server-side.** Analytics ▸ Overview reads
  `/health/load/pmc` and `/health/load/weekly`; `AnalyticsEngine` is the
  fallback when the request fails, and the footnote says which was used, so
  the phone and the web cannot quietly disagree. Analytics ▸ Progress
  (`Views/AnalyticsProgressTab.swift`) lays out the same `/analytics/program`
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
  `day_name`. The phone's Log ▸ Activity uses them for logs whose legacy key
  resolves to nothing — or to the wrong session: "3-Friday-0" exists in the
  current program too, so a planned date before the current program's start
  overrides the key lookup (`LogSessions.rows`).

## Watch Screens (Connect IQ)

**Two watches, one contract** (`docs/watch.md`: the rule, the parity table, the
tests). A watch feature lands with its `today-session` key and both watches in
one branch, or its row in that table says pending. The Apple Watch reads it
through the phone, which relays `today-session?spec=1&week=1` as the server
wrote it (`WatchDayMessage`: the JSON, lzfse-compressed, in the reply to the
watch's request and queued with `transferUserInfo`); the watch decodes
`WatchDay`. Every step is drawn as the Garmin draws it: `Views/StepPageView.swift`
(design-system §9.6), from `WatchSpecText`. On the simulator, the watch's debug builds
take `SIMCTL_CHILD_TC_SESSION=<id>`, `TC_STEP`, `TC_RUN=1`, `TC_LAPS=<k>` and
`TC_SKIP_HEALTH=1` (`WatchDebugLaunch`) to reach any step's page without a tap, and
`TC_PAGE=week|progress|day` for the Today list's pages, `TC_END=1` for a session's end.
`data/watch_day_fixture.json` is that body, written by the route
(`test_today_session.py --write`, which fails when they part) and decoded by
`WatchDayTests`.

The Garmin app (`garmin/`) is a **core library** (`garmin/core`) inside an app
shell (`garmin/TrainingCompanionCIQ`); **packages own their watch screens** the
way they own their analytics. Layout and the add-a-philosophy walk-through:
`garmin/TrainingCompanionCIQ/README.md`.

- **One vocabulary, three readers.** `data/commons/watch_vocabulary.json` lists the
  templates (engine modes), field ids, title parts, lines, LAP actions and
  behaviours; its slot-type defaults are the screens the watch drew by slot type
  before. `src/watch_spec.py` resolves a package's `watch.yaml` against it (deep
  merge: package slot-type defaults < archetype < archetype slot type < slot role
  < slot role's slot type); `garmin/tools/gen_vocab.py` generates the Garmin's
  `Vocab.mc` and the Apple Watch's `WatchVocab.swift` from it. An id is added to the
  JSON and implemented in `garmin/core/source/spec/SpecRenderer.mc` and
  `ios/TrainingCompanion/WatchSpecText.swift` (exhaustive switches: it does not build
  until it is) in the same change, with a case in `data/watch_fixtures.json` — both
  renderers run those cases (`WatchSpecTests`; `SpecFixtures.mc`, generated by
  `garmin/tools/gen_spec_fixtures.py`).
- **`?spec=1` only adds keys.** `GET /user/today-session?spec=1` gives each session
  `packageId` — the **archetype's owner**, not the program's philosophy, so a
  borrowed session keeps its owner's screens — `watch` and a deduplicated
  `screens` table, and each exercise a `screen` key. Without the parameter the
  payload is what 1.3 builds parse. `api.encode_watch_session` is the one encoder.
- **Nothing in `garmin/core` names a philosophy or archetype**
  (`garmin/tools/check_core_neutral.py`). The engine runs a step by its spec's
  `template`, never by slot type or archetype id; `ArchetypeBehavior.mc` is gone,
  and with it three bugs its archetype-wide flags hid (a get-up that never
  switched sides, a ruck's warm-up shown in km, a dead distance flag).
- **Compiled modules are the escape hatch**, not the norm: `garmin/packages/<id>/`
  + `gen_registry.py` (Monkey C has no reflection, so `Registry.mc` is generated).
  A module's slots keep a complete declarative spec; `--without <id>` builds draw it.
  None ships yet.
- **The glance reads `GlanceCache`'s slim copy** (`todayGlance`), never the
  payload: it runs in 64 KB.
- **today-session carries `progress`** in every payload, `?spec=1` or not (an
  older build ignores the key) (`api._watch_progress`): this program
  week's sessions done / due / in all, the program's done of due, and the
  methodology's headline sentence read from the cached `/analytics/program`
  snapshot — never computed on the watch's sync. The Garmin glance shows
  "3/5 wk" on a rest day and when a finished day logged no sets (GlanceCache
  keeps the two numbers, and each session's icon, exercise count and colour); the Apple Watch reads `completed`
  and `progress` from the day the phone relays, joins them to what it recorded
  itself and shows the week's count over the week ahead. The
  Garmin app's activity menu has a Progress page (week, programme, the
  headline); the Apple Watch complication rings the week around today's
  session. With `?spec=1` each exercise carries `last` — what was done last
  time ("24kg × 10", `src/last_time.py`) — shown on the Garmin Steps list, in
  a sets workout until its first set is done (the vocabulary's
  `last_then_next` line, the sets template's default), and under the Apple
  Watch's current exercise.
- **Uploads speak the server's shape** (since 2026-10-17). The Garmin app keyed its
  set logs by exercise *name* with `reps` and no `completed`, so the analytics read
  none of them; `garmin/core/source/engine/Wire.mc` now sends them keyed by exercise
  id with `setIndex`, `repsActual` (a hold's seconds as `durationSeconds`),
  `completed`, plus a round step's `rounds`, a for-time step's `durationSec` and a
  distance step's `distanceKm`. The Apple Watch kept the for-time clock, the AMRAP
  rounds and the distance in its views and dropped them; `WorkoutSessionState.outcomes`
  keeps them and `WatchUpload.sessionLog` sends them (`WatchUploadTests`). Both send
  each step's window as `exerciseTimeline` (`Wire.timeline`, `WorkoutSessionState.stepWindows`)
  — from when the step became current to when the athlete moved on — which is what
  lets the server count a warm-up's heart rate in zones and the main piece's not.
- **A test step shows its standard and asks for its result.** With `?spec=1` a test's
  scored slot carries `standard` — `{id, name, result, best, target}`
  (`standards.watch_standard`) — and its screen's lines become `standard_target`
  (`watch_spec.with_lines`), whatever the package's spec says. The Garmin's Save
  opens a Results menu (enter or correct each value, then Save results / Not a test);
  the Apple Watch's completion screen has the same choice. The answer rides in the
  session log as `standardResults` (src/standard_results.py), so it travels with a
  buffered upload.
- **Cues come from the package, in the load** (since 2026-10-18). A slot's
  `switch_at_sec` (a hand switch so many seconds into the work) and an interval
  slot's `rest_until_hr_pct` (its rest ends once HR is under that share of max HR;
  `rest_sec` is the cap) are copied into the load by `progression.watch_cues`, since
  the slot does not survive storage; an exercise's `bells: 2` marks a double.
  `_encode_watch_exercise` sends `switchAtSec`, `restUntilHr` in bpm (the athlete's
  `_get_user_max_hr`) and `bells`, each only where it applies. Both watches switch
  hands in a timed block and in an interval's work, and end a gated rest after 5 s
  under the target (Garmin `WorkoutController.updateIntervalTiming`, Apple Watch
  `WatchCues`); neither guesses bells from an exercise id.
- **The watch asks for its own day.** It sends `date=` (its local date) with
  `week=1`; the server's own date is UTC. `week=1` adds `days` (today and the
  six after it, inside the program, no screen specs) for the Week menu; the
  watch stores them apart from the day (`weekAhead`), and `SyncCache` serves a
  cached day only if it is today's — yesterday's rest day used to stand in for
  a failed morning sync.

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
- **Rebuilding ahead is the same block carrying on** (since 2026-10-17). A regenerate
  never rewrites a day already behind the athlete: both clients splice the start week
  day by day (web `lib/programSource.spliceRegenerated`, iOS `Regeneration.splice`,
  `keepBefore` = tomorrow for "from tomorrow", today for the injury/schedule/equipment
  regenerates). `record_version` then walks the block's intervals newest first: each
  whose elapsed days the new version plans exactly as they were (modality + archetype per
  slot, `divergence_date` / `carry_over_until`) is closed empty, and the new activation
  runs from the earliest one taken over — reason `continued`. Every match, suggestion and
  log on a session those versions plan as the new one does moves to the new uid
  (`same_sessions`, `_carry_over`), in or out of the version's own interval, oldest
  version first so the log written while a session was in force keeps it. A version that
  rewrites an elapsed day still switches on today. Before this every rebuild left the
  block's matches on the old uids, which `session_scope` and both clients'
  `belongsToVersion` reject, so a week's adherence vanished; a program caught by it is
  repaired with `scripts/restore_elapsed_days.py --user <id>` (dry run; `--apply`).
- **The matcher's index is a union** (`workout_matcher.history_aware_index`):
  the current program first, history overwriting any date it covers. Strictly
  additive — history is empty on a fresh deploy and in local dev with no
  `DATABASE_URL`, and indexing it alone would stop all auto-matching.
- **`session_uid` is resolved in `health_store`, not in the matcher**, so all
  five match writers get it. Resolve it **before** opening a connection:
  `get_conn()` hands out one connection per thread and a nested `with` on it
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
LOCAL_API=1 ROUTE='trainingcompanion://analytics?section=progress' ./ios/run_sim.sh /tmp/p.png
LOCAL_API=0 ./ios/run_sim.sh                                                            # back to production
```

Routes: `today`, `workout-complete[?id=…]` (the Workout complete sheet, newest workout if no id), `program?section=overview|calendar|history`
(`&phase=<n>|compare` pushes a phase's screen or Compare phases from Overview),
`analytics?section=progress|blocks|load|recovery` (`overview`, `development` and `program`
still alias Load, Blocks and Progress; `&measure=<entry id>` or `&exercise=<id>` selects it on Progress's chart,
`&open=readiness|sleep|hrv|resting-hr|checkins` a Recovery one, `pmc|load-focus|mix|weekly` Load's, `score|scorecard|intensity|movement|workouts` Progress's (`shapes` aliases workouts), `block-load` Blocks'), `log?section=workouts|linking|sessions` (`suggestions` aliases Linking),
`profile?section=…` (`DeepLink.swift`, routed through `AppRouter`). The route travels
in the launch environment (`SIMCTL_CHILD_TC_ROUTE`), because `simctl openurl` makes
iOS ask "Open in Training Companion?" and nothing can tap that. Screens behind a tap
(the swap sheet, the exercise sheet) are still out of reach; test their models.
A simulator that has never answered the Health sheet shows it on every launch, over
whatever route was asked for; `SIMCTL_CHILD_TC_SKIP_HEALTH=1` skips the request in
debug builds (`HealthKitManager.skipsAuthorizationRequest`).
Settings ▸ API target shows the current target and, in debug builds, the switch.
Never generate, adjust or swap from a simulator pointed at production.

**Releases.** `ios/VERSION` is the version testers see (MAJOR.MINOR.PATCH:
minor for a batch of features, patch for fixes only; started at 1.1.0 on
2026-10-15 after every build had shipped as 1.0); the build number is the
commit count. `./ios/archive.sh` passes both to all five targets and refuses
to archive when the project's `MARKETING_VERSION` differs from `ios/VERSION`,
so bump both in one change. With the App Store Connect key in the login
Keychain (`ios/tools/store_asc_key.sh`, once, from 1Password) `./ios/archive.sh`
uploads by itself — no 1Password, nobody at the Mac; without it, upload from
Xcode's Organizer (the account-based command-line upload fails "Failed to Use
Accounts"). Then tag it `ios-v<VERSION>`. The watch app rides inside the phone
app with the same version and build; on the tester's phone TestFlight's
*Automatic Updates* and the Watch app's *Automatic App Install* make it follow,
and Settings ▸ Apple Watch says *App not installed* when it did not
(`docs/watch.md`, Releases).

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

**Every check runs locally, before the push; GitHub runs none** (since 2026-10-26;
the Training contracts and Frontend Build workflows are gone, Deploy API and Cloudflare
Pages still deploy). The shared hooks in `../code-checks` (`core.hooksPath`; once per
machine `../code-checks/install.sh`) call `checks.sh`: at commit the syntax of the
changed Python and each changed data YAML against its schema; at push, by the paths the
pushed commits touch:

- **backend** (engine, data, schemas, API, tools, tests, migrations) — every command of
  `checks/python_suites.yaml`, run by `tools/run_checks.py` in a clean checkout of the
  pushed commit outside the repository (no `.env`/`.env.local`, database and Supabase
  variables blank, the gitignored `data/*.fit` copied in), in parallel; the three suites
  that drop tables each on a database made and dropped for the run, skipped — never run
  on `training_test` — without a local Postgres. The list is the registry:
  `run_checks.py` fails while a root `test_*.py` is in none of its sections,
  `package_fidelity` counts a package's cited test only when it is listed, and
  `check_package_status.py` holds the package README's gate table to it.
- **frontend** — lint, `npm run build` (tsc + vite), vitest (`npm ci` first in a
  worktree without `node_modules`).
- **ios** — `./ios/run_tests.sh` on a booted simulator.
- **garmin** — the release build (all devices) in the clean checkout, `test_watch_spec.py`
  and `check_code_neutral.py`; the core's `--test` needs the open simulator and stays manual.

`../code-checks/try.sh pre-push --all` runs every area by hand; `.venv/bin/python
tools/run_checks.py --only test_selection.py` one suite as the hook would. A worktree
needs the hooks path absolute (`git config core.hooksPath <abs>/code-checks/hooks`): the
relative one resolves from `.claude/worktrees/<name>/` to nothing, and git then runs no
hook at all.

Run this after touching analytics, a package's `analytics.yaml`, the matcher's
zone edges or the session-log path (needs `SUPABASE_URL=''` for the routing checks):

```bash
SUPABASE_URL='' .venv/bin/python test_program_analytics.py   # engine, specs, primitives, routing (no DB)
.venv/bin/python test_development_analytics.py               # development across programs, on a throwaway history (no DB)
SUPABASE_URL='' .venv/bin/python test_workout_metrics.py     # the per-workout metrics cache and the load routes' reader (no DB)
SUPABASE_URL='' .venv/bin/python test_workout_analysis.py    # one workout's analysis, pinned to the browser's golden values (no DB)
SUPABASE_URL='' .venv/bin/python test_load_summary.py        # Analytics ▸ Load's summary and its route (no DB)
```

**Numbers are computed on the server and shown by both clients** — a workout's
zones, TRIMP, training effect, recovery, decoupling and best efforts
(`analysis`), Analytics ▸ Load's totals and mixes (`/health/load/summary`) and
Today's completion (`scorecard.weeks`). The phone's `AnalyticsEngine` is only a
labelled fallback; the web has none. When the two clients' copies existed they
disagreed: the phone bucketed with the old Friel edges, both clients' normal
CDF was wrong (Φ(mean) ≈ 0), and two different numbers were called
"Development". Add a new number to the server, not to a client.

Before anything that changes production structure (a migration, a backfill):

```bash
scripts/backup_prod.sh                    # pg_dump 17 + restore-test + row-count compare; exits 1 on mismatch
```

**Package fidelity** (`docs/package-fidelity/`): the method for checking and improving a
package against its source — every rule into data, no invented structure, an inventions
ledger. Each package keeps its **record** in its own folder (since 2026-10-21):
`data/packages/<id>/fidelity.yaml` (sources with how much was read and when; rules `R1…`
with what they `cite` and what they are `enforced_by` — `data:<file>#<path>`,
`checks:<track>/<phase>.<key>`, `week:<id>`, `test:<file>::<fn>`; inventions `I1…`
with where they are `implemented_by`; `currency`; `excluded_tracks`; the shape) and
`source_weeks.yaml` (the source's own example weeks and progressions, transcribed;
`src/source_weeks.py` generates and compares only the fields written), beside the
prose dossier `docs/package-fidelity/<id>.md`, which names every id. The status is
**earned, not chosen**: `tools/evaluate_packages.py` grades every package × track on six
dimensions — Source, Execution, Robustness, Data, Measurement, Portability — each criterion pass,
partial or fail (`src/package_eval.py`, the table in the README, today's grades in
`scorecard.md`), never a blended number. Source is computed from the record
(`src/package_fidelity.py`: debt is a rule nothing enforces; a claim, contract, template,
hand-entered standard or lead measure counts only when a rule or invention names it; S5
is the source weeks reproducing), never declared. It generates the fidelity profiles and
its own (every level, a knee flag, three days, 30 minutes, one bell) in one parallel pass
with the exercise reach (D2) and the source weeks, runs `check_fidelity.gate` on the same
programs, ratchets `tools/scorecard_baseline.json` — a worse grade fails, and so does a
better one left unrecorded (`--update-baseline`; `--accept-worse` for a stricter grader)
— and writes `status.yaml` from the records and the grades: never edit it by hand
(`audited`: every criterion but hygiene passes on every track not in `excluded_tracks`).
CI (`.github/workflows/training-contract.yml`) runs every gate the README's table names;
`check_package_status.py` fails when the two part.
**No code names a package** (Portability, X1/X2): `tools/check_code_neutral.py` fails on
any string literal in `src/`, `api.py`, `mcp_server.py`, `frontend/src`, the iOS, Apple
Watch and widget sources or `garmin/core/source` that is an id one package owns (or a
two-part prefix of its ids) — no baseline, there are none left. What used to: the level
concepts are commons data (`data/commons/level_concepts.yaml`), a split day's mobility
session prefers an archetype that declares it `complements` the day's modality, both
builders name required movements from `entry_requirements.exercise_names`. A contract
module's `advice` is the method's recommendation, said in the advancing blocks' notes and
never enforced (Wildman's repeat after a week off). `test_package_dropin.py` copies three
packages (contract, templates, scheduler) under new ids into `TRAINING_PACKAGES_DIR`
(`loader._PACKAGES_DIR`; every module finds packages through it) and runs them through
validation, generation, the API, the watch payload, analytics and the scorecard with the
repository unchanged. `tools/print_package.py <id>` prints a package's programs beside its
rules for the output review, recorded in the record's `reviews` (S6, hygiene).
A phase's `checks:` may now state its defining claims — `max_substituted_share`,
`modality_outnumbers`, `max_archetype_share`, `min_distinct_archetypes`
(`fidelity.claim_violations`) — which the gate checks and a contract's
`verify_phase_rules` refuses to save broken. Injury flags name only catalog ids, each
substitution pair inside one package (`validate_entities`).
Starting Strength runs as a training contract (since 2026-10-20): Workouts A and B
alternate by a module's `variants` + `rotation`, the Texas Method is its intermediate
track (`track_for_level` routes a request with no track by level), and
`load_per_exposure` prescribes kg from what each lift made — a miss repeats, two
reset 5 % (after the first reset the week's second squat is a light day, after the
second the squat, bench and press run 5×3; a third stall finishes the lift), a lift
with no weight works up on the day; layoff resets are the module's `advice`; the one-tap confirm takes
`lifts: {id: {made, weightKg}}` (docs/logic/training_contracts.md).
**In a worktree under `.claude/worktrees/`, blank `DATABASE_URL` and `SUPABASE_URL`**:
`load_dotenv()` walks up to the main checkout's production `.env`.

Run these after touching engine code or package data:

```bash
.venv/bin/python tools/validate_entities.py --all -q     # YAML vs docs/schemas (packages, commons, standards)
.venv/bin/python tools/check_provenance.py               # no package leaks; 11 philosophies x 3 profiles
.venv/bin/python tools/check_provenance.py --coverage    # coverage gaps + authoring problems
.venv/bin/python tools/check_styles.py                   # every philosophy x track x phase generates on its framework
SUPABASE_URL='' .venv/bin/python test_phases.py          # tracks, phase text ownership, start phase, event date, legacy picks
SUPABASE_URL='' .venv/bin/python test_composition.py     # several tracks: request, shares, cuts, real compositions, the API
.venv/bin/python test_single_lane_golden.py              # every one-track program unchanged (~6 min; --record only on purpose)
.venv/bin/python test_provenance.py                      # source-policy rules
SUPABASE_URL='' .venv/bin/python test_week_numbering.py  # a partial regenerate's tail continues the numbering
SUPABASE_URL='' .venv/bin/python test_today_session.py   # the watch's today-session: completed flags, tomorrow, ?spec=1, progress
.venv/bin/python test_last_time.py                       # each exercise's last time, for the watches
SUPABASE_URL='' .venv/bin/python tools/evaluate_packages.py   # the scorecard, the fidelity gate, orphans, source weeks; --report docs/package-fidelity/scorecard.md, --update-baseline (writes status.yaml)
.venv/bin/python test_package_eval.py                    # each scorecard grader on hand-built programs and records (no generation)
.venv/bin/python test_source_weeks.py                    # a source week against hand-built programs: structure, numbers, silence
.venv/bin/python tools/check_code_neutral.py             # no code (server, web, iOS, watches) names a package
.venv/bin/python test_package_dropin.py                  # three packages under new ids need no code change, end to end
SUPABASE_URL='' .venv/bin/python tools/print_package.py <id> [--profile ideal]  # its programs beside its rules, for the output review
.venv/bin/python tools/check_fidelity.py                 # the fidelity rules alone (evaluate_packages runs the same gate); --report docs/fidelity-report.md
SUPABASE_URL='' .venv/bin/python tools/check_exercise_coverage.py -v  # each package's reach by track and level (evaluate_packages gates the orphans)
.venv/bin/python tools/check_package_status.py           # records name their own tracks; status.yaml is what records + recorded grades write; README gates = CI
.venv/bin/python tools/check_analytics.py                # every declared analytics measure applies in some track; every headline leads somewhere
.venv/bin/python test_fidelity.py                        # each fidelity rule on hand-built weeks (no generation)
SUPABASE_URL='' .venv/bin/python test_selection.py       # what the generator picks: SS A/B, pinned lifts, deloads, gaps, cadence
SUPABASE_URL='' .venv/bin/python test_phase_summary.py   # Program ▸ Overview's phase_summary, served and never stored
SUPABASE_URL='' .venv/bin/python test_devlab_trace.py    # the Dev Lab's recorded trace has the server's shape; --record after a trace change
SUPABASE_URL='' .venv/bin/python test_constraint_impact.py  # what each constraint changes against the reference, and which (Dev Lab ▸ Impact)
SUPABASE_URL='' .venv/bin/python test_portability.py     # Dev Lab ▸ Model Interactions' report; every open gap still anchored in the code; --write re-records the web's copy
SUPABASE_URL='' .venv/bin/python test_explore_links.py     # Explore's lineage: slot links by the selector's rule, progression, movements
SUPABASE_URL='' .venv/bin/python test_explore_philosophy.py  # Explore's philosophy page: weeks from contracts and templates, mixes, rules, sessions
```

The Dev Lab's panels render a recorded `generate?trace=1` answer
(`frontend/src/mocks/fixtures/traced-programs.json`) in
`components/devlab/DevLabPanels.test.tsx`; `test_devlab_trace.py` fails when the
server's trace keys drift from it. Re-record, then run the panels' test: the
Schedule step once crashed for every program because tracks changed the trace
under it. A training contract's trace (`training_contract._trace`) has the same
skeleton — framework selection `training_contract`, empty candidate lists, each
slot's `module_id` — and the Schedule step shows its placed modules instead of
an allocation.

A fix that clears fidelity findings ends with `tools/check_fidelity.py --update-baseline
--report docs/fidelity-report.md`; the baseline only shrinks. A new finding fails the
check — fix it, or, if the theory says otherwise, change the package's `checks:`.

Run these after touching the watch app, a package's `watch.yaml` or the
watch vocabulary (the Monkey C tests need the Connect IQ simulator open):

```bash
SUPABASE_URL='' .venv/bin/python test_watch_spec.py   # resolver, payload, generated files, core neutrality
SUPABASE_URL='' .venv/bin/python garmin/tools/gen_watch_demo.py   # after a watch.yaml or vocabulary change
garmin/TrainingCompanionCIQ/build.sh --release        # all products
garmin/TrainingCompanionCIQ/build.sh --test           # the core's (:test) functions, in the simulator
```

Run this after touching anything under `ios/` (in addition to the simulator):

```bash
./ios/run_tests.sh                         # TrainingCompanionTests on the booted sim
```

Run these after touching standards or results (the SQL one makes and drops its own database;
`TEST_ADMIN_DSN` points it at a server, and it skips without one):

```bash
SUPABASE_URL='' .venv/bin/python test_standards.py   # levels, text, input, days, blocks, routes
SUPABASE_URL='' .venv/bin/python test_standard_tests.py   # when a phase tests, what it replaces, skips, carry
.venv/bin/python test_standard_results_sql.py         # the store on a production-shaped performance_logs
SUPABASE_URL='' .venv/bin/python test_standard_suggestions.py  # a logged test → a suggestion → a result (SQL half on a scratch DB)
```

Run these after touching program history, the matcher or the session-log path:

```bash
.venv/bin/python test_program_history.py      # hashing, flattening, intervals (no DB)
.venv/bin/python test_session_scope.py        # a match or log belongs to the active program by its dates (no DB)
.venv/bin/python test_workout_matcher.py      # the cross-language parity contract
SUPABASE_URL='' .venv/bin/python test_linking.py  # Log ▸ Linking's day cards, the same cases as lib/linking.test.ts
```

Run these after touching sign-in or account deletion (the SQL half makes and
drops its own database; set `TEST_ADMIN_DSN` if Postgres has no `postgres` role):

```bash
SUPABASE_URL='' .venv/bin/python test_account_delete.py   # deletion order, preconditions, the route, the rows
.venv/bin/python test_apple_client_secret.py              # the web Apple client secret's claims and lifetime
./ios/run_tests.sh AuthFlowTests                          # nonce, session migration, messages
```

Run these after touching watch pairing, device tokens or wellness (the SQL half
of `test_wellness.py` makes and drops its own database; it skips without a server):

```bash
.venv/bin/python test_device_scope.py      # device-token allowlist, revoke by display id, model names
SUPABASE_URL='' .venv/bin/python test_wellness.py   # validate, the scoring merge, the store, the routes
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
