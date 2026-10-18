import Foundation

/// Launch switches for looking at the watch's screens on the simulator,
/// whose window cannot be tapped from a script — debug builds only (a
/// release build reads none). Pass them as `SIMCTL_CHILD_<name>`:
///
/// - `TC_SKIP_HEALTH=1` — no HealthKit sheet (it covers every fresh install).
/// - `TC_SESSION=<sessionId>` — open that session and begin its workout.
/// - `TC_STEP=<n>` — go to step n; `TC_RUN=1` — press its Start;
///   `TC_LAPS=<k>` — press its primary button k times (a set is logged as
///   prescribed).
/// - `TC_PAGE=week|progress|day` — open that page of the Today list (day:
///   the first day of the week that has sessions).
enum WatchDebugLaunch {
    #if DEBUG
    private static let env = ProcessInfo.processInfo.environment
    #else
    private static let env: [String: String] = [:]
    #endif

    static var skipHealth: Bool { env["TC_SKIP_HEALTH"] == "1" }
    static var session: String? { env["TC_SESSION"] }
    static var step: Int? { env["TC_STEP"].flatMap(Int.init) }
    static var run: Bool { env["TC_RUN"] == "1" }
    static var laps: Int { env["TC_LAPS"].flatMap(Int.init) ?? 0 }
    static var page: String? { env["TC_PAGE"].flatMap { $0.isEmpty ? nil : $0 } }
}
