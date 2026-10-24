# Training Companion — Garmin Connect IQ app (Fenix 9)

On-wrist companion to the training platform, mirroring the Apple Watch app
(`ios/TrainingCompanionWatch Watch App/`). It pairs to a user account, pulls
today's session from the backend, guides the athlete through it, records HR + a
FIT activity, and syncs the result back to the same backend — no Garmin partner
API required.

> Status: **Feature-complete for a watch-app; builds clean; not yet verified on
> hardware.** Compiles for Fenix 9 against SDK 9.2.0 (`./build.sh` and
> `./build.sh --device` both succeed). Implemented: code + QR + phone-push pairing,
> today-session fetch/render, guided sessions with `ActivityRecording`, HR-zone
> drift alerts, GPS/distance/elevation capture, EMOM/AMRAP/for-time logic, an
> on-wrist set logger, a readiness dot on the glance + today screen, Phase-3
> watch-side phone-link hooks, and a complication/glance deep-link. No `TODO(sdk)`
> markers remain. **The one remaining gate is hardware verification** — the first
> sideload + a full pair→today→run→upload cycle on the watch. Phases 4–5 are
> platform-blocked (see below). See the repo plan at
> `~/.claude/plans/i-have-a-garmin-parsed-twilight.md`.

## Layout

The app is a shell around a core library; each training philosophy owns its
watch screens as data, and may add compiled code only where data cannot say it.

```
garmin/
  core/                       the library: names no philosophy (check_core_neutral.py)
    source/
      engine/WorkoutController.mc  state machine, ActivityRecording, HR/GPS, timing by
                              the step's template, set/rest flow, Edit Set, summary
      model/                  SessionModel (exercise + its screen spec), Steps
      net/                    SyncManager (?spec=1), PhoneLink, Wellness
      store/                  Config, DayLog, GlanceCache (the glance's slim copy)
      spec/                   ScreenSpec (payload spec or slot-type default),
                              SpecRenderer (every id the vocabulary names), PackageModule
      gen/                    Vocab.mc, Registry.mc — GENERATED, never edit
      ui/ views/ input/       Garmin's activity grammar, the pages, the button map
    resources/                icons, Personality Library styles, layouts, strings
    test/                     (:test) functions — ./build.sh --test
  packages/<id>/              optional compiled module per philosophy (none yet)
    package.json              {"id": "<id>", "class": "<Class>"}
    source/<Class>.mc         class <Class> extends PackageModule, annotated (:pkg_<id>)
  tools/
    gen_vocab.py              data/commons/watch_vocabulary.json -> core/source/gen/Vocab.mc
    gen_registry.py           garmin/packages/*/package.json -> Registry.mc + packages.jungle
    gen_watch_demo.py         gives the demo programmes their packages' specs
    check_core_neutral.py     fails on a package or archetype id in garmin/core
    gen_icons.py              the menu / category / pattern icon SVGs
  TrainingCompanionCIQ/       the app shell
    manifest.xml  monkey.jungle  packages.jungle (generated)  build.sh  run-sim.sh
    source/                   TrainingCompanionApp, DemoProgram, DemoSession
    resources/                AppName, launcher icon, settings/properties, demo jsonData
```

### Packages own their watch screens

What a session looks like on the watch is its package's, the way its analytics
are (`data/packages/<id>/analytics.yaml`):

1. **The vocabulary** — `data/commons/watch_vocabulary.json` — lists the templates
   (the engine modes: sets, hold, interval, rounds, for_time, distance, timed,
   round_timer), the field ids for the two data fields, title parts, the lines
   under the rule, LAP actions and behaviours (side_tracked, cumulative_target,
   ladder, load_wave, metronome_rpm). Its slot-type defaults are the screens the
   watch drew by slot type before packages owned them. Every id is implemented in
   `core/source/spec/SpecRenderer.mc`; add both in one change, then run
   `gen_vocab.py`.
2. **A package's `watch.yaml`** (`docs/schemas/watch.schema.json`) overrides them
   per archetype and slot role — e.g. Gym Jones' get-ups count toward 100 per
   side, BJJ's class runs as a round timer. A package without one gets the
   defaults. `src/watch_spec.py` resolves it.
3. **The server** sends the resolved specs: `GET /user/today-session?spec=1` adds
   `packageId` (the archetype's owner, so a borrowed session keeps its owner's
   screens), `watch` (label, accent, summary pages, edit steps, module) and a
   deduplicated `screens` table each exercise names by `screen`.
4. **The watch** draws each exercise through `ScreenSpec` + `SpecRenderer`; a
   payload without specs, or an id this build lacks, falls back to the slot
   type's default, field by field.
   A test's scored slot (`standard` on the exercise) is the one exception the
   server makes to a package's spec: its screen's lines are `standard_target`
   ("Best 7:32" / "7:00 for advanced", the server's words), and Save opens a
   **Results** menu first (`views/ResultsMenu.mc`): each standard with what the
   watch captured, select one to enter or correct it (a timed step's reps are the
   athlete's count), then *Save results* or *Not a test* — sent as
   `standardResults` in the session log. The session log goes up in the server's
   shape (`engine/Wire.mc`: keyed by exercise id, `repsActual` on completed sets,
   a hold's seconds as `durationSeconds`, a round step's `rounds`, a for-time
   clock as `durationSec`); in memory sets stay keyed by name, where Edit Set and
   the summary read them.
5. **A compiled module** is the escape hatch for what the vocabulary cannot say:
   `garmin/packages/<id>/`, then `gen_registry.py`; the package's `watch.yaml`
   names `module: <id>` and a slot's `module_screen`. The slot's spec stays
   complete without it, so `gen_registry.py --without <id>` builds draw the
   declarative screen. Prefer growing the vocabulary: a module ships in every
   build and every module needs a store release.

**Adding a philosophy, back to front:** its package in `data/packages/<id>/`
(philosophy, frameworks, archetypes, exercises), optionally a `watch.yaml`; run
`validate_entities.py`, `check_provenance.py`, `test_watch_spec.py`. The watch
needs no change and no release unless the package ships a module.

App settings (`resources/settings`, editable in Garmin Connect Mobile):
- `apiBaseUrl` — backend base URL (default `https://training-api.fly.dev/api`).
- `webBaseUrl` — web app URL; when set, the pairing QR becomes a `<webBaseUrl>/pair?code=…`
  deep link (empty encodes the raw code).
- `autoStartOnLaunch` — when opened from the complication/glance, start today's
  session immediately instead of just showing the today screen (default off).
- `cueTones`, `cueVibrate` — the workout's tones and vibrations (default on).
- `leadIn` — "Work in 3, 2, 1, go" before work that starts on a clock: the last three
  seconds of a set rest or an interval rest, a rest-less EMOM's minute, and a rest that
  ends on heart rate once HR is under its target (default on).
- `countdownStart` — the same count after START, before the timer starts, as Garmin's
  Countdown Start (default on).
- `leadTickTone`, `leadGoTone` — the count's and the go's tones (`Toybox.Attention`
  `TONE_*`, default Alert Low and Loud Beep). Picked by ear on the watch only (Settings ▸
  Lead-in Tones plays each as it is selected), so they are not in Garmin Connect Mobile.
- `glanceStyle` — the glance (since 1.12.0; `GlanceView.mc` draws, `GlanceDay.mc` words):
  **Next up** (default) — Garmin's own glance layout, left-aligned in the glance font:
  the day's state ("TODAY · 2/3"), the next session, its minutes and the week's
  "3/5 this wk", beside a bar in that session's colour; **Day bar** — a title, a
  segment per session in its modality's colour (bright once done; on a rest day the
  week's sessions) and "2 left · 1h 10m" under it; **Ring** — the glance before 1.12,
  a ring at the left (readiness, then the day's sessions, then a tick) beside a label
  and one line. Rest days, the evening's look at tomorrow and the finished day follow
  each style. Also on the watch: Settings ▸ Glance.

The same switches are on the watch: Settings, in the pre-start page's hold-UP menu and
the workout's (`SettingsMenu.mc`, values in `Cues.mc`). **The Garmin cannot speak.**
Connect IQ has no text-to-speech, no sound-file resource and no way to reach the watch's
own voice prompts, and a custom `ToneProfile` pitch plays nothing on a watch with a
speaker (the fenix 8 and 9) — so the lead-in is the watch's built-in tones. The Apple
Watch says it ("Work in 3", "2", "1", "Go", `watch_vocabulary.json` `cues`).

## How it talks to the backend

Base URL from the `apiBaseUrl` app setting (default `https://training-api.fly.dev/api`).
Auth is a device token (`ciqdev_…`) sent as `Authorization: Bearer <token>`.

1. **Pair** — `POST /devices/pair` (no auth) → store token, show the 6-char code
   and a scan-to-claim QR. The athlete claims it either by entering the code in the
   signed-in web/phone app (**Devices** screen) → `POST /devices/claim`, or (Phase 3)
   by the phone glue app pushing a claimed token over BLE (see `PhoneLink.mc`). The
   watch polls `GET /devices/status` until `claimed`.
2. **Today** — `GET /user/today-session` → compact session list (already
   slot-typed + zone-parsed server-side).
3. **Wellness** — on every open (at most every 15 min): `Wellness.read()` →
   `POST /health/wellness` with the local date. One reading that failed to send is
   kept and folded into the next (lows kept low, the Body Battery high kept high),
   because the heart-rate history holds six hours.
4. **Readiness** — `GET /health/readiness`, after the wellness post so it scores
   this morning's resting HR → cached; rendered as a green/yellow/red dot on the
   glance and today screen.
5. **Upload** — on finish: `POST /health/workouts` (`source:"garmin"`) →
   `PUT /health/sessions/{key}`. Any failure buffers the whole payload in
   `Storage` and retries on next open.

These flow into the same tables the Apple Watch app uses, so a Garmin session
shows up in the iOS Analytics tab with no analytics changes.

## Build / run (terminal workflow — no VS Code extension needed)

Verified environment on this machine (all present):
- SDK: `connectiq-sdk-win-9.2.0-2026-06-09` (CIQ 9 generation)
- Devices downloaded: `fenix943mm`, `fenix947mm` (47mm profile also covers 51mm)
- Developer key: `~/.garmin-keys/developer_key` (outside the repo)
- JDK: Temurin 17 at `C:/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot`
  (`monkeyc` is a JAR and needs a JDK). It is **not on PATH** — export it per shell:
  `export JAVA_HOME="C:/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot"; export PATH="$JAVA_HOME/bin:$PATH"`
- `resources/drawables/launcher_icon.png` is present (required to build).

Steps:

1. **Build for the simulator:** `./build.sh`   (targets `fenix947mm`; override with
   `DEVICE=fenix943mm ./build.sh`).
2. **Run in the simulator:** `./run-sim.sh` (starts `connectiq` + loads the .prg).
   Set `apiBaseUrl` (Garmin Connect Mobile app settings, or the sim's settings
   editor) to your local `python api.py` — use your LAN IP, not localhost — or the
   deployed API.
3. **Sideload to the watch:** `./build.sh --device`, then copy
   `bin/TrainingCompanion-fenix947mm.prg` to `GARMIN/APPS/` over USB.
4. **Store test upload:** `./build.sh --release` writes `bin/TrainingCompanion.iq`
   (the real app, all seven devices); `./build.sh --demo` writes
   `bin/TrainingCompanionDemo.iq` with the demo programmes on. Same app id, so each
   uploads as a new version of one app. The demo switch is the `demoProgrammes`
   setting (renamed from `demoMode`, whose stored `true` from the demo builds would
   otherwise outlive the update).

`build.sh` / `run-sim.sh` auto-detect the SDK path and key; override with
`CIQ_SDK`, `CIQ_KEY`, `DEVICE` env vars. Builds use the default type-check level;
`-l 3` (strict) surfaces pre-existing untyped-style warnings across the codebase
and is not part of the normal build.

## Done / remaining

Resolved (verified by compiling against SDK 9.2.0):
- `SPORT_*/SUB_SPORT_*` constants, `getGlanceView` signature, Fenix 9 product ids.
- On-device pairing QR via `ScanCode.createQrCodeImage` (CIQ 6+, guarded with `has`;
  falls back to the code text on older devices). Set the `webBaseUrl` app setting to
  make the QR a deep link (`<webBaseUrl>/pair?code=…`); empty encodes the raw code.
- Phase 2 SDK features:
  - GPS/distance/elevation capture for cardio sessions (`Activity.Info` +
    `currentLocation`); sent as `distance`/`elevation`/`gpsTrack` — the backend
    recomputes elevation gain/loss from track altitudes.
  - HR-zone drift alerts: live HR vs. the prescribed zone band (resolved from the
    athlete's own `UserProfile` zone boundaries); buzz + coloured arrow after
    `HR_DRIFT_HOLD_SEC` out of band.
  - EMOM per-interval buzz + round counter; AMRAP time-cap countdown with
    SELECT-to-count rounds; for-time round counter.
- Garmin-style workout (2026-10-09, matching the watch's own Strength workout):
  the pre-start page is Garmin's (since 1.10.0, from the athlete's photos of
  Strength): the battery, the session's icon and name over a rule in its colour,
  and a list below it (`NativeList`) — Workouts (the day's other sessions), Steps
  (each exercise's reps, hold, weight and RPE for the run), Training Calendar,
  Progress, Readiness, Settings, Sync. With the header focused START starts the
  workout at once (after Countdown Start); DOWN moves into the list, START opens a
  row, BACK returns to the header. Once started, START pauses and opens Resume / Save / Discard (Discard asks with the system's
  delete confirmation); BACK is LAP — it ends a set (then the rest runs), ends a
  rest early, counts a round or lap, or moves to the next step; DOWN/UP turn the
  pages, and on the step page walk the list; hold UP opens Stop Workout / Skip / Set Next
  (the next sets' reps and load) / Edit Set / Settings. Edit Set changes the last set (reps ±1, weight ±2.5 kg, RPE ±0.5) and
  carries the new values to the sets after it. When every step is done the
  activity keeps recording ("Workout complete") until Save. The end is Garmin's
  too (since 1.11.0): Save shows "Saving" while an arc sweeps the bezel, then
  "Activity Saved" in a green ring (red, "Activity Not Saved", when the recording's
  save failed), then the post-save list (`SummaryList.mc`): Done (the sync's state
  below it), All Stats, Training Effect, Heart Rate, Sets, each with its headline
  number left of the rule. A row opens All Stats at its page: Summary, Heart Rate,
  HR Zones (time and share per zone on the athlete's own zones), Training Effect
  (aerobic only), Training Status (recovery time left and VO2 max — the status
  word itself is a complication, which only watch faces may read), Exercises;
  BACK returns to the list, Done or BACK there closes the app. Discard shows
  "Discarding" with a red sweep, then "Activity Discarded", and closes.
  Touch is off while recording. Icons and button hints are the Personality Library's
  (`resources/drawables/garmin.xml`); glyphs it lacks are drawn by `tools/gen_icons.py`.

- Phase 3 **watch-side** phone-link hooks (`PhoneLink.mc`): registers for BLE
  phone-app messages while the pairing screen is up, so the future glue app can
  push a claimed token instead of the athlete typing the code. Protocol:
  - Watch → Phone: `{ "type": "authRequest", "code": <pendingCode|null> }`
  - Phone → Watch: `{ "type": "auth", "deviceToken": "ciqdev_…", "apiBaseUrl"?: "…" }`
    → watch stores the token, marks itself claimed, advances to today's session.
  - Phone → Watch: `{ "type": "claimed" }` → watch marks the minted code claimed.
- Readiness dot: `SyncManager` fetches `GET /health/readiness` and caches it; the
  glance and the session-list screen render a green/yellow/red dot (+ score on the
  list). Glances have no reliable network, so the main app refreshes the cache and
  both surfaces read from it.
- Complication / glance deep-link: `onStart(state)` detects `:launchedFromComplication`
  / `:launchedFromGlance` and routes straight to today's session. Safe by default
  (lands on the today screen); the `autoStartOnLaunch` setting makes a complication
  tap jump directly into the guided session. (Watch-face complication *placement* is
  watch-face-dependent; the app just handles the launch context.)

Remaining:
- Hardware verification: first watch sideload + full pair→today→run→upload test.
- The glance on the fenix 9 (1.12.0), which the simulator cannot answer: each style
  in the glance loop and in a glance folder, whether the app is listed among the
  START button's activities and can be a favourite, and whether a copy launched from
  the glance records (if not, a glance tap should open Today read-only). A Connect IQ
  app has one glance, so the styles are a setting, not three glances. The glance's
  accent colour (`AppBase.getGlanceTheme`) is not offered: the SDK lists the fenix 8
  for it, not the fenix 9.
- Daily wellness is sent on open (slice 5 of item 2 in `docs/roadmap.md`), written
  2026-10-06 against calls the hardware spike in `../WellnessSpike/` ran on the
  fēnix 9 Pro, and **not compiled yet**: `DEVICE=fenix9pro47mm ./build.sh --device`.
  The background send without opening the app is slice 6. The spike is a separate
  app id, so it sideloads beside this one.
- Phase 3 **phone app itself** (CIQ Mobile SDK, iOS/Android): Supabase login +
  the phone half of the protocol above. Native-mobile work (not built here).
- Phase 4: server-side Training API push of conditioning workouts. Blocked — Garmin
  partner (Training API) onboarding is paused; the app avoids the partner API.
- Phase 5: **blocked at the platform for a watch-app.** Fenix Stamina has no Connect
  IQ API; adaptive workout steps (`DataField.setWorkout`) are data-field-only and need
  ActivityControl; `Activity.getCurrentWorkoutStep` only reads a *native* workout the
  athlete isn't running while in this app. Revisit only with a data-field companion.
