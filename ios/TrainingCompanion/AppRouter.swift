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
    /// The five root tabs, in `MainTabView` order — Analytics before Log
    /// since 2026-10-16, as in the web's sidebar. `.dashboard` is the Today
    /// tab (the case name predates the rename; the widgets deep-link to it).
    enum Tab: Int, Hashable {
        case dashboard, program, analytics, log, profile
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

    /// A detail screen an Analytics section pushes (§6.37): Progress's
    /// measures and exercises, Recovery's readiness, sleep, trends and
    /// check-ins, Load's fitness, fatigue and form.
    enum AnalyticsDetail: Hashable {
        case measure(String)
        case exercise(String)
        case score
        case readiness, sleep, hrv, restingHR, checkIns
        case pmc, loadFocus, mix, weekly
        case scorecard, intensity, movement, sessionShapes
        case blockLoad

        /// The section that pushes it.
        var section: AnalyticsTab {
            switch self {
            case .measure, .exercise, .score: return .progress
            case .readiness, .sleep, .hrv, .restingHR, .checkIns: return .recovery
            case .pmc, .loadFocus, .mix, .weekly: return .load
            case .scorecard, .intensity, .movement, .sessionShapes: return .program
            case .blockLoad: return .blocks
            }
        }
    }

    /// Asked for by a deep link; the section pushes it once its data is loaded.
    @Published var pendingAnalyticsDetail: AnalyticsDetail? = nil

    func openAnalyticsDetail(_ detail: AnalyticsDetail) {
        pendingAnalyticsDetail = detail
        showAnalytics(detail.section)
    }

    func clearPendingAnalyticsDetail() {
        pendingAnalyticsDetail = nil
    }

    /// A Log section asked for from outside, cleared once applied, and for
    /// Activity, which type it shows (nil leaves the filter as it is).
    @Published var logSection: LogTab? = nil
    private(set) var logShow: LogEntryKind? = nil

    func showLog(_ section: LogTab, show kind: LogEntryKind? = nil) {
        logShow = kind
        logSection = section
        show(.log)
    }

    func clearLogSection() {
        logSection = nil
        logShow = nil
    }

    /// A Program section asked for from outside, cleared once applied.
    @Published var programSection: ProgramTab? = nil

    func showProgram(_ section: ProgramTab) {
        programSection = section
        show(.program)
    }

    func clearProgramSection() {
        programSection = nil
    }

    /// A screen Program ▸ Overview should push (a deep link): a phase's index
    /// as a string, or "compare"; cleared once pushed.
    @Published var pendingProgramPhase: String? = nil

    func openProgramPhase(_ phase: String) {
        pendingProgramPhase = phase
        showProgram(.overview)
    }

    func clearPendingProgramPhase() {
        pendingProgramPhase = nil
    }

    /// A Profile section asked for from outside, cleared once applied.
    @Published var profileSection: ProfileTab? = nil

    func showProfile(_ section: ProfileTab) {
        profileSection = section
        show(.profile)
    }

    func clearProfileSection() {
        profileSection = nil
    }

    /// A standard whose sheet Profile ▸ Standards should open (a deep link,
    /// or Analytics' "tap a standard"); cleared once the sheet is up.
    @Published var pendingStandardId: String? = nil

    func openStandard(_ id: String) {
        pendingStandardId = id
        showProfile(.standards)
    }

    func clearPendingStandard() {
        pendingStandardId = nil
    }

    /// A session key Today should open, set by a widget or a deep link;
    /// Today clears it once the sheet is up.
    @Published var pendingSessionKey: String? = nil

    func openSession(_ key: String) {
        pendingSessionKey = key
        show(.dashboard)
    }

    func clearPendingSession() {
        pendingSessionKey = nil
    }

    /// A "Workout complete" sheet asked for by a deep link: a workout id, ""
    /// for the newest, or `workoutCompleteDemo` for the newest eight in turn.
    /// `ContentView` presents it once workouts are loaded.
    static let workoutCompleteDemo = "\u{0}demo"
    @Published var pendingWorkoutComplete: String? = nil

    func showWorkoutComplete(_ workoutId: String?) {
        pendingWorkoutComplete = workoutId ?? ""
    }

    func clearPendingWorkoutComplete() {
        pendingWorkoutComplete = nil
    }
}
