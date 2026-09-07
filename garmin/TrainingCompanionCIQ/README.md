# Training Companion — Garmin Connect IQ app (Fenix 9)

On-wrist companion to the training platform, mirroring the Apple Watch app
(`ios/TrainingCompanionWatch Watch App/`). It pairs to a user account, pulls
today's session from the backend, guides the athlete through it, records HR + a
FIT activity, and syncs the result back to the same backend — no Garmin partner
API required.

> Status: **Phase 0–1 scaffold.** Backend endpoints it depends on are implemented
> and tested (`/api/devices/*`, `/api/user/today-session`). The Monkey C code here
> is a structured skeleton — it has **not** been compiled. Every spot needing SDK
> confirmation is marked `TODO(sdk:...)`. See the repo plan at
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
    PairingView.mc      Mint code → poll until claimed (QR = TODO, code works now)
    SessionListView.mc  Today's session / rest day; SELECT starts it
    ExerciseView.mc     Dispatch by slotType + rest overlay + live HR
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

## Remaining TODO(sdk) / next phases

- `TODO(sdk)` markers: Fenix 9 product id + minApiLevel; QR generation (CIQ 9);
  `SPORT_*/SUB_SPORT_*` constants; glance signature.
- Phase 2: EMOM/AMRAP round logic, HR-zone drift alerts (use `UserProfile`
  zones on CIQ 9), GPS/distance/elevation capture, richer set logger UI.
- Phase 3: phone glue app (CIQ Mobile SDK) for one-tap Supabase login.
- Phase 4: server-side Training API push of conditioning workouts.
- Phase 5: adaptive workout steps + Fenix 9 Stamina pacing.
