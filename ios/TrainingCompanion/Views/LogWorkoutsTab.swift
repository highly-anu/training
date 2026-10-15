import SwiftUI

/// Log ▸ Workouts — the recorded-activity list (a section of Analytics until
/// 2026-10-01; the record belongs with the log, the interpretation with
/// Analytics). Period filter, sort, activity filter, delete, and the TRIMP
/// badge; the `.fit` importer sits in the Log toolbar.
struct LogWorkoutsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var period: AnalyticsPeriod
    @Binding var selectedWorkout: ImportedWorkout?
    @State private var sortKey: WorkoutSortKey = .date
    @State private var activityFilter: String? = nil  // nil = all types
    @State private var trimpCache: [String: Int] = [:]

    // MARK: - Filtered + Sorted Workouts

    private var filtered: [ImportedWorkout] {
        var ws = AnalyticsEngine.filter(appState.importedWorkouts, withinDays: period.days)
        if let f = activityFilter {
            ws = ws.filter { ImportedWorkout.activityLabel($0.activityType) == f }
        }
        switch sortKey {
        case .date:     return ws.sorted { $0.date > $1.date }
        case .duration: return ws.sorted { ($0.durationMinutes ?? 0) > ($1.durationMinutes ?? 0) }
        case .distance: return ws.sorted { ($0.distance?.value ?? 0) > ($1.distance?.value ?? 0) }
        case .avgHR:    return ws.sorted { ($0.heartRate?.avg ?? 0) > ($1.heartRate?.avg ?? 0) }
        }
    }

    private var uniqueActivityTypes: [String] {
        Array(Set(AnalyticsEngine.filter(appState.importedWorkouts, withinDays: period.days)
            .map { ImportedWorkout.activityLabel($0.activityType) }
        )).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            AnalyticsPeriodPicker(period: $period)
                .padding(.horizontal)
                .padding(.top, 4)
            filterSortBar
            Divider()
            if appState.isLoadingWorkouts && appState.importedWorkouts.isEmpty {
                Spacer()
                ProgressView().scaleEffect(1.2)
                Spacer()
            } else if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { workout in
                        WorkoutRow(workout: workout, trimp: trimpCache[workout.id])
                            .contentShape(Rectangle())
                            .onTapGesture { selectedWorkout = workout }
                    }
                    .onDelete { [snapshot = filtered] indexSet in
                        for idx in indexSet {
                            let w = snapshot[idx]
                            Task { try? await appState.deleteWorkout(id: w.id) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await AppRefresh.perform { await appState.loadWorkouts() }
                }
                .task(id: appState.importedWorkouts.map(\.id).joined()) {
                    let workouts = appState.importedWorkouts
                    let hrConfig = appState.profile.hrConfig
                    let dob = appState.profile.dateOfBirth
                    let result = await Task.detached(priority: .background) {
                        Dictionary(uniqueKeysWithValues: workouts.compactMap { w -> (String, Int)? in
                            guard let t = AnalyticsEngine.computeWorkoutTRIMP(
                                workout: w, hrConfig: hrConfig, dateOfBirth: dob)
                            else { return nil }
                            return (w.id, t)
                        })
                    }.value
                    trimpCache = result
                }
            }
        }
    }

    // MARK: - Filter / Sort Bar

    private var filterSortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Sort pills
                ForEach(WorkoutSortKey.allCases) { key in
                    Button {
                        AppHaptics.selection()
                        sortKey = key
                    } label: {
                        Text(key.rawValue)
                            .font(.caption).fontWeight(sortKey == key ? .semibold : .regular)
                            .foregroundStyle(sortKey == key ? .white : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(sortKey == key ? Color.blue : Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if uniqueActivityTypes.count > 1 {
                    Divider().frame(height: 20)
                    // Activity type filter chips
                    Button {
                        AppHaptics.selection()
                        withAnimation { activityFilter = nil }
                    } label: {
                        Text("All")
                            .font(.caption).fontWeight(activityFilter == nil ? .semibold : .regular)
                            .foregroundStyle(activityFilter == nil ? .white : .primary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(activityFilter == nil ? Color.purple : Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    ForEach(uniqueActivityTypes, id: \.self) { type in
                        Button {
                            AppHaptics.selection()
                            withAnimation { activityFilter = activityFilter == type ? nil : type }
                        } label: {
                            Text(type)
                                .font(.caption).fontWeight(activityFilter == type ? .semibold : .regular)
                                .foregroundStyle(activityFilter == type ? .white : .primary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(activityFilter == type ? Color.purple : Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(activityFilter != nil ? "No \(activityFilter!) workouts" : "No Workouts")
                .font(.headline)
            Text(appState.importedWorkouts.isEmpty
                 ? "Import a .fit file or complete a Watch session."
                 : "Try a longer period or remove the activity filter.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            if activityFilter != nil {
                Button("Clear Filter") {
                    AppHaptics.light()
                    withAnimation { activityFilter = nil }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
