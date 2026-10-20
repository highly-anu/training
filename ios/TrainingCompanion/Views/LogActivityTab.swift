import SwiftUI

/// Log ▸ Activity — recorded workouts and what was logged against planned
/// sessions, in one list (`WorkoutListFilter.entries`). They were the
/// Workouts and Sessions sections until 2026-10-20, and the workouts list a
/// section of Analytics until 2026-10-01. Show, period, sort and activity are
/// the Log toolbar's filter menu (`WorkoutFilterMenu`), beside the `.fit`
/// importer, and the scope line above the list names them. A workout swipes
/// to delete and carries the TRIMP badge; a session that resolves in the
/// current program opens its detail. The web's Log ▸ Activity is the same
/// list.
struct LogActivityTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var filter: WorkoutListFilter
    @Binding var selectedWorkout: ImportedWorkout?
    @Binding var selectedSession: AppState.LocatedSession?
    @State private var trimpCache: [String: Int] = [:]

    private var sessionRows: [LogSessionRow] {
        LogSessions.rows(logs: Array(appState.sessionLogs.values) + appState.earlierSessionLogs,
                         locate: { appState.locateSession(key: $0) },
                         exerciseNames: appState.exerciseCatalog.mapValues(\.name),
                         currentProgramStart: LogSessions.parseServerDate(appState.serverProgram?.programStartDate))
    }

    var body: some View {
        let entries = filter.entries(workouts: appState.importedWorkouts, sessions: sessionRows)
        VStack(spacing: 0) {
            if appState.isLoadingWorkouts && appState.importedWorkouts.isEmpty && filter.show != .sessions {
                Spacer()
                ProgressView().scaleEffect(1.2)
                Spacer()
            } else if entries.isEmpty {
                WorkoutFilterScopeLine(filter: $filter, entries: entries)
                emptyState
            } else {
                // The scope line is the list's header, so it scrolls with
                // the rows and the list stays the scroll view the navigation
                // bar collapses its title by (§6.8).
                List {
                    Section {
                    ForEach(entries) { entry in
                        switch entry {
                        case .workout(let workout):
                            WorkoutRow(workout: workout, trimp: trimpCache[workout.id])
                                .contentShape(Rectangle())
                                .onTapGesture { selectedWorkout = workout }
                        case .session(let row):
                            sessionRow(row)
                                .deleteDisabled(true)
                        }
                    }
                    .onDelete { [snapshot = entries] indexSet in
                        for idx in indexSet {
                            guard case .workout(let w) = snapshot[idx] else { continue }
                            Task { try? await appState.deleteWorkout(id: w.id) }
                        }
                    }
                    } header: {
                        WorkoutFilterScopeLine(filter: $filter, entries: entries)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets())
                            .padding(.horizontal, -16)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await AppRefresh.perform {
                        await appState.loadWorkouts()
                        await appState.loadRecentSessionLogs()
                    }
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
        .task { await appState.loadExercisesIfNeeded() }
    }

    // MARK: - Session row

    /// A logged session: its name, when, and a line per exercise with
    /// something logged ("Back Squat — 3 sets · 3×5 @ 80 kg").
    private func sessionRow(_ row: LogSessionRow) -> some View {
        Button {
            guard let found = appState.locateSession(key: row.key) else { return }
            AppHaptics.selection()
            selectedSession = found
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: row.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.isComplete ? Color.green : Color.secondary)
                        .font(.caption)
                    Text(row.title).font(.subheadline).fontWeight(.medium)
                    Spacer()
                    if row.isLocatable {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(["Session", row.subtitle].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(row.lines, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.primary).monospacedDigit()
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!row.isLocatable)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let nothingAtAll = appState.importedWorkouts.isEmpty && sessionRows.isEmpty
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: filter.show == .sessions ? "square.and.pencil" : "figure.run.circle")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(filter.activity.map { "No \($0) workouts" }
                 ?? (filter.show == .sessions ? "No sessions logged" : "Nothing recorded"))
                .font(.headline)
            Text(nothingAtAll
                 ? "Import a .fit file or complete a Watch session. Open a session and swipe right on an exercise to log what you did."
                 : "Try a longer period or remove a filter.")
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
