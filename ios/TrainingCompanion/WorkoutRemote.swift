import Foundation

/// The workout moved on from outside the player: the Live Activity's Pause
/// and Skip (WorkoutActivityIntents). The system runs the intent in the app,
/// in the background; with the player still in memory it is the player's own
/// engine that moves, and after the app was let go the kept workout's
/// (ActiveWorkoutStore) — either way caught up to now first, then saved, the
/// cues scheduled again and the Live Activity redrawn.
@MainActor
enum WorkoutRemote {
    /// The player on screen, or behind the Lock Screen.
    static weak var player: WorkoutPlayerModel?

    static func install() {
        WorkoutActivityControl.handler = { perform($0) }
    }

    static func perform(_ action: WorkoutActivityControl.Action) {
        if let player, player.startedAt != nil, !player.finished {
            player.remote(action)
            return
        }
        guard let kept = ActiveWorkoutStore.load(), !kept.finished else { return }
        let engine = WorkoutSessionState()
        engine.muted = true
        engine.restore(kept.snapshot, session: kept.session)
        engine.catchUp(to: Date())
        apply(action, to: engine, session: kept.session)
        ActiveWorkoutStore.save(.init(target: kept.target, session: kept.session, startedAt: kept.startedAt,
                                      snapshot: engine.snapshot(), finished: kept.finished, notes: kept.notes))
        WorkoutLockScreen.shared.scheduleCues(engine.forecast(), session: kept.target.title)
        WorkoutLockScreen.shared.update(engine: engine, session: kept.session, title: kept.target.title)
    }

    /// What a button does to the engine, as the player's own buttons do it:
    /// Skip ends a rest, else the step; Pause holds a timed step's clock and
    /// does nothing anywhere else. Past the last step nothing moves.
    static func apply(_ action: WorkoutActivityControl.Action, to engine: WorkoutSessionState, session: WatchSession) {
        guard let index = engine.phase.exerciseIndex, session.exercises.indices.contains(index) else { return }
        switch action {
        case .pauseResume:
            guard case .timedWork = engine.phase else { return }
            engine.isTimerPaused ? engine.resumeTimer() : engine.pauseTimer()
        case .skip:
            if case let .resting(ei, set, _) = engine.phase {
                engine.skipRest(exerciseIndex: ei, completedSet: set)
            } else {
                let exercise = session.exercises[index]
                engine.finishStep(index, exercise, session.screen(for: exercise))
            }
        }
    }
}
