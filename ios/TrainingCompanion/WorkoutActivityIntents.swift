import AppIntents

/// The Live Activity's buttons (design-system §6.44): Pause or Resume on a
/// timed step, Skip on any. Compiled into the widget extension, which draws
/// the buttons, and the app, where the system runs the intent — so nothing
/// here names the player: the app sets `handler` when it starts
/// (WorkoutRemote), and an intent only calls it.
@MainActor
enum WorkoutActivityControl {
    enum Action: String, Sendable { case pauseResume, skip }

    static var handler: ((Action) -> Void)?
}

struct WorkoutPauseResumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume the workout"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutActivityControl.handler?(.pauseResume) }
        return .result()
    }
}

struct WorkoutSkipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Skip the workout's step"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutActivityControl.handler?(.skip) }
        return .result()
    }
}
