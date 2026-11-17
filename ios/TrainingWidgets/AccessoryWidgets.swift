import WidgetKit
import SwiftUI

// The Lock Screen's widgets (design-system §6.58): today's session in the
// rectangle or the line above the clock, and the week's count as a ring. They
// read what the home-screen widgets read (WidgetDataStore) and are drawn in
// the system's one tint, so nothing here carries a colour: what is done is a
// checkmark and a number, never a hue.

// MARK: - Today's session

/// Today in one line: the session and its minutes, how many when several,
/// the rest day, or that all of it is done.
enum AccessoryText {
    static func today(_ data: WidgetTodayData?) -> String {
        guard let data else { return "Open Training Companion" }
        if data.sessions.isEmpty { return "Rest day" }
        if data.allDone { return "Today done" }
        if data.sessions.count == 1, let s = data.sessions.first {
            return "\(s.archetypeName) · \(s.estimatedMinutes) min"
        }
        let done = data.sessions.filter { (data.completedIds ?? []).contains($0.id) }.count
        return done > 0 ? "\(done) of \(data.sessions.count) sessions done" : "\(data.sessions.count) sessions today"
    }

    /// Sessions done and in all this week; nil without a week, or once the
    /// stored week is over (the app has not been opened since).
    static func weekCount(_ week: WidgetWeekData?, today: String) -> (done: Int, total: Int)? {
        guard let week, let last = week.days.last?.date, today <= last else { return nil }
        let all = week.days.flatMap(\.sessions)
        return (all.filter(\.done).count, all.count)
    }

    static func week(_ week: WidgetWeekData?, today: String) -> String {
        guard let week, let count = weekCount(week, today: today) else { return "Open Training Companion" }
        return "Week \(week.weekNumber) · \(count.done) of \(count.total) done"
    }
}

struct AccessoryTodayRectangle: View {
    let data: WidgetTodayData?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let data, let first = data.sessions.first {
                let done = (data.completedIds ?? [])
                HStack(spacing: 4) {
                    Image(symbol: data.allDone ? "checkmark.circle.fill" : WidgetModalityStyle.symbol(for: first))
                        .widgetAccentable()
                    Text(data.sessions.count == 1 ? first.archetypeName : "\(data.sessions.count) sessions")
                        .font(.headline)
                        .lineLimit(1)
                }
                if data.sessions.count == 1 {
                    Text(data.allDone ? "Done" : "\(first.estimatedMinutes) min · \(WidgetModalityStyle.label(for: first.modalityId))")
                        .font(.caption)
                        .lineLimit(1)
                    if !first.exerciseNames.isEmpty {
                        Text(first.exerciseNames.prefix(2).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    ForEach(data.sessions.prefix(2)) { s in
                        Label(s.archetypeName, systemImage: done.contains(s.id) ? "checkmark" : "circle")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            } else {
                Label(data == nil ? "Training" : "Rest day", systemImage: data == nil ? "figure.run" : "battery.100.bolt")
                    .font(.headline)
                    .widgetAccentable()
                Text(data == nil ? "Open the app to load today." : "Recovery is training.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessoryText.today(data))
    }
}

// MARK: - The week's count

struct WeekProgressWidget: Widget {
    static let kind = "WeekProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WeekProvider()) { entry in
            WeekProgressView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "trainingcompanion://program?section=calendar"))
        }
        .configurationDisplayName("Week Count")
        .description("This program week's sessions, done of all.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WeekProgressView: View {
    let entry: WeekEntry
    @Environment(\.widgetFamily) private var family

    private var today: String { homeDayString(entry.date) }

    var body: some View {
        let count = AccessoryText.weekCount(entry.week, today: today)
        switch family {
        case .accessoryInline:
            Label(AccessoryText.week(entry.week, today: today), systemImage: "calendar")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                if let week = entry.week, let count {
                    Text("Week \(week.weekNumber) of \(week.totalWeeks)")
                        .font(.headline)
                        .widgetAccentable()
                    Text("\(count.done) of \(count.total) sessions done")
                        .font(.caption)
                    HStack(spacing: 4) {
                        ForEach(week.days, id: \.date) { day in
                            // A done day is filled, a day to do a ring, a rest day a dash:
                            // shapes, since the Lock Screen has one colour.
                            Image(systemName: day.sessions.isEmpty ? "minus"
                                  : day.sessions.allSatisfy(\.done) ? "circle.fill" : "circle")
                                .font(.caption2)
                                .fontWeight(day.date == today ? .black : .regular)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityHidden(true)
                } else {
                    Text("Week").font(.headline)
                    Text("Open the app to load it.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        default:
            Gauge(value: Double(count?.done ?? 0), in: 0...Double(max(count?.total ?? 1, 1))) {
                Text("Wk")
            } currentValueLabel: {
                Text(count.map { "\($0.done)/\($0.total)" } ?? "—")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AccessoryText.week(entry.week, today: today))
        }
    }
}
