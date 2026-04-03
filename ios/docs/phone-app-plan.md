# Phone App — Implementation Plan

## Context

The iPhone app is currently a health-data sync utility (HealthKit → server) plus a WCSession relay to the watch. This plan expands it into a full native equivalent of the React web app, while staying consistent with `ios/docs/design-system.md`. The watch app is unchanged. The phone becomes the primary native screen for program management, session logging, and program generation — no browser required.

---

## Information Architecture

4 tabs. Each represents a genuinely parallel context the user switches between.

```
┌──────────┬──────────┬──────────┬──────────┐
│  Today   │ Program  │ Library  │ Profile  │
└──────────┴──────────┴──────────┴──────────┘
```

`SessionDetailView` is pushed onto the nav stack from both Today and Program — it is not tab-specific. `ProgramBuilderView` is a sheet presented from both Today and Program empty states.

---

## Tab 1 — Today

**Root:** `TodayView`

### States

**No program (empty state):**
```
[barbell icon]
No program yet
Generate one to get started.
[Generate a Program]   ← primary button, presents ProgramBuilderView sheet
```

**Rest day:**
- Rest day card with moon/zzz icon, "Rest Day — Recovery"
- Deload banner if `session.isDeload` (see design-system.md §6.7)

**Has sessions:**
- Watch sync strip (if `WCSession.isReachable || isPaired`):
  - "Synced to Watch · {N} min ago" with watch icon
  - "Not synced — tap to sync" if stale → tap calls `WatchSessionManager.syncProgram()`
- List of `SessionCard` components for today's sessions (see design-system.md §6.1)
- Tap session card → push `SessionDetailView`

---

## Tab 2 — Program

**Root:** `ProgramCalendarView`

- Nav bar title: "Program"
- Nav bar trailing: `+` button → presents `ProgramBuilderView` sheet
- Week strip: 7 day pills (Mon–Sun), today highlighted with `Accent` background
- `<` / `>` buttons to navigate weeks
- Below week strip: day detail — tapping a day expands its sessions as `SessionCard` rows
- Tap session → push `SessionDetailView`
- **Empty state:** same as Today's no-program state

### ProgramBuilderView (sheet, 3 steps)

Mirrors the web `ProgramBuilder` wizard. Presented as a `.sheet` with a drag-to-dismiss handle.

| Step | Content | API |
|---|---|---|
| 1 — Goal | Scrollable list of goal cards (icon + name + description). Tap to select. | `GET /api/goals` |
| 2 — Constraints | Athlete level segmented control; days/week stepper; session time slider (30–120 min); equipment profile picker; injury flag toggles | `GET /api/constraints/equipment-profiles`, `GET /api/constraints/injury-flags` |
| 3 — Review | Summary card showing selections; "Generate" primary button → loading state → dismiss on success | `POST /api/programs/generate` |

On success: `ProgramStore` refreshes, both Today and Program tabs update, `NotificationManager.scheduleAll()` runs.

---

## Tab 3 — Library

**Root:** `ExerciseCatalogView`

- Sticky search bar at top
- Filter chips below search: category (All / Barbell / Bodyweight / Kettlebell / Aerobic / Carries / Mobility / Skill / Rehab / Sandbag)
- `List` with section headers by category
- 198 exercises loaded from `GET /api/exercises`; cached on first load; filtered client-side
- Tap exercise → `ExerciseDetailSheet` (name, category, movement patterns, equipment, coaching notes)

---

## Tab 4 — Profile

**Root:** `ProfileView`

Sections in a `Form` / `List`:

| Section | Content |
|---|---|
| Athlete | Level picker (Beginner / Intermediate / Advanced); Max HR field (for watch zone calc) |
| Equipment | Equipment profile picker (from `GET /api/constraints/equipment-profiles`) |
| Injuries | Toggle list of injury flags (from `GET /api/constraints/injury-flags`) |
| Benchmarks | Performance log entries; mirrors web `ProfileBenchmarks` |
| Notifications | Master toggle; daily reminder time picker (DatePicker, `.hourAndMinute`) |
| Account | User email (read-only); Sign Out button |

Profile changes that affect program generation (equipment, injuries) show a banner: "Regenerate your program to apply changes."

---

## SessionDetailView (shared)

Pushed from Today or Program. Shows one full session.

**Header:**
- Modality color bar (2pt stripe, full width) — see design-system.md §6.1
- Archetype name (`.title3`, `.bold`)
- Modality badge + estimated duration pill
- Deload banner if applicable

**Exercise list:**
Each exercise row:
- Slot-type icon + exercise name (`.subheadline`, `.semibold`)
- Load description (`.caption.monospaced()`, amber — see design-system.md §4.2)
- Coaching cue: collapsed chevron; tap to expand inline
- Logging controls (see Phone Logging below)

**Footer:**
- "Mark Complete" primary button → assembles log → `PUT /api/health/sessions/{sessionKey}`
- If watch paired: "Open on Watch" nav bar button → triggers `WatchSessionManager.syncProgram()`

---

## Phone Session Logging

**New file: `ios/TrainingCompanion/PhoneSessionLogger.swift`**

`ObservableObject` (match watchOS target's `ObservableObject` pattern — don't mix `@Observable` macro between targets yet).

No `HKWorkoutSession`. No live HR. Simpler state machine than the watch.

```swift
enum PhoneSessionPhase {
    case idle
    case logging(exerciseIndex: Int, setIndex: Int)
    case timerRunning(exerciseIndex: Int, secondsElapsed: Int)
    case complete
}
```

Tracked state:
- `currentSession: WatchSession?`
- `phase: PhoneSessionPhase`
- `setLogs: [String: [WatchSetLog]]` — keyed by `exerciseId`
- `startedAt: Date`
- `completedExerciseIds: Set<String>`

Persisted to `UserDefaults` on every mutation — crash recovery. On app launch, `restoreIfNeeded()` checks for an in-progress session.

On complete: assembles `WatchWorkoutSummary` with `source: "iphone"` → calls `APIClient.saveWorkoutLog()`.

### Inline Logging Controls by Slot Type

**File: `ios/TrainingCompanion/Views/Today/PhoneSlotViews.swift`**

Uses `resolvedSlotType` (from `WatchModels.swift` Phase 6) — same inference logic as watch.

| Slot type | Phone control |
|---|---|
| `sets_reps` | Set rows: each row shows set number, reps field, weight field, RPE stepper. Tap row to activate inline editing. "Add Set" button appends. |
| `time_domain` | Start/Pause button + elapsed time counter + zone target label |
| `emom` | Auto-cycling WORK/REST timer (same logic as `EMOMView` on watch) |
| `amrap` | Countdown timer + round `+` counter |
| `for_time` | Count-up stopwatch + "Done" button |
| `distance` | Distance entry field with unit (km) |
| `static_hold` | Per-set countdown ring + "Begin / Fail" |
| `skill_practice` | Timer + coaching cue prominent |
| `amrap_movement` | Rep counter + `+` button; no rest timer |

---

## Notifications

**New file: `ios/TrainingCompanion/NotificationManager.swift`**

`UNUserNotificationCenter`. Request permission contextually — after first program generation, not on first launch.

### Notification Types

| Type | Trigger | Title | Body |
|---|---|---|---|
| Daily workout | User-configured time (default 07:00) on each training day | "Time to train" | "Today: {archetypeName} · {N} min" |
| Deload week | 07:00 on first day of a deload week | "Deload week" | "Focus on quality over load" |
| Program complete | 07:00 on day after final session | "Program complete" | "Time to generate a new one" |

### Implementation

```swift
func scheduleAll(for program: ServerProgram, reminderTime: DateComponents) {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    // Walk weeks × days, schedule UNCalendarNotificationTrigger per training day
    // repeats: false — one notification per day, re-scheduled on each program fetch
}
```

Deep link: `userInfo["destination"] = "today"` → `TrainingCompanionApp` handles `UNUserNotificationCenterDelegate.didReceive` → sets `selectedTab = .today`.

---

## New Files

| File | Purpose |
|---|---|
| `ios/TrainingCompanion/ProgramStore.swift` | `ObservableObject` — program data, current week, today's sessions; `.environmentObject` on `MainTabView` |
| `ios/TrainingCompanion/PhoneSessionLogger.swift` | Session logging state machine |
| `ios/TrainingCompanion/NotificationManager.swift` | Local notification scheduling |
| `ios/TrainingCompanion/Extensions/Color+Hex.swift` | `Color(hex:)` initializer — add to both targets |
| `ios/TrainingCompanion/Views/MainTabView.swift` | Root `TabView` |
| `ios/TrainingCompanion/Views/Today/TodayView.swift` | Today tab root |
| `ios/TrainingCompanion/Views/Today/SessionDetailView.swift` | Shared session detail + logging |
| `ios/TrainingCompanion/Views/Today/PhoneSlotViews.swift` | Slot-type logging controls |
| `ios/TrainingCompanion/Views/Program/ProgramCalendarView.swift` | Week strip + session grid |
| `ios/TrainingCompanion/Views/Program/ProgramBuilderView.swift` | 3-step generation wizard sheet |
| `ios/TrainingCompanion/Views/Library/ExerciseCatalogView.swift` | Search + filter exercise list |
| `ios/TrainingCompanion/Views/Library/ExerciseDetailView.swift` | Exercise detail sheet |
| `ios/TrainingCompanion/Views/Profile/ProfileView.swift` | Profile root |
| `ios/TrainingCompanion/Views/Profile/BenchmarksView.swift` | Performance log entries |

---

## Reuse (do not rewrite)

| Existing file | What to reuse |
|---|---|
| `ios/TrainingCompanion/APIClient.swift` | `fetchProgram()`, `saveWorkoutLog()` (added in watch plan Phase 2) |
| `ios/TrainingCompanion/AuthManager.swift` | Auth state, sign out |
| `ios/TrainingCompanion/WatchModels.swift` | `WatchSession`, `WatchExercise`, `WatchSetLog`, `resolvedSlotType` |
| `ios/TrainingCompanion/WatchSessionManager.swift` | `syncProgram()` — `ProgramStore` calls this; don't duplicate the fetch logic |
| `ios/TrainingCompanionWatch/ModalityStyle.swift` | Move to a shared location or duplicate into `ios/TrainingCompanion/ModalityStyle.swift` — update hex values to match design-system.md §3.1 |

---

## API Endpoints

| Endpoint | Used by |
|---|---|
| `GET /api/goals` | ProgramBuilderView step 1 |
| `GET /api/exercises` | ExerciseCatalogView |
| `GET /api/constraints/equipment-profiles` | ProfileView, ProgramBuilderView step 2 |
| `GET /api/constraints/injury-flags` | ProfileView, ProgramBuilderView step 2 |
| `POST /api/programs/generate` | ProgramBuilderView step 3 |
| `GET /api/user/program` | ProgramStore (via WatchSessionManager) |
| `PUT /api/health/sessions/{sessionKey}` | SessionDetailView (phone logging) |

No new backend endpoints required.

---

## Build Order

0. **`Color+Hex.swift`** — add to both targets; update `ModalityStyle.swift` hex values
1. **`ProgramStore.swift`** — fetch + cache program; compute today's sessions and current week
2. **`MainTabView.swift`** — 4-tab shell; wire `ProgramStore` as `.environmentObject`
3. **Today tab** — `TodayView` with all three states (empty, rest, sessions); `SessionCard` with modality styling
4. **`SessionDetailView`** — exercise list with load descriptions and coaching cues; no logging yet
5. **`PhoneSessionLogger`** + **`PhoneSlotViews`** — inline logging wired into `SessionDetailView`
6. **Program tab** — `ProgramCalendarView` week strip + `ProgramBuilderView` sheet
7. **Library tab** — `ExerciseCatalogView` with search + filter
8. **Profile tab** — `ProfileView` all sections
9. **`NotificationManager`** — schedule on program fetch; permission prompt after generation; deep link
10. **Watch sync strip** — watch status in `TodayView`; tap-to-sync

---

## Verification

- No program → empty state → tap "Generate" → builder sheet → generates → Today shows today's sessions
- Tap session card → `SessionDetailView` shows correct modality color bar, exercises, load specs in amber monospace
- Log a sets/reps session on phone → `source: "iphone"` log appears in web app session history
- Timer sessions (time_domain, emom, amrap) — timer starts, runs, completes, log recorded
- Notification fires at configured time on a training day; tap → app opens to Today tab
- Program tab week strip: navigate weeks, tap day to see sessions, tap session → `SessionDetailView`
- Library search "deadlift" → filtered results; category filter "barbell" → correct subset
- Profile: change equipment → banner "Regenerate to apply"; sign out → returns to auth screen
