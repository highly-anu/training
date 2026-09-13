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

```
manifest.xml            App id, Fenix 9 product target, permissions
monkey.jungle           Build config
resources/
  strings/strings.xml   UI strings
  drawables/            launcher_icon.png (present)
  settings/ properties/ apiBaseUrl, webBaseUrl, autoStartOnLaunch
                        (overridable in Garmin Connect Mobile)
source/
  Config.mc             Constants, storage keys, apiBaseUrl/webBaseUrl, rest defaults
  PhoneLink.mc          Phase-3 phone glue-app link (BLE phone-app messages)
  TrainingCompanionApp.mc  Entry point + glance + routing (pair vs. today; deep-link)
  SyncManager.mc        All backend I/O: pairing, today-session, readiness, upload
  SessionModel.mc       WorkoutSession / WorkoutExercise wrappers over the JSON
  WorkoutController.mc  State machine, ActivityRecording, HR/GPS capture,
                        HR-zone drift, EMOM/AMRAP timing, set editor, summary
  views/
    PairingView.mc      Mint code → scan-to-claim QR + code → poll (or phone push)
    SessionListView.mc  Today's session / rest day + readiness dot; SELECT starts it
    ExerciseView.mc     Dispatch by slotType + rest overlay + live HR + drift arrow;
                        on-wrist set editor for sets_reps (edit reps/weight/RPE)
    SessionCompleteView.mc
    GlanceView.mc       At-a-glance card + readiness dot, from cache
```

App settings (`resources/settings`, editable in Garmin Connect Mobile):
- `apiBaseUrl` — backend base URL (default `https://training-api.fly.dev/api`).
- `webBaseUrl` — web app URL; when set, the pairing QR becomes a `<webBaseUrl>/pair?code=…`
  deep link (empty encodes the raw code).
- `autoStartOnLaunch` — when opened from the complication/glance, start today's
  session immediately instead of just showing the today screen (default off).

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
3. **Readiness** — `GET /health/readiness` → cached; rendered as a green/yellow/red
   dot on the glance and today screen.
4. **Upload** — on finish: `POST /health/workouts` (`source:"garmin"`) →
   `PUT /health/sessions/{key}` → optional `PUT /health/bio/{date}`. Any failure
   buffers the whole payload in `Storage` and retries on next open.

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
- On-wrist set logger for sets_reps: SELECT logs the set with edited values,
  UP/DOWN adjust the focused field (reps ±1, weight ±2.5 kg, RPE ±0.5), BACK
  cycles the field. Values seed from the prescription and carry across sets;
  hold-UP still finishes the session early.

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
- Phase 3 **phone app itself** (CIQ Mobile SDK, iOS/Android): Supabase login +
  the phone half of the protocol above. Native-mobile work (not built here).
- Phase 4: server-side Training API push of conditioning workouts. Blocked — Garmin
  partner (Training API) onboarding is paused; the app avoids the partner API.
- Phase 5: **blocked at the platform for a watch-app.** Fenix Stamina has no Connect
  IQ API; adaptive workout steps (`DataField.setWorkout`) are data-field-only and need
  ActivityControl; `Activity.getCurrentWorkoutStep` only reads a *native* workout the
  athlete isn't running while in this app. Revisit only with a data-field companion.
