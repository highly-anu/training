import SwiftUI

/// Internal rather than private: `AppRouter` names a section so another screen
/// can send the user to one (the Dashboard's readiness card → Recovery).
enum AnalyticsTab: Int, AppSubTab {
    case program, overview, progress, development, recovery

    var label: String {
        switch self {
        case .program: return "Program"
        case .overview: return "Overview"
        case .progress: return "Progress"
        // "Development" on the web; five segments share the width here and
        // the segmented control truncates anything longer (§6.8).
        case .development: return "Blocks"
        case .recovery: return "Recovery"
        }
    }
}

/// Root container for the Analytics tab. Owns shared state: period selector
/// and the bio entry sheet. Progress (the progression review) lives here as a
/// section rather than as a push from Today, so the review has one home.
/// Recorded workouts moved to the Log tab on 2026-10-01 (§6.19); Development
/// (every block, not just this one) was added the same day (§6.20).
struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter

    @State private var selectedSegment: AnalyticsTab = .overview
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var showBioEntry = false

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
                    case .progress:
                        ProgressionView()
                            .environmentObject(appState)
                    case .development:
                        AnalyticsDevelopmentTab()
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
                    if selectedSegment == .recovery {
                        Button {
                            showBioEntry = true
                        } label: {
                            Label("Add Entry", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showBioEntry) {
                BioCheckInView()
                    .environmentObject(appState)
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
