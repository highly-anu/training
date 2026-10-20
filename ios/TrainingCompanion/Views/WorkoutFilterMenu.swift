import SwiftUI

/// Log ▸ Activity's type filter (the web's `LogShow`): recorded workouts,
/// sessions logged against the plan, or both.
enum LogEntryKind: String, CaseIterable, Identifiable {
    case all = "All"
    case workouts = "Workouts"
    case sessions = "Sessions"

    var id: String { rawValue }
}

/// One row of Log ▸ Activity.
enum LogEntry: Identifiable {
    case workout(ImportedWorkout)
    case session(LogSessionRow)

    var id: String {
        switch self {
        case .workout(let w): return "w:\(w.id)"
        case .session(let row): return "s:\(row.id)"
        }
    }
}

/// What Log ▸ Activity shows: which type, over what period, in what order,
/// of which activity (design-system §6.24). One value, so the toolbar menu
/// that sets it and the list that reads it cannot disagree.
struct WorkoutListFilter: Equatable {
    var show: LogEntryKind = .all
    var period: AnalyticsPeriod = .thirtyDays
    var sort: WorkoutSortKey = .date
    /// An `ImportedWorkout.activityLabel`; nil is every activity.
    var activity: String? = nil

    var isDefault: Bool { self == WorkoutListFilter() }

    /// Log ▸ Activity's list: the workouts `apply(to:)` keeps and the
    /// sessions logged in the period, newest first — a workout by its start,
    /// a log by its completion, one still open (sets logged, not completed)
    /// last. With another sort the workouts lead in that order and the
    /// sessions follow, since a log has no duration, distance or heart
    /// rate; an activity keeps only workouts of it. Workouts and Sessions
    /// were two sections until 2026-10-20; the web's
    /// `lib/logSessions.mergeLogEntries` merges the same way.
    func entries(workouts: [ImportedWorkout], sessions: [LogSessionRow], now: Date = Date()) -> [LogEntry] {
        typealias Dated = (entry: LogEntry, at: Date?)
        let kept: [ImportedWorkout] = show == .sessions ? [] : apply(to: workouts, now: now)
        let cutoff: Date? = period.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: now) }
        let logs: [LogSessionRow] = show == .workouts || activity != nil ? [] : sessions.filter { row in
            guard let cutoff, let done = row.completedAt else { return true }
            return done >= cutoff
        }
        let sessionEntries: [Dated] = logs.map { (entry: .session($0), at: $0.completedAt) }
        guard sort == .date else {
            let newestFirst = sessionEntries.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
            return kept.map { LogEntry.workout($0) } + newestFirst.map { $0.entry }
        }
        let workoutEntries: [Dated] = kept.map { (entry: .workout($0), at: Self.started($0)) }
        let all: [Dated] = workoutEntries + sessionEntries
        let ordered = all.enumerated().sorted { (a: (offset: Int, element: Dated), b: (offset: Int, element: Dated)) -> Bool in
            switch (a.element.at, b.element.at) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }
        return ordered.map { $0.element.entry }
    }

    /// When a workout began: its start time, else its day.
    private static func started(_ w: ImportedWorkout) -> Date? {
        if let start = w.startTime.flatMap(LogSessions.parseServerDate) { return start }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: w.date)
    }

    func apply(to workouts: [ImportedWorkout], now: Date = Date()) -> [ImportedWorkout] {
        var ws = AnalyticsEngine.filter(workouts, withinDays: period.days, now: now)
        if let activity {
            ws = ws.filter { ImportedWorkout.activityLabel($0.activityType) == activity }
        }
        switch sort {
        case .date:     return ws.sorted { $0.date > $1.date }
        case .duration: return ws.sorted { ($0.durationMinutes ?? 0) > ($1.durationMinutes ?? 0) }
        case .distance: return ws.sorted { ($0.distance?.value ?? 0) > ($1.distance?.value ?? 0) }
        case .avgHR:    return ws.sorted { ($0.heartRate?.avg ?? 0) > ($1.heartRate?.avg ?? 0) }
        }
    }

    /// The activities recorded in the period — the Activity menu's choices.
    func activities(in workouts: [ImportedWorkout]) -> [String] {
        Array(Set(AnalyticsEngine.filter(workouts, withinDays: period.days)
            .map { ImportedWorkout.activityLabel($0.activityType) })).sorted()
    }
}

/// The toolbar's filter button: Show, Period, Sort By and Activity as
/// submenus that name their current value, and Reset when anything differs
/// from the default. The glyph fills while a filter is on — the system's convention
/// (Mail, Files) for "this list is narrowed".
struct WorkoutFilterMenu: View {
    @Binding var filter: WorkoutListFilter
    let activities: [String]

    var body: some View {
        Menu {
            Picker(selection: $filter.show) {
                ForEach(LogEntryKind.allCases) { Text($0.rawValue).tag($0) }
            } label: {
                Label("Show", systemImage: "square.stack")
            }
            .pickerStyle(.menu)

            Picker(selection: $filter.period) {
                ForEach(AnalyticsPeriod.allCases) { Text($0.longLabel).tag($0) }
            } label: {
                Label("Period", systemImage: "calendar")
            }
            .pickerStyle(.menu)

            Picker(selection: $filter.sort) {
                ForEach(WorkoutSortKey.allCases) { Text($0.rawValue).tag($0) }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)

            if filter.show != .sessions && (activities.count > 1 || filter.activity != nil) {
                Picker(selection: $filter.activity) {
                    Text("All Activities").tag(String?.none)
                    ForEach(activities, id: \.self) { Text($0).tag(String?.some($0)) }
                } label: {
                    Label("Activity", systemImage: "figure.run")
                }
                .pickerStyle(.menu)
            }

            if !filter.isDefault {
                Divider()
                Button(role: .destructive) {
                    withAnimation { filter = WorkoutListFilter() }
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Label("Filter", systemImage: filter.isDefault
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .onChange(of: filter) { AppHaptics.selection() }
    }
}

/// The line above the list that says what it shows, so a filter set in the
/// menu is never invisible (§6.11): the counts and period always, and a chip
/// per narrowing that a tap removes.
struct WorkoutFilterScopeLine: View {
    @Binding var filter: WorkoutListFilter
    let entries: [LogEntry]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(Self.counts(entries, filter: filter) + " · \(filter.period.longLabel)")
                    .font(.footnote).foregroundStyle(.secondary)
                if filter.show != .all {
                    chip(filter.show.rawValue) { filter.show = .all }
                }
                if let activity = filter.activity {
                    chip(activity) { filter.activity = nil }
                }
                if filter.sort != .date {
                    chip("By \(filter.sort.rawValue)") { filter.sort = .date }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    /// "3 workouts · 2 sessions"; one type when the filter shows one.
    static func counts(_ entries: [LogEntry], filter: WorkoutListFilter) -> String {
        let workouts = entries.filter { if case .workout = $0 { return true } else { return false } }.count
        let sessions = entries.count - workouts
        func n(_ count: Int, _ one: String, _ many: String) -> String { "\(count) \(count == 1 ? one : many)" }
        switch filter.show {
        case .workouts: return n(workouts, "workout", "workouts")
        case .sessions: return n(sessions, "session", "sessions")
        case .all: return n(workouts, "workout", "workouts") + " · " + n(sessions, "session", "sessions")
        }
    }

    private func chip(_ text: String, clear: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.selection()
            withAnimation { clear() }
        } label: {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter \(text)")
    }
}
