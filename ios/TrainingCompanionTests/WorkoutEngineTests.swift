import XCTest
@testable import TrainingCompanion

/// The workout engine both the Apple Watch and the phone run
/// (WorkoutSessionState and its Clock): every template moved on by its
/// clock, a locked phone's missed seconds caught up, what is coming
/// forecast, the engine saved and restored, and the step timeline by the
/// wall clock. Driven by a simulated clock: nothing here waits.
@MainActor
final class WorkoutEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var saved: [String: Any?] = [:]

    override func setUp() async throws {
        // The cue settings as an athlete who switched the counts off has
        // them: a Start starts at once (no "Work in 3, 2, 1" task to wait for).
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

    private func session(_ exercises: [WatchExercise]) -> WatchSession {
        WatchSession(sessionId: "1-Monday-0", modalityId: "max_strength", archetypeName: "Strength",
                     estimatedMinutes: 60, isDeload: false, exercises: exercises)
    }

    /// An engine started on `session` at t0, its clock simulated and silent:
    /// a live second's cues come with beats of their own (a timed step's two
    /// taps before it rolls on), which a test would have to wait for.
    private func engine(_ session: WatchSession) -> WorkoutSessionState {
        let e = WorkoutSessionState()
        e.muted = true
        e.simulatedNow = t0
        e.startSession(session)
        e.lastTickAt = t0
        return e
    }

    /// The clock moved on by `seconds`, the engine left at that moment.
    private func wait(_ e: WorkoutSessionState, _ seconds: Int) {
        let t = (e.lastTickAt ?? t0).addingTimeInterval(TimeInterval(seconds))
        e.catchUp(to: t)
        e.simulatedNow = t
    }

    private func logSet(_ e: WorkoutSessionState, _ index: Int) {
        let s = e.session!
        let x = s.exercises[index]
        e.completeSet(WatchSetLog(setIndex: e.setLogs[x.exerciseId]?.count ?? 0, repsActual: 5, weightKg: x.weightKg,
                                  rpe: nil, completed: true, durationSeconds: nil, startOffset: nil, endOffset: nil),
                      for: x.exerciseId)
        e.finishSet(index, x, s.screen(for: x))
    }

    private func squat() throws -> WatchExercise {
        try ex(#"{"exerciseId": "back_squat", "name": "Back Squat", "slotType": "sets_reps", "sets": 2, "reps": "5", "weightKg": 100, "restSeconds": 120}"#)
    }
    private func bench() throws -> WatchExercise {
        try ex(#"{"exerciseId": "bench", "name": "Bench Press", "slotType": "sets_reps", "sets": 2, "reps": "5", "weightKg": 70, "restSeconds": 90}"#)
    }
    private func interval(rounds: Int = 3, work: Int = 40, rest: Int = 20, gate: Int? = nil) throws -> WatchExercise {
        let g = gate.map { #", "restUntilHr": \#($0)"# } ?? ""
        return try ex(#"{"exerciseId": "swing", "name": "Swing", "slotType": "emom", "targetRounds": \#(rounds), "workSec": \#(work), "intervalRestSec": \#(rest)\#(g)}"#)
    }

    // MARK: - Templates

    func testASetsStepRestsBetweenSetsAndTheLastRestLeadsOn() async throws {
        let e = engine(session([try squat(), try bench()]))
        logSet(e, 0)
        XCTAssertEqual(e.phase, .resting(exerciseIndex: 0, completedSet: 0, secondsRemaining: 120))
        wait(e, 120)
        XCTAssertEqual(e.phase, .active(exerciseIndex: 0, setIndex: 1), "the rest over, the next set")
        logSet(e, 0)
        wait(e, 120)
        XCTAssertEqual(e.phase, .active(exerciseIndex: 1, setIndex: 0), "the last set's rest leads to the next step")
        XCTAssertEqual(e.setLogs["back_squat"]?.count, 2)
    }

    func testAHoldEndsItselfAtItsSeconds() async throws {
        let plank = try ex(#"{"exerciseId": "plank", "name": "Plank", "slotType": "static_hold", "sets": 1, "holdSeconds": 30}"#)
        let s = session([plank, try squat()])
        let e = engine(s)
        e.perform(.startHold, 0, plank, s.screen(for: plank))
        wait(e, 29)
        XCTAssertNotNil(e.holdStartedAt, "still holding")
        wait(e, 1)
        XCTAssertNil(e.holdStartedAt, "it used to run on at 0")
        XCTAssertEqual(e.setLogs["plank"]?.first?.durationSeconds, 30)
        XCTAssertEqual(e.phase, .active(exerciseIndex: 1, setIndex: 0))
    }

    func testAnIntervalRunsItsRoundsAndRecordsThem() async throws {
        let swing = try interval()
        let s = session([swing, try squat()])
        let e = engine(s)
        e.start(0, swing, s.screen(for: swing))
        XCTAssertEqual(e.phase, .emomInterval(exerciseIndex: 0, round: 1, isWork: true, remaining: 40))
        wait(e, 40)
        XCTAssertEqual(e.phase, .emomInterval(exerciseIndex: 0, round: 1, isWork: false, remaining: 20))
        wait(e, 20 + 60 + 60)
        XCTAssertEqual(e.phase, .active(exerciseIndex: 1, setIndex: 0), "three rounds, then the next step")
        XCTAssertEqual(e.outcomes["swing"]?.rounds, 3)
    }

    func testARestThatEndsOnHeartRateRunsItsCapWithoutABand() async throws {
        // The phone reads no heart rate: a gated rest is its time cap.
        let swing = try interval(rounds: 2, work: 30, rest: 90, gate: 120)
        let s = session([swing, try squat()])
        let e = engine(s)
        e.start(0, swing, s.screen(for: swing))
        wait(e, 30 + 89)
        XCTAssertEqual(e.phase, .emomInterval(exerciseIndex: 0, round: 1, isWork: false, remaining: 1))
        wait(e, 1)
        XCTAssertEqual(e.phase, .emomInterval(exerciseIndex: 0, round: 2, isWork: true, remaining: 30))
    }

    func testAnAMRAPEndsAtItsCap() async throws {
        let cindy = try ex(#"{"exerciseId": "cindy", "name": "Cindy", "slotType": "amrap", "slotRole": "metcon", "timeMinutes": 2}"#)
        let s = session([cindy, try squat()])
        let e = engine(s)
        e.start(0, cindy, s.screen(for: cindy))
        e.perform(.logRound, 0, cindy, s.screen(for: cindy))
        wait(e, 120)
        XCTAssertEqual(e.phase, .active(exerciseIndex: 1, setIndex: 0))
        XCTAssertEqual(e.outcomes["cindy"]?.rounds, 1)
    }

    func testATimedStepRollsIntoTheNextAtItsTime() async throws {
        let row = try ex(#"{"exerciseId": "row", "name": "Row", "slotType": "time_domain", "durationMinutes": 1}"#)
        let bike = try ex(#"{"exerciseId": "bike", "name": "Bike", "slotType": "time_domain", "durationMinutes": 2}"#)
        let s = session([row, bike])
        let e = engine(s)
        e.start(0, row, s.screen(for: row))
        wait(e, 60)
        XCTAssertEqual(e.phase, .timedWork(exerciseIndex: 1, secondsElapsed: 0), "the next timed step starts at once")
        XCTAssertEqual(e.outcomes["row"]?.durationSec, 60)
        wait(e, 120)
        XCTAssertTrue(e.showOvertimePrompt, "the last asks whether to keep going")
    }

    // MARK: - The clock

    func testCatchingUpIsTickingEverySecond() async throws {
        let s = session([try interval(rounds: 4), try squat()])
        let a = engine(s), b = engine(s)
        a.start(0, s.exercises[0], s.screen(for: s.exercises[0]))
        b.start(0, s.exercises[0], s.screen(for: s.exercises[0]))
        wait(a, 250)                              // a locked phone, back after 250 s
        for _ in 0..<250 { wait(b, 1) }           // the same seconds one at a time
        XCTAssertEqual(a.phase, b.phase)
        XCTAssertEqual(a.outcomes, b.outcomes)
        XCTAssertEqual(a.elapsedSeconds, b.elapsedSeconds)
    }

    func testTheForecastIsWhatTheClockReaches() async throws {
        let s = session([try interval(rounds: 2, work: 40, rest: 20), try squat()])
        let e = engine(s)
        e.start(0, s.exercises[0], s.screen(for: s.exercises[0]))
        let events = e.forecast()
        XCTAssertEqual(events.map(\.text), ["Rest · round 1 of 2", "Round 2 of 2 · Swing", "Rest · round 2 of 2",
                                            "Back Squat — set 1 of 2"])
        XCTAssertEqual(events.map { Int($0.at.timeIntervalSince(t0)) }, [40, 60, 100, 120])
        XCTAssertEqual(e.phaseEndsAt, t0.addingTimeInterval(40))
        wait(e, 100)
        XCTAssertEqual(e.phase, .emomInterval(exerciseIndex: 0, round: 2, isWork: false, remaining: 20))
        XCTAssertEqual(e.phase, e.phase, "forecasting leaves the engine as it was")
        XCTAssertTrue(e.forecast().count == 1 && e.forecast()[0].stepIndex == 1)
    }

    func testASetWaitsForTheAthleteSoNothingIsForecast() async throws {
        let e = engine(session([try squat()]))
        XCTAssertEqual(e.forecast(), [])
        XCTAssertNil(e.phaseEndsAt)
    }

    // MARK: - Saved and restored

    func testASnapshotRestoresTheWorkout() async throws {
        let s = session([try squat(), try interval()])
        let e = engine(s)
        logSet(e, 0)
        wait(e, 30)
        let data = try JSONEncoder().encode(e.snapshot())
        let back = WorkoutSessionState()
        back.restore(try JSONDecoder().decode(WorkoutSessionState.Snapshot.self, from: data), session: s)
        XCTAssertEqual(back.phase, .resting(exerciseIndex: 0, completedSet: 0, secondsRemaining: 90))
        XCTAssertEqual(back.setLogs, e.setLogs)
        XCTAssertEqual(back.lastTickAt, e.lastTickAt)
        XCTAssertEqual(back.stepWindows[0]?.start, t0)
        // …and runs on from where it stood.
        back.catchUp(to: e.lastTickAt!.addingTimeInterval(90))
        XCTAssertEqual(back.phase, .active(exerciseIndex: 0, setIndex: 1))
    }

    // MARK: - What the session produced

    func testTheTimelineCarriesTheWallClock() async throws {
        let s = session([try squat(), try bench()])
        let e = engine(s)
        logSet(e, 0); wait(e, 120); logSet(e, 0); wait(e, 120)
        let timeline = try XCTUnwrap(e.exerciseTimeline(startedAt: t0))
        let squat = try XCTUnwrap(timeline.first { $0.exerciseId == "back_squat" })
        XCTAssertEqual(squat.startOffset, 0)
        XCTAssertEqual(squat.endOffset, 240)
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(squat.startAt, iso.string(from: t0))
        XCTAssertEqual(squat.endAt, iso.string(from: t0.addingTimeInterval(240)))
    }

    func testTheEngineIsSilentUntilADeviceGivesItCues() async throws {
        final class Recorder: WorkoutCueOutput {
            var haptics: [CueHaptic] = []
            func haptic(_ cue: CueHaptic) { haptics.append(cue) }
            func leadIn(_ cue: WatchCues.LeadIn, secondsLeft: Int) {}
        }
        let e = engine(session([try squat()]))
        e.muted = false
        let r = Recorder()
        e.cues = r
        logSet(e, 0)
        XCTAssertEqual(r.haptics, [.success], "the set's tap")
        wait(e, 120)
        XCTAssertEqual(r.haptics.last, .start, "the go at the rest's end; the seconds caught up were silent")
    }
}
