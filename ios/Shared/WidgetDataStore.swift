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

    static let weekKey = "widget_week_data"
    static let statusKey = "widget_status_data"

    /// The week strip and the status row; redraws only those two widgets.
    static func writeHome(week: WidgetWeekData?, status: WidgetStatusData) {
        guard let defaults = sharedDefaults else { return }
        if let week, let encoded = try? JSONEncoder().encode(week) {
            defaults.set(encoded, forKey: weekKey)
        } else {
            defaults.removeObject(forKey: weekKey)
        }
        if let encoded = try? JSONEncoder().encode(status) { defaults.set(encoded, forKey: statusKey) }
        WidgetCenter.shared.reloadTimelines(ofKind: "WeekOverviewWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "StatusRowWidget")
    }

    static func readWeek() -> WidgetWeekData? {
        guard let data = sharedDefaults?.data(forKey: weekKey) else { return nil }
        return try? JSONDecoder().decode(WidgetWeekData.self, from: data)
    }

    static func readStatus() -> WidgetStatusData? {
        guard let data = sharedDefaults?.data(forKey: statusKey) else { return nil }
        return try? JSONDecoder().decode(WidgetStatusData.self, from: data)
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
