# Training Companion — Garmin Connect IQ app (Fenix 9)

On-wrist companion to the training platform, mirroring the Apple Watch app
(`ios/TrainingCompanionWatch Watch App/`). It pairs to a user account, pulls
today's session from the backend, guides the athlete through it, records HR + a
FIT activity, and syncs the result back to the same backend — no Garmin partner
API required.

> Status: **Phase 1–2, builds clean.** Compiles for Fenix 9 against SDK 9.2.0
> (`./build.sh` and `./build.sh --device` both succeed). Backend endpoints it
> depends on are implemented and tested (`/api/devices/*`, `/api/user/today-session`).
> Phase-2 SDK features are implemented: GPS/distance/elevation capture, HR-zone
> drift alerts (`UserProfile` zones), EMOM/AMRAP round logic, and a scan-to-claim
> pairing QR (`ScanCode`, CIQ 6+). All prior `TODO(sdk)` markers are resolved.
> Not yet verified on real hardware — first sideload + full pair→run→upload test
> are the next step. See the repo plan at
> `~/.claude/plans/i-have-a-garmin-parsed-twilight.md`.

## Layout

```
manifest.xml            App id, Fenix 9 product target, permissions
monkey.jungle           Build config
resources/
  strings/strings.xml   UI strings
  drawables/            launcher_icon.png (ADD THIS — required to build)
  settings/ properties/ apiBaseUrl (overridable in Garmin Connect Mobile)
source/
  Config.mc             Constants, storage keys, apiBaseUrl, rest defaults
  TrainingCompanionApp.mc  Entry point + glance + routing (pair vs. today)
  SyncManager.mc        All backend I/O: pairing, today-session, buffered upload
  SessionModel.mc       WorkoutSession / WorkoutExercise wrappers over the JSON
  WorkoutController.mc  State machine, ActivityRecording, HR capture, summary
  views/
    PairingView.mc      Mint code → show scan-to-claim QR + code → poll until claimed
    SessionListView.mc  Today's session / rest day; SELECT starts it
    ExerciseView.mc     Dispatch by slotType + rest overlay + live HR;
                        on-wrist set editor for sets_reps (edit reps/weight/RPE)
    SessionCompleteView.mc
    GlanceView.mc       At-a-glance card from cache
```

## How it talks to the backend

Base URL from the `apiBaseUrl` app setting (default `https://training-api.fly.dev/api`).
Auth is a device token (`ciqdev_…`) sent as `Authorization: Bearer <token>`.

1. **Pair** — `POST /devices/pair` (no auth) → store token, show the 6-char code.
   User opens the web/phone app (signed in) → **Devices** → enters the code →
   `POST /devices/claim`. Watch polls `GET /devices/status` until `claimed`.
2. **Today** — `GET /user/today-session` → compact session list (already
   slot-typed + zone-parsed server-side).
3. **Upload** — on finish: `POST /health/workouts` (`source:"garmin"`) →
   `PUT /health/sessions/{key}` → optional `PUT /health/bio/{date}`. Any failure
   buffers the whole payload in `Storage` and retries on next open.

These flow into the same tables the Apple Watch app uses, so a Garmin session
shows up in the iOS Analytics tab with no analytics changes.

## Build / run (terminal workflow — no VS Code extension needed)

Verified environment on this machine:
- SDK: `connectiq-sdk-win-9.2.0-2026-06-09` (CIQ 9 generation)
- Devices downloaded: `fenix943mm`, `fenix947mm` (47mm profile also covers 51mm)
- Developer key: `~/.garmin-keys/developer_key` (created; outside the repo)
- **Java: NOT yet installed — required.** `monkeyc` is a JAR and needs a JDK.

Steps:

1. **Install a JDK** (one-time). E.g. `winget install EclipseAdoptium.Temurin.17.JDK`,
   then ensure `java` is on PATH (`java -version` works in a new shell).
2. **Add `resources/drawables/launcher_icon.png`** — a ~40×40 PNG. `monkeyc`
   fails the build without it.
3. **Build for the simulator:** `./build.sh`   (targets `fenix947mm`; override with
   `DEVICE=fenix943mm ./build.sh`).
4. **Run in the simulator:** `./run-sim.sh` (starts `connectiq` + loads the .prg).
   Set `apiBaseUrl` (Garmin Connect Mobile app settings, or the sim's settings
   editor) to your local `python api.py` — use your LAN IP, not localhost — or the
   deployed API.
5. **Sideload to the watch:** `./build.sh --device`, then copy
   `bin/TrainingCompanion-fenix947mm.prg` to `GARMIN/APPS/` over USB.

`build.sh` / `run-sim.sh` auto-detect the SDK path and key; override with
`CIQ_SDK`, `CIQ_KEY`, `DEVICE` env vars.

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

Remaining:
- Hardware verification: first watch sideload + full pair→today→run→upload test.
- Phase 3: phone glue app (CIQ Mobile SDK) for one-tap Supabase login.
- Phase 4: server-side Training API push of conditioning workouts.
- Phase 5: adaptive workout steps + Fenix 9 Stamina pacing.
