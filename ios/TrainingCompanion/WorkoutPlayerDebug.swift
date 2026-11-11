import Foundation

/// Launch switches for looking at the workout player on the simulator,
/// whose window cannot be tapped from a script — debug builds only, as the
/// watch's (WatchDebugLaunch). Pass them as `SIMCTL_CHILD_<name>` with the
/// session's route (`TC_ROUTE=trainingcompanion://session?key=<key>`):
///
/// - `TC_PLAYER=<sessionKey>` — open that session's player and start it.
/// - `TC_PLAYER_STEP=<n>` — go to step n; `TC_PLAYER_RUN=1` — press its
///   Start; `TC_PLAYER_LAPS=<k>` — press its primary button k times (a set
///   is logged as prescribed; the last set's rest is left running).
/// - `TC_PLAYER_END=1` — then finish the workout (its completion screen);
///   `TC_PLAYER_SAVE=1` — and save it, as Save workout does.
enum WorkoutPlayerDebug {
    #if DEBUG
    private static let env = ProcessInfo.processInfo.environment
    #else
    private static let env: [String: String] = [:]
    #endif

    static var sessionKey: String? { env["TC_PLAYER"].flatMap { $0.isEmpty ? nil : $0 } }
    static var step: Int? { env["TC_PLAYER_STEP"].flatMap(Int.init) }
    static var run: Bool { env["TC_PLAYER_RUN"] == "1" }
    static var laps: Int { env["TC_PLAYER_LAPS"].flatMap(Int.init) ?? 0 }
    static var end: Bool { env["TC_PLAYER_END"] == "1" }
    static var save: Bool { env["TC_PLAYER_SAVE"] == "1" }

    private static var taken = false

    /// Whether this launch should open `key`'s player: once, and from the
    /// start (a kept workout from an earlier launch is let go).
    @MainActor static func take(_ key: String) -> Bool {
        guard !taken, sessionKey == key else { return false }
        taken = true
        ActiveWorkoutStore.clear()
        return true
    }

    /// Carries the switches out on a loaded player, once.
    @MainActor static func apply(_ player: WorkoutPlayerModel, appState: AppState) {
        guard let key = sessionKey, key == player.target.sessionKey, let session = player.session,
              player.startedAt == nil else { return }
        player.begin()
        let engine = player.engine
        if let n = step, n < session.exercises.count { engine.advance(to: n) }
        let i = engine.phase.exerciseIndex ?? 0
        guard i < session.exercises.count else { return }
        let ex = session.exercises[i], screen = session.screen(for: ex)
        if run { engine.start(i, ex, screen) }
        for lap in 0..<laps {
            let outcome = WatchSpecText.lap(ex, screen, engine.stepState(ex, index: i, screen: screen))
            if outcome == .completeSet {
                let reps = Int(ex.reps?.prefix { $0.isNumber } ?? "") ?? 5
                engine.completeSet(WatchSetLog(setIndex: engine.setLogs[ex.exerciseId]?.count ?? 0, repsActual: reps,
                                               weightKg: ex.weightKg, rpe: 7, completed: true, durationSeconds: 40,
                                               startOffset: nil, endOffset: nil), for: ex.exerciseId)
                engine.finishSet(i, ex, screen)
                if lap < laps - 1, case let .resting(ei, cs, _) = engine.phase {
                    engine.skipRest(exerciseIndex: ei, completedSet: cs)
                }
            } else {
                engine.perform(outcome, i, ex, screen)
            }
        }
        guard end else { return }
        player.finish()
        if save { Task { _ = await player.save(decision: nil, appState: appState) } }
    }
}
