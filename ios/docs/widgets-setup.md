# Widget Setup — Xcode Configuration

All Swift code is written. Follow these steps in Xcode to connect everything.

---

## 1. Create the iPhone Widget Extension

1. File → New → Target → **Widget Extension**
2. Name: `TrainingWidgets`
3. Bundle Identifier: `haerdsoft.TrainingCompanion.widgets`
4. **Uncheck** "Include Configuration App Intent" (we use StaticConfiguration)
5. When asked "Activate scheme?", click Activate
6. **Add files to the target:**
   - `ios/Shared/WidgetSharedModels.swift` → check ✓ TrainingWidgets
   - `ios/Shared/WidgetDataStore.swift` → check ✓ TrainingWidgets
   - `ios/TrainingWidgets/TrainingWidgets.swift` (already in target — replaces default)
   - `ios/TrainingWidgets/TodayWidget.swift` → add to TrainingWidgets target
   - `ios/TrainingWidgets/TodayWidgetViews.swift` → add to TrainingWidgets target
7. **Delete** the default `TrainingWidgets.swift` Xcode generated and replace with the files above.

---

## 2. Create the Watch Widget Extension

1. File → New → Target → **Widget Extension**
2. Name: `TrainingWatchWidgets`
3. Bundle Identifier: `haerdsoft.TrainingCompanion.watchkitapp.watchwidgets`
4. Set **Deployment Target** to match the watch app
5. **Add files to the target:**
   - `ios/Shared/WidgetSharedModels.swift` → check ✓ TrainingWatchWidgets
   - `ios/Shared/WidgetDataStore.swift` → check ✓ TrainingWatchWidgets
   - `ios/TrainingWatchWidgets/TrainingWatchWidgets.swift`
   - `ios/TrainingWatchWidgets/SessionStartWidget.swift`

---

## 3. Add Shared Files to Main Targets

Select each file and add to the correct targets:

| File | Targets |
|------|---------|
| `Shared/WidgetSharedModels.swift` | TrainingCompanion, TrainingWidgets, TrainingCompanionWatch Watch App, TrainingWatchWidgets |
| `Shared/WidgetDataStore.swift` | TrainingCompanion, TrainingWidgets, TrainingCompanionWatch Watch App, TrainingWatchWidgets |

To add to a target: select the file → File Inspector (right panel) → check the target boxes.

---

## 4. Add App Group Capability

Add the App Group `group.haerdsoft.TrainingCompanion` to **all four targets**:

1. Select target → Signing & Capabilities → + Capability → App Groups
2. Click `+` → enter `group.haerdsoft.TrainingCompanion`
3. Repeat for: TrainingCompanion, TrainingWidgets, TrainingCompanionWatch Watch App, TrainingWatchWidgets

---

## 5. Register URL Scheme (for phone widget deep links)

1. Select the **TrainingCompanion** target → Info tab
2. Under "URL Types", click `+`
3. Identifier: `haerdsoft.TrainingCompanion`
4. URL Schemes: `trainingcompanion`

This allows widget `Link(destination: URL(string: "trainingcompanion://today")!)` taps to open the app on the Dashboard tab.

---

## 6. Link Watch Widget to Watch App

In the watch app target's `Info.plist`, ensure the watch widget extension is listed. Xcode usually handles this automatically when you create the target, but verify:

- **TrainingCompanionWatch Watch App** target → Build Phases → Embed Watch Content (or Embed App Extensions)
- `TrainingWatchWidgets.appex` should appear there

---

## 7. Add WidgetKit to Targets

For each target that uses `WidgetDataStore.swift` (TrainingCompanion, Watch App):
- Select target → General → Frameworks, Libraries, and Embedded Content → `+` → WidgetKit.framework

---

## How it Works

### Data Flow
```
iOS App loads program → AppState.writeWidgetData() → App Group UserDefaults
    ↓
TrainingWidgets reads App Group → displays today's sessions in iPhone widget

Watch app receives sessions via WCSession → WatchConnectivityManager.writeWidgetData()
    ↓
TrainingWatchWidgets reads App Group (watch container) → displays complication
```

### Phone Widget
- **Small**: Shows first session's modality icon + archetype name + duration. Rest day shows a green battery icon.
- **Medium**: Shows up to 2 sessions with modality icons and durations.
- **Large**: Shows all sessions with exercise name previews, colored backgrounds.
- **Tap action**: Opens the Dashboard tab (`trainingcompanion://today` URL scheme).

### Watch Widget / Complication
- **Circular**: Modality icon in a tinted circle; session count badge if multiple.
- **Rectangular**: Session name + duration/modality label.
- **Corner**: Icon with session name label.
- **Inline**: One-liner with icon.
- **Tap action (single session)**: Deep links to `trainingcompanion://start?session=<id>`, which navigates directly to `ActiveWorkoutView` for that session.
- **Tap action (multiple sessions)**: Opens the session list (`trainingcompanion://today`).
