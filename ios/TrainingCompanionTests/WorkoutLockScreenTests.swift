import XCTest
@testable import TrainingCompanion

/// What the workout player shows on a locked phone (WorkoutLockScreen): the
/// notifications made from the engine's forecast, and the Live Activity's
/// state — its phase, when that phase ends, what follows, the step.
@MainActor
final class WorkoutLockScreenTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var saved: [String: Any?] = [:]

    override func setUp() async throws {
        // No count-ins: a Start starts at once, as in WorkoutEngineTests.
        for key in [WatchCueSettings.leadInKey, WatchCueSettings.countdownStartKey, WatchCueSettings.voiceKey] {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.set(false, forKey: key)
        }
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    private func ex(_ json: String) throws -> WatchExercise {
        try JSONDecoder().decode(WatchExercise.self, from: Data(json.utf8))
    }

    private func session() throws -> WatchSession {
        WatchSession(sessionId: "1-Monday-0", modalityId: "kettlebell", archetypeName: "Swings",
                     estimatedMinutes: 30, isDeload: false, exercises: [
                        try ex(#"{"exerciseId": "swing", "name": "Swing", "slotType": "emom", "targetRounds": 2, "workSec": 40, "intervalRestSec": 20}"#),
                        try ex(#"{"exerciseId": "back_squat", "name": "Back Squat", "slotType": "sets_reps", "sets": 2, "reps": "5", "weightKg": 100, "restSeconds": 120}"#),
                     ])
    }

    private func engine(_ s: WatchSession) -> WorkoutSessionState {
        let e = WorkoutSessionState()
        e.muted = true
        e.simulatedNow = t0
        e.startSession(s)
        e.lastTickAt = t0
        return e
    }

    func testEachForecastMomentIsANotificationWithTheSession() async throws {
        let events = [
            WorkoutSessionState.ForecastEvent(at: t0.addingTimeInterval(40), text: "Rest · round 1 of 2", stepIndex: 0),
            WorkoutSessionState.ForecastEvent(at: t0.addingTimeInterval(120), text: "Back Squat — set 1 of 2", stepIndex: 1),
        ]
        XCTAssertEqual(WorkoutLockScreen.cues(events, session: "Swings"), [
            .init(at: t0.addingTimeInterval(40), title: "Rest", body: "round 1 of 2 — Swings"),
            .init(at: t0.addingTimeInterval(120), title: "Back Squat — set 1 of 2", body: "Swings"),
        ])
    }

    func testTheCuesLeaveRoomForTheSessionReminders() async throws {
        let events = (0..<100).map {
            WorkoutSessionState.ForecastEvent(at: t0.addingTimeInterval(TimeInterval($0)), text: "Round \($0)", stepIndex: 0)
        }
        XCTAssertEqual(WorkoutLockScreen.cues(events, session: "S").count, WorkoutLockScreen.maxCues)
        XCTAssertLessThan(WorkoutLockScreen.maxCues, 64, "iOS keeps 64 pending notifications in all")
    }

    func testAnIntervalsWorkCountsDownToItsRest() async throws {
        let s = try session()
        let e = engine(s)
        e.start(0, s.exercises[0], s.screen(for: s.exercises[0]))
        let state = WorkoutLockScreen.state(e, session: s)
        XCTAssertEqual(state.phase, .work)
        XCTAssertEqual(state.endsAt, t0.addingTimeInterval(40))
        XCTAssertEqual(state.next, "Rest · round 1 of 2")
        XCTAssertEqual(state.step, 1)
        XCTAssertEqual(state.steps, 2)
    }

    func testASetWaitsForTheAthlete() async throws {
        let s = try session()
        let e = engine(s)
        e.advance(to: 1)
        let state = WorkoutLockScreen.state(e, session: s)
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertNil(state.endsAt, "nothing counts down: the lock screen shows the step")
        XCTAssertEqual(state.step, 2)
    }

    func testARestCountsDownToTheNextSet() async throws {
        let s = try session()
        let e = engine(s)
        e.advance(to: 1)
        let squat = s.exercises[1]
        e.completeSet(WatchSetLog(setIndex: 0, repsActual: 5, weightKg: 100, rpe: nil, completed: true,
                                  durationSeconds: nil, startOffset: nil, endOffset: nil), for: squat.exerciseId)
        e.finishSet(1, squat, s.screen(for: squat))
        let state = WorkoutLockScreen.state(e, session: s)
        XCTAssertEqual(state.phase, .rest)
        XCTAssertEqual(state.endsAt, t0.addingTimeInterval(120))
        XCTAssertEqual(state.next, "Back Squat — set 2 of 2")
    }
}
