import WidgetKit
import SwiftUI

// The two full-width (systemMedium) home-screen widgets: the program week as
// one row of seven days, and the status row — Today · Readiness · Adherence ·
// Progress — the web's Today cards in one strip. The phone writes both
// (AppState.writeHomeWidgets); nothing here is computed.

// MARK: - Week overview

struct WeekEntry: TimelineEntry {
    let date: Date
    let week: WidgetWeekData?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry { WeekEntry(date: .now, week: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekEntry(date: .now, week: WidgetDataStore.readWeek() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        // The app reloads it on every change; past midnight "today" moves on.
        let next = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_700))
        completion(Timeline(entries: [WeekEntry(date: .now, week: WidgetDataStore.readWeek())], policy: .after(next)))
    }
}

struct WeekOverviewWidget: Widget {
    let kind = "WeekOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeekProvider()) { entry in
            WeekOverviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "trainingcompanion://program?section=calendar"))
        }
        .configurationDisplayName("Week Overview")
        .description("This program week, day by day, with what is done.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeekOverviewView: View {
    let entry: WeekEntry

    private var todayString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: entry.date)
    }

    var body: some View {
        if let week = entry.week {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("WEEK \(week.weekNumber)")
                        .font(.caption2).fontWeight(.bold)
                    Text("of \(week.totalWeeks)" + (week.phase.map { " · \($0.capitalized)" } ?? "")
                         + (week.isDeload ? " · Deload" : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    let all = week.days.flatMap(\.sessions)
                    Text("\(all.filter(\.done).count)/\(all.count) done")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    ForEach(week.days, id: \.date) { day in
                        DayColumn(day: day, isToday: day.date == todayString, isPast: day.date < todayString)
                    }
                }
            }
        } else {
            NoHomeData(text: "Open Training Companion to load your program.")
        }
    }
}

private struct DayColumn: View {
    let day: WidgetWeekData.Day
    let isToday: Bool
    let isPast: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(String(day.dayName.prefix(3)).uppercased())
                .font(.system(size: 10, weight: isToday ? .bold : .semibold))
                .foregroundStyle(isToday ? Color.orange : .secondary)
            if day.sessions.isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("rest").font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(day.sessions.prefix(2).enumerated()), id: \.offset) { _, s in
                    SessionChip(session: s, missed: isPast && !s.done)
                }
                if day.sessions.count > 2 {
                    Text("+\(day.sessions.count - 2)").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isToday ? Color.orange.opacity(0.6) : .clear, lineWidth: 1)
        )
    }
}

private struct SessionChip: View {
    let session: WidgetWeekData.Session
    let missed: Bool

    var body: some View {
        let color = WidgetModalityStyle.color(for: session.modalityId)
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(color.opacity(session.done ? 1 : 0.22)).frame(width: 22, height: 22)
                Image(systemName: session.done ? "checkmark" : WidgetModalityStyle.icon(for: session.modalityId))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(session.done ? Color.white : color)
            }
            Text("\(session.minutes)′")
                .font(.system(size: 9)).monospacedDigit()
                .foregroundStyle(missed ? Color.red.opacity(0.8) : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.name), \(session.minutes) minutes, \(session.done ? "done" : missed ? "missed" : "to do")")
    }
}

// MARK: - Status row

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetStatusData?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { StatusEntry(date: .now, status: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, status: WidgetDataStore.readStatus() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let next = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_700))
        completion(Timeline(entries: [StatusEntry(date: .now, status: WidgetDataStore.readStatus())],
                            policy: .after(next)))
    }
}

struct StatusRowWidget: Widget {
    let kind = "StatusRowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusRowView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Training Status")
        .description("Today, readiness, adherence and progress in one row.")
        .supportedFamilies([.systemMedium])
    }
}

struct StatusRowView: View {
    let entry: StatusEntry

    var body: some View {
        if let s = entry.status {
            HStack(spacing: 6) {
                todayCell(s)
                readinessCell(s)
                adherenceCell(s)
                progressCell(s)
            }
        } else {
            NoHomeData(text: "Open Training Companion to load today.")
        }
    }

    // A stale "today" (yesterday's write, no app open since) shows nothing.
    private func isToday(_ t: WidgetStatusData.Today) -> Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return t.date == f.string(from: entry.date)
    }

    private func todayCell(_ s: WidgetStatusData) -> some View {
        Link(destination: URL(string: "trainingcompanion://today")!) {
            StatusCell(title: "TODAY", tint: s.today?.firstModality.map(WidgetModalityStyle.color(for:)) ?? .secondary) {
                if let t = s.today, isToday(t), t.sessionCount > 0 {
                    if t.doneCount >= t.sessionCount {
                        Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                        Text("Done").font(.caption).fontWeight(.semibold)
                    } else {
                        Text(t.firstName ?? "Session")
                            .font(.caption).fontWeight(.semibold).lineLimit(3).minimumScaleFactor(0.8)
                        Text(t.sessionCount > 1 ? "\(t.doneCount)/\(t.sessionCount) done"
                                                : "\(t.minutes ?? 45) min")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else if let t = s.today, isToday(t) {
                    Image(systemName: "battery.100.bolt").font(.title3).foregroundStyle(.green)
                    Text("Rest day").font(.caption).fontWeight(.semibold)
                } else {
                    Text("—").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func readinessCell(_ s: WidgetStatusData) -> some View {
        Link(destination: URL(string: "trainingcompanion://analytics?section=recovery")!) {
            StatusCell(title: "READINESS", tint: Self.readinessColor(s.readiness?.status)) {
                if let r = s.readiness {
                    Text("\(r.score)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.readinessColor(r.status))
                    Text(Self.readinessWord(r.status)).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func adherenceCell(_ s: WidgetStatusData) -> some View {
        Link(destination: URL(string: "trainingcompanion://analytics?section=program")!) {
            StatusCell(title: "ADHERENCE", tint: Self.verdictColor(s.adherence?.verdict)) {
                if let a = s.adherence {
                    Text("\(a.pct)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Self.verdictColor(a.verdict))
                        .minimumScaleFactor(0.7)
                    Text(a.verdict == "off_plan" ? "Off plan" : a.verdict == "on_plan" ? "On plan" : "Not started")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(Self.verdictColor(a.verdict))
                    if let done = a.weekDone, let due = a.weekDue {
                        Text("Wk \(done)/\(due)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Text("—").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func progressCell(_ s: WidgetStatusData) -> some View {
        Link(destination: URL(string: "trainingcompanion://analytics?section=progress")!) {
            StatusCell(title: "PROGRESS", tint: Self.statusColor(s.progress?.status)) {
                if let p = s.progress {
                    Text(p.label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    Text(p.text ?? "Not measured yet")
                        .font(.caption).fontWeight(.semibold).lineLimit(3).minimumScaleFactor(0.75)
                        .foregroundStyle(p.text == nil ? .secondary : .primary)
                } else {
                    Text("—").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
    }

    // The app's words and colours (ReadinessPresentation, AnalyticsStatusStyle),
    // repeated here: the extension does not link the app's code.
    static func readinessWord(_ status: String) -> String {
        status == "green" ? "Ready" : status == "yellow" ? "Moderate" : "Low"
    }
    static func readinessColor(_ status: String?) -> Color {
        switch status { case "green": return .green; case "yellow": return .yellow; case "red": return .red; default: return .secondary }
    }
    static func verdictColor(_ verdict: String?) -> Color {
        switch verdict { case "on_plan": return .green; case "off_plan": return .red; default: return .secondary }
    }
    static func statusColor(_ status: String?) -> Color {
        switch status {
        case "ahead", "on_track", "met", "on_target", "stable_by_design": return .green
        case "behind", "partial", "off_target": return .yellow
        case "stalled", "below": return .red
        default: return .secondary
        }
    }
}

private struct StatusCell<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A Link tints and centres its label; the cell keeps its own colours.
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
        .tint(.primary)
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1).fill(tint.opacity(0.7)).frame(height: 2).padding(.horizontal, 8)
        }
    }
}

private struct NoHomeData: View {
    let text: String
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Placeholders

extension WidgetWeekData {
    static let placeholder = WidgetWeekData(
        updatedAt: .now, weekNumber: 2, totalWeeks: 12, phase: "base", isDeload: false,
        days: {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            let mods: [[String]] = [[], ["movement_skill"], ["aerobic_base"], [], ["max_strength"], [], ["movement_skill"]]
            let monday = Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
            return names.enumerated().map { i, name in
                let date = Calendar.current.date(byAdding: .day, value: i, to: monday) ?? .now
                return Day(dayName: name, date: f.string(from: date),
                           sessions: mods[i].map { Session(modalityId: $0, name: $0, minutes: 40, done: i < 3) })
            }
        }())
}

extension WidgetStatusData {
    static let placeholder = WidgetStatusData(
        updatedAt: .now,
        today: Today(date: { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: .now) }(),
                     sessionCount: 1, doneCount: 0, firstName: "Double KB Strength", firstModality: "max_strength",
                     minutes: 40),
        readiness: Readiness(score: 72, status: "green"),
        adherence: Adherence(pct: 86, verdict: "on_plan", weekDone: 2, weekDue: 2),
        progress: Progress(label: "Movements earned", text: "3 of 15 movements practised", status: "on_track"))
}
