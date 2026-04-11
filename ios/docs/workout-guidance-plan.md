# Workout Guidance (Personal Trainer) — Implementation Plan

## Context

The iOS app is currently a pure health-data sync utility — two screens, no training awareness. This document plans the full workout guidance experience: the iPhone fetches today's sessions from the server, relays them to a new watchOS app target, and the Watch guides the user through every exercise with live HR monitoring, interval timers, coaching cues, and post-workout sync back to the API.

---

## Critical Files

| File | Role |
|---|---|
| `api.py:238` | `_clean_exercise_assignment` — add `slot_type` + `rest_sec` |
| `api.py:1244` | `GET /api/user/program` — already exists, iOS app calls this |
| `frontend/src/api/types.ts` | Add `slot_type?: string`, `rest_sec?: number` to `ExerciseAssignment` |
| `frontend/src/lib/hrZones.ts` | Port zone math to Swift (`HRZoneCalculator.swift`) |
| `ios/TrainingCompanion/APIClient.swift` | Extend with program fetch + session log push |
| `ios/TrainingCompanion/SyncManager.swift` | Wire in Watch sync after bio sync |

---

## Phase 1 — Backend Fix (prerequisite, deploy first)

**`api.py:238` — `_clean_exercise_assignment`**

Add two keys. The `slot` dict is already present in `ea` (line 251 uses it for `notes`):

```python
'slot_type': (ea.get('slot') or {}).get('slot_type'),  # NEW
'rest_sec':  (ea.get('slot') or {}).get('rest_sec'),    # NEW
```

Non-breaking — frontend ignores unknown keys. Also add to `frontend/src/api/types.ts`:
```typescript
slot_type?: string
rest_sec?: number
```

**Supabase migration** — distinguish Watch-logged sessions from web-logged:
```sql
ALTER TABLE session_logs ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'web';
```
Update `src/health_store.py` `upsert_session_log()` to store `source` field.

---

## Phase 2 — iPhone: Program Sync to Watch

### New file: `ios/TrainingCompanion/WatchModels.swift`
Add to **both** iOS and watchOS targets.

`WatchExercise` fields:
- Identity: `exerciseId`, `name`, `slotType`, `slotRole`, `isMeta`
- Display: `loadDescription` (pre-formatted string e.g. "5×5 @ 100kg"), `loadNote`, `coachingCue`
- Timer/screen logic: `sets`, `reps`, `weightKg`, `targetRpe`, `durationMinutes`, `zoneTarget`, `timeMinutes`, `targetRounds`, `format`, `holdSeconds`, `distanceKm`, `restSeconds`
- Parsed zones: `prescribedZoneLower`, `prescribedZoneUpper` (integers 1–5, parsed from `zoneTarget` on iPhone)

Keep Watch payload under 10KB — send today's sessions only, not the full program.

### New file: `ios/TrainingCompanion/WatchSessionManager.swift`
- `WCSessionDelegate` on iPhone side
- On launch (after auth): call `GET /api/user/program`, decode `ServerProgram`
- Compute today's slot: week index = `floor(daysSinceStart / 7)`, day name from `Calendar.current.weekday`
- Encode today's `[Session]` → `[WatchSession]` → `WCSession.transferUserInfo()`
- Re-send only if date changed or >4 hours since last send (UserDefaults anchor)
- Receive `type: "workout_complete"` from Watch → call `APIClient.saveWorkoutLog()`
- Edge cases: program expired (week index ≥ weeks.count), no program (null response)

Wire into `SyncManager.syncAll()` — after bio sync, call `WatchSessionManager.syncProgram()`.

### Extend `ios/TrainingCompanion/APIClient.swift`
Add:
- `fetchProgram() async throws -> ServerProgram?` → `GET /api/user/program`
- `saveWorkoutLog(_ log: WatchWorkoutSummary, sessionKey: String) async throws` → `PUT /api/health/sessions/{sessionKey}` (existing endpoint — no new endpoint needed)

---

## Phase 3 — watchOS Target

### Xcode setup
- File → New → Target → Watch App (no notification scene); name: `TrainingCompanionWatch`
- Capabilities: HealthKit, Background Modes → Workout Processing
- `WatchModels.swift` added to both targets

### New files (watchOS target)

**`WatchConnectivityManager.swift`**
- `WCSessionDelegate` Watch side
- Receives `[WatchSession]` from iPhone `userInfo`, persists to `UserDefaults`
- `@Published var todaySessions: [WatchSession]`
- "Request Sync" button sends `sendMessage` to iPhone

**`HRZoneCalculator.swift`** — Swift port of `frontend/src/lib/hrZones.ts`
```swift
// Friel/Coggan: Z1 <60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 90%+
// 1-indexed to match frontend display (Z1=1 … Z5=5)
func zone(for bpm: Int, maxHR: Int) -> Int
func parseZoneRange(_ target: String) -> (lower: Int, upper: Int)?
// "Zone 1–2 (conversational)" → (1, 2)
```
Note: `hrZones.ts` `assignZone` is 0-indexed internally; Swift port uses 1-indexed to match displayed "Zone 1–5" labels.

**`WorkoutSessionState.swift`** (`ObservableObject` — target watchOS 9 for Series 4+ compatibility)

State machine phases:
```
.idle
.active(exerciseIndex: Int, setIndex: Int)
.timedWork(exerciseIndex: Int, secondsElapsed: Int)
.emomInterval(exerciseIndex: Int, round: Int, phase: .work | .rest, remaining: Int)
.amrapRunning(exerciseIndex: Int, round: Int, secondsRemaining: Int)
.resting(exerciseIndex: Int, completedSet: Int, secondsRemaining: Int)
.sessionComplete
```

Persisted to `UserDefaults` on every change — enables mid-workout app re-launch recovery.

Key tracked data: `currentHR`, `peakHR`, `avgHRSamples: [Int]`, `hrOutOfZoneSeconds`, `setLogs: [String: [WatchSetLog]]`, `emomRound`, `completedExerciseIds: Set<String>`.

**`WorkoutManager.swift`** (`HKWorkoutSessionDelegate + HKLiveWorkoutBuilderDelegate`)
- Owns `HKWorkoutSession` + `HKLiveWorkoutBuilder`
- `startWorkout()`, `pauseWorkout()`, `endWorkout()`
- Live HR via `workoutBuilder(_:didCollectDataOf:)` → updates `WorkoutSessionState`
- Zone alert logic: HR outside prescribed zone for >30 continuous seconds → haptic `.notification` × 3 + overlay banner; 60s cooldown before re-alerting
- Smart rest extension: when rest timer hits 0, if HR > (zone_upper_bpm + 5), suppress auto-advance and show "Still recovering" indicator with current HR

---

## Phase 4 — Watch UI Screens

Navigation pattern: `NavigationStack` for pre-workout linear drill-down; `TabView(.page)` for the three active-workout pages; `.fullScreenCover` for rest timer (non-dismissable by back gesture).

### Screen inventory

| Screen | View | Notes |
|---|---|---|
| S1 Today | `SessionListView` | Root. Session cards with modality + duration. "Rest Day" if empty. |
| S2 Session Overview | `SessionOverviewView` | Scrollable exercise list, deload badge, "Begin Workout" |
| S3 Active Workout | `ActiveWorkoutView` | `TabView(.page)` container |
| S3-A Current Exercise | `CurrentExerciseView` | Dispatches to slot-type-specific child view |
| S3-B Session Progress | `SessionProgressView` | All exercises with checkmarks; tap to jump |
| S3-C Live Metrics | `LiveMetricsView` | HR ring (zone-colored), elapsed time, calories |
| S4 Rest Timer | `RestTimerView` | `.fullScreenCover`; countdown ring; smart recovery extension |
| S5 Set Logger | `SetLoggerSheetView` | `.sheet`; reps via `.digitalCrownRotation`, RPE 1–5, Done |
| S6 Session Complete | `SessionCompleteView` | Total time, HR stats, Save Workout |
| S8 No Program | `NoProgramView` | "Request Sync" button |
| S9 Settings | `SettingsView` | HR alerts toggle, haptic intensity, force sync |

### slot_type → view mapping (all render inside S3-A)

| `slot_type` | View | Key behavior |
|---|---|---|
| `sets_reps` | `SetsRepsView` | Set dots (●●○○○), Complete Set → S5 set logger → rest timer |
| `time_domain` | `TimeDomainView` | Count-up elapsed ring, zone target label, HR zone alerts |
| `skill_practice` | `TimeDomainView` | Same; coaching cues take screen priority over HR |
| `emom` | `EMOMView` | Auto-cycling work/rest timer, WORK/REST pill, haptic each interval |
| `amrap` | `AMRAPView` | Countdown timer, + button to log rounds |
| `for_time` | `ForTimeView` | Count-up stopwatch, movement checklist to mark off |
| `distance` | `DistanceView` | GPS elapsed distance; fallback to manual entry if no GPS |
| `static_hold` | `StaticHoldView` | Per-set countdown ring; "Fail" records actual hold time |

### Personal trainer features

- **Coaching cue**: `assignment.notes` preferred over `exercise.notes`; shown on exercise card
- **Progression note**: `load_note` ("+2.5kg from last session") in accent color below load
- **Deload reminder**: banner on S2 if `session.is_deload` — "Deload week — quality over load"
- **Set quality feedback**: RPE ≥ prescribed+2 → "Felt hard — consider lighter load"; RPE ≤ prescribed-2 → "Felt easy — ready to progress"
- **Zone alerts**: haptic + overlay if HR outside target zone >30s (primarily `time_domain`)
- **Smart rest extension**: HR > zone_upper+5 bpm when rest expires → show recovery indicator, suppress auto-advance
- **EMOM haptic coaching**: `.start` each work interval, `.stop` each rest interval
- **Warm-up card**: if first slot `role == "warm_up"`, show notes as full-screen card before main work

### Haptics schedule

| Event | Pattern |
|---|---|
| Workout start | `.start` |
| Set complete | `.success` |
| Rest: 30s remaining | `.notification` |
| Rest: 10s remaining | `.directionUp` |
| Rest: 0s (next set) | `.start` |
| Zone alert (out >30s) | `.notification` × 3 |
| EMOM work interval start | `.start` |
| EMOM rest interval start | `.stop` |
| Session complete | `.success` × 2 |

---

## Phase 5 — Post-Workout Sync

After "Save Workout" on S6:
1. `WorkoutManager.endWorkout()` → `HKLiveWorkoutBuilder.finishWorkout()` writes to HealthKit (auto-syncs to iPhone — no duplicate write needed)
2. Watch sends `WCSession.transferUserInfo(["type": "workout_complete", ...])` with `WatchWorkoutSummary`
3. iPhone `WatchSessionManager` receives → calls `APIClient.saveWorkoutLog()` → `PUT /api/health/sessions/{sessionKey}`

`WatchWorkoutSummary` shape:
```json
{
  "type": "workout_complete",
  "sessionId": "3-Thursday-0",
  "date": "2026-04-02",
  "startedAt": "...", "endedAt": "...",
  "durationMinutes": 73,
  "avgHR": 142, "peakHR": 171,
  "setLogs": {
    "back_squat": [
      { "setIndex": 0, "repsActual": 5, "weightKg": 100, "rpe": 8, "completed": true }
    ]
  },
  "exercisesCompleted": 4,
  "source": "apple_watch_live"
}
```

---

## Build Order

1. **Backend fix** — add `slot_type`/`rest_sec` to `_clean_exercise_assignment`; deploy; verify in API response
2. **TypeScript types** — `slot_type?: string`, `rest_sec?: number` in `frontend/src/api/types.ts`
3. **Supabase migration** — `source` column on `session_logs`
4. **Create Xcode project** (iOS target from existing 6 Swift files)
5. **Add watchOS target**; create `WatchModels.swift` (both targets)
6. **`APIClient.swift`** extensions + **`WatchSessionManager.swift`** (iOS) — data pipeline
7. **`WatchConnectivityManager.swift`** (watchOS) — receive + persist sessions
8. **End-to-end pipeline test** — program on web → appears on Watch
9. **`HRZoneCalculator.swift`** + **`WorkoutSessionState.swift`** — unit-testable without device
10. **`WorkoutManager.swift`** — device required for `HKWorkoutSession`
11. **Watch UI** — skeletons with mock data, then wire to state machine
12. **Post-workout sync** — `SessionCompleteView` + iPhone receiver
13. **End-to-end workout test** — complete session on Watch, verify in web app

---

## Edge Cases

- **Mid-workout app exit**: `HKWorkoutSession` continues silently. On re-launch, restore `WorkoutSessionState` from `UserDefaults` and re-join the existing session via `currentState == .running`.
- **Watch without iPhone nearby**: Workouts run from cached `[WatchSession]`. Post-workout `transferUserInfo` is guaranteed-delivery — queued until connectivity restores. No workout data is ever lost.
- **No GPS (Watch SE / Series 3)**: `DistanceView` detects `CLAuthorizationStatus`, falls back to manual distance entry.
- **EMOM format parsing**: Regex `(\d+)\s*[×x]\s*(\d+)\s*/\s*(\d+)` extracts rounds/work_sec/rest_sec from `load.format`. Fallback: 60s work / 0s rest if format absent.
- **Program expired**: week index ≥ `weeks.count` → "Program complete — generate a new one on the web app."
- **watchOS target version**: watchOS 9 (Series 4+ compatible). Use `ObservableObject` + `@Published`; do not use `@Observable` macro (requires watchOS 10).

---

## Phase 6 — Visual Polish & Coverage Fixes

### 6-A: Missing Slot Type — `amrap_movement`

**Problem:** `data/archetypes/conditioning/mixed_modal_amrap.yaml` uses `slot_type: amrap_movement` for individual movements within an AMRAP (pull-ups, push-ups, etc.). `CurrentExerciseView` has no case for it — silently routes to `SetsRepsView` via `default:`, which shows set dots + rest timer. That's wrong for an athlete self-pacing inside an ongoing AMRAP.

**Fix:** Add `case "amrap_movement"` to the switch in `CurrentExerciseView.swift` → new `AMRAPMovementView`:

- Exercise name + rep target ("10 Pull-ups")
- Tap-counter (`+` button) for rep/round tracking within the AMRAP
- **No rest timer** — athlete self-manages pace
- Parent AMRAP countdown visible via swipe to S3-C (LiveMetricsView)

Files:
- `ios/TrainingCompanionWatch/Views/CurrentExerciseView.swift` — add case
- `ios/TrainingCompanionWatch/Views/ExerciseViews/AMRAPMovementView.swift` — new file

Updated slot_type → view table (add row):

| `slot_type` | View | Key behavior |
|---|---|---|
| `amrap_movement` | `AMRAPMovementView` | Rep counter, no rest timer, self-paced within parent AMRAP |

---

### 6-B: Modality Coloring

**Problem:** Session cards (S1, S2) and exercise view headers are entirely neutral. On a small watch face, color is the fastest signal.

**New file:** `ios/TrainingCompanionWatch/ModalityStyle.swift`

```swift
struct ModalityStyle {
    static func color(for modalityId: String) -> Color { ... }
    static func icon(for modalityId: String) -> String { ... }
}
```

Color map:

| Modality ID | Color |
|---|---|
| `max_strength`, `relative_strength`, `combat_sport` | `.red` |
| `strength_endurance` | `.orange` |
| `power` | `.yellow` |
| `aerobic_base` | `.green` |
| `anaerobic_intervals` | `.mint` |
| `mixed_modal_conditioning` | `.cyan` |
| `kettlebell` | `.indigo` |
| `movement_skill` | `.purple` |
| `mobility` | `.teal` |
| `durability` | `.brown` |

Where to apply:
- `SessionListView` — session card left-border accent or modality pill background
- `SessionOverviewView` — header bar foregroundStyle tint
- `CurrentExerciseView` — thin colored bar at top of S3-A exercise card

---

### 6-C: Icon System

**Problem:** Every session card and exercise row uses `figure.strengthtraining.traditional`. No visual differentiation across modalities or slot types.

Modality → SF Symbol map (add to `ModalityStyle.swift`):

| Modality | SF Symbol |
|---|---|
| `max_strength`, `relative_strength` | `figure.strengthtraining.traditional` |
| `aerobic_base` | `figure.run` |
| `anaerobic_intervals` | `heart.circle` |
| `kettlebell` | `dumbbell` |
| `movement_skill` | `figure.flexibility` |
| `mobility` | `figure.cooldown` |
| `durability` | `backpack` |
| `mixed_modal_conditioning` | `bolt.heart` |
| `power` | `bolt.fill` |
| `combat_sport` | `figure.boxing` |

Slot-type → SF Symbol map (used in S3-B `SessionProgressView` beside exercise name):

| Slot Type | SF Symbol |
|---|---|
| `sets_reps` | `dumbbell.fill` |
| `time_domain` | `clock.fill` |
| `emom` | `timer` |
| `amrap` | `arrow.clockwise` |
| `for_time` | `flag.checkered` |
| `distance` | `map.fill` |
| `static_hold` | `pause.circle.fill` |
| `skill_practice` | `sparkles` |
| `amrap_movement` | `repeat` |

Files to update:
- `SessionListView.swift` — session card icon (modality icon)
- `SessionOverviewView.swift` — exercise list slot-type icons
- `SessionProgressView.swift` — per-exercise slot-type icon in S3-B progress list

---

### 6-D: `resolvedSlotType` — Generalized Screen Inference

**Problem:** `slot_type` is an archetype-slot concept. For user-created archetypes that omit it, or future freeform sessions, the current `default: SetsRepsView` fallback is blind.

**Fix:** Add a computed property `resolvedSlotType` to `WatchExercise` in `WatchModels.swift`. `CurrentExerciseView` switches on this instead of `slotType` directly.

```swift
// ios/TrainingCompanion/WatchModels.swift
extension WatchExercise {
    var resolvedSlotType: String {
        let known = ["sets_reps","time_domain","skill_practice","emom",
                     "amrap","amrap_movement","for_time","distance","static_hold"]
        if known.contains(slotType) { return slotType }
        // Field-based inference — order matters
        if distanceKm != nil                              { return "distance" }
        if holdSeconds != nil                             { return "static_hold" }
        if emomFormat != nil                              { return "emom" }
        if durationMinutes != nil                         { return "time_domain" }
        if timeMinutes != nil && targetRounds != nil      { return "amrap" }
        if targetRounds != nil                            { return "for_time" }
        return "sets_reps"
    }
}
```

**Why this generalizes:**
- `slot_type` is just a shorthand label — the populated load fields are the ground truth
- Custom archetypes (`POST /api/archetypes`) that set `slot_type` explicitly → pass through unchanged
- Custom archetypes that omit `slot_type` → inference picks the right screen from load fields
- User-created exercises assigned to standard slots → inherit slot's `slot_type` → no change needed
- Future freeform sessions → inference handles them without any new code

**File:** `ios/TrainingCompanion/WatchModels.swift` (new extension)
**File:** `ios/TrainingCompanionWatch/Views/CurrentExerciseView.swift` — switch on `ex.resolvedSlotType`

---

### Known Remaining Gaps (no screen yet)

These interaction patterns exist in the training data but have no dedicated watch view:

| Pattern | Current fallback | Notes |
|---|---|---|
| **Breathing ladder** (1-20-1 reps per rung) | `for_time` (stopwatch) | No rung-by-rung progression; athlete self-tracks |
| **Barbell/KB complex** (multiple movements, no put-down) | `for_time` or `amrap` | No exercise-sequence chaining within one slot |
| **Pyramid sets** (5-4-3-2-1 ascending/descending reps) | `sets_reps` (fixed reps) | Load description shows full pyramid as text only |
| **Superset / paired sets** (A1/A2 alternating) | Two sequential `sets_reps` slots | No explicit pairing UI; athlete follows order in S3-B |

These are not blockers — the fallback views are functional. A dedicated `LadderView` or `ComplexView` would be Phase 7+ work.

---

### Phase 6 Build Order

1. Add `resolvedSlotType` to `WatchModels.swift`; update `CurrentExerciseView.swift` to use it
2. Create `ModalityStyle.swift` with color + icon maps; add to watchOS target
3. Add `amrap_movement` case to `CurrentExerciseView.swift`; create `AMRAPMovementView.swift`
4. Update `SessionListView` — modality color accent + icon
5. Update `SessionOverviewView` — header tint + exercise slot-type icons
6. Update `SessionProgressView` — slot-type icons per row
7. Update `CurrentExerciseView` — thin modality color bar above exercise card

### Verification

- All modality IDs from `data/modalities/*.yaml` have a `ModalityStyle` entry (no silent `.secondary` fallback)
- `amrap_movement` case routes to `AMRAPMovementView`, not `SetsRepsView`
- S1 session list shows visually distinct colors for a mixed-modality week (run `general_gpp` goal to get a variety)
- Create a custom archetype via `POST /api/archetypes` without a `slot_type` field; verify watch shows a sensible screen based on load fields
