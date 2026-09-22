import SwiftUI
import UniformTypeIdentifiers

private enum AnalyticsTab: Int, AppSubTab {
    case overview, workouts, recovery

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .workouts: return "Workouts"
        case .recovery: return "Recovery"
        }
    }
}

/// Root container for the Analytics tab. Owns shared state: period selector, selected workout
/// sheet, and bio entry sheet. Replaces LogView at tab position 2 in ContentView.
struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState

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
                    case .overview:
                        AnalyticsOverviewTab(period: $period)
                            .environmentObject(appState)
                    case .workouts:
                        AnalyticsWorkoutsTab(period: $period, selectedWorkout: $selectedWorkout)
                            .environmentObject(appState)
                    case .recovery:
                        AnalyticsRecoveryTab(showBioEntry: $showBioEntry)
                            .environmentObject(appState)
                    }
                }
            }
            .navigationTitle("Analytics")
            .appTabStyle()
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
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailSheet(workout: workout)
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
}
