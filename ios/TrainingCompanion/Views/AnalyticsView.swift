import SwiftUI

/// Internal rather than private: `AppRouter` names a section so another screen
/// can send the user to one (the Dashboard's readiness card → Recovery).
enum AnalyticsTab: Int, AppSubTab {
    // The web's Analytics tabs, in the web's order (information-architecture.md
    // §2). Load was "Overview" here until 2026-10-13, and Program a section of
    // its own until 2026-10-23, when it merged into Progress; `section=overview`,
    // `section=development` and `section=program` still deep-link (DeepLink.swift).
    case progress, blocks, load, recovery

    var label: String {
        switch self {
        case .progress: return "Progress"
        // Five segments shared the width until 2026-10-23 and the segmented
        // control truncated anything longer (§6.8), which is why both
        // clients say Blocks.
        case .blocks: return "Blocks"
        case .load: return "Load"
        case .recovery: return "Recovery"
        }
    }
}

/// Root container for the Analytics tab. Owns shared state: period selector
/// and the bio entry sheet. Progress (the program document and the
/// progression review) lives here as a section rather than as a push from
/// Today, so the review has one home.
/// Recorded workouts moved to the Log tab on 2026-10-01 (§6.19); Development
/// (every block, not just this one) was added the same day (§6.20).
struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter

    @State private var selectedSegment: AnalyticsTab = .progress
    @State private var period: AnalyticsPeriod = .thirtyDays
    @State private var showBioEntry = false

    var body: some View {
        NavigationStack {
            AppSubTabScreen(selection: $selectedSegment) { tab in
                switch tab {
                case .progress:
                    AnalyticsProgressTab()
                        .environmentObject(appState)
                case .blocks:
                    AnalyticsDevelopmentTab()
                        .environmentObject(appState)
                case .load:
                    AnalyticsOverviewTab(period: $period)
                        .environmentObject(appState)
                case .recovery:
                    AnalyticsRecoveryTab(showBioEntry: $showBioEntry)
                        .environmentObject(appState)
                }
            }
            .navigationTitle("Analytics")
            .appTabStyle()
            // A section asked for from another tab. Handled in both places
            // because the router may set it before this view exists (.task
            // catches that, after the first frame — §6.8) or while it is
            // already on screen (onChange does).
            .task { applyRequestedSection() }
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
