import Foundation

/// Launch switches for looking at the session log form on the simulator,
/// whose window cannot be tapped from a script — debug builds only, as the
/// player's (WorkoutPlayerDebug). Pass them as `SIMCTL_CHILD_<name>` with the
/// session's route (`TC_ROUTE=trainingcompanion://session?key=<key>`):
///
/// - `TC_LOG=<sessionKey>` — open that session's log form.
/// - `TC_LOG_SAVE=<seconds>` — tick every exercise as prescribed and press
///   Save that many seconds after the form opens (time to stop the API and
///   see a save with no connection).
enum SessionLogDebug {
    #if DEBUG
    private static let env = ProcessInfo.processInfo.environment
    #else
    private static let env: [String: String] = [:]
    #endif

    private static var taken = false
    private static var saved = false

    /// Whether this launch should open `key`'s log form: once.
    @MainActor static func take(_ key: String) -> Bool {
        guard !taken, env["TC_LOG"] == key else { return false }
        taken = true
        return true
    }

    /// How long after opening the form opened by `take` should save by itself,
    /// when it should: once.
    @MainActor static func takeSave(_ key: String) -> Duration? {
        guard !saved, env["TC_LOG"] == key, let seconds = env["TC_LOG_SAVE"].flatMap(Double.init) else { return nil }
        saved = true
        return .seconds(seconds)
    }
}
