import Foundation

/// `trainingcompanion://` URLs, parsed once, routed through `AppRouter`.
///
/// The widgets open `today` and `session?key=…`; `program`, `analytics`
/// (`?section=program|progress|blocks|load|recovery`; `overview` and
/// `development` are the old names of Load and Blocks) and `profile`
/// exist so a simulator can be driven to any section from the command line
/// and screenshotted — the Simulator window is not scriptable. Opening the
/// URL from outside (`simctl openurl`) makes iOS ask "Open in Training
/// Companion?", which nothing can tap, so `run_sim.sh` passes the route in
/// the launch environment instead (`SIMCTL_CHILD_TC_ROUTE=…`) and the app
/// routes itself on its first appearance.
enum DeepLink: Equatable {
    case tab(AppRouter.Tab)
    case analytics(AnalyticsTab)
    /// `analytics?section=progress&measure=<entry id>` or `&exercise=<exercise id>` —
    /// Progress pushes that measure's or exercise's screen (§6.37);
    /// `analytics?open=readiness|sleep|hrv|resting-hr|checkins` one of Recovery's,
    /// `open=pmc` Load's fitness, fatigue and form, `open=movement|shapes` Program's.
    case analyticsDetail(AppRouter.AnalyticsDetail)
    /// `session?key=<week number>-<Day>-<index>` — Today opens that session.
    case session(String)
    /// `profile?section=athlete|equipment|schedule|standards` (`injuries` aliases Athlete,
    /// `benchmarks` Standards).
    case profile(ProfileTab)
    /// `profile?section=standards&standard=<id>` — one standard's sheet
    /// (`bodyweight_kg` opens the bodyweight series).
    case standard(String)
    /// `log?section=workouts|linking|sessions` (`suggestions`, the old name, still works).
    case log(LogTab)
    /// `program?section=overview|calendar|history`.
    case program(ProgramTab)
    /// `program?section=overview&phase=<n>|compare` — Overview pushes the n-th
    /// phase's screen (from 0, the order the Phases card lists them) or
    /// Compare phases.
    case programPhase(String)
    /// `workout-complete[?id=<workout id>]` — the "Workout complete" sheet for
    /// that workout, or the newest, seen or not (design-system §6.30);
    /// `?demo=1` lines up the newest eight, one after another.
    case workoutComplete(String?)
    case workoutCompleteDemo

    static let scheme = "trainingcompanion"
    static let launchEnvironmentKey = "TC_ROUTE"

    /// The route a developer launched the app with, if any.
    static func fromLaunchEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> DeepLink? {
        guard let raw = environment[launchEnvironmentKey], let url = URL(string: raw) else { return nil }
        return parse(url)
    }

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch host {
        case "", "today", "dashboard":
            return .tab(.dashboard)
        case "session":
            if let key = query.first(where: { $0.name == "key" })?.value, !key.isEmpty {
                return .session(key)
            }
            return .tab(.dashboard)
        case "program":
            if let phase = query.first(where: { $0.name == "phase" })?.value?.lowercased(),
               phase == "compare" || (Int(phase).map { $0 >= 0 } ?? false) {
                return .programPhase(phase)
            }
            if let wanted = query.first(where: { $0.name == "section" })?.value?.lowercased(),
               let section = ProgramTab.allCases.first(where: { $0.label.lowercased() == wanted }) {
                return .program(section)
            }
            return .tab(.program)
        case "log":
            // "suggestions" is the section's old name.
            if let wanted = query.first(where: { $0.name == "section" })?.value?.lowercased()
                .replacingOccurrences(of: "suggestions", with: "linking"),
               let section = LogTab.allCases.first(where: { $0.label.lowercased() == wanted }) {
                return .log(section)
            }
            return .tab(.log)
        case "profile":
            // Injuries moved into Athlete, and Benchmarks was renamed Standards,
            // on 2026-10-17; the old links land on the new names.
            if let id = query.first(where: { $0.name == "standard" })?.value, !id.isEmpty {
                return .standard(id)
            }
            if let raw = query.first(where: { $0.name == "section" })?.value?.lowercased() {
                let wanted = ["injuries": "athlete", "benchmarks": "standards"][raw] ?? raw
                if let section = ProfileTab.allCases.first(where: { $0.label.lowercased() == wanted }) {
                    return .profile(section)
                }
            }
            return .tab(.profile)
        case "analytics":
            if let id = query.first(where: { $0.name == "measure" })?.value, !id.isEmpty {
                return .analyticsDetail(.measure(id))
            }
            if let id = query.first(where: { $0.name == "exercise" })?.value, !id.isEmpty {
                return .analyticsDetail(.exercise(id))
            }
            let recovery: [String: AppRouter.AnalyticsDetail] = [
                "readiness": .readiness, "sleep": .sleep, "hrv": .hrv, "resting-hr": .restingHR, "checkins": .checkIns,
                "pmc": .pmc, "movement": .movement, "shapes": .sessionShapes]
            if let open = query.first(where: { $0.name == "open" })?.value?.lowercased(), let detail = recovery[open] {
                return .analyticsDetail(detail)
            }
            if let raw = query.first(where: { $0.name == "section" })?.value?.lowercased() {
                let wanted = ["overview": "load", "development": "blocks"][raw] ?? raw
                if let section = AnalyticsTab.allCases.first(where: { $0.label.lowercased() == wanted }) {
                    return .analytics(section)
                }
            }
            return .tab(.analytics)
        case "workout-complete":
            if query.first(where: { $0.name == "demo" })?.value == "1" { return .workoutCompleteDemo }
            let id = query.first(where: { $0.name == "id" })?.value
            return .workoutComplete(id?.isEmpty == false ? id : nil)
        default:
            return nil
        }
    }
}

extension AppRouter {
    /// Go where a deep link points (§6.9: only the router moves between tabs).
    func open(_ link: DeepLink) {
        switch link {
        case .tab(let tab): show(tab)
        case .analytics(let section): showAnalytics(section)
        case .analyticsDetail(let detail): openAnalyticsDetail(detail)
        case .session(let key): openSession(key)
        case .profile(let section): showProfile(section)
        case .standard(let id): openStandard(id)
        case .log(let section): showLog(section)
        case .program(let section): showProgram(section)
        case .programPhase(let phase): openProgramPhase(phase)
        case .workoutComplete(let id): showWorkoutComplete(id)
        case .workoutCompleteDemo: showWorkoutComplete(AppRouter.workoutCompleteDemo)
        }
    }
}
