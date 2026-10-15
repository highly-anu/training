import SwiftUI

/// Log ▸ Workouts — the recorded-activity list (a section of Analytics until
/// 2026-10-01; the record belongs with the log, the interpretation with
/// Analytics). Swipe-to-delete and the TRIMP badge; the period, sort and
/// activity filter are the Log toolbar's filter menu (`WorkoutFilterMenu`),
/// beside the `.fit` importer, and the scope line above the list names them.
struct LogWorkoutsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var filter: WorkoutListFilter
    @Binding var selectedWorkout: ImportedWorkout?
    @State private var trimpCache: [String: Int] = [:]

    private var filtered: [ImportedWorkout] { filter.apply(to: appState.importedWorkouts) }

    var body: some View {
        VStack(spacing: 0) {
            if appState.isLoadingWorkouts && appState.importedWorkouts.isEmpty {
                Spacer()
                ProgressView().scaleEffect(1.2)
                Spacer()
            } else if filtered.isEmpty {
                WorkoutFilterScopeLine(filter: $filter, count: 0)
                emptyState
            } else {
                // The scope line is the list's header, so it scrolls with
                // the rows and the list stays the scroll view the navigation
                // bar collapses its title by (§6.8).
                List {
                    Section {
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
                    } header: {
                        WorkoutFilterScopeLine(filter: $filter, count: filtered.count)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets())
                            .padding(.horizontal, -16)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.run.circle")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(filter.activity.map { "No \($0) workouts" } ?? "No Workouts")
                .font(.headline)
            Text(appState.importedWorkouts.isEmpty
                 ? "Import a .fit file or complete a Watch session."
                 : "Try a longer period or remove the activity filter.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            if !filter.isDefault {
                Button("Reset Filters") {
                    AppHaptics.light()
                    withAnimation { filter = WorkoutListFilter() }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
