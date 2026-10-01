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
        benchmarks, HR zones, connections, devices, account
```

Rules the layout must satisfy:

1. **Every block has one home.** A workout list, a session detail, a load chart, a
   philosophy detail each render from one component, reachable from one primary place.
2. **Every arrow above is a visible control**, not a sidebar round-trip: Explore →
   Builder, Session → Exercise reference, Program → Methodology, Review → Adjust,
   Body → Today.
3. **Inputs sit where the question is asked.** Daily check-in on Home and in Recovery;
   the import action in the workout log; PRs in Benchmarks; suggestions where you decide.
4. **Configuration is not a destination.** Profile is visited to change something, never
   to learn what happened today.
5. **Dev tooling is not user navigation.**

## 2. Web — grouped sidebar

| Group | Item | Route | Sub-tabs (header pills) | Header actions |
|---|---|---|---|---|
| Train | **Home** | `/` | — | Program settings sheet |
| Train | **Program** | `/program` | Calendar · Overview · History | New program · Settings (rebuild, regenerate from week, event date, injuries) |
| Train | **Log** | `/log` | Workouts · Suggestions (count badge) | Import (sheet) |
| Insight | **Analytics** | `/analytics` | Program · Progress · Load · Recovery | — (period selector is a control strip) |
| Library | **Explore** | `/explore` | Philosophies · Frameworks · Modalities · Archetypes · Exercises · Standards | — |
| You | **Profile** | `/profile` | Athlete · Equipment · Injuries · Schedule · Benchmarks · Heart Rate · Connections | — |
| Dev (build flag) | Dev Lab | `/dev` | Pipeline Trace · Object Browser · Ontology · Model Interactions | — |

Flows and details, not nav items: `/program/new` (the builder, launched from the Home
and Program empty states, the Program header, the settings sheet's Rebuild/New, and
Explore CTAs; its header gains a back link to `/program`), `/program/:week/:day`,
`/program/history/:versionId`, `/log/:workoutId`, `/login`, and a catch-all 404.

Redirects, query and `location.state` preserved: `/builder` → `/program/new`,
`/import` → `/log`, `/import/:id` → `/log/:id`, `/bio` → `/analytics?tab=recovery`,
`/exercises` → `/explore?topic=exercises`, `/philosophies` → `/explore?topic=philosophies`.
`/profile?tab=connections` stays where it is: the OAuth landing URL is a server-side
string (`api.py` `_integrations_redirect`), so a `/settings` split waits until Profile's
sub-tab row overflows or a web Devices UI exists.

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
start date is server state. No Sessions sub-tab — completed sessions already have the
Session Log inside Progress, and a second list would be a fourth workout-list
implementation.

**Analytics** is the interpretation: Program (methodology scorecard, server-side),
Progress (the current ProgressionTab), Load (weekly TRIMP, PMC, zones — the single load
surface), Recovery (readiness, sleep, HRV, RHR, check-in and history — the current
Bio Log). The Overview KPIs fold into Load; Activity is deleted in favour of
Log ▸ Workouts. Tabs are URL-driven (`?tab=`) so Home cards and redirects can land on one.

**Explore** gains a Standards topic (benchmarks) and one CTA per topic where it makes
sense: philosophy → "Build a program with this" (prefills source and priorities),
framework → "Build with this framework" (prefills source and framework), Standards →
"Log a PR". The ontology graph lives in Dev Lab, where it already is.
`PhilosophyExplorerPanel` moves from `components/devlab/` to `components/explore/`;
Dev Lab does not use it.

**Profile** gains an Athlete tab: training level (from the header), date of birth (from
Benchmarks), sex (a new profile key; unblocks the female benchmark standards), bodyweight
(the `bodyweight_kg` benchmark series), and the account switcher and sign-out.

## 3. iOS — four tabs

| Tab | Root | Sections (`AppSubTabs`) | Notes |
|---|---|---|---|
| **Today** | `TodayView` | — | Renamed from "Dashboard". Empty state gets a "Generate a program" button (design system §6.3); adds a Suggestions card and a Progress card that routes to Analytics ▸ Progress. |
| **Program** | `ProgramView` | Current · History | Builder picks a methodology from `/api/philosophies`; Settings sheet has its title and Cancel; Current gains "About this methodology". |
| **Analytics** | `AnalyticsView` | Overview · Workouts · Progress · Recovery | Progress = today's pushed `ProgressionView`; Workouts keeps the `.fit` importer and gains suggestion accept/dismiss. |
| **Profile** | `ProfileView` | Athlete · Equipment · Injuries · Schedule · Benchmarks | Athlete = level, DOB, bodyweight, editable HR zones. Toolbar gear pushes **Settings**: Connections (integration toggles), Devices & Sync (pair Garmin, Sync Now, last sync, sync details, debug log), Account (sign out), Appearance. |

The **Sync** tab is removed. `resetProgramStartToToday()` — a program mutation hiding on
the Sync tab — is deleted; a start-date repair, if still wanted, belongs under Program
settings behind a confirmation.

Why four tabs and not five: a Log tab would be one list moved, because the phone has no
session logging until 2026-10-01; it logs from the session detail now, and the log stays on the session rather than in a tab. A Library tab has no content to show; the
exercise reference is contextual (a detail sheet from any session row) and philosophy
detail sits inside the builder's step 1.

Cross-tab moves go through `AppRouter` methods (design system §6.9): `showAnalytics(.progress)`,
`showProgram()`; the direct `router.tab` write in `ContentView.onOpenURL` becomes
`router.show(.dashboard)`.

## 4. Connectivity map — the seams that must exist

| From | To | Control | Status 2026-10-01, after the restructure (web / iOS) |
|---|---|---|---|
| Explore philosophy / framework | Builder, prefilled | "Build with this" | ✓ / n.a. (no Explore on the phone) |
| Home or Program empty state | Builder | primary button | ✓ / ✓ |
| Session exercise | Exercise reference (cues, media, prereqs) | popover → "Open in Explore" / detail sheet | ✓ / ✓ (`ExerciseDetailSheet`, design-system §6.14) |
| Program overview | Methodology detail | link | ✓ / ✓ ("About this methodology" row under the phase bar → `PhilosophyDetailSheet`) |
| Session detail | Recorded workout | "Workout" link | ✓ / ✓ |
| Session detail | Import or link a workout | "Link existing" / "Import" | ✓ / ✓ |
| Server suggestions | Accept / dismiss | Home card + Log ▸ Suggestions / Today card | ✓ / ✓ |
| Recorded workout | Planned session | "Link to session" | ✓ / ✓ |
| Home readiness card | Analytics ▸ Recovery | whole-card link | ✓ / ✓ |
| Home progression widget | Analytics ▸ Progress | whole-card link | ✓ / ✓ |
| Progress recommendation | The stored program, from this week on | "Apply from week N" (`POST /api/programs/adjust`) | ✓ Analytics ▸ Progress / ✓ Analytics ▸ Progress |
| Session exercise | A ranked alternative for the same slot | "Swap" (`POST /api/exercises/substitute`) | ✓ swap icon on every exercise row / ✓ context menu or swipe on a session row |
| Analytics ▸ Program methodology | Explore philosophy | link | ✓ / n.a. |
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
