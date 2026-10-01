# TrainingCompanion — iOS and watchOS

The phone and watch clients of the training app. The phone shows the program
the web app (or the phone itself) generated, logs completion and notes, relays
Apple Health data to the server, and hosts the live-workout watch app.

## What it does

**Today** — today's sessions (swipe for other days), readiness, workout
suggestions waiting for a match decision, development and progression cards
that open Analytics, and an empty state that starts the builder.

**Program** — the current plan week by week with a phase bar; a four-step
builder sheet (methodology from `GET /api/philosophies`, schedule, constraints,
review); a settings sheet that regenerates with changed constraints or an event
date; move and replace a session; **History** of every archived program version.

**Analytics** — Overview (totals, load focus, modality mix, PMC), Workouts (the
recorded-workout list with `.fit` import and suggestion accept/dismiss),
Progress (the weekly progression review), Recovery (readiness, sleep, HRV,
resting HR, check-ins).

**Profile** — Athlete (level, date of birth, bodyweight, HR zones), Equipment,
Injuries, Schedule, Benchmarks. The toolbar gear pushes **Settings**:
Connections (auto-import toggles), Devices & Sync (Garmin pairing, Sync Now,
sync log), Appearance, Account.

**Watch app** — the live session: per-slot views (sets × reps, AMRAP, EMOM, for
time, distance, static hold, time domain), rest timer, HR zones, GPS route; the
summary flows back through the phone to `PUT /api/health/sessions/<key>`.

## Architecture

```
AppState            — the store: program, logs, profile, workouts, suggestions, readiness
AppRouter           — tab selection and cross-tab routes (design-system.md §6.9)
APIClient           — the Flask API (JWT) plus direct Supabase reads/writes for workouts
SyncManager         — HealthKit relay: bio metrics (sleep, HRV, RHR, SpO2, respiratory
                      rate) and workouts, anchored and background-delivered
HealthKitManager    — HealthKit queries and authorization
WatchSessionManager — phone ↔ watch: today's sessions out, workout summaries back
AuthManager         — Supabase email/password sign-in, Face ID, token refresh
```

The server's contracts the phone depends on: `philosophy_id` on generate,
`POST /api/health/performance` for PRs (never the profile blob),
`DELETE /api/health/sessions/<key>/completion` to undo a completion,
`GET /api/health/matches/suggestions` for the Today card.

## Running it

```bash
./ios/run_sim.sh                      # build + install + relaunch on a booted simulator
./ios/run_sim.sh /tmp/after.png       # …and screenshot the result
./ios/run_tests.sh                    # TrainingCompanionTests on the booted simulator
```

`API_BASE_URL` in `Info.plist` points at production; the simulator talks to the
real backend with the signed-in account, so do not generate a program from it
casually. Every change ends in the simulator with a screenshot (CLAUDE.md).

## Where things are specified

- `docs/design-system.md` — colour, type, spacing, the component catalogue
  (§6, including §6.13 the tab structure) and the routing rule.
- `docs/ios-interactive-design.md` — the interactive-polish plan (steps 4 and 6 open).
- `docs/workout-guidance-plan.md` — the watch app plan and its remaining gaps.
- `docs/widgets-setup.md` — wiring the iPhone and watch widget extensions.
- `../docs/information-architecture.md` — the journey both clients implement.
- `../docs/roadmap.md` — the ranked backlog (phone session logging,
  notifications and a Library tab are under *Later*).
