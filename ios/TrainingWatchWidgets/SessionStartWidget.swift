import WidgetKit
import SwiftUI

// MARK: - Timeline Entry & Provider

struct WatchSessionEntry: TimelineEntry {
    let date: Date
    let todayData: WidgetTodayData?
}

struct WatchSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSessionEntry {
        WatchSessionEntry(date: .now, todayData: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchSessionEntry) -> Void) {
        completion(WatchSessionEntry(date: .now, todayData: WidgetDataStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSessionEntry>) -> Void) {
        let entry = WatchSessionEntry(date: .now, todayData: WidgetDataStore.read())
        let nextRefresh = Calendar.current.startOfDay(for: Date().addingTimeInterval(86700))
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Widget Configuration

struct SessionStartWidget: Widget {
    let kind = "SessionStartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchSessionProvider()) { entry in
            SessionStartWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Start Session")
        .description("Quick-start today's training.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}

// MARK: - Entry View

struct SessionStartWidgetView: View {
    var entry: WatchSessionEntry
    @Environment(\.widgetFamily) var family

    private var sessions: [WidgetSession] { entry.todayData?.sessions ?? [] }
    /// The first session not yet done, else the first.
    private var first: WidgetSession? {
        let done = Set(entry.todayData?.completedIds ?? [])
        return sessions.first { !done.contains($0.id) } ?? sessions.first
    }
    private var allDone: Bool { entry.todayData?.allDone ?? false }
    /// This program week, from the watch app's copy of the server's progress.
    private var week: (done: Int, sessions: Int)? {
        guard let d = entry.todayData?.weekDone, let n = entry.todayData?.weekSessions, n > 0 else { return nil }
        return (d, n)
    }
    /// "Week 3/5 · Ready 58" — the rectangular's third line; nil without data.
    private var weekLine: String? {
        var parts: [String] = []
        if let w = week { parts.append("Week \(w.done)/\(w.sessions)") }
        if let r = entry.todayData?.readinessScore { parts.append("Ready \(r)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Single session → deep link directly to that session; multiple → open session list
    private var deepLinkURL: URL {
        if sessions.count == 1, let s = first {
            return URL(string: "trainingcompanion://start?session=\(s.id)")!
        }
        return URL(string: "trainingcompanion://today")!
    }

    var body: some View {
        Link(destination: deepLinkURL) {
            switch family {
            case .accessoryCircular:   circularView
            case .accessoryRectangular: rectangularView
            case .accessoryCorner:     cornerView
            case .accessoryInline:     inlineView
            default:                   circularView
            }
        }
    }

    // MARK: Circular — the week as a ring around today's session

    @ViewBuilder
    private var circularView: some View {
        if let w = week {
            // The ring fills with the week's sessions done; inside it, today's
            // next session — or a tick once the day is done.
            Gauge(value: Double(min(w.done, w.sessions)), in: 0...Double(w.sessions)) {
                EmptyView()
            } currentValueLabel: {
                Image(symbol: allDone ? "checkmark" : first.map { sessionIcon($0) } ?? "battery.100.bolt")
                    .foregroundStyle(allDone ? .green : first.map { modalityColor($0.modalityId) } ?? .green)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(allDone ? .green : first.map { modalityColor($0.modalityId) } ?? .green)
        } else {
            sessionIconView
        }
    }

    private var sessionIconView: some View {
        ZStack {
            if let s = first {
                Circle()
                    .fill(modalityColor(s.modalityId).opacity(0.2))
                VStack(spacing: 1) {
                    Image(symbol: sessions.count > 1
                          ? "play.circle.fill"
                          : sessionIcon(s))
                        .font(.title3)
                        .foregroundStyle(modalityColor(s.modalityId))
                    if sessions.count > 1 {
                        Text("\(sessions.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Rest day
                Image(systemName: "battery.100.bolt")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: Rectangular — archetype name + duration/modality

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if allDone {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Done today").font(.headline)
                }
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let s = first {
                HStack(spacing: 4) {
                    Image(symbol: sessionIcon(s))
                        .font(.caption2)
                        .foregroundStyle(modalityColor(s.modalityId))
                    Text(sessions.count > 1
                         ? "\(sessions.count) Sessions"
                         : s.archetypeName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(sessions.count > 1
                     ? sessions.prefix(2).map { modalityShortLabel($0.modalityId) }.joined(separator: " · ")
                     : "\(s.estimatedMinutes) min · \(modalityShortLabel(s.modalityId))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "battery.100.bolt")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Rest Day")
                        .font(.headline)
                }
                Text("Recovery is training.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let line = weekLine {
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Corner — icon + session name label

    private var cornerView: some View {
        Image(symbol: first.map { sessionIcon($0) } ?? "battery.100.bolt")
            .foregroundStyle(first.map { modalityColor($0.modalityId) } ?? .green)
            .widgetLabel {
                Text(first.map { sessions.count > 1 ? "\(sessions.count) sessions" : $0.archetypeName } ?? "Rest")
                    .lineLimit(1)
            }
    }

    // MARK: Inline — compact one-liner

    @ViewBuilder
    private var inlineView: some View {
        if allDone {
            Label("Done today" + (week.map { " · \($0.done)/\($0.sessions) wk" } ?? ""), systemImage: "checkmark")
        } else if let s = first {
            Label(
                (sessions.count > 1 ? "\(sessions.count) sessions today" : s.archetypeName)
                    + (week.map { " · \($0.done)/\($0.sessions) wk" } ?? ""),
                systemImage: watchIcon(s.modalityId)
            )
        } else {
            Label("Rest Day", systemImage: "battery.100.bolt")
        }
    }

    // MARK: - Helpers

    /// watchOS prefers system semantic colors over custom RGB values for readability.
    private func modalityColor(_ id: String) -> Color {
        switch id {
        case "max_strength", "relative_strength":  return .red
        case "strength_endurance":                  return .orange
        case "power":                               return .yellow
        case "aerobic_base":                        return .blue
        case "anaerobic_intervals":                 return .cyan
        case "mixed_modal_conditioning":            return .purple
        case "movement_skill":                      return .teal
        case "mobility":                            return .mint
        case "durability":                          return .orange
        case "combat_sport":                        return .pink
        case "rehab":                               return .green
        default:                                    return .blue
        }
    }

    /// A session's workout icon, else its modality's. The inline complication
    /// keeps the modality's: it renders system symbols beside its text.
    private func sessionIcon(_ s: WidgetSession) -> String {
        if let icon = s.icon, AppSymbol.custom.contains(icon) { return icon }
        return watchIcon(s.modalityId)
    }

    private func watchIcon(_ id: String) -> String {
        switch id {
        case "max_strength", "relative_strength": return "figure.strengthtraining.traditional"
        case "strength_endurance":       return "dumbbell.fill"
        case "aerobic_base":             return "figure.run"
        case "anaerobic_intervals":      return "heart.circle.fill"
        case "mixed_modal_conditioning": return "bolt.heart.fill"
        case "power":                    return "bolt.fill"
        case "movement_skill":           return "figure.flexibility"
        case "mobility":                 return "figure.cooldown"
        case "durability":               return "backpack.fill"
        case "combat_sport":             return "figure.boxing"
        case "rehab":                    return "cross.case.fill"
        default:                         return "figure.strengthtraining.traditional"
        }
    }

    private func modalityShortLabel(_ id: String) -> String {
        switch id {
        case "max_strength":             return "Strength"
        case "relative_strength":        return "Strength"
        case "strength_endurance":       return "Str. Endurance"
        case "power":                    return "Power"
        case "aerobic_base":             return "Zone 2"
        case "anaerobic_intervals":      return "Intervals"
        case "mixed_modal_conditioning": return "Mixed Modal"
        case "movement_skill":           return "Skill"
        case "mobility":                 return "Mobility"
        case "durability":               return "Durability"
        case "combat_sport":             return "Combat"
        case "rehab":                    return "Rehab"
        default:                         return id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
