import SwiftUI
import UniformTypeIdentifiers

/// Root container for the Analytics tab. Owns shared state: period selector, selected workout
/// sheet, and bio entry sheet. Replaces LogView at tab position 2 in ContentView.
struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedSegment = 0
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var selectedWorkout: ImportedWorkout? = nil
    @State private var showBioEntry = false
    @State private var showImportPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    Text("Overview").tag(0)
                    Text("Workouts").tag(1)
                    Text("Recovery").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: selectedSegment) { _ in AppHaptics.selection() }

                TabView(selection: $selectedSegment) {
                    AnalyticsOverviewTab(period: $period)
                        .tag(0)
                        .environmentObject(appState)

                    AnalyticsWorkoutsTab(period: $period, selectedWorkout: $selectedWorkout)
                        .tag(1)
                        .environmentObject(appState)

                    AnalyticsRecoveryTab(showBioEntry: $showBioEntry)
                        .tag(2)
                        .environmentObject(appState)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(AppAnimation.springStandard, value: selectedSegment)
            }
            .navigationTitle("Analytics")
            .appTabStyle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedSegment == 1 {
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Import .fit", systemImage: "square.and.arrow.down")
                        }
                    } else if selectedSegment == 2 {
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
