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
            saved.updateValue(UserDefaults.standard.object(forKey: key), forKey: key)
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

    /// A session whose last step is timed, the player on that step with the
    /// phone away for `away` seconds.
    private func awayOnATimedLastStep(_ away: TimeInterval) throws -> WorkoutPlayerModel {
        func ex(_ json: String) throws -> WatchExercise { try JSONDecoder().decode(WatchExercise.self, from: Data(json.utf8)) }
        let s = WatchSession(sessionId: "1-Monday-0", modalityId: "aerobic_base", archetypeName: "Easy day",
                             estimatedMinutes: 30, isDeload: false, exercises: [
                                try ex(#"{"exerciseId": "row", "name": "Row", "slotType": "time_domain", "durationMinutes": 1}"#),
                                try ex(#"{"exerciseId": "walk", "name": "Walk", "slotType": "time_domain", "durationMinutes": 2}"#),
                             ])
        let e = WorkoutSessionState()
        e.muted = true
        e.startSession(s)
        e.startTimedWork(exerciseIndex: 1)
        e.lastTickAt = Date()
        let model = WorkoutPlayerModel(target: .init(sessionKey: s.sessionId, date: "2026-11-11", title: s.archetypeName))
        model.resume(.init(target: model.target, session: s, startedAt: Date().addingTimeInterval(-away - 60),
                           snapshot: e.snapshot(), finished: false, notes: ""))
        model.engine.lastTickAt = Date().addingTimeInterval(-away)
        return model
    }

    /// The phone comes back from the Lock Screen after the workout's last
    /// timed step ran out (1.46.0): every second it was away was handled as
    /// a move of its own — a save, a Live Activity update and a three-hour
    /// forecast each — and the app stood still until the system ended it.
    func testComingBackAfterALongLockIsHandledOnce() async throws {
        let model = try awayOnATimedLastStep(40 * 60)
        let before = model.movesHandled
        let began = Date()
        model.cameToForeground()
        await Task { @MainActor in }.value
        await settle()
        let took = Date().timeIntervalSince(began)
        model.discard()
        XCTAssertTrue(model.engine.showOvertimePrompt, "the last step ran its time while away")
        XCTAssertLessThanOrEqual(model.movesHandled - before, 3, "the seconds away are one return, not a move each")
        XCTAssertLessThan(took, 2, "back within a moment (took \(took) s)")
    }

    /// Away for the four hours the engine replays at most, in the middle of
    /// an interval that is the workout's last step: back on the end screen,
    /// its rounds counted, without a wait.
    func testComingBackAfterTheLastIntervalEndedIsTheEndScreen() async throws {
        func ex(_ json: String) throws -> WatchExercise { try JSONDecoder().decode(WatchExercise.self, from: Data(json.utf8)) }
        let s = WatchSession(sessionId: "1-Monday-0", modalityId: "power", archetypeName: "Swings",
                             estimatedMinutes: 20, isDeload: false, exercises: [
                                try ex(#"{"exerciseId": "swing", "name": "Swing", "slotType": "emom", "targetRounds": 20, "workSec": 60, "intervalRestSec": 0}"#),
                             ])
        let e = WorkoutSessionState()
        e.muted = true
        e.startSession(s)
        e.startEMOM(exerciseIndex: 0, workSeconds: 60)
        e.lastTickAt = Date()
        let model = WorkoutPlayerModel(target: .init(sessionKey: s.sessionId, date: "2026-11-11", title: s.archetypeName))
        model.resume(.init(target: model.target, session: s, startedAt: Date().addingTimeInterval(-4 * 3600),
                           snapshot: e.snapshot(), finished: false, notes: ""))
        model.engine.lastTickAt = Date().addingTimeInterval(-4 * 3600)
        let began = Date()
        model.cameToForeground()
        await Task { @MainActor in }.value
        await settle()
        let took = Date().timeIntervalSince(began)
        XCTAssertTrue(model.finished, "the interval ran out while away: the end screen")
        XCTAssertEqual(model.engine.phase, .sessionComplete)
        XCTAssertLessThan(took, 2, "back within a moment (took \(took) s)")
        model.discard()
    }
}
