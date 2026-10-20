import SwiftUI
import UniformTypeIdentifiers

/// The Log tab's sections. Internal so `AppRouter` can name one.
enum LogTab: Int, AppSubTab {
    case activity, linking

    var label: String {
        switch self {
        case .activity: return "Activity"
        case .linking: return "Linking"
        }
    }
}

/// The record and the decision queue — the phone's counterpart to the web's
/// Log area (design-system §6.19). Activity is recorded workouts and what
/// was logged against planned sessions in one list, with the `.fit`
/// importer (`LogActivityTab`; Workouts and Sessions until 2026-10-20);
/// Linking is one section per day, workouts beside planned sessions, with
/// same-day suggestions and links across days (`LogLinkingTab`).
struct LogView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter

    @State private var selectedSegment: LogTab = .activity
    @State private var workoutFilter = WorkoutListFilter()
    @State private var selectedWorkout: ImportedWorkout? = nil
    @State private var selectedSession: AppState.LocatedSession? = nil
    @State private var showImportPicker = false

    var body: some View {
        NavigationStack {
            AppSubTabScreen(selection: $selectedSegment) { tab in
                switch tab {
                case .activity:
                    LogActivityTab(filter: $workoutFilter, selectedWorkout: $selectedWorkout,
                                   selectedSession: $selectedSession)
                        .environmentObject(appState)
                case .linking:
                    LogLinkingTab(reviewWorkout: $selectedWorkout)
                        .environmentObject(appState)
                }
            }
            .navigationTitle("Log")
            .appTabStyle()
            .task { applyRequestedSection() }
            .onChange(of: router.logSection) { applyRequestedSection() }
            .toolbar {
                // Filtering is a toolbar menu, not rows of pills above the
                // list (§6.24): the section picker stays the only band.
                if selectedSegment == .activity {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        WorkoutFilterMenu(filter: $workoutFilter,
                                          activities: workoutFilter.activities(in: appState.importedWorkouts))
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
        if let show = router.logShow { workoutFilter.show = show }
        if selectedSegment != requested {
            withAnimation(AppAnimation.springStandard) { selectedSegment = requested }
        }
        router.clearLogSection()
    }
}
