# Roadmap

The single backlog for this project. Last verified against the code and the
production database on 2026-09-30; the information-architecture items were added
from the functionality review of 2026-10-01 (`information-architecture.md`).
The Garmin items (1, 2 and 5) were added on 2026-10-05 from the Connect IQ
connection plan, after a read-only look at production; item 4 on 2026-10-09
from the watch-app demo tests. Item 9 was rewritten on 2026-10-19 as the combined
generation-fidelity plan (the Codex audit, its Wildman contract and a re-measurement).

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
| 4 | Watch app: Garmin-native look, menus and icons | P2 | M | watch |
| 5 | On-demand HRV capture on the watch | P3 | M | watch, API |
| 6 | Watch: package-owned screens — verify and finish | P2 | M | watch, API |
| 7 | Phases and tracks: review the drafted phase text; verify the iOS track picker and phase names (*IA*) | P2 | S | content, iOS |
| 8 | Web ↔ iOS parity: what the 2026-10-13 consolidation left open (*IA*) | P2 | M | iOS, web, API |
| 9 | Generation fidelity: every package built as its method prescribes — all eleven audited and merged 2026-10-22; Horsemen's media and unpublished material left | P1 | L | engine, content |
| 10 | Progress tracking: what phases A–E left open, and the watches | P2 | M | API, web, iOS, watch |
| 11 | Apple accounts: switch on, verify on a phone and the web; email code and passkeys later | P2 | S | iOS, web, API |
| 12 | Standards: the Garmin unit tests, a test day on both watches | P2 | S | API, watch |
| 13 | Heart rate from the programming: ship the watches' exercise times, fidelity, pauses | P2 | M | watch, engine |
| 14 | Watch parity: the Apple Watch on the server's contract and vocabulary | P2 | M | watch, iOS, API |
| 15 | Program preview on the phone; the regenerate offer that asks the server first (*IA*) | P2 | M | iOS, web |
| 16 | Garmin's official Connect API, open again since 2026-10-21: verify the integration, then health data and workouts pushed to the watch | P2 | M | API, watch, web, iOS |

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

*Status (2026-10-06, `feat/garmin-wellness`):* 2 and 3 are done but not yet
compiled — the watch sends its part number and the server names it from
`data/garmin_devices.json` (`device_store.device_label`; an unknown part shows
as itself so it can be added); the manifest lists all five fēnix 9 Pro ids, as
the spike's SDK-generated manifest spells them. 1 is done on the web: `/pair`
(`pages/PairDevice.tsx`) shows the code and claims it on a tap, and sign-in
keeps the link (`ProtectedRoute` → `LoginPage` → `lib/returnPath.ts`). For the
watch to encode the link, set its `webBaseUrl` setting to the web origin in the
Garmin Connect app (Connect IQ app settings) — no rebuild. Still to do: compile
`fenix9pro47mm` on the Mac. Revoke is fixed (below).

The Devices card's Revoke button sent back the truncated token the list shows
and always 404'd. Fixed in item 2, slice 2: revoke resolves the display id to
exactly one of the athlete's own tokens.

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
  readings wins, ties go to `daily_bio`), and the response gains `sources`
  saying where each component's data came from. Body Battery and recovery
  time were display-only in v1; since 2026-10-15 they are scored — they stand
  in for missing HRV and recovery left caps the score (`recovery_pending`),
  because a steady resting HR read 67 against Garmin's 17 (CLAUDE.md, Watch
  wellness). Garmin's Training Readiness and overnight HRV stay out of reach:
  Connect IQ SDK 9.2 exposes neither (its complications add a sleep score and
  training status, which a device app may not be able to read — untested).
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

   *Results so far* (installed 2026-10-05 16:04; morning 1 = 2026-10-06, read
   at 10:35–10:50 after a workout; the app was closed 07:02–10:42):

   | # | Finding | State |
   |---|---|---|
   | 1 | `r` read **46, 46, 46** on mornings 1–3 while the watch showed **46, 45, 49**: `UserProfile.restingHeartRate` is the zone *setting*, not the day's value. `a` (7-day average) 47, 46, 47 matches Connect's. `h` (HR low, 6 h) 42, 43, 47 — 4, 2 and 2 under the watch, moving with it (+1/−1, +4/+4) | **fails** for `r`; the `h` fallback passes. Scoring now uses `hr_min` (below) |
   | 2 | From the background: `h42/42#360`, `b95/48/68#240`; `getMin/getMax` return numbers equal to the walk's (hr 42/163, bb 51/95, kinds `NN`), so the real feature can skip the walk. Run 563 ms (hr 173, bb 118). Memory: start 17 816, read 24 448, peak 29 544 **of 61 344** | pass on this watch — the 24 KB line was for 32 KB devices; this budget is 60 KB |
   | 2a | Heart-rate history holds **6 hours, not 8**: 360 samples at one a minute, span 359 min, below the 600 cap; `ActivityMonitor` also n360. A morning read covers only the last 6 h, so read early in the morning window | design constraint |
   | 3 | `tr` 58, 35, 82 = the watch's 58 h, 35 h, 82 h on mornings 1–3 | pass (3 of 3) |
   | 4 | 10-06: 44 runs, 00:04 → 10:35, longest gap 15 min (43 temporal + wake); 10-05: 33 (32 + sleep); overnight 23:49 → 00:04. API ok 20, fail 0, killed 0; last 1 283 ms, worst 6 434 ms | pass |
   | 5 | `w07:00 s22:15` | awaiting Connect's configured times |
   | 6 | Part number `006-B4953-00`, fw 6.49, Monkey C 6.0.3 — a fēnix 9 Pro, 47 mm by the owner's account (`fenix9pro47mm`); `tools/gen_products.py --part 006-B4953-00` would confirm it | owner's answer; the manifest carries all five Pro ids meanwhile |

   SpO2 read null with no samples (Pulse Ox off at night); nothing uses it.

   **Garmin's exact daily resting HR already reaches the server another way.**
   Garmin Connect writes it to Apple Health, one value a day (46, 45, 49 for
   6–8 Oct, identical to the watch), and the iOS relay reads HealthKit's
   resting heart rate from any source into `daily_bio`. So `merge_for_scoring`
   keeps `daily_bio` first and scores the watch's `hr_min` only where that
   path has fewer readings; the watch's `resting_hr` is stored for display and
   never scored. Two relay defects keep the exact value from arriving on time
   (`ios/TrainingCompanion/SyncManager.swift`, `syncAll`): it stops at
   `cursor < today`, so today's value lands tomorrow, and it skips any date
   already on the server, so a day pushed before Garmin Connect synced keeps no
   resting HR for good. **Written, not yet built** (2026-10-08):
   `BioSyncPlan` (`ios/TrainingCompanion/BioSyncPlan.swift`, pinned by
   `BioSyncPlanTests`) sends today and the two days before it on every sync,
   and older days only when the server lacks them. On the Mac:
   `./ios/run_tests.sh BioSyncPlanTests`, then a sync in the simulator. One
   side effect to know: `upsert_daily_bio` replaces a day wholesale, so a
   manual check-in (web `DailyCheckin`) for one of those three days is now
   overwritten by the next sync, where before only older days could be.
1. **Done** (`feat/garmin-wellness`, not deployed). The migration, `src/wellness.py` (`validate`, `merge_for_scoring`) and
   `test_wellness.py`. The SQL suite makes its own throwaway database, not
   `training_test`.
2. **Done**, `test_device_scope.py`. A device-token allowlist (the four routes the watch calls today plus the new
   one, everything else 403) and the Revoke fix (the list shows a 14-character
   prefix and revoke deletes by the full token); a test enumerates every
   protected route.
3. **Done**. `POST /api/health/wellness` (gated by the Garmin integration toggle,
   validated, idempotent, 503 on a failed write so the watch retries),
   `wellness_store.py`, one `_bio_for_scoring` loader at the four scoring sites,
   and the program-analytics digest hashing merged values (it hashes only bio
   *dates* today, so a changed same-date value never busts the cache).
4. `GET /api/health/wellness/latest`, `data/garmin_devices.json` (part number to
   model), a Devices-card line and a readiness footnote on web and iOS. **Done
   except iOS**: the route, the lookup, and on the web the Devices card's
   "Last wellness reading" line (`lib/wellness.ts`) and the readiness footnote
   (`lib/readiness.readinessSourceNote`, `ReadinessWidget.test.tsx`). **iOS
   written, not yet built** (2026-10-08): `ReadinessSourceNote` on Today and
   Analytics ▸ Recovery, the last reading in Settings ▸ Devices
   (design-system §6.21, `ReadinessSourceTests`). On the Mac:
   `./ios/run_tests.sh ReadinessSourceTests BioSyncPlanTests`, then
   `LOCAL_API=1 ./ios/run_sim.sh` on Today and Settings.
5. Watch: foreground-on-open sync; delete the dead `PUT /health/bio/{date}`
   chain (`SyncManager.mc:185-192`) and the TODO at `WorkoutController.mc:807`.
   **Written, not compiled** (2026-10-06): `Wellness.mc` reads only calls the
   spike ran on the watch, keeps each value inside the server's bounds
   (`test_wellness.py` checks the two agree), and `SyncManager.sendWellness`
   posts on open (at most every 15 min) before readiness is fetched, keeping
   one unsent reading for the next open. The bio chain and the TODO are gone.
   **Gate 2** — a week of rows matching Connect's numbers.
6. Watch: the background service, a morning window (wake time + 30 min to + 6 h)
   and a once-a-day marker. Send on the **first** fire in the window, not the
   last: the heart-rate history holds six hours (spike finding 2a), so a late
   send has already lost the overnight low. **Gate 3** — at least 6 of 7 mornings sent without
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

#### Next steps — handoff of 2026-10-08

State: everything above is on branch `feat/garmin-wellness`, open as **PR #101**
(CI green on the web and server). Nothing is deployed. Two parts have never
been compiled, because the cloud sessions that wrote them had no Xcode and no
Connect IQ SDK: the Swift in `ios/` (`BioSyncPlan`, `ReadinessSourceNote`,
`WellnessReading`) and the Monkey C in `garmin/TrainingCompanionCIQ/`
(`Wellness.mc`, `SyncManager.sendWellness`, the manifest). The athlete has a
Mac again from about 2026-10-14.

**A. Until the Mac (phone only, daily).**

1. Spike mornings 4 and 5 (2026-10-09, -10): before any workout, a photo of the
   spike's LOG page plus the watch's resting HR, recovery time and 7-day
   average. Add a column to the results table above. What is still being
   watched: `h` keeps moving with the watch's resting HR (within 5 bpm), and
   `tr` keeps matching. `r` is settled (the zone setting) and needs no more
   data.
2. Leave the spike installed until step B10 is done; it costs nothing and its
   DAYS page keeps proving the background events fire.

**B. The Mac session, in this order.** Stop at the first step that fails, fix
it (or paste the error into a session), and only then go on — B6 deploys.

1. *Branch.* `git fetch origin && git checkout feat/garmin-wellness && git pull`.
2. *Server checks* (`.venv`, a local Postgres for the SQL halves):
   `.venv/bin/python test_device_scope.py`,
   `SUPABASE_URL='' .venv/bin/python test_wellness.py`,
   `SUPABASE_URL='' .venv/bin/python test_program_analytics.py`,
   `cd frontend && npx vitest run`. All must pass; they passed in the cloud.
3. *iOS compile and tests.* `./ios/run_tests.sh BioSyncPlanTests ReadinessSourceTests`,
   then the whole bundle `./ios/run_tests.sh`. A compile error here is the
   expected kind of failure (the Swift was never built); fix it on this branch.
   Then the simulator, per CLAUDE.md: `python api.py` on this branch, and
   `LOCAL_API=1 ./ios/run_sim.sh /tmp/today.png`. Check the readiness card on
   Today shows the source line under the score ("Resting HR … from Apple
   Health and check-ins.") and, via Profile ▸ gear ▸ Settings, that Devices
   still lists devices and Sync Now still works. Screenshot both.
4. *Watch compile.* `cd garmin/TrainingCompanionCIQ && DEVICE=fenix9pro47mm ./build.sh --device`.
   The part number `006-B4953-00` is mapped to `fenix9pro47mm` only from the
   athlete's word; `python3 ../WellnessSpike/tools/gen_products.py --part 006-B4953-00`
   confirms it from the SDK's device files. If the id differs, change
   `data/garmin_devices.json` (`product`) and the build command, nothing else.
   Fix any compile error in `Wellness.mc` / `SyncManager.mc` on this branch;
   `test_wellness.py` (watch parity) must still pass afterwards.
5. *Production database.* `scripts/backup_prod.sh` (needs `.env` from
   `op inject -i .env.template -o .env` and Homebrew `libpq`'s pg_dump 17; it
   must exit 0 with every row count `ok`). Then
   `python run_migration.py 009_wellness`. Check the policy exists:
   `select policyname from pg_policies where tablename = 'daily_wellness';`
   → `users access own wellness`.
6. *Merge PR #101.* Merging deploys the API (`deploy-api.yml`); wait for it to
   go green. Smoke test: `curl -s https://training-api.fly.dev/api/devices/status`
   answers 400 `Missing device token`; signed in on the web, Settings ▸
   Connections still lists devices and Home still shows readiness (now with a
   source line).
7. *Watch app on the watch.* USB, copy the `.prg` from `bin/` into
   `GARMIN/APPS/`, eject, open Training Companion. Pair: the watch shows a
   code — enter it under Settings ▸ Connections ▸ Watch devices, or scan the
   QR once B9 is done. The Devices card must name it "fēnix 9 Pro 47 mm" (an
   unknown part shows as "Garmin 006-…": add it to `data/garmin_devices.json`).
8. *First wellness post.* Opening the app posts one reading. Within a minute
   the Devices card shows "Last wellness reading from the fēnix 9 Pro 47 mm:
   … HR low …, 7-day resting HR …, Body Battery …, recovery … h". Compare HR
   low and recovery with the spike's LOG and the watch. Nothing there after
   two opens 15 min apart → the post failed; the watch keeps it in Storage
   (`wellnessPending`) and resends on the next open — check the Fly logs for
   `POST /api/health/wellness` and its status (422 lists the refused field).
9. *Pairing QR link.* In the Garmin Connect app ▸ Training Companion ▸
   Settings, set **Web app URL** to the web origin (the `FRONTEND_URL` Fly
   secret). Unpair and pair again: scanning the QR with the phone opens
   `/pair?code=…`, which pairs on a tap.
10. *iOS on the phone.* Install the build from Xcode, open it, Sync Now. Then
    check that today's resting HR on the server equals the watch's
    (`GET /api/health/bio/recent` or Analytics ▸ Recovery): that is the
    `BioSyncPlan` fix. Garmin Connect must have synced first (open it).
    Readiness's source line should now read "Resting HR, HRV and sleep from
    Apple Health and check-ins." Uninstall the spike app afterwards.
11. *One real workout.* Start today's session in the app: the live HR must
    match the watch's own HR field, and the zone it announces must match
    Garmin's zone colour (`UserProfile.getHeartRateZones`). After finishing,
    the workout appears in the web Log and is matched to the session. If the
    server's zones disagree with the watch's, set Garmin's max HR under
    Profile ▸ Heart Rate (the server uses that, else 220 − age).

**C. Gate 2 — the seven days after B.** Each morning, open the watch app once
before training, then check on the web: a `daily_wellness` row for the day
(Devices card), its HR low within 5 bpm of the watch's resting HR, and today's
`daily_bio` resting HR equal to the watch's once Garmin Connect has synced.
Record the seven days in a table here. Pass: 7 of 7 rows, 7 of 7 equal resting
HR values. A fail of the second half points at the relay (B10), not the watch.

**D. After Gate 2.**

1. Slice 6, the background send (item 6 above). Reuse `Wellness.read()` and
   `SyncManager.sendWellness`'s pending/fold logic in a `(:background)` service;
   send on the first temporal event after wake time + 30 min, once a day
   (marker in Storage); the spike measured a 61 KB budget with 29.5 KB peak
   for the reads alone, so keep the service free of view code. Also refresh
   the glance cache (today's session and readiness) from the same run, so the
   glance stops saying "Open to sync". Gate 3: 6 of 7 mornings sent without
   opening the app.
2. Delete `garmin/WellnessSpike/` (its findings live in the table above) in
   the slice-6 change.
3. Optional hardening: `upsert_daily_bio` replaces a day wholesale, so a manual
   web check-in for one of the last three days is overwritten by the next
   phone sync (`BioSyncPlan` re-sends them). If manual check-ins are used,
   make that upsert merge non-null fields instead.

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

### 4. Watch app: Garmin-native look, menus and icons — P2 · M

The demo builds (`./build.sh --demo`, tested on the athlete's fenix 9 Pro
47mm, 2026-10-08/09) work, but every screen is our own invention: the stop menu
is a plain `Menu2`, the finish screen is one page, there is no confirmation on
Discard, and the button map (BACK cycles reps → weight → RPE → pages → END)
exists nowhere else on the watch. The athlete photographed Garmin's own
activity flow (pre-start list, data page, stop menu, "Discard?", the summary
page loop, "Delete activity?") and asked for ours to match it.

**Garmin's guides ship inside the SDK** — no web lookup needed, and they match
the installed SDK 9.2.0 exactly:

- `<SDK>/doc/docs/User_Experience_Guidelines/` — workflows, menus, views,
  confirmations, visual design. Its rules that bind us: *"Use the native menus,
  confirmations and progress bars. They will automatically have the product
  personality"*; up/down page loops, never left/right; at most seven items in a
  menu; don't change the back behaviour; keep input minimal during activity.
- `<SDK>/doc/docs/Personality_Library/` — the **Personality UI** style system:
  Monkey Style selectors (`personality="…"` in resource XML, `Rez.Styles.*` in
  code) that resolve per device to Garmin's own colours, fonts, icon assets,
  positions and input mappings.
- `~/Library/Application Support/Garmin/ConnectIQ/Devices/<id>/personality.mss`
  plus the SVGs beside it — present for all seven products in the manifest. On
  `fenix9pro47mm` the delete-confirmation hint sits at (353, 77), the START
  button, mapped to `KEY_ENTER` — exactly the red trash arc in the photo.

**What the library gives us, and what it does not:**

| Need | Source |
|---|---|
| Save, Discard (red variant), Check (green), Cancel, Revert (undo), Warning, Question, About | `system_icon_{dark,positive,destructive}__*` |
| Button hints for all five buttons (the white arc at the START button on every summary page) | `system_icon_dark__hint_button_*` + `system_loc__hint_button_*` |
| "Discard?" / "Delete activity?" page | `confirmation_icon__hint_delete`, `__hint_reject`, `confirmation_font__body`, `confirmation_input__delete` (the Personality *Delete Confirmation* recipe; `WatchUi.Confirmation` only does yes/no) |
| Black/white activity colours, prompt colours and fonts | `activity_color_dark__*`, `prompt_*` |
| Menu icon size, toast icon size | `system_size__menu_icon`, `system_size__toast_icon` |
| Resume ▶, Lap, Skip, Week, Workout, Rest, Heart icons | **Not in the library.** Draw our own SVGs at the same size and stroke weight. Copying Garmin's artwork is out: the store review guidelines require owning or licensing all IP. |

APIs, all within the fenix 9's on-device API 6.0.3: `Menu2` + `IconMenuItem`
(3.0), `CustomMenu` with a `:foreground` drawable (for the red paused ring),
`ActionMenu` (3.4), `ViewLoop` (the system page loop with its own page
indicator), `showToast`, `View.setActionMenuIndicator` (5.1.1), and
`Activity.Info.trainingEffect` (live aerobic TE, for the summary).

**Fonts.** Garmin uses two families: Roboto for text and Bionic for numbers
(`simulator.json`: `FONT_MEDIUM` is Roboto-Regular, `FONT_NUMBER_HOT` is
Bionic_Medium on the 47mm). `ui/Text.mc` already asks for Bionic and Roboto
Condensed by vector face, but the two **solar (MIP) models have neither
BionicBold nor BionicMedium** — only `BionicSemiBold` — so every hero number
there silently falls back to a bitmap font. Add `BionicSemiBold` to each face
list, and use Roboto Regular in capitals for the field labels ("DISTANCE",
"PACE"), as the native data page does.

**The flow, screen by screen** (Garmin's, from the photos → ours):

1. *Pre-start* — activity icon in its colour, the name, a subtitle, a coloured
   rule, then a list of icon + title + subtitle rows (Training, Navigate…). →
   `SessionListView` becomes that page: modality icon, session name, "45 min ·
   6 exercises", the accent rule, and rows for Workout (the exercise list),
   Week (`UpcomingView`) and Readiness, with the START hint arc. BACK exits
   (done in v8).
2. *Data pages* — a heart-rate zone gauge across the top (five zone colours,
   a marker), capital Roboto labels over Bionic numbers, hairline dividers,
   vertical page dots on the left, the timer at the bottom. → Restyle
   `ExerciseScreen`'s three pages in that grammar, the HR gauge from
   `UserProfile.getHeartRateZones`, and the page dots on the left.
3. *Stop menu* — START pauses; a red ring circles the screen; Resume, Save,
   Discard, Lap… with icons. → `CustomMenu` with the red ring as its
   foreground and icon rows: Resume, Save, Discard, Skip exercise, Lap.
4. *Discard?* — the Personality delete confirmation: red trash at START, back
   arrow on BACK. → Built from the selectors; Discard asks first again (v7
   dropped that because of a view-stack bug, not because the dialog was wrong:
   the confirmation must pop itself before anything switches views).
5. *Summary* — a page loop with vertical dots and the next page named at the
   bottom ("HEART RATE", "TRAINING EFFECT"); START opens Done / All Stats /
   … / Delete. → A `ViewLoop` of Overview (duration, sets, volume), Heart rate
   (avg/max and a chart from the samples the controller already keeps),
   Exercises (sets × reps @ kg each) and Sync. START opens an `ActionMenu`:
   Done (exits), Exercises, Heart rate. No Delete: Connect IQ cannot delete an
   activity once `ActivityRecording.save()` has run — Discard before saving is
   the only delete there is.
6. *Toasts* — "Set logged", "Synced", "Sync failed — will retry" through
   `showToast` with the library's check and warning icons, instead of hint-line
   text.
7. Week view, glance and pairing: system fonts and personality colours, no
   layout change.

**The button map: Garmin's** (the athlete's decision, 2026-10-09, with photos of
Garmin's own Strength workout). START pauses into the stop menu; BACK is LAP — it
ends a set and starts the rest, ends a rest early, counts a round or lap, or moves
to the next step; DOWN/UP turn the pages, the last page being the scrollable step
list ("Now: 2/5 Sets" in yellow, the focused row marked blue), which DOWN walks to
its end and then wraps to page 1; hold UP opens Stop Workout / Skip / Edit Set.
Garmin's own page 1 is ♥ HR, REPS | SET, a rule, "Next: Rest" / "1:00"; page 2 the
five-zone gauge, ♥ HR, the timer, REPS | ACTIVE CALORIES, the time of day.

*Status (2026-10-09, `feat/garmin-wellness`, uncommitted; store test upload v1.1.0):* all seven slices are
built and compile for all seven products; the Delete Confirmation, menu icons and
button hints come from the Personality Library (`resources/drawables/garmin.xml`,
`resources/layouts/confirm.xml`, `source/ui/Native.mc`). Not yet run on the watch:
the simulator could not be observed from the build machine's session (no screen
capture), so the first check is the athlete's. Two findings on the way: Rez.Styles
entries can only be read field by field (passing one as a value crashes the
assembler with "undefined symbol"), and with the Background permission and no
annotated code the whole app is the background image, which outgrew 64 KB —
`Config` is now `(:glance, :background)`.

*1.1.0 on the watch (2026-10-09):* START during a workout crashed the app — the
stop menu's IconMenuItems were given bitmaps loaded into the app heap; 1.1.1 hands
them a Drawable that draws a graphics-pool BitmapReference (Garmin's Menu2 sample
does the same) and gives the stop menu its title back. Not reproducible here, so
unconfirmed until the watch says so. Also from the test: a workout began recording
the moment it was chosen. 1.1.1 adds Garmin's workout menu on START (Do Workout /
Steps, where each exercise's reps, hold, weight and RPE are set for the run), a
ready state that records nothing until START, and Set Next in the hold-UP menu.

*1.1.2 (2026-10-09):* the glance follows the day — readiness ring and the next
session before any training; one segment per session, filled as each is done;
a green ring with a tick and the day's totals once all are done; tomorrow on a
rest day and after `Config.GLANCE_EVENING_HOUR`. A saved workout is recorded on
the watch (`DayLog`, Storage, local date; a discard is not); `GET
/api/user/today-session` now marks each session `completed` (a session log with a
completion time, or a non-rejected match — so another device's workout counts)
and carries `tomorrow` (`test_today_session.py`). Garmin's SDK has no glance
layout guide beyond "an executive summary"; the label-over-value shape copies
the watch's own glances.

*1.2.0 (2026-10-10):* three demo programmes chosen from hold UP ▸ Programme
(`demo_sof.json`, `demo_kb.json`, `demo_uphill.json`; `DemoProgram` loads only the
selected one and seeds the glance from it). New engine behaviour, all Garmin's:
timed steps end themselves (LAP ends them early), a full-screen step alert as each
step or interval phase begins (`views/StepAlertView.mc`), interval blocks as
Run / Recover or Work / Rest repeats in the step list, a toast when HR leaves the
target zone, a metronome for paced sets (hold UP ▸ Metronome), a hand switch
mid-set, rest that ends when HR drops under a target, and distance / pace on a
run's heart page. A session counts as cardio (GPS, run page, RUNNING sport) only
when it is aerobic *and* moves — an aerobic-base kettlebell session no longer
records as a run. **Follow-up:** `targetRpm`, `switchAtSec` and `restUntilHr` are
demo-only; `api._encode_watch_exercise` should send them once the generator carries
them (today they live in the archetypes' `notes`).

*1.2.1 (2026-10-10), from the 1.2.0 watch test:* the metronome beats on its own
timer (`60000 / targetRpm` ms), so paces above 60 RPM work — the hand-to-hand swing
is 70; Plan and Set Next edit the number of sets (Set Next never below the next set);
a double-kettlebell exercise (`bells`, or a `double_` exercise id) edits and shows one
bell ("5 Reps @ 2x24 kg", "KG PER BELL") while the step page and the "Next:" line show
the total (`Steps.preview`); kettlebell weights step by 4 kg (half a pood). `bells`
joins the encoder follow-up above.

*1.2.2:* the step alert announces only timed steps (a duration, an interval block)
and AMRAP / for-time blocks; set-based exercises start silently, and LAP no longer
shows a "Set 2/5" toast — the rest screen is the confirmation.

*1.3.0 (2026-10-10): the real app.* The athlete trains from the server's sessions from
here on: `./build.sh --release` builds the store `.iq`, which saves each workout to
Garmin Connect and uploads it. The demo property is now `demoProgrammes` (a stored
`demoMode = true` from the demo builds would have outlived the update). Double
kettlebell weights are per bell everywhere, as the packages prescribe them
(`kb_press_double` starts at 16 kg); the id suffix `_double` marks a double, and the
summary's volume counts both bells.

*1.10.0 (2026-10-23): cue settings and the lead-in, on both watches.* "Work in 3, 2, 1,
go" before work on a clock: the last three seconds of a set rest or an interval rest, a
rest-less EMOM's minute, and a heart-rate rest once HR is under its target; after START too,
with Countdown Start (`watch_vocabulary.json` `cues`; Garmin `Cues.mc`, Apple Watch
`WatchCues.leadIn` + `WatchCuePlayer`). Settings on the Garmin (pre-start and workout
hold-UP menus, and Garmin Connect Mobile): Tones, Vibration, Lead-in, Countdown Start, and
Lead-in Tones, picked by ear. On the Apple Watch (the Today list): Lead-in, Countdown Start,
Voice. What the platform will not do, found on the way:
- **No voice on the Garmin.** Connect IQ has no text-to-speech, no sound-file resource and no
  way to reach the watch's voice prompts. A custom `ToneProfile` pitch is silent on speaker
  watches (fenix 8 and 9; forum reports from the Connect IQ team), so only the 19 built-in
  `TONE_*` sounds are usable. *Later:* the phone could speak for the Garmin (the Connect IQ
  Mobile SDK in the iOS app, a phone-app message per count; Bluetooth adds 0.5–2 s).
- **The simulator cannot show the native screens.** It runs only Connect IQ code, and its
  `Menu2` is generic; on the watch `Menu2`, `Confirmation` and the Personality layouts draw
  natively. The reference stays the athlete's photos and the fenix 8 manual (Activity
  Settings, Strength, HIIT, Stopping an Activity).
- **Post-workout data:** aerobic TE only (`Activity.Info.trainingEffect`); recovery time,
  training status and VO2 max through `Complications` (API 4.2); no anaerobic TE and no
  Acute Load. The TE page will show aerobic only.
- **One glance per app:** variants are a style setting. Whether a Connect IQ glance can go
  in a fenix glance folder, and whether a glance-launched app may record, needs the watch.

*The pre-start page as Garmin's (2026-10-23, same release):* the header focused, START
starts at once, DOWN into a list (Workouts, Steps, Training Calendar, Progress, Readiness,
Settings, Sync) drawn by `NativeList` — in place of the Do Workout / Steps menu and UP/DOWN
cycling the day's sessions; hold UP lists the same rows as a Menu2.

*1.11.0 (2026-10-23): the end as Garmin's, from the athlete's photos of Strength.* Save →
"Saving" (an arc sweeps the bezel) → "Activity Saved" (green ring) → the post-save list
(Done · All Stats · Training Effect · Heart Rate · Sets, each page's number left of the
rule; `SummaryList.mc`) → All Stats: Summary, Heart Rate, HR Zones and Training Status (new
`summary_pages`), Training Effect, Exercises. Discard → "Discarding" (red) → "Activity
Discarded" → closed (`OutcomeView.mc`). Training Status shows recovery time and VO2 max:
the status word is a complication, and `ComplicationSubscriber` is a watch-face
permission (the SDK's `projectInfo.xml`), so a watch app cannot read it.

*1.12.0 (2026-10-24): glance styles.* `glanceStyle` (Settings ▸ Glance, and Garmin Connect
Mobile): Next up (the default, left-aligned in `FONT_GLANCE` — the day's state, the next
session, its minutes and the week), Day bar (a segment per session, or the week's on a rest
day) and Ring (the glance until now). The words are `GlanceDay.mc`'s, tested on hand-built
days. Still for the watch: the glance in a folder, the app among START's activities, and
whether a glance-launched copy records.

*Next:* HIIT and Run need the same photos as Strength (pre-start, pause, summary) before
their pages are matched.

**Order of work** (each slice ends in a demo `.iq` and photos from the watch;
the simulator can't be scripted, so also passive `monkeydo` screenshots on a
round AMOLED and a solar MIP device):

0. *Spike (S).* Add one Personality layout (the delete confirmation) and one
   icon menu item; build all seven devices; confirm `Rez.Styles` compiles at
   `minApiLevel` 4.0.0 and the solar 260/280 px screens place the hints.
1. *Menus, confirmation, toasts (S).* Slices 3, 4 and 6 above; the icon SVGs we
   draw ourselves.
2. *Summary loop (M).* Slice 5.
3. *Data pages (M).* Slice 2, and the button map once decided.
4. *Pre-start page (S).* Slice 1.
5. *Fonts and the rest (S).* The `BionicSemiBold` fix and slice 7.

Acceptance: on the fenix 9 Pro and in the solar simulator, the stop menu,
Discard confirmation and summary sit beside Garmin's own photos without
standing out — same fonts, the library's icons where it has them, hints at the
real buttons — and no screen needs a hint line to explain its buttons.

---

### 5. On-demand HRV capture on the watch — P3 · M

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

### 6. Watch: package-owned screens — verify and finish — P2 · M

Added 2026-10-11. The watch app is now a core library (`garmin/core`) inside an
app shell, and each package's `watch.yaml` says how its sessions look
(`data/commons/watch_vocabulary.json`, `src/watch_spec.py`,
`GET /user/today-session?spec=1`, one `SpecRenderer` in place of the eight
slot-type renderers and `ArchetypeBehavior.mc`). Everything builds for the seven
products and `test_watch_spec.py` passes. Still to do:

1. **Hardware (S).** Sideload a `--demo` build and walk each demo programme:
   pre-start → data pages → LAP → stop menu → Discard? → summary, beside the
   1.3.0 photos. Visible changes to confirm: a side-tracked get-up alternates
   Left/Right on each set (it never switched before), Gym Jones' get-ups count
   toward 100, the TGU phases strip, the pentathlon RPM beside the clock, and a
   weighted ruck in km on its main block only. Then a real day against
   production with `?spec=1`.
2. **Monkey C unit tests (S).** `build.sh --test` compiles `garmin/core/test`; it
   was never run, because the simulator was not reachable from the session that
   wrote it. It did not even compile from #152 until 2026-10-18 (`WireTests.mc` indexed an
   untyped `{}`). First run 2026-10-18 on `watch/spec-render`: 13 tests, all passed, among
   them `specFixturesDrawEveryCase` (the 28 cases the Apple Watch's `WatchSpecTests` run).
   `monkeydo -t` exits 1 even when all pass; read its RESULTS table.
3. **Server fields — done 2026-10-18 (item 14.5).** `targetRpm` came from the
   exercise's IKMF cap (#102); `switchAtSec`, `restUntilHr` and `bells` now do
   too — from archetype slots and exercises.yaml, through `_encode_watch_exercise`.
4. **Split `WorkoutController` (M).** Still 1,300 lines; the plan was
   Recorder / HrStore / GpsTrack / StepClock / SetLog / Upload behind the same
   facade. Not needed for packages to own their screens, so it was left for
   after the hardware check.
5. **iOS Apple Watch (M).** It still picks views by `slotType`/`archetypeId`; it
   could read the same `?spec=1` table. Moved to item 14.

---

### 7. Phases and tracks: review the text, verify iOS — P2 · S

Philosophies own their phases since 2026-10-13 (`src/phases.py`, CLAUDE.md
*Philosophies own their phases*). Open:

1. **Review the drafted phase text (S, content).** Every phase name, focus,
   description, adaptation list and intensity line in the eleven
   `philosophy.yaml` files was drafted from that package's own notes. Gym Jones'
   Accumulation → Transmutation → Realization, Horsemen's four months and Ido
   Portal's isolation → integration → expression come from their notes;
   Wildman's phase names, and the single repeatable phase given to Starting
   Strength, CrossFit, Marcus Filly and BJJ, are inferences.
2. **Review the widened `applicable_phases` (S, content).** The per-phase
   coverage check needed eleven archetypes to apply to more kinds. Wildman's
   General Practice now runs `kb_pentathlon_training` as its strength-endurance
   session in every phase, because that is the package's only one; a general
   strength-endurance archetype may be the better fix.
3. **iOS — verify in the simulator (S).** Written on 2026-10-13 without a Mac:
   the builder's track picker and start phase, the settings sheet's, Program ▸
   Current's phase names and kind colours, Today's label, the methodology
   sheet's tracks and Analytics ▸ Program's phase name and focus;
   `PhaseTrackTests` added. Not yet compiled or run: build, run
   `./ios/run_tests.sh`, and screenshot the builder's step 2 (Wildman, two
   tracks), Program ▸ Current on an Uphill program, and the methodology sheet.
4. **Analytics frame (S).** `/analytics/program` now returns the phase's
   `label`, `description` and the `track`; both clients show the label and
   the phone the focus, neither the description yet.

---

### 8. Web ↔ iOS parity — P2 · M

From the feature-parity audit of 2026-10-13 (branch `web-ios-consolidation`),
which unified the menus and sections of both clients
(`information-architecture.md` §2), made Recovery and the Apple Watch show the
server's readiness, gave Today's suggestions Accept, added Log ▸ Sessions on the
web, and moved the workout analysis, the Load KPIs and Today's compliance to the
server. Left open:

1. **Strava and Garmin connect on the phone (M).** The web connects, syncs and
   backfills both (Settings ▸ Connections); the phone only has the per-source
   toggles. The OAuth callbacks land on the web (`_integrations_redirect`), so
   the phone needs a server-side return URL for the app
   (`ASWebAuthenticationSession` with a custom scheme) before any UI.
2. **Equipment profiles (S).** `GET /constraints/equipment-profiles` exists and
   neither client offers the presets: the web's equipment list is hard-coded and
   `useEquipment` is never called; the phone's `fetchEquipmentProfiles` has no
   caller. Offer them on both Equipment sections or delete the route.
3. **Dead code (S).** `FITFileParser.swift` and `Swiss3DMapView.swift` (iOS);
   `usePlannedSessions`, `fetchProgressionHistory` and `useEquipment` (web);
   `computeWeekInsights` and `computeDevelopmentTrends` in `lib/sessionAnalysis.ts`
   since Today's card reads the scorecard; the phone's `AnalyticsEngine`
   weekly-consistency and modality helpers once the fallback is retired.
5. **Session insights are still client-side (M).** `lib/sessionAnalysis.ts`
   `computeSessionInsight` (prescribed vs actual on a matched workout) runs only
   on the web; the phone has no equivalent. Serve it with the workout analysis
   so both clients show it.
6. **Weekly zone summary (S).** Analytics ▸ Recovery's `WeeklyZoneSummary` on the
   web still splits zones in the browser; read `/health/load/summary`'s zone
   minutes instead.
4. **Profile's fifth segment truncates on the phone (S).** "Benchmarks" shows as
   "Benchm…" in the segmented control (it did in fourth place too). Either a
   shorter label on both clients or a scrolling selector in `AppSubTabPicker`.

### 9. Generation fidelity: every package built as its method prescribes — P1 · L

The combined plan of the Codex audit (`docs/package-quality-and-generation-audit.md`,
the ten root causes and matrix A–I), its Wildman contract
(`docs/wildman-generation-branch-handoff.md`, `src/training_contract.py`) and the
2026-10-19 re-measurement and research appended to the audit. It absorbs this
item's earlier contents (the fidelity baseline, kept below as 2.1–2.6).

**Where it stands (2026-10-22): every package is audited.** All eleven grade
`audited` on every track (`docs/package-fidelity/scorecard.md`), none graded out
since Horsemen's GPP Circuits was dropped. Each runs its author's published program as written — five as training
contracts (Wildman, Starting Strength, BJJ, Uphill, Marcus Filly), six as week
templates (Horsemen, CrossFit, Gym Jones, ATG, Kelly Starrett, Ido Portal) — and no
shipped package runs on the modality scheduler any more (its tests use
`test_packages/block_fixture`). What is left, in order:
1. *Ship the stack* — **done 2026-10-22**: #192–#195 merged, each reviewed first; the
   reviews found BJJ's module-only deload week read as ordinary by the analytics
   (`Context.is_deload_session`) and four dropped tracks with no successor, whose stored
   programs answered 422 on a regenerate (`former_ids`). iOS 1.28.0 (build 671) and
   Garmin 1.8.0 carry the rep schemes to the devices.
2. *Assessment gating* — **done 2026-10-22, as advice** (the owner's call, the rule of
   Wildman's layoff: recommended, never enforced). No source writes a pass mark, so a
   framework category's `advice` (`week_template.advice_for`, per level when it differs)
   says the method's recommendation once in each session, at its first movement: ATG's
   ladders (move up a step when it is yours without pain), Ido's versions (set the next
   level in the profile once yours is owned), Built to Move's retests (after day 21).
   The engine never moves a level. Left: Built to Move's tests scored against the
   book's bands (needs a copy of the book).
3. *Hygiene* — **output reviews done 2026-10-22**: every package's programs were read
   against its record (S6, recorded in each `fidelity.yaml` `reviews` and dossier),
   and what they found fixed — the first movement of a for-time or AMRAP piece had no
   count in CrossFit, Gym Jones and Horsemen (55 slots; `progression._parent_count`);
   Starting Strength's work-up forecast named the wrong jump (the deadlift had one
   7.5 kg jump where Rippetoe gives three); BJJ's conditioning appeared in the deload
   week alone (optional work now goes by the last build week's minutes); Uphill's
   Specific long days were apart (R20, `adjacent_to_by_phase`); Gym Jones's day 17
   pressed from the floor where the PDF writes a bench press; Wildman's shortfall notes
   lacked their weeks; `print_package` failed on CrossFit. Media (D3) and D4 now pass
   everywhere but Horsemen. Horsemen's D4 passes too (the plate shuffle read as a
   plank moving a plate; the rest went with GPP Circuits). Left: Horsemen's exercise
   media (15 of 217; content, item 3's kind of work, to be done on its own).
4. *GPP Circuits* — **dropped 2026-10-22** (the owner's choice): the source has no
   circuits program, only a circuit day in the macro, which itself repeats. The track,
   its framework, seven archetypes and the twenty exercises only they used are gone; a
   stored program that names it regenerates as the 4-Month Macro from its first month
   (a track's `former_ids`, `phases.find_track`).
5. *Rep schemes and the phone* — **done 2026-10-22**: a slot's `rep_scheme`
   (`progression.round_count`) carries Fran's [21, 15, 9] and 24 other workouts' schemes
   in CrossFit, Gym Jones and Horsemen, in place of the per-round average or first
   round; the web, the phone (`LoadFormat`, which now also shows an AMRAP's and a
   for-time piece's own count) and both watches show it, the watches each round's own
   count. A for-time piece's movements fold into its round on the Apple Watch, as they
   did on the Garmin, and its step lists them (`for_time` lines `components`). Needs
   the Garmin store release and a TestFlight build to reach the devices.
6. *Each package's "Left"* (step 4 below) — mostly material that is not public:
   Uphill's novice plan, Filly's 4x/5x tracks and Base Camp, CrossFit's scaled
   novice track, Operator Fitness II, the Starrett books; then Wildman's follow-ups
   (step 5), the portability leftovers and the Dev Lab (step 6).

The finding behind it: the contract fixed Wildman, and nothing else moved. Novice
Gym Jones, Horsemen, Filly and Uphill programs are half to three-quarters
substitutes, CrossFit is one AMRAP template, BJJ trains the mat once a week in
five, Starting Strength serves intermediates other sessions inside its novice
track — and the fidelity gate (184 of its 228 findings are intensity splits) sees
none of it. The Dev Lab's Impact tab waits: it explains degraded programs, and
the aim is to stop generating them.

**0. Land what exists (S) — done 2026-10-19.** `wildman-contract` merged as #172
(after a review that found the 422-for-every-infeasible regression, split sessions
refusing contract tracks, requirements ignoring level seeds, iOS never decoding
them, blends refused, and more — all fixed) and `dev_lab` as #173. CI also caught
that the loader listed files in the filesystem's order, so Linux (production) and a
Mac generated different programs from one request; it now sorts. Existing programs
keep their weeks until the athlete regenerates from tomorrow on, which keeps the
elapsed days, their logs and matches.

**1. Make the failures fail (M, engine + content).** A generated-sample check over
every package × track × level (the 2026-10-19 table, reproducible), with each
package's defining claims as failing rules — not intensity splits:
- a novice program is not mostly substitutes; a refused level says so instead;
- BJJ mat sessions cannot be satisfied by gym S&C, and outnumber it;
- CrossFit varies element count, modality and time domain across a cycle;
- Starting Strength serves novice LP to novices and a weekly-progression track
  to intermediates;
- no session is delivered with every slot empty;
- the constraint-impact profiles (no equipment, a knee flag, one bell, 3 days)
  either keep the method or refuse with the constraint that would unblock it.
Run in CI next to `check_fidelity.py`; its baseline only shrinks. Every step below
is judged by it.

**2. Shared fixes for the ten packages still on the old generator (S–M).** Since
2026-10-22 none is: what follows binds only a package written for the modality
scheduler (and Horsemen's excluded GPP Circuits).
1. *Injury data that resolves (S, content)* — **done 2026-10-20.** 54 of 63
   `modified_exercises` pairs and 78 of 143 `excluded_exercises` named no exercise
   (the "94" first counted here predated Horsemen's full catalog). Every id now names
   a catalog exercise, each pair is declared together in one package (a program draws
   only on its own), names the flag's patterns already cover went, and
   `validate_entities.py` holds both.
2. *No silent degradation (S).* A session with no exercise left is refused or
   replaced by a declared substitute, never delivered; `EQUIPMENT_SCALED` stops
   promising scaling — the 44 archetypes' `scaling.equipment_limited` becomes
   structured substitutions or goes.
3. *An acceptance gate for every program (M).* Run the step-1 rules and the
   fidelity errors at generate time, as the contract's `verify` does: 422 with the
   reason, never a saved program that breaks its method.
4. *Level against track (S).* A level a track is not written for is refused with
   the track that fits (or, until one exists, the honest reason), not served other
   sessions.
5. *The fidelity baseline's own items (from before):* intensity splits that cannot
   be met (content); Uphill's base phase never ramps (engine — becomes the weekly
   ramp policy below); deloads keep more than declared; real two-a-days and per-day
   session time; the framework's `progression_model` drives no prescription.

**3. Grow the contract (M each, engine).** The policies the remaining methods need,
each with a schema field, compiler support, a `verify` check and a test:
load per confirmed exposure (Starting Strength, Horsemen strength); a weekly ramp
that restarts after a deload (Uphill, Gym Jones); protected external sessions —
attendance, not exercises (BJJ classes); variation within declared families and
time domains (CrossFit, Gym Jones, Filly conditioning); assessment-gated selection
(Kelly Starrett, ATG, Ido Portal; the one not built, 2026-10-22). Optional modules on free days exist (2026-10-19).

**4. Move packages onto contracts (M–L each, content + engine)**, ordered by how
badly the default misrepresents the method and whether its policies exist:
1. *Starting Strength* — **done 2026-10-20**, audited 2026-10-21. A contract from
   Rippetoe's 2013 articles and Alter's "The Reset": A/B variants alternating A-B-A /
   B-A-B, `load_per_exposure` (a made lift goes up, a miss repeats, two reset 5 %, a lift
   with no weight works up), the Texas Method as the intermediate track
   (`track_for_level`), confirm by lift on both clients. Since 2026-10-21 (branch
   `bjj-strength-deload`) the stall ladder is Alter's: after one reset the week's second
   squat is a light day (80 % of the first, 2×5), after two the squat, bench and press run
   5×3 (`stall.light_day`, `stall.scheme`, `with_stall`); layoff resets are the module's
   `advice`, never applied (I4, the owner's Wildman rule). Left: a stalled Texas Method
   Friday (no source rule), exercise media.
2. *BJJ* — **done 2026-10-19** (`data/packages/bjj/training_contract.yaml`): classes
   grow with the week and always outnumber strength; deloads drop rolling; declared
   substitutes and optional blocks. The compiler gained sets × reps and hold blocks,
   exposures by days, per-block deloads, alternatives and optional blocks. Since
   2026-10-21 the strength is StrengthLog's program as written (module `periods`).
3. *Uphill* — **done 2026-10-21** (branch `uphill-review`): a contract from Uphill
   Athlete's public articles, PDFs and podcasts (the books could not be read) — six days,
   the long day half the aerobic time, the `weekly_volume` ramp (three build weeks of 10 %,
   a recovery week at half, holding from Specific on), the General Strength circuit, max
   strength, the ME PDF's ten workouts, Zone 3 from week 13, a one-week taper; modules in
   named `phases`. It borrows nothing now. Left: a novice track (the beginner plan is sold,
   so on the mountaineering article's numbers), hill ME, exercise media.
4. *Marcus Filly* — **done 2026-10-21** (branch `filly-review`): a contract running
   Persist's two published 3x sample weeks as printed (Pump Condition, Pump Lift: warm-up,
   strength intensity, strength balance, conditioning or a finisher, cooldown; tempo and
   RPE per block), two six-week cycles and a Bridge week at RPE 6–7. The shoulder rehab,
   bodyweight and mobility sessions (no source) are gone. Left: the 4x/5x tracks and a
   novice track on Base Camp (neither public), the within-cycle progression.
5. *Horsemen* — **done 2026-10-19.** Stage 1 corrected the package against the source;
   stage 2 runs the 4-Month Macro as written: each month's example weeks day by day
   (`week_templates`), every named workout of the source (and its API section) an archetype in
   its category's pool, prescribed as written, the athlete's missing equipment passing a
   workout over (`src/week_template.py`, CLAUDE.md). Names with profanity or the slur are
   cleaned; the PT test takes the first and last hard job-specific days. Left: the clients do
   not send a templated day's `category` on a single-session regenerate yet (the server
   infers it from the modality); a session that prescribes one lift twice (the 1RM work-up,
   then sets at a percentage of it) shares one log entry per exercise on every client — logs
   need a slot-scoped key; elliptical, stair master, climbing, paddling and skiing have no
   equipment id; "400 m Rob Shauls" is undefined in the source; GPP Circuits remains an app
   track on its own archetypes.
6. *CrossFit* — **done 2026-10-21** (branch `filly-review`): Glassman's template as week
   templates — three on, one off (and five on, two off), the day types (one element, a
   couplet for time, a triplet for 20 minutes) as pools of named workouts as written:
   Table 4, the Girls, Murph, Michael, J.T. and the 2005 days read; the Girls are
   selectable tests of their standards, recurring irregularly. The single 20-minute AMRAP,
   the every-fourth-week test and `avoid_with: [max_strength, aerobic_base]` are gone.
   Audited on 2026-10-22, once the scorecard's equipment had `rings` (the Gym Jones
   review), the ring dip no longer required a removed `dip`, and Murph came round within
   twelve weeks. Left: a scaled novice track, more of the archive.
7. *Gym Jones* — **done 2026-10-21** (branch `filly-review`): the two plans the
   repository holds, as written, day by day — Operator Fitness (six days: strength,
   recovery, progression, circuit, the pack hike, power endurance, intervals, the
   breathing ladder, accumulation) and Soldier of Steel (hard day, recovery day, one rest
   day; a novice with no track named gets it) — as week templates of one-workout pools.
   The three-block periodization, its deloads, the 2 km row block test and the generic
   strength/EMOM/complex sessions are gone; the old package is the modality scheduler's
   test fixture (`test_packages/block_fixture`). Left: Operator Fitness II (the copy ends
   at day 17).
8. *ATG, Kelly Starrett, Ido Portal* — audited ahead of assessment gating (the owner's
   call, 2026-10-22), each recording the gating as open. *ATG* — **done 2026-10-22**:
   Ben Patrick's own published workouts as week templates of one-workout pools — ATG
   Zero (ten movements, no equipment, three days), Program #2 (two workouts, once each a
   week) and his Knee Ability Pro week (four days); every movement at its pain-free step
   of its ladder, which the engine does not track (Patrick writes no pass marks). The
   Range → Load → Maintain phases, their deload and the post-operative rehab ladder from
   the design document are gone. *Kelly Starrett* — **done 2026-10-22**: Kelly and
   Juliet Starrett's Built to Move 21-Day Challenge (their own day pages), day by day —
   ten vital signs' tests and practices, then the practices stacked (sit-stands one more a
   day to 21) — then day 21 every day; the through-the-day habits (steps, food, standing,
   sleep) in each day's notes. The books were not found to read; the Supple Leopard track
   built from descriptions of them is gone. The tests are practised, not scored: their
   bands are on the book's pages. *Ido Portal* — **done 2026-10-22**: the Floreio Routines
   PDF, all thirteen routines at the athlete's level (beginner, intermediate, advanced),
   six days a week in the PDF's order. The Isolation → Integration → Expression phases and
   the `requires` that locked movements behind exercises the package did not have are
   gone. Assessment gating for all three is advice since 2026-10-22 (step 2 above);
   Built to Move's tests scored against its bands are left.
   A `requires` naming an exercise the package lacks locks that movement below elite;
   Horsemen's did too (`kb_clean_single`, `kb_halo`, `sb_clean`, `sb_squat`), which kept its snatch test, snatch ladder and 12-minute
   complex from ever being placed; fixed 2026-10-22, and the reach check
   (`check_exercise_coverage._pooled`) now counts a pool workout only when the level
   has unlocked every slot.

**Package fidelity method (2026-10-20).** `docs/package-fidelity/` is how every
package is checked and improved from here: the method, `status.yaml` (where each
package stands and which engine shape it needs, gated by
`tools/check_package_status.py`) and the source dossiers. The order below follows it.

**The scorecard (2026-10-20)** is step 1 above made concrete: `tools/evaluate_packages.py`
grades every package × track on Source, Execution, Robustness, Data and Measurement
(`docs/package-fidelity/scorecard.md`), ratchets in CI, and derives `audited`. Audited:
Wildman, BJJ, Horsemen (4-Month Macro), Starting Strength (2026-10-21); Uphill, Marcus
Filly, CrossFit and Gym Jones (2026-10-21/22); ATG, Kelly Starrett and Ido Portal
(2026-10-22) — every package. What the rest failed when the scorecard landed (E3 novices
served frameworks not written for them, E4 one archetype per modality, R1 empty sessions
under injuries, E5 no defining claims, M1 no currency) went with the rebuilds; what
still grades partial is hygiene (S6, D3, D4) and the excluded GPP Circuits.

**The review, reviewed (2026-10-21, branch `package-review`).** The Source grades were
declarations — five headings, a count of inventions, `sources_kind: primary`, `debt: []`
— and nothing compared a program with the source's numbers. Now each package keeps a
record in its folder (`fidelity.yaml`: sources with how much was read, rules with what
enforces each, inventions; `source_weeks.yaml`: the source's own weeks, generated and
compared), `status.yaml` is generated, a claim or lead measure counts only when a rule
cites it, CI runs every gate the README names, and a stale baseline fails (README,
CLAUDE.md). Re-reading the sources: Horsemen's sixteen weeks, Wildman's 32 swing
sessions and Starting Strength's weeks reproduce. Decided by the owner the same day:
BJJ's four classes at six days stand (I7, where BJJEE's week has five); Wildman's
"repeat workouts after a week off" (R11) is recommended in every swing session's note
and never enforced (the contract's module `advice`, I5). BJJ follows StrengthLog (owner,
the same day; branch `bjj-strength-deload`): its strength is StrengthLog's program as the
article prints it — two full-body workouts, six weeks of strength and hypertrophy, the
deload week's own two workouts, five weeks of power, repeating (R4, R6–R9; module
`periods`) — with the athlete's own weights and StrengthLog's rule for adding them (I2);
the grip and joint-maintenance session and the RPE targets are gone. The mat never
deloads on a schedule (I3). BJJ is audited.

**Packages without code (2026-10-21, branch `package-portability`).** R1 reads the
fidelity rules on the scorecard's own constrained profiles too. A Portability dimension:
X1, no code names the package (`tools/check_code_neutral.py`, no baseline — the last
literals went: the scheduler's `'bjj'` mobility branch and Kelly Starrett's archetype ids
became an archetype's `complements`, the selector's level concepts commons data, the
tracker's stale family copy the canonical one, the dead `gym_jones` exercise category,
both builders' `wk_kb_` stripping the server's `exercise_names`); X2, every step resolves
to a watch screen. `test_package_dropin.py` drops three packages in under new ids
(`TRAINING_PACKAGES_DIR`) and runs them end to end with the repository unchanged.
`tools/print_package.py` and the record's `reviews` (S6) are the output review.
Left — what a package still cannot bring in its folder, none of it naming a package:
- its own standards (`benchmarks_data.BENCHMARK_FILES` lists `data/benchmarks/` files;
  The Cell has its own loader);
- per-exercise constants in code (`progression._SESSIONS_PER_WEEK` keys shared lifts);
- a non-kettlebell implement in a contract (the wording and `requires_kettlebell_pair`);
- a new slot type, modality, phase kind or equipment id (each client keeps its own
  table: `outcomeFields.ts` / `SessionLogging.swift`, the colour maps — `ModalityDonut`
  reads `MODALITY_COLORS[m].label` unguarded);
- what each watch template captures, declared in `watch_vocabulary.json` so a package's
  lead measure can be checked as recorded on the wrist (X2 checks only the screens).

**5. Wildman follow-ups (from the handoff).** General Practice runs Wildman's Phase II
since 2026-10-20 (the Nerd Math swing approaches, get-up and deck squat stacked as time
allows, the snatch once confirmed). Left: his hand-to-hand option (alternating minutes
needs a block that alternates two movements), his get-up and deck-squat numbers (paid
programs; the cycles here are the Nerd Math pattern), Double-Bell Practice (his double
bells are Phase III, deliberately non-repeating). Review the double-jerk block (an app
invention) and whether advanced and elite should differ from intermediate; test
the new tracks in both builders and on both watches; close editing paths (moving a
session) that can break module spacing; generalise catalog reachability
(`check_exercise_coverage.py`) to every package once each is on a contract.

**6. Then the Dev Lab (S–M).** The Impact tab over `POST /api/dev/constraint-impact`
and the trace's per-candidate reasons — the step-1 report seen per program.

### 10. Progress tracking: what phases A–E left open — P2 · M

The plan of 2026-10-16 (Today's Adherence and Progress cards, the Program /
Progress split, a declared `analytics.yaml` for every package) shipped in
phases A–E. Open:

- **Exercise cards on the phone.** The web's come from `/progression/exercises`,
  whose expected line is `compute_expected_trajectory` — the generator replay
  the analytics engine replaced. Build them from the `/analytics/program`
  document's per-exercise series (`progress[].exercises`), on both clients.
- ~~Capture gaps~~ — closed 2026-10-16: a static hold logs seconds per set on
  the web (it had the reps column), an isometric skill-practice exercise logs
  its hold in seconds and a kettlebell in a timed slot its reps, on both
  clients (`lib/outcomeFields.ts`, `SessionLogging.outcomeFields`), and the
  Apple Watch writes each set's `durationSeconds`. The "clean" tick followed
  the same day (`require_clean`, Ido and Wildman).
- ~~Marcus Filly prescribes kg, not RPE~~ — closed 2026-10-16: a framework's
  `progression_overrides` (modality → model) writes the load; Filly's strength
  work is RPE 8 (6 in a deload) with a suggested starting weight, and his spec
  leads with load at the target RPE.
- ~~A standard per track~~ — closed 2026-10-16: a declared benchmark may be
  `{id, frameworks}`; Wildman declares the five pentathlon events for
  `kb_pentathlon` only.
- **Decision: does the review's score keep completion?** It is
  `0.4 × completion + 0.6 × trends`; Today no longer shows it (Adherence
  carries completion), so nothing depends on the answer but the Progress tab.
- **Watches (phase F).** Garmin glance: a week line from the `days` the watch
  already has (`week=1`), no server change. Apple Watch: the server's
  `completed` flags (it tracks completion locally and resets daily), then a
  complication with the week ring and readiness. One slim server `progress`
  object (week done/due, program %, the headline sentence) for both, read from
  the cached analytics snapshot — never computed on the morning sync. "Last
  time" per exercise in the session screens.

`tools/check_analytics.py` fails on a declared measure that applies in no
track; it caught Wildman's Ballistic load, Ido's Holds, and three measures
scoped to session types their frameworks never schedule.

### 11. Apple accounts: switch on and verify — P2 · S

Built on 2026-10-17 (branch `mobile-sign-up`): the iOS app signs up and in with
Sign in with Apple (supabase-swift `Auth`, `AuthManager.swift`, `Views/Auth/`) —
a native ID token checked against Apple's keys, so no secret, no email and no
domain — keeps password sign-in for web-made accounts, and deletes the account
from Settings ▸ Account (`DELETE /api/account`, `src/account.py`). The web
signs in to the same account with "Continue with Apple" (Supabase's OAuth
redirect). Done in the consoles: Supabase ▸ Apple on with the bundle id; the App
ID has Sign in with Apple; the Services ID `haerdsoft.TrainingCompanion.web`
(domain `<ref>.supabase.co`, return URL `<ref>.supabase.co/auth/v1/callback`);
a Sign in with Apple key (.p8).

1. **Switches left:** Supabase ▸ Apple ▸ Client IDs gains the Services ID beside
   the bundle id (comma-separated), Secret Key gets the output of
   `scripts/apple_client_secret.py`; Authentication ▸ URL Configuration lists
   the web host as redirect URLs (`https://training-e58.pages.dev/**` and
   `https://*.training-e58.pages.dev/**` for the per-deploy hosts);
   `fly secrets set SUPABASE_SERVICE_ROLE_KEY=…` and the 1Password field
   `.env.template` names.
2. **Renew the web secret every six months** (the script prints the date). A
   lapsed one stops only the web's Apple sign-in. A scheduled job could do it
   (the .p8 plus a Supabase access token as CI secrets, the Management API's
   auth config) if the calendar reminder proves unreliable.
3. **Revoke Apple's tokens on account deletion** before App Store or external
   TestFlight review (App Review requires it of apps with Sign in with Apple
   since 2022; Supabase does not). The phone sends the credential's
   `authorizationCode` with the delete; the server exchanges it at
   `appleid.apple.com/auth/token` (client secret signed with the same .p8, `sub`
   the bundle id) and posts the refresh token to `/auth/revoke`.
4. **On a phone** (TestFlight; the simulator has no Apple sign-in): sign up with
   Apple → empty Today; the same account on the web; sign out and back in;
   delete that account; an existing build updating stays signed in (the
   UserDefaults session is handed to the SDK once).
5. **Email code** (built and removed on 2026-10-17): `signInWithOTP` +
   `verifyOTP`, the "Magic Link" and "Confirm signup" templates carrying
   `{{ .Token }}`, Email OTP Length 6, and outgoing mail — Supabase's built-in
   mailer reaches only the organisation's members; a free single-sender SMTP
   (Brevo, or an iCloud alias with an app-specific password) needs no domain.
6. **Passkeys, once the web has a permanent domain** — the relying-party id is
   the domain and can never change without orphaning every saved passkey.
   Supabase's are a beta that adds a passkey to an existing, confirmed account
   (it cannot create one); they need the `webcredentials:` associated domain, an
   `apple-app-site-association` file on the site, supabase-swift's
   `@_spi(Experimental)` passkey calls and supabase-js ≥ 2.118 (Node 22).
### 12. Standards: deploy and verify on the devices — P2 · S

Built on 2026-10-17 in seven phases (each in *Done*): one name and one ladder in the
modality's colour; a history the athlete can manage; only a program's own standards lead;
programs schedule package-declared tests; logged sessions, both watches and imported runs
suggest results the athlete confirms. Left:

1. ~~**Production, in order**~~ — done 2026-10-17: backup, `011`, the `logged_on` backfill,
   `012`, then the deploy (#149). Existing Cell results dropped a level (Cell's own II–V
   words now map to entry…elite).
2. **The Garmin unit tests** — run 2026-10-18 (13 passed, `WireTests.mc` included; see
   item 6.2).
3. **On the watches:** a test day on the fenix (the `standard_target` line, the Results menu
   at Save, the session log arriving with `repsActual` and `standardResults`) and on the
   Apple Watch (the line under the exercise, Save Results / Not a test). Neither screen has
   been seen on a device or a simulator. Then a store release and a TestFlight build.
4. **A partial regenerate in a test week** can run the test twice or drop it when the days
   per week change: the clients keep the days before the cut (`spliceRegenerated`,
   `Regeneration.splice`) and the server places the week's test without knowing them (5 →
   3 days moves Fran from Monday to Tuesday; a kept Monday Fran and a new Tuesday Fran).
   Fix: send the kept weekdays and whether they hold the test; `_plan_week_tests` places
   only on days at or after the cut and skips with `already_tested`. Found in the review of
   #149.
5. **`contraindicated_with: [lumbar_disc_pathology]`** names no flag (the id is
   `lumbar_disc`) on 33 exercises, so it excludes nothing; `validate_entities.py` should
   check contraindications against `injury_flags.yaml`. The two the standards added say
   `lumbar_disc`.
6. **A test tries one session of its modality** (`_test_slot`, the first or the last of the
   week): if that day is too short the test is skipped even when another session of the
   modality sits on a long day.
7. **Not in scope, noted:** 400/800 m best efforts (no standard measures them); best efforts
   from Apple Health or live watch runs (no recorded speed — positions alone would invent
   records).

### 13. Heart rate from the programming: what is left — P2 · M

Since 2026-10-17 heart rate counts only where an exercise prescribes zones
(`src/analytics/hr_plan.py`): the whole recording when every prescription is a zone,
only the watch-timed minutes of the zoned exercises when a session mixes zones with load
(Fran's warm-up, a Starting Strength day's warm-up), nothing otherwise. Open:

- **Ship the watches.** The Garmin app's `exerciseTimeline` (`Wire.timeline`) needs a
  store release, the Apple Watch's step windows a TestFlight build; until then a mixed
  session recorded on the fenix counts nothing in zones (`untimed`). The Garmin unit
  test (`stepWindowsGoUpAsTheTimeline`) compiled but was not run — the Connect IQ
  simulator was in use.
- **Mixed sessions logged without a watch** (phone or web) stay `untimed`. Placing the
  zoned exercises by the plan's order and durations would be an estimate; decide whether
  it is worth showing as one.
- **Fidelity still uses the family rule** for the planned split (`src/fidelity.py`).
  Reading `hr_plan` there instead fires 126 new findings in seven packages — mostly
  strength-family sessions with zoned slots that the frameworks' `intensity_distribution`
  never planned for. Align the packages' distributions first, then the rule.
- **Pauses.** The Garmin app's offsets count its session clock, which stops while
  paused, as its own heart-rate samples do; a Garmin Connect file that becomes the
  canonical row is stamped by the wall clock, so after a pause a window lands late. Sending absolute `startAt`/`endAt`
  (the server already prefers them) would close it.
- **`progressing`** (Starting Strength's three lifts) is a load word that
  `progression._INTENSITY_ZONES` maps to a Zone 2–4 band; `hr_plan` treats it as load.
  Drop it from the map or give the progression its own token.

### 14. Watch parity: the Apple Watch on the server's contract — P2 · M

Added 2026-10-17 (`docs/watch.md` is the process and the parity table). The Garmin app
reads `today-session?spec=1&week=1` and renders the package's screens; the Apple Watch
gets sessions the phone builds from `/user/program` and picks views by slot type, so every
Garmin screen feature had to be rebuilt by hand or never reached it. Slices, each its own
branch:

1. **The missing app and the defects (S) — done on `apple-watch`.** The watch listed the
   app as "TrainingCompanionWatch"; it and both widget extensions now say Training
   Companion, and Settings ▸ Apple Watch says *App not installed* (`isWatchAppInstalled`)
   with where to install it. Fixed: a summary sent twice on finish; Save & End never
   marking the session done; a static hold that restarted its sets after each rest and
   never moved on; AMRAP-movement reps dropped; EMOM and AMRAP clocks that stopped off
   their page (now in `WorkoutManager`'s ticker); a second `WatchSessionManager` per
   `SyncManager.configure`; the phone crashing on a program that starts a week or more
   ahead; the watch saying *iPhone unreachable* while the phone's queued answer was on
   its way (the phone now replies to the request with the day; the watch says
   unreachable only when it is, *Couldn't sync* when the phone could not reach the
   server, and keeps a known state while asking); Settings' watch row not redrawing.
   Seen on a paired simulator (No Program, no program in the dev database); the
   workout fixes not yet seen on a watch.
2. **The phone relays the server's day (M) — done on `watch/relay-day`.** `syncProgram`
   forwards `today-session?date=&spec=1&week=1` as it is (`WatchDayMessage`: compressed,
   2.7 KB for a 20 KB day), the watch decodes `WatchDay` (in `WatchModels.swift`, which
   both targets compile); the phone's week/day maths, slot-type guesses, load wording, its
   own max HR and week list and its stored readiness copy are gone. The server adds
   `maxHR` with `?spec=1`; meta blocks (a BJJ round) now reach the watch, logged by name
   as on the Garmin; `not_started` says "Starts Mon 20 Oct". `data/watch_day_fixture.json`
   is written by the route and decoded by `WatchDayTests`. Uploads go live to a reachable
   phone, which answers once the server has them (`WatchUploadMessage`); the queued
   transfer is the fallback — between simulators it was never delivered, so an end-to-end
   run (watch → phone → workout, log, match → `completed` on the next sync) now passes
   there. The watch's done mark keeps the log's `apple_watch_live` source, and
   `standard_results` files that source as the watch's. The phone refreshes when it has stored
   a watch session (`.watchWorkoutStored`), so Today marks it done and the Workout complete
   sheet comes up; an empty first load now counts as the install's first, so the first
   workout ever is news, not history.
3. **Spec rendering (M), in two PRs.**
   - **3a, the shared ground — done on `watch/spec-render`.** `gen_vocab.py` also writes
     `ios/TrainingCompanion/WatchVocab.swift`; `WatchSpecText.swift` ports `ScreenSpec.mc` and
     `SpecRenderer.mc` (title, fields, lines, what LAP does) over a `WatchStepState` the
     engine will fill, with every switch exhaustive. `data/watch_fixtures.json` (28 cases,
     every template, field, title part, line, action and behaviour, and the fallbacks for
     unknown ids) runs in `WatchSpecTests` and, generated by `gen_spec_fixtures.py`, in the
     Garmin's `SpecFixtures.mc`. Sessions decode `screens`; exercises the fields the
     screens read. No screen changes yet.
   - **3b, the screens — done on `watch/spec-screens`.** Every step is the Garmin's data page
     (`DataPageView`: title, two fields, the rule, two lines) over `StepControlsView` (Start,
     then one button for what LAP does, and Skip); the eight slot-type views are gone.
     `WorkoutSessionState` fills `WatchStepState` (`+Page.swift`) and carries the outcome out;
     sides alternate per set, holds count down, a last set's rest leads on, and an AMRAP's
     movements are its round (`WatchSteps`: folded, "Next:" skips them). Seen on the
     simulator for all eight templates through `WatchDebugLaunch` (`TC_SESSION`, `TC_STEP`,
     `TC_RUN`, `TC_LAPS`, `TC_SKIP_HEALTH`, debug builds only).
4. **What the Garmin has (M), in two PRs.**
   - **4a, the list — done on `watch/garmin-features`.** Today ends in the Garmin's menu
     rows: Week (`WeekAheadView`: the server's days → sessions → steps), Progress (this
     week, the programme, the methodology's measure and trend) and Sync (the last sync in
     words, "ok 07:41" / "failed 07:41 · No phone"; a tap syncs). A rest day, or a day whose
     sessions are done, says tomorrow. The words are `WatchListText` (shared, tested), the
     Garmin's ActivityMenu.mc and SyncManager.mc.
   - **4b, the workout — done on `watch/workout-tools`.** The commands page has Set Next (the
     coming sets' reps, weight, RPE) and Edit Set (corrects the last set and carries it
     forward), and switches the metronome — a haptic beat at 60/RPM s while an interval works
     or a timed step runs. The end of a session shows the package's `watch.summary.pages`
     in its order: summary (time, sets, volume kg else kcal), heart rate (average, maximum,
     time per zone), exercises ("3x5 @ 100"); training effect stays the Garmin's
     (`WatchSummaryText`, shared, tested). Not yet: editing the plan before the start, pace
     edit.
5. **Server fields both use (M; 6.3) — done on `watch/server-fields`.** A slot's
   `switch_at_sec` and an interval slot's `rest_until_hr_pct` ride in the load
   (`progression.watch_cues`, also for a test's as-written load); an exercise's `bells: 2`
   marks a double. `_encode_watch_exercise` sends `switchAtSec`, `restUntilHr` — the share
   of the athlete's max HR in bpm — and `bells`, each only where it applies (the library's
   `bells` for a program stored before the field). The packages that prescribe them now
   use them: Wildman's anti-glycolytic practice is 20 × 15 s with each rest ending under
   68 % of max HR (~130 at 190; 90 s cap), Uphill's VO2max hill repeats 6 × 2 min with the
   walk down ending under 66 % (3 min cap) — both planning the minutes their timed blocks
   did, and an HR-gated interval's load carries its zone — and the pentathlon test's five
   events cue a hand switch at 3:00. Both watches switch hands in a timed block as well as
   an interval's work (the Garmin from 1.7.0; the timed title shows Left/Right), end the
   rest 5 s under the target (the Apple Watch through `WatchCues`), and read `bells` only
   from the payload, the id guess gone. The Apple Watch's "still recovering" guess on a
   set's rest is gone: neither watch gates a set's rest.

   `garmin/VERSION` (1.7.0) is read by `build.sh --release` and `--demo`, which print the
   version for the store form and the `ciq-v<VERSION>` tag.

### 15. Program preview: the phone, and what is left — P2 · M

The web and the server landed on 2026-10-20 (`feat/program-preview`): a generated program
is a draft until started (Program ▸ Preview: Overview · Calendar · Held back, Adjust, swaps
on the draft), slots carry `blocked_by`, `POST /programs/impact` opens the Dev Lab's
comparison to every athlete, and the Profile offers a regenerate only when
`POST /programs/constraint-change` says the change moves a session (an unaffected one is
adopted with `PATCH /user/program/constraints`). Before this, adding a kettlebell no
session used asked to rebuild the plan. Left open:

1. **iOS (M) — done 2026-10-20** (`feat/program-preview-ios`). The builder and the
   settings sheet's full regenerate preview a `persist: false` draft
   (`ProgramPreviewView`, design-system §6.39: Plan · Held back, Adjust, swaps on the
   draft) and start it through `saveProgramToServer`; `RegenerateOfferCard` asks
   `/programs/constraint-change` and adopts or offers (§6.17); `ProgramConstraintsDiff`
   ignores `open_space` and carries a contract's confirmations; the equipment and injury
   toggles are one component (§6.38). Left: a replaced *session* on the draft (the web
   has it; the phone swaps exercises only).
2. **Week templates say which check failed (S).** `generator._fits_as_written` answers a
   boolean; a templated day nothing fits says "equipment, injuries or N minutes". Return
   the failed check so the day's note can name it (Held back already does, from the runs).
3. **Held back is slow (S).** 7–10 s for 12 weeks (seven generations; 79 MB peak RSS
   measured). Cached per body in the process; a deploy or a second machine starts cold.
   Consider running the relaxed generations only for the constraints the athlete has
   (already so) and fewer weeks for the comparison.
4. **The Program page's injuries sheet and "From tomorrow onwards"** still regenerate
   without a preview; route both through the regenerate preview. On the phone, Program
   settings' "Regenerate from this week" does the same.
5. **The regenerate offer said nothing after Apply — fixed 2026-10-20.** Apply removes the
   difference the banner (web) and card (iOS) were shown for, so they vanished. Both now
   say "Rebuilt N weeks with these settings" until a new difference appears (web
   `RegenerateFromWeekBanner`'s `outcome`, iOS `AppState.profileOfferOutcome`, which also
   carries "doesn't change"; `preview.test.tsx`).
6. **Programs stored before `blocked_by` (S).** Their empty slots read the older generic
   words ("Nothing fits your equipment") until they are regenerated. Leave it, or fill
   `blocked_by` on read for the current program's empty slots (one selector call per slot).
7. **The impact comparison's totals — fixed 2026-10-20.** `analyse` counted `total` over
   the athlete's sessions while `changed` also counted reference sessions the program no
   longer had, so Horsemen read 48 changed of 26. `total` is now every position either
   program has a session at (`actual` and `reference` beside it), and both clients say
   "N of M sessions change" again (`test_constraint_impact.py`).
8. **The validator's minimum-days warning misleads single-modality methods (S).**
   `MINIMAL_DAYS` says "lower-priority modalities will be dropped" for Starting Strength,
   where nothing is; the preview's Schedule section repeats it. Word it from what the
   scheduler actually dropped (its compromises), or say nothing when one modality runs.
9. **Vite in a worktree under `.claude/` misses file changes (dev tooling, S).** The
   watcher served the first transform of each file until Vite was restarted. Try
   `server.watch.usePolling` or an explicit `server.watch` path when the root is under a
   dot directory; meanwhile restart Vite (`--force`) after edits in a worktree.

---

### 16. Garmin's official Connect API — P2 · M

Added 2026-10-23, from a r/Garmin thread the athlete shared. On 2026-10-21 Garmin
reopened its Connect Developer Program, closed to new applicants since March 2026, as three
tiers ([DC Rainmaker](https://www.dcrainmaker.com/2026/10/garmin-connect-api-revamps-connect-developer.html),
[the5krunner](https://the5krunner.com/2026/10/22/garmin-personal-api/); check
developer.garmin.com for the terms):

- **Personal**: free. One person makes a key in Garmin Connect themselves, with no
  application, and it is read-only. It gives activity summaries, full FIT files, and
  health and women's health summaries. FIT files sent through the API have some fields
  Garmin calls proprietary removed. VO2 max, recovery time and training status or load are
  not listed.
- **Startup**: free, for up to 1,000 users, and approval is said to be almost immediate. It
  has the same data plus the **Training and Courses APIs**: structured workouts and courses
  pushed to Garmin Connect, which sends them on to the watch. Data arrives by push only,
  with no historical backfill.
- **Enterprise**: historical backfill, support, and more than 1,000 users. There is a
  $1,000 entry fee, then a fee per monthly active user, payable from 2027-04-01.

**What exists.** `src/garmin_connect.py` (OAuth 2.0 + PKCE, activity fetch, backfill), the
webhook and `src/garmin_worker.py` with its `garmin_webhook_events` queue. Because the portal
was closed, all of it was written against a local stub (`test_garmin_webhook.py`). The
module docstring says its hosts, paths and scope are unverified. The web's Settings ▸
Connections has the Garmin button.

1. **A Personal key on the athlete's own account (S).** This is a spike: pull one activity
   and one day's health summary, and compare them with what the Connect IQ app and the
   Apple Health relay send now. Check which FIT fields are removed (HR series, laps, sets),
   whether sleep, HRV, Body Battery and resting HR are in the health summary, and the rate
   limits.
2. **Apply for Startup and verify the integration (S).** Check every endpoint in
   `garmin_connect.py` against the real documentation. The backfill call is Enterprise-only,
   so connecting an account must manage without it: say "from today on", or ask for a
   manual FIT upload of older workouts. Then turn it on in production.
3. **Activities by webhook (S).** For a Garmin user this replaces Garmin → Apple Health →
   relay and the manual FIT upload. Dedup already ranks the `garmin` source; check that the
   matcher and `fastest_seconds` get the speed they need from an API FIT file.
4. **Health summaries (M).** Daily resting HR, sleep, Body Battery and stress, read by
   `_bio_for_scoring`. It could replace the Connect IQ wellness posts (item 2) and the
   phone relay's resting HR, which only gets there after Garmin Connect has synced to Apple
   Health. Keep one series per method (`wellness.merge_for_scoring`), never a day-by-day mix.
5. **Push the program's sessions as Garmin workouts (M–L).** This is the big one: today's
   and the week's sessions arrive on any Garmin, without the Connect IQ app, and run in the
   watch's own workout player and summary. Map each watch template to Garmin's workout
   steps (sets with exercise, reps and weight; intervals; repeats; time and distance
   targets). Note what does not carry over: AMRAP rounds, for-time clocks, the lead-in and
   test results. Decide what that means for the Connect IQ app: keep it for what the
   native player cannot do, or offer both.

## Later

Larger items from the IA review. Each needs a backend step first; none is
scheduled ahead of the ranked list.

- **Progress as a section of Program** — Analytics ▸ Progress answers "is it
  working?" (lift and skill trends, the adjustments), Program "am I doing the
  plan?". Since 2026-10-16 Progress takes its compliance from Program's
  scorecard and explains its score (`src/analytics/review.py`); the two could
  become one tab with a Trends section, once trends carry enough data to be
  worth their own place. Both clients, one change (§2 of the IA).
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

**Standards, phase 7 (2026-10-17)**: imported runs suggest run results. A standard's YAML
`best_effort` names its distance (1, 3, 5 miles); a FIT run — uploaded, or from Garmin Connect
— is read over exactly that distance from its recorded speed and suggested when it is matched
to a test of the standard or beats the best on one the athlete tracks. Apple Health and live
watch runs carry no speed and are not read; the Standard detail says so. The suggestion row
reads "1-Mile Run 6:23 · Advanced — new best · fastest 1 mile of 5.2 km · Running".

**Standards, phase 6 (2026-10-17)**: the watches. Capture first: the Garmin app's set logs
went up keyed by exercise name with `reps` and no `completed`, so the analytics read none of
them — they now go up in the server's shape (`Wire.mc`), with a round step's rounds, a
for-time clock and a step's distance; the Apple Watch keeps the for-time clock, AMRAP rounds
and distance its views used to drop. A test step shows the standard's best and the number for
the next level on both watches (`standard_target`), and the end of a test session asks for
the results — enter or correct each, then Save results / Not a test — which ride in the
session log (`standardResults`).

**Standards, phase 5 (2026-10-17)**: sessions suggest results. A logged test slot — a
2 km row's clock, Cindy's rounds with the partial round, reps in six minutes, a hold — and a
single that beats the current result on a ×BW lift come back from the session-log save as
suggestions (`standard_result_suggestions`), never as results until the athlete saves them:
Save result · Correct · Not a test, on Profile ▸ Standards' *To confirm*, Today and under the
test, on both clients. A re-logged value reopens a saved one to correct its result; a
dismissal sticks. The session-log PUT now answers 503 when the write fails (it said "saved"
over lost writes) and accepts a watch's decisions in `standardResults`. A for-time slot logs
m:ss on both clients (the web stored whole minutes; the phone prefilled the cap, which a test
nobody changed would have saved as its result), and a test slot asks for its standard's
number first (push-ups in three minutes logged minutes and km).

**Standards, phase 4 (2026-10-17)**: programs test their standards. A phase's `tests:`
places a test archetype (`test:`, scored slots with `standard:`) in place of one session of
its week; the replaced session is still selected so nothing else in the program changes, and
is recorded (`test.instead_of`) so fidelity and the phase summary read the test as that
session. A test is prescribed as written, skipped with a reason when the athlete cannot do it
(level, equipment, time, an injury), and never picked by ordinary selection. Wildman's
pentathlon, Gym Jones' 2 km row, Horsemen's PT test and CrossFit's benchmark girls; CrossFit's
level seed unlocks its own pull-up for intermediates (it was locked for everyone but an
elite). `_DERIVED_FROM` became each standard's `derived_from`; the six standards files are
validated against `benchmark.schema.json`. Both clients badge test sessions and name what
each scored exercise measures; Today says "Test today" on the web.

**Standards, phase 3 (2026-10-17)**: only a program's own standards lead.
`analytics.benchmarks.program_standards` (declared by the package for the frameworks the
program runs, or tested by it) decides Progress's standards, Profile ▸ Standards' *This
program* and Blocks' order; a result alone no longer makes a standard primary (a logged
back squat used to lead a kettlebell block). Progress says how far each moved this block
("+1 level this block", a sparkline from the block's start); Blocks draws each standard as a
chart across blocks; Profile is *This program* · *Your results* · *All standards*
(collapsed). Every standard on Progress and Blocks opens its detail, on both clients.

**Standards, phase 2 (2026-10-17)**: a history the athlete can manage. Every result
can be logged with its day and a note, and corrected or deleted on its own (it used to
be add-only, clearing a web field deleted the whole series, and nothing chose the day).
A ×BW standard may be logged as the load lifted (kg × reps ÷ the bodyweight that day,
Epley past one rep). A result counts for the athlete's day (`logged_on`,
`migrations/011`; readers took the UTC timestamp's day, a day late every evening west of
Greenwich) and falls in the block in force then. Standard detail on both clients: the
ladder, a history chart across blocks, the list. The `benchmark_level` measure now reads
the same estimate as the ladder beside it (`analytics.benchmarks.standing`).

**Standards, phase 1 (2026-10-17)**: one name, one ladder. Every screen on both
clients says *Standards* (Profile's tab included; `?tab=benchmarks` and
`section=benchmarks` land on it) and *result* for a logged value. The server places
and prints every value (`benchmarks_data.level_of`, `format_value`, `parse_input`;
`GET /standards/results` via `src/standards.py`), and one `StandardLadder` per client
draws it in the standard's modality colour. Fixed on the way: the phone's Profile tab
decoded nothing (it required `higher_is_better`, which the server never sent); the web
field wrote twice on Enter and on every blur, and clearing it deleted the standard's
whole history; `POST /health/performance` answered "saved" when the insert failed;
cached analytics keyed on the number of results, so an edit never showed; female
tables read `None` thresholds in the analytics rows; Cell's levels were off by one
(I–IV, now II–V by Cell's own words) and its thruster never loaded; the static
fallback was a male-only third copy of the loader.

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
