import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct TodayEntry: TimelineEntry {
    let date: Date
    let todayData: WidgetTodayData?
}

// MARK: - Provider

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, todayData: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, todayData: WidgetDataStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: .now, todayData: WidgetDataStore.read())
        // Refresh just after midnight so tomorrow's sessions appear promptly
        let nextRefresh = Calendar.current.startOfDay(for: Date().addingTimeInterval(86700))
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Widget

struct TodaySessionWidget: Widget {
    let kind = "TodaySessionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Training")
        .description("See today's scheduled sessions at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

