import Combine
import SwiftUI

/// Where the app is pointed.
///
/// Tab selection used to be `@State` inside `ContentView`, which meant only
/// `ContentView` could move the user: a card on the Dashboard had no way to
/// open a section of Analytics. Hoisting it here lets any screen point the app
/// somewhere else without knowing anything about the screen it is pointing at —
/// the Dashboard's readiness card opens Analytics → Recovery, and Analytics
/// never learns the Dashboard exists.
///
/// Route through the methods rather than assigning the properties: the haptic
/// and the ordering of the two writes belong to the router, not to each call
/// site (§1.7 of `ios/docs/design-system.md`).
@MainActor
final class AppRouter: ObservableObject {
    /// The four root tabs, in `MainTabView` order. `.dashboard` is the Today
    /// tab (the case name predates the rename; the widgets deep-link to it).
    enum Tab: Int, Hashable {
        case dashboard, program, analytics, profile
    }

    @Published var tab: Tab = .dashboard

    /// A sub-tab Analytics should land on, set only when something outside
    /// Analytics asks for one. Analytics clears it once applied, so coming back
    /// to the tab later restores whatever section the user last chose rather
    /// than yanking them to Recovery again.
    @Published var analyticsSection: AnalyticsTab? = nil

    func show(_ tab: Tab) {
        AppHaptics.light()
        self.tab = tab
    }

    /// Open Analytics on a specific section.
    func showAnalytics(_ section: AnalyticsTab) {
        analyticsSection = section
        show(.analytics)
    }

    /// Called by Analytics when it has applied a requested section.
    func clearAnalyticsSection() {
        analyticsSection = nil
    }
}
