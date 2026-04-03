# TrainingCompanion iOS App

A minimal iPhone app that syncs Apple Watch health data to the training dashboard. That's its entire current scope — it is a data sync utility, not a full training app.

**What it does:** reads sleep stages, HRV, resting HR, SpO2, and respiratory rate from HealthKit and pushes them to the Flask backend via `PUT /api/health/bio/{date}`. The web app's BioLog tab then displays the synced data automatically with an "Apple Watch" badge.

**What it does not do (yet):** show training programs, log sessions, display workouts, send reminders, or run on Apple Watch itself.

---

## Architecture

```
HealthKitManager   — queries HealthKit for sleep stages, HRV, RHR, SpO2, resp rate
SyncManager        — incremental sync: skips already-synced dates, walks 30-day backfill
APIClient          — authenticated PUT /api/health/bio/{date} to Flask; GET synced-dates
AuthManager        — Supabase email/password sign-in (same account as the web app), JWT refresh
ContentView        — two screens: sign-in form + sync status with manual "Sync Now" button
TrainingCompanionApp — registers BGAppRefreshTask for background sync every ~6 hours
```

### Data synced per day

| Field | Source |
|---|---|
| Sleep total, deep, REM, light, awake (minutes) | HKCategoryType sleepAnalysis |
| Sleep start / end times | First/last Apple Watch sample in window |
| Resting heart rate (bpm) | HKQuantityType restingHeartRate |
| HRV RMSSD (ms) | HKQuantityType heartRateVariabilitySDNN |
| SpO2 average (%) | HKQuantityType oxygenSaturation |
| Respiratory rate (breaths/min) | HKQuantityType respiratoryRate |

Sleep window: previous evening 6 pm → current morning noon. Only Apple Watch samples are used (bundle ID filter: `com.apple`).

---

## Files

| File | Purpose |
|---|---|
| `TrainingCompanionApp.swift` | App entry point, background task registration |
| `ContentView.swift` | Sign-in screen + sync status screen |
| `AuthManager.swift` | Supabase auth (email/password → JWT, persisted to UserDefaults) |
| `HealthKitManager.swift` | HealthKit queries for sleep + biometrics |
| `APIClient.swift` | Authenticated HTTP client (`GET`, `PUT`) for Flask API |
| `SyncManager.swift` | Incremental sync logic, last-sync anchor in UserDefaults |

---

## Setup

### 1. Create the Xcode project

1. Open Xcode → New Project → iOS App
2. Product name: `TrainingCompanion`, Bundle ID: `com.training.companion`
3. Copy the Swift files from this directory into the project
4. No Swift packages needed — auth and networking use URLSession directly

### 2. Configure Info.plist

```xml
<key>SUPABASE_URL</key>
<string>https://bophctdejctqekplwnvp.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string><!-- anon key from Supabase dashboard --></string>
<key>API_BASE_URL</key>
<string>https://training-api.fly.dev/api</string>

<key>NSHealthShareUsageDescription</key>
<string>TrainingCompanion reads your sleep, heart rate, and HRV data to sync with your training dashboard.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>TrainingCompanion does not write health data.</string>

<!-- Required for background sync -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.training.sync</string>
</array>
```

### 3. Enable capabilities in Xcode

- Signing & Capabilities → **HealthKit**
- Signing & Capabilities → **Background Modes** → check **Background App Refresh**

### 4. Run the Supabase migration

The `daily_bio` table needs a `source` column to distinguish `apple_watch` from `manual` entries. Run the migration block at the bottom of `supabase/schema.sql` in the Supabase SQL editor.

### 5. Build and run on device

HealthKit is unavailable in the simulator. Run on a physical iPhone paired with an Apple Watch.
