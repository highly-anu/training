import SwiftUI

/// What Log ▸ Workouts shows: over what period, in what order, of which
/// activity (design-system §6.24). One value, so the toolbar menu that sets
/// it and the list that reads it cannot disagree.
struct WorkoutListFilter: Equatable {
    var period: AnalyticsPeriod = .thirtyDays
    var sort: WorkoutSortKey = .date
    /// An `ImportedWorkout.activityLabel`; nil is every activity.
    var activity: String? = nil

    var isDefault: Bool { self == WorkoutListFilter() }

    func apply(to workouts: [ImportedWorkout]) -> [ImportedWorkout] {
        var ws = AnalyticsEngine.filter(workouts, withinDays: period.days)
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

/// The toolbar's filter button: Period, Sort By and Activity as submenus that
/// name their current value, and Reset when anything differs from the
/// default. The glyph fills while a filter is on — the system's convention
/// (Mail, Files) for "this list is narrowed".
struct WorkoutFilterMenu: View {
    @Binding var filter: WorkoutListFilter
    let activities: [String]

    var body: some View {
        Menu {
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

            if activities.count > 1 || filter.activity != nil {
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
/// menu is never invisible (§6.11): the count and period always, and a chip
/// per narrowing that a tap removes.
struct WorkoutFilterScopeLine: View {
    @Binding var filter: WorkoutListFilter
    let count: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("\(count) \(count == 1 ? "workout" : "workouts") · \(filter.period.longLabel)")
                    .font(.footnote).foregroundStyle(.secondary)
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
