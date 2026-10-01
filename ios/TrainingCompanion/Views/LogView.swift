import SwiftUI
import UniformTypeIdentifiers

/// The Log tab's sections. Internal so `AppRouter` can name one.
enum LogTab: Int, AppSubTab {
    case workouts, suggestions, sessions

    var label: String {
        switch self {
        case .workouts: return "Workouts"
        case .suggestions: return "Suggestions"
        case .sessions: return "Sessions"
        }
    }
}

/// The record and the decision queue — the phone's counterpart to the web's
/// Log area (design-system §6.19). Workouts is the recorded-activity list
/// that used to be a section of Analytics, with the `.fit` importer;
/// Suggestions is the inbox of server matches to accept, review or dismiss;
/// Sessions is what was logged against planned sessions, across the program.
struct LogView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter

    @State private var selectedSegment: LogTab = .workouts
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var selectedWorkout: ImportedWorkout? = nil
    @State private var selectedSession: AppState.LocatedSession? = nil
    @State private var showImportPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSubTabPicker(selection: $selectedSegment)

                AppSubTabContent(selection: $selectedSegment) { tab in
                    switch tab {
                    case .workouts:
                        LogWorkoutsTab(period: $period, selectedWorkout: $selectedWorkout)
                            .environmentObject(appState)
                    case .suggestions:
                        LogSuggestionsTab(reviewWorkout: $selectedWorkout)
                            .environmentObject(appState)
                    case .sessions:
                        LogSessionsTab(selectedSession: $selectedSession)
                            .environmentObject(appState)
                    }
                }
            }
            .navigationTitle("Log")
            .appTabStyle()
            .onAppear { applyRequestedSection() }
            .onChange(of: router.logSection) { applyRequestedSection() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedSegment == .workouts {
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Import .fit", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            // Pushed, not presented: a workout detail is a place you go and
            // come back from. Attached here rather than inside the paged
            // content — a destination on an off-screen page is not reliably
            // found.
            .navigationDestination(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
                    .environmentObject(appState)
            }
            .sheet(item: $selectedSession) { found in
                SessionDetailView(session: found.session, sessionKey: found.key,
                                  weekIndex: found.weekIndex, dayName: found.dayName,
                                  sessionIndex: found.sessionIndex)
                    .environmentObject(appState)
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [UTType(filenameExtension: "fit") ?? .data]
            ) { result in
                if let url = try? result.get() {
                    appState.pendingFITURL = url
                }
            }
        }
    }

    private func applyRequestedSection() {
        guard let requested = router.logSection else { return }
        if selectedSegment != requested {
            withAnimation(AppAnimation.springStandard) { selectedSegment = requested }
        }
        router.clearLogSection()
    }
}

// MARK: - Suggestions

struct LogSuggestionsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var reviewWorkout: ImportedWorkout?

    var body: some View {
        let pending = appState.pendingMatchSuggestions()
        Group {
            if pending.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Nothing to decide").font(.headline)
                    Text("When a recorded workout looks like a planned session but the server is not sure, it lands here for you to accept, review or dismiss.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(pending, id: \.suggestion.id) { item in
                            SuggestionRowView(
                                suggestion: item.suggestion, workout: item.workout,
                                planned: appState.locateSession(key: item.suggestion.sessionKey)?.session,
                                onAccept: {
                                    Task { try? await appState.matchAndComplete(workout: item.workout,
                                                                                sessionKey: item.suggestion.sessionKey) }
                                },
                                onReview: { reviewWorkout = item.workout },
                                onDismiss: { Task { await appState.dismissSuggestion(workoutId: item.workout.id) } })
                        }
                    }
                    .padding()
                }
            }
        }
        .refreshable {
            await AppRefresh.perform {
                await appState.loadMatchSuggestions()
                await appState.loadWorkouts()
            }
        }
    }
}

// MARK: - Sessions

struct LogSessionsTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedSession: AppState.LocatedSession?

    private var rows: [LogSessionRow] {
        LogSessions.rows(logs: Array(appState.sessionLogs.values),
                         locate: { appState.locateSession(key: $0) },
                         exerciseNames: appState.exerciseCatalog.mapValues(\.name))
    }

    var body: some View {
        let rows = rows
        Group {
            if rows.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Nothing logged yet").font(.headline)
                    Text("Open a session and swipe right on an exercise to log what you did. Completed sessions appear here too.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(rows) { row in
                        Button {
                            guard let found = appState.locateSession(key: row.key) else { return }
                            AppHaptics.selection()
                            selectedSession = found
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.title).font(.subheadline).fontWeight(.medium)
                                    Spacer()
                                    if row.isComplete {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                                    }
                                    if row.isLocatable {
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                                if !row.subtitle.isEmpty {
                                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
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
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { await appState.loadExercisesIfNeeded() }
        .refreshable {
            await AppRefresh.perform { await appState.loadRecentSessionLogs() }
        }
    }
}
