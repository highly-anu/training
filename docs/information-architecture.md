# Information architecture

The target layout and connectivity for both clients, and the reasons behind it.
Rationale document, same standing as `frontend-fix-plan.md`; the work it implies is
ranked in `roadmap.md` (items tagged *IA*). Written from the functionality review of
2026-09-30; findings that changed a priority were verified in code, not taken from a
summary.

The product has four blocks of functionality — an Explorer (inspiration and reference),
a program builder and scheduler, workout tracking (planned sessions, recorded workouts,
matching) and general health data (readiness, sleep, HRV, load) — built one feature at a
time on two platforms. Navigation grew by appending: nine flat sidebar items on the web,
a debug "Sync" tab as a top-level destination on the phone, and several seams the journey
depends on never closed. This document is the layout those blocks should have had.

## 1. The journey model

```
        ┌──────────── DISCOVER ────────────┐
        │  Explore: philosophies, frame-   │   "Build with this"
        │  works, modalities, archetypes,  ├────────────────┐
        │  exercises, standards            │                │
        └──────────▲───────────────────────┘                ▼
   reference       │                                 ┌── PLAN ─────────────┐
   (what is this?) │                                 │ Builder → Program   │
                   │                                 │ calendar · overview │
        ┌──────────┴──────────┐   adjust (settings,  │ history · settings  │
        │  REVIEW             │◄──replace, move,─────┤                     │
        │  Analytics: program │   regenerate)        └──────────┬──────────┘
        │  progress, load,    │                                 │ today / this week
        │  recovery           │                                 ▼
        └──────────▲──────────┘                      ┌── TRAIN ────────────┐
                   │  logs, matches, bio             │ Today · session ·   │
                   └─────────────────────────────────┤ log (sets/outcomes) │
                                                     │ recorded workouts · │
        BODY (continuous input): check-in, HealthKit,│ suggestions · import│
        Garmin/Strava, watch                         └─────────────────────┘
        PROFILE (configuration): athlete, equipment, injuries, schedule,
        standards, HR zones, connections, devices, account
```

Rules the layout must satisfy:

1. **Every block has one home.** A workout list, a session detail, a load chart, a
   philosophy detail each render from one component, reachable from one primary place.
2. **Every arrow above is a visible control**, not a sidebar round-trip: Explore →
   Builder, Session → Exercise reference, Program → Methodology, Review → Adjust,
   Body → Today.
3. **Inputs sit where the question is asked.** Daily check-in on Home and in Recovery;
   the import action in the workout log; results in Standards; suggestions where you decide.
4. **Configuration is not a destination.** Profile is visited to change something, never
   to learn what happened today.
5. **Dev tooling is not user navigation.**

## 2. One menu on both clients

Since 2026-10-13 the web sidebar and the phone's tab bar name the same places
and the same sections, in the same order, so moving between them needs no
translation. The web groups its items (Train · Library · You); the
phone shows the same items as tabs. Analytics sits before Log on both since
2026-10-16 — how the plan is going before the record of it — which folded the
web's Insight group into Train.

| Item | Web sections (`?tab=`) | iOS sections (`AppSubTabs`) |
|---|---|---|
| **Today** | — (web route `/`) | — |
| **Program** | Overview · Calendar · History | Overview · Calendar · History |
| **Analytics** | Progress · Blocks · Load · Recovery | Progress · Blocks · Load · Recovery |
| **Log** | Activity · Linking | Activity · Linking |
| **Explore** | Philosophies · Frameworks · Modalities · Archetypes · Exercises · Movements · Equipment · Standards | — |
| **Profile** | Athlete · Equipment · Injuries · Schedule · Standards | Athlete (incl. injuries) · Equipment · Schedule · Standards — Injuries folded into Athlete on 2026-10-17; `section=injuries` lands there. Benchmarks was renamed Standards the same day (`?tab=benchmarks` / `section=benchmarks` land there): *This program* · *Your results* · *All standards*, each standard's history one tap away |
| **Settings** | Connections · Appearance · Account (· Developer) | Connections · Devices · Pair · Notifications · Appearance · Account · developer sections (pushed from Profile's gear) |

Differences kept on purpose:

- **Explore is web-only.** It is reference material to browse at a desk; on the
  phone the exercise sheet and the methodology sheet cover lookup in context
  (*Later* in the roadmap).
- **Notifications are phone-only.** Local session reminders; the web has nothing
  to remind with.
- **Settings is a tab row on the web and a grouped list on the phone**, in the
  same order. The phone keeps its sync details and debug log in release builds:
  on the athlete's own phone they are the only way to read a sync failure.
- **Settings is reached from Profile's gear on the phone** (five tabs is the
  bar's limit) and from the sidebar on the web.

Renames, with the old links kept: Home → **Today** (web label; the route stays
`/`); Analytics Development → **Blocks** (`?tab=development` still lands there —
the phone's segmented control cannot fit the long word) and the phone's
Overview → **Load** (`section=overview` and `section=development` still
deep-link); Analytics Program merged into **Progress** on 2026-10-23
(`?tab=program` and `section=program` land on Progress), and its Session shapes
became **Workouts** (`open=shapes` still opens them); web Profile ▸ Heart Rate folded into **Athlete**, as on the phone
(`?tab=heartrate` lands on Athlete); the phone's Program ▸ Current → **Calendar**,
with a new **Overview** (methodology, phases, priority mix) beside it.

### 2.1 Web — grouped sidebar

| Group | Item | Route | Sub-tabs (header pills) | Header actions |
|---|---|---|---|---|
| Train | **Today** | `/` | — | Program settings sheet |
| Train | **Program** | `/program` | Overview · Calendar · History | New program · Settings (rebuild, regenerate from week, event date, injuries) |
| Train | **Analytics** | `/analytics` | Progress · Blocks · Load · Recovery | — (period selector is a control strip) |
| Train | **Log** | `/log` | Activity (All · Workouts · Sessions) · Linking (count badge) | Import (sheet) |
| Library | **Explore** | `/explore` | Philosophies · Frameworks · Modalities · Archetypes · Exercises · Movements · Equipment · Standards | — |
| You | **Profile** | `/profile` | Athlete (incl. heart-rate zones) · Equipment · Injuries · Schedule · Standards | — |
| You | **Settings** | `/settings` | Connections · Appearance · Account (· Developer in dev builds and for `dev` users) | — |
| Dev (build flag) | Dev Lab | `/dev` | Pipeline Trace · Object Browser · Ontology · Model Interactions | — |

Flows and details, not nav items: `/program/new` (the builder, launched from the Home
and Program empty states, the Program header, the settings sheet's Rebuild/New, and
Explore CTAs; its header gains a back link to `/program`), `/program/:week/:day`,
`/program/history/:versionId`, `/log/:workoutId`, `/login`, and a catch-all 404.

Redirects, query and `location.state` preserved: `/builder` → `/program/new`,
`/import` → `/log`, `/import/:id` → `/log/:id`, `/bio` → `/analytics?tab=recovery`,
`/exercises` → `/explore?topic=exercises`, `/philosophies` → `/explore?topic=philosophies`.
`/profile?tab=connections` → `/settings?tab=connections` (query intact). The server's
OAuth landing URL (`api.py` `_integrations_redirect`) keeps naming the old Profile tab on
purpose: every frontend deployment knows it, and `FRONTEND_URL` may pin one that predates
Settings — the client-side redirect is what lands the athlete on Settings. The split was deferred
until Profile's sub-tab row overflowed or a web Devices UI existed — both happened on
2026-10-01, and Settings mirrors the phone's: the services connected, the account, the
look, and the developer switches.

**Home** is the only page that mixes blocks, deliberately: today's session(s) with the
side panel, readiness plus a one-tap check-in, the week strip with drag-and-drop, a
*Suggestions* card ("2 workouts look like planned sessions"), and compact Development and
Progression widgets whose whole card links to Analytics ▸ Progress. Home has no sub-tabs:
the Dashboard's Analytics charts (donut, phase timeline, volume) describe program *shape*
and belong in Program ▸ Overview; its Progress tab belongs in Analytics ▸ Progress. The
tab header itself stays (roadmap: *Explicitly not doing*).

**Program ▸ Overview** gains "About this methodology → Explore" and "Entry standards →
Explore ▸ Standards" beside the shape charts. **Session detail** offers the outcome logger
for non-set slots and an "Open in Explore" link on each exercise. **Program settings**
generalises "Regenerate from week N" (today injuries-only) to equipment and level changes.

**Log** is the record and the decision queue: one recorded-workouts list (one row
component; filters all / matched / unmatched; source and match badges) and the
suggestions inbox read from `GET /api/health/matches/suggestions`. Import is a header
action opening a sheet, not a page, and the manual "program start date" field goes:
start date is server state. A Sessions sub-tab was refused here on 2026-10-01 (a
second list of completed sessions beside Progress's Session Log); it was added on
2026-10-13 for parity with the phone's Log ▸ Sessions, once the server named the
logs of earlier programs (`GET /api/health/sessions/recent` resolves each
`session_uid` through `planned_sessions`). It lists what was logged against planned
sessions — earlier programs' included — not recorded workouts, so it is not a
fourth workout list. On 2026-10-20 the two lists became one, Activity: workouts and
logged sessions by date, with a filter for each type (`?show=workouts|sessions`).

**Analytics** is the interpretation: Progress (what was done against the plan and
whether it is working — the review's score; one chart of every exercise's sets, reps
and load done against prescribed and of each methodology measure against its
expectation; the measures as rows; the scorecard and intensity split; the standards the
program tests or estimates from its lifts; the workouts; load. Program — am I doing the
plan — and Progress were two tabs until 2026-10-23, when they merged and the exercise
cards and per-measure charts became the one chart; Movement is parked), Development (every block, not just this one —
the history tables read as one document, `GET /api/analytics/development`: the
activation timeline, each lift across the span with the blocks as bands and per-block
deltas, weekly load by block, the standards ladder over time), Load (weekly TRIMP, PMC,
zones — the single load surface), Recovery (readiness, sleep, HRV, RHR, check-in and
history — the current Bio Log). The Overview KPIs fold into Load; Activity is deleted
in favour of Log ▸ Activity. Tabs are URL-driven (`?tab=`) so Home cards and redirects
can land on one. Home's Adherence card (Development until 2026-10-16) stays about the
current program and links to the tab; its Progress card shows the methodology's headline
measure (`methodologies[].headlineSummary`) and opens Progress.

**Explore** gains a Standards topic and one CTA per topic where it makes
sense: philosophy → "Build a program with this" (prefills source and priorities),
framework → "Build with this framework" (prefills source and framework), Standards →
"Log a result". The ontology graph lives in Dev Lab, where it already is.
`PhilosophyExplorerPanel` moves from `components/devlab/` to `components/explore/`;
Dev Lab does not use it.

**Profile** gains an Athlete tab: training level (from the header), date of birth (from
Standards), sex (a new profile key; unblocks the female standards' tables), bodyweight
(the `bodyweight_kg` series), and the account switcher and sign-out.

## 3. iOS — five tabs (the same menu as §2)

| Tab | Root | Sections (`AppSubTabs`) | Notes |
|---|---|---|---|
| **Today** | `TodayView` | — | Renamed from "Dashboard". Empty state gets a "Generate a program" button (design system §6.3); adds a Suggestions card and a Progress card that routes to Analytics ▸ Progress. |
| **Program** | `ProgramView` | Overview · Calendar · History | Builder picks a methodology from `/api/philosophies`; Settings sheet has its title and Cancel; Overview holds "About this methodology", the phases and the priority mix. |
| **Log** | `LogView` | Activity · Linking | Added 2026-10-01 once the phone could log: the recorded-workout list (with the `.fit` importer) moved here from Analytics, the suggestions inbox with accept/review/dismiss, and what was logged against planned sessions across the program — earlier programs' logs included, named by the server from `planned_sessions`. |
| **Analytics** | `AnalyticsView` | Progress · Blocks · Load · Recovery | Progress = the program document and the review in one (`AnalyticsProgressTab`; Program until 2026-10-23); Blocks = every program (design system §6.20); Load = the old Overview. |
| **Profile** | `ProfileView` | Athlete · Equipment · Schedule · Standards | Athlete = level, DOB, bodyweight, editable HR zones (a zone-coloured bar, §3.5), injuries. Toolbar gear pushes **Settings**: Connections (integration toggles), Devices & Sync (pair Garmin, Sync Now, last sync, sync details, debug log), Account (sign out), Appearance. |

The **Sync** tab is removed. `resetProgramStartToToday()` — a program mutation hiding on
the Sync tab — is deleted; a start-date repair, if still wanted, belongs under Program
settings behind a confirmation.

Why a Log tab now and not before: until 2026-10-01 the phone had no session logging, so a
Log tab would have been one list moved. It logs from the session detail now, and the tab
is the record across sessions — the same area as the web's Log. A Library tab still has
no content to show; the exercise reference is contextual (a detail sheet from any session
row) and philosophy detail sits inside the builder's step 1 and Program ▸ Overview.

Cross-tab moves go through `AppRouter` methods (design system §6.9): `showAnalytics(.progress)`,
`showProgram()`; the direct `router.tab` write in `ContentView.onOpenURL` becomes
`router.show(.dashboard)`.

## 4. Connectivity map — the seams that must exist

| From | To | Control | Status 2026-10-01, after the restructure (web / iOS) |
|---|---|---|---|
| Explore philosophy / framework | Builder, prefilled | "Build with this" | ✓ / n.a. (no Explore on the phone) |
| Any Explore detail | The levels above and below it (philosophy ↔ framework ↔ modality ↔ archetype ↔ exercise ↔ movement) | "Leads into it" / "Follows from it" pills (`?topic=&id=`, pushed, so Back retraces the trail) | ✓ since 2026-10-26 / n.a. |
| Home or Program empty state | Builder | primary button | ✓ / ✓ |
| Session exercise | Exercise reference (cues, media, prereqs) | popover → "Open in Explore" / detail sheet | ✓ / ✓ (`ExerciseDetailSheet`, design-system §6.14) |
| Program overview | Methodology detail | link | ✓ / ✓ ("About this methodology" row under the phase bar → `PhilosophyDetailSheet`) |
| Session detail | Recorded workout | "Workout" link | ✓ / ✓ |
| Session detail | Import or link a workout | "Link existing" / "Import" | ✓ / ✓ |
| Server suggestions | Accept / dismiss | Home card + Log ▸ Suggestions / Today card | ✓ / ✓ |
| Recorded workout | Planned session | "Link to session" | ✓ / ✓ |
| Home readiness card | Analytics ▸ Recovery | whole-card link | ✓ / ✓ |
| Home progression widget | Analytics ▸ Progress | whole-card link | ✓ / ✓ |
| Home development card (the current program) | Analytics ▸ Development (every program) | footer link | ✓ / n.a. (Today has no development card; Analytics ▸ Blocks) |
| Progress recommendation | The stored program, from this week on | "Apply from week N" (`POST /api/programs/adjust`) | ✓ Analytics ▸ Progress / ✓ Analytics ▸ Progress |
| Session exercise | A ranked alternative for the same slot | "Swap" (`POST /api/exercises/substitute`) | ✓ swap icon on every exercise row / ✓ context menu or swipe on a session row |
| Analytics ▸ Progress methodology | Explore philosophy | link | ✓ / n.a. |
| Profile change with an active program | Regenerate from this week | inline offer | ✓ `RegenerateFromWeekBanner` on Profile / ✓ `RegenerateOfferCard` on Profile and in the settings sheet |
| Session with a rounds / minutes / km currency | Outcome logger | inputs beside the prescription | ✓ / ✓ (`ExerciseLogSheet`, design-system §6.16) |

## 5. Decisions and why

- **Builder is a flow under Program, not a nav item.** Every existing entry point is an
  action (three empty states, Rebuild/New in the settings sheet). `builderStore`
  persists `step`, so a permanent sidebar item re-opens a half-finished wizard with no
  program context — and it is the one screen that can overwrite the athlete's program.
- **Log is its own area; Analytics is read-only.** Log is a decision queue (confirm,
  reject, dismiss, delete, link). Burying an inbox inside Analytics is how the
  suggestions endpoint stayed invisible for months.
- **Route renames only where the page disappears or the name misleads.** `/bio`,
  `/exercises`, `/philosophies` must redirect because their pages go. `/builder` and
  `/import` are renamed because "Build Program" and "Import Workouts" are tasks, not
  places. `/settings` is deferred (server-side OAuth landing URL; nothing to fill a web
  Devices page yet).
- **Dev Lab and the authoring routes are developer tooling.** The route and nav entry
  exist only in dev builds (`src/lib/featureFlags.ts`); the six YAML-writing routes
  require a signed-in user and `AUTHORING_ENABLED`, which local development gets for free
  (no `SUPABASE_URL`).
- **Shared extractions before new features.** Session detail existed twice, the workout
  row three times, the session-key parser five times, the load charts twice. Each copy is
  the next inconsistency; `lib/sessionKeys.ts` and `components/bio/SuggestionRow.tsx`
  are the first two the new code builds on.
