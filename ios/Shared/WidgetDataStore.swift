import Foundation
import WidgetKit

// Reads and writes WidgetTodayData from/to the shared App Group container so that
// widget extensions can access today's sessions without a network call.
//
// App Group ID must be added to all four targets in Xcode:
//   TrainingCompanion · TrainingWidgets · TrainingCompanionWatch Watch App · TrainingWatchWidgets

enum WidgetDataStore {
    static let appGroupID = "group.haerdsoft.TrainingCompanion"
    static let todayKey   = "widget_today_data"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Write today's sessions and trigger an immediate widget refresh.
    /// Call this from the main app and watch app after loading/receiving sessions.
    static func write(_ data: WidgetTodayData) {
        guard let defaults = sharedDefaults,
              let encoded = try? JSONEncoder().encode(data) else { return }
        defaults.set(encoded, forKey: todayKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Read the last saved WidgetTodayData from the App Group container.
    static func read() -> WidgetTodayData? {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: todayKey),
              let decoded = try? JSONDecoder().decode(WidgetTodayData.self, from: data) else { return nil }
        // Discard stale data from a previous day
        let today = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }()
        return decoded.date == today ? decoded : nil
    }
}
