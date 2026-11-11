import XCTest
@testable import TrainingCompanion

/// The phone's player around the engine (WorkoutPlayerModel). After the last
/// step the engine stands past the session's end — the watch shows Finish
/// Session there — and the phone drew the last step again from its first
/// set, so the workout looped (1.34.0). It now ends on the end screen.
@MainActor
final class WorkoutPlayerTests: XCTestCase {
    private var saved: [String: Any?] = [:]

    override func setUp() async throws {
        for key in [WatchCueSettings.leadInKey, WatchCueSettings.countdownStartKey, WatchCueSettings.voiceKey] {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.set(false, forKey: key)
        }
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        ActiveWorkoutStore.clear()
    }

    private func session() throws -> WatchSession {
        func ex(_ json: String) throws -> WatchExercise { try JSONDecoder().decode(WatchExercise.self, from: Data(json.utf8)) }
        return WatchSession(sessionId: "1-Monday-0", modalityId: "max_strength", archetypeName: "Workout A",
                            estimatedMinutes: 45, isDeload: false, exercises: [
                                try ex(#"{"exerciseId": "back_squat", "name": "Back Squat", "slotType": "sets_reps", "sets": 1, "reps": "5", "weightKg": 100, "restSeconds": 180}"#),
                                try ex(#"{"exerciseId": "bench", "name": "Bench Press", "slotType": "sets_reps", "sets": 2, "reps": "5", "weightKg": 70, "restSeconds": 180}"#),
                            ])
    }

    /// A player resumed on `session` with the engine at `phase`.
    private func player(_ s: WatchSession, at step: Int) -> WorkoutPlayerModel {
        let e = WorkoutSessionState()
        e.muted = true
        e.startSession(s)
        e.advance(to: step)
        let model = WorkoutPlayerModel(target: .init(sessionKey: s.sessionId, date: "2026-11-11", title: s.archetypeName))
        model.resume(.init(target: model.target, session: s, startedAt: Date(), snapshot: e.snapshot(),
                           finished: false, notes: ""))
        model.engine.muted = true
        return model
    }

    private func logSet(_ model: WorkoutPlayerModel, _ index: Int) {
        let e = model.engine, s = model.session!, x = s.exercises[index]
        e.completeSet(WatchSetLog(setIndex: e.setLogs[x.exerciseId]?.count ?? 0, repsActual: 5, weightKg: x.weightKg,
                                  rpe: 7, completed: true, durationSeconds: nil, startOffset: nil, endOffset: nil),
                      for: x.exerciseId)
        e.finishSet(index, x, s.screen(for: x))
    }

    /// The player's phase handler runs on the next turns of the main actor.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    func testTheLastSetEndsTheWorkout() async throws {
        let s = try session()
        let model = player(s, at: 1)
        logSet(model, 1)
        XCTAssertEqual(model.engine.phase, .resting(exerciseIndex: 1, completedSet: 0, secondsRemaining: 180),
                       "a set before the last rests")
        model.engine.skipRest(exerciseIndex: 1, completedSet: 0)
        logSet(model, 1)
        await settle()
        XCTAssertEqual(model.engine.phase, .sessionComplete)
        XCTAssertTrue(model.finished, "the end screen, not the last step again from set 1")
        XCTAssertEqual(model.engine.setLogs["bench"]?.count, 2)
    }

    func testASetBeforeTheLastStepLeadsOn() async throws {
        let s = try session()
        let model = player(s, at: 0)
        logSet(model, 0)
        await settle()
        XCTAssertFalse(model.finished)
        XCTAssertEqual(model.engine.phase, .resting(exerciseIndex: 0, completedSet: 0, secondsRemaining: 180),
                       "the last set of a step that has one after it still rests")
    }

    func testAWorkoutSavedPastItsLastStepResumesOnTheEndScreen() async throws {
        let s = try session()
        let model = player(s, at: 2)
        await settle()
        XCTAssertTrue(model.finished)
        XCTAssertEqual(model.engine.phase, .sessionComplete)
    }
}
