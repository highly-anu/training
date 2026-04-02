# TrainingCompanion iOS App

Reads sleep stages, HRV, resting HR, SpO2, and respiratory rate from Apple Watch via HealthKit and pushes them to the training Flask backend. The web app BioLog tab then shows the synced data automatically.

## Setup

### 1. Create the Xcode project

1. Open Xcode → New Project → iOS App
2. Product name: `TrainingCompanion`, Bundle ID: `com.training.companion`
3. Copy the Swift files from this directory into the project
4. Add Swift Package: `https://github.com/supabase/supabase-swift` (not actually needed — auth is handled manually via URLSession to avoid the package dependency)

### 2. Configure Info.plist

Add these keys to `Info.plist`:

```xml
<key>SUPABASE_URL</key>
<string>https://bophctdejctqekplwnvp.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string><!-- your anon key from Supabase dashboard --></string>
<key>API_BASE_URL</key>
<string>https://training-api.fly.dev/api</string>

<!-- HealthKit usage descriptions (required by App Store) -->
<key>NSHealthShareUsageDescription</key>
<string>TrainingCompanion reads your sleep, heart rate, and HRV data to sync with your training dashboard.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>TrainingCompanion does not write health data.</string>
```

### 3. Enable capabilities in Xcode

- Signing & Capabilities → + Capability → **HealthKit**
- Signing & Capabilities → + Capability → **Background Modes** → check **Background App Refresh**

### 4. Run the migration on Supabase

Run the migration SQL from `supabase/schema.sql` (the commented-out ALTER TABLE block at the bottom of the `daily_bio` section) in the Supabase SQL editor for your project.

### 5. Build and run on device

HealthKit cannot be tested in the simulator. Run on a physical iPhone paired with your Apple Watch.

## Architecture

```
HealthKitManager  — queries HealthKit (sleep stages, HRV, RHR, SpO2, resp rate)
SyncManager       — orchestrates incremental sync (skips already-synced dates)
APIClient         — authenticated PUT /api/health/bio/{date} requests to Flask
AuthManager       — Supabase email/password sign-in, persists session to UserDefaults
ContentView       — minimal UI: sync status + manual "Sync Now" button
TrainingCompanionApp — registers BGAppRefreshTask for nightly background sync
```

## File list

| File | Purpose |
|------|---------|
| `TrainingCompanionApp.swift` | App entry point, background task registration |
| `ContentView.swift` | Sign-in screen + sync status screen |
| `AuthManager.swift` | Supabase auth (email/password → JWT) |
| `HealthKitManager.swift` | HealthKit queries for sleep + biometrics |
| `APIClient.swift` | Authenticated HTTP client for Flask API |
| `SyncManager.swift` | Incremental sync logic, UserDefaults anchor |
