import Foundation

/// `trainingcompanion://` URLs, parsed once, routed through `AppRouter`.
///
/// The widgets open `today` and `session?key=…`; `program`, `analytics`
/// (`?section=program|overview|workouts|progress|recovery`) and `profile`
/// exist so a simulator can be driven to any section from the command line
/// and screenshotted — the Simulator window is not scriptable. Opening the
/// URL from outside (`simctl openurl`) makes iOS ask "Open in Training
/// Companion?", which nothing can tap, so `run_sim.sh` passes the route in
/// the launch environment instead (`SIMCTL_CHILD_TC_ROUTE=…`) and the app
/// routes itself on its first appearance.
enum DeepLink: Equatable {
    case tab(AppRouter.Tab)
    case analytics(AnalyticsTab)
    /// `session?key=<week number>-<Day>-<index>` — Today opens that session.
    case session(String)
    /// `profile?section=athlete|equipment|injuries|benchmarks|schedule`.
    case profile(ProfileTab)

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
            return .tab(.program)
        case "profile":
            if let wanted = query.first(where: { $0.name == "section" })?.value?.lowercased(),
               let section = ProfileTab.allCases.first(where: { $0.label.lowercased() == wanted }) {
                return .profile(section)
            }
            return .tab(.profile)
        case "analytics":
            if let wanted = query.first(where: { $0.name == "section" })?.value?.lowercased(),
               let section = AnalyticsTab.allCases.first(where: { $0.label.lowercased() == wanted }) {
                return .analytics(section)
            }
            return .tab(.analytics)
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
        case .session(let key): openSession(key)
        case .profile(let section): showProfile(section)
        }
    }
}
