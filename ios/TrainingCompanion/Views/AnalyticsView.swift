import SwiftUI
import UniformTypeIdentifiers

/// Internal rather than private: `AppRouter` names a section so another screen
/// can send the user to one (the Dashboard's readiness card → Recovery).
enum AnalyticsTab: Int, AppSubTab {
    case program, overview, workouts, progress, recovery

    var label: String {
        switch self {
        case .program: return "Program"
        case .overview: return "Overview"
        case .workouts: return "Workouts"
        case .progress: return "Progress"
        case .recovery: return "Recovery"
        }
    }
}

/// Root container for the Analytics tab. Owns shared state: period selector, selected workout
/// sheet, and bio entry sheet. Progress (the progression review) lives here as a
/// section rather than as a push from Today, so the review has one home.
struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter

    @State private var selectedSegment: AnalyticsTab = .overview
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var selectedWorkout: ImportedWorkout? = nil
    @State private var showBioEntry = false
    @State private var showImportPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSubTabPicker(selection: $selectedSegment)

                AppSubTabContent(selection: $selectedSegment) { tab in
                    switch tab {
                    case .program:
                        AnalyticsProgramTab()
                            .environmentObject(appState)
                    case .overview:
                        AnalyticsOverviewTab(period: $period)
                            .environmentObject(appState)
                    case .workouts:
                        AnalyticsWorkoutsTab(period: $period, selectedWorkout: $selectedWorkout)
                            .environmentObject(appState)
                    case .progress:
                        ProgressionView()
                            .environmentObject(appState)
                    case .recovery:
                        AnalyticsRecoveryTab(showBioEntry: $showBioEntry)
                            .environmentObject(appState)
                    }
                }
            }
            .navigationTitle("Analytics")
            .appTabStyle()
            // A section asked for from another tab. Handled in both places
            // because the router may set it before this view exists (onAppear
            // catches that) or while it is already on screen (onChange does).
            .onAppear { applyRequestedSection() }
            .onChange(of: router.analyticsSection) { applyRequestedSection() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedSegment == .workouts {
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Import .fit", systemImage: "square.and.arrow.down")
                        }
                    } else if selectedSegment == .recovery {
                        Button {
                            showBioEntry = true
                        } label: {
                            Label("Add Entry", systemImage: "plus")
                        }
                    }
                }
            }
            // Pushed, not presented: a workout detail is a place you go and
            // come back from, and a sheet is cramped for a map plus charts.
            // Attached to the VStack rather than inside AppSubTabContent — a
            // destination registered on an off-screen page of a paged TabView
            // is not reliably found.
            .navigationDestination(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showBioEntry) {
                BioCheckInView()
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

    /// Move to the section the router asked for, if any, and clear the request
    /// so a later visit keeps the user's own last choice.
    private func applyRequestedSection() {
        guard let requested = router.analyticsSection else { return }
        if selectedSegment != requested {
            withAnimation(AppAnimation.springStandard) { selectedSegment = requested }
        }
        router.clearAnalyticsSection()
    }
}
