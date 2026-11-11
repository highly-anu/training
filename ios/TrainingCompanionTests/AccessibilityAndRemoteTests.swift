import SwiftUI
import XCTest
@testable import TrainingCompanion

/// The words accessibility says (AppAccessibility: chart summaries, spoken
/// units, the grid at the accessibility sizes) and what the Live Activity's
/// buttons do to the engine (WorkoutRemote.apply, WorkoutLockScreen.state).
@MainActor
final class AccessibilityAndRemoteTests: XCTestCase {
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

    // MARK: - Chart summaries

    func testARecordingSaysItsAverageAndRange() async throws {
        XCTAssertEqual(ChartSummary.range([100, 140, 180], unit: "beats per minute"),
                       "Average 140 beats per minute, from 100 to 180")
        XCTAssertEqual(ChartSummary.range([120, 120]), "120 throughout")
        XCTAssertNil(ChartSummary.range([]))
    }

    func testASeriesLeadsWithItsLatest() async throws {
        XCTAssertEqual(ChartSummary.series([1, 5, 3], unit: "sessions"), "Latest 3 sessions, average 3, from 1 to 5")
        XCTAssertEqual(ChartSummary.series([4], unit: "sessions"), "4 sessions")
        XCTAssertNil(ChartSummary.series([]))
    }

    func testSharesAreSaidLargestFirstWithoutTheZeros() async throws {
        XCTAssertEqual(ChartSummary.shares([("Z1", 20), ("Z2", 62.4), ("Z3", 0.2), ("Z4", 17.4)]),
                       "Z2 62 percent, Z1 20 percent, Z4 17 percent")
        XCTAssertNil(ChartSummary.shares([("Z1", 0)]))
    }

    func testUnitsAreSaidAsWords() async throws {
        XCTAssertEqual(SpokenUnit.text("min"), "minutes")
        XCTAssertEqual(SpokenUnit.text("BPM"), "beats per minute")
        XCTAssertEqual(SpokenUnit.text("/km"), "per kilometre")
        XCTAssertEqual(SpokenUnit.text("TRIMP"), "TRIMP")
    }

    func testAGridNarrowsAtTheAccessibilitySizes() async throws {
        XCTAssertEqual(AppAdaptiveGrid<EmptyView>.count(3, accessibility: false), 3)
        XCTAssertEqual(AppAdaptiveGrid<EmptyView>.count(3, accessibility: true), 2)
        XCTAssertEqual(AppAdaptiveGrid<EmptyView>.count(2, accessibility: true), 1)
    }

    // MARK: - The Live Activity's buttons

    private func ex(_ json: String) throws -> WatchExercise {
        try JSONDecoder().decode(WatchExercise.self, from: Data(json.utf8))
    }

    private func session() throws -> WatchSession {
        WatchSession(sessionId: "1-Monday-0", modalityId: "max_strength", archetypeName: "Strength",
                     estimatedMinutes: 60, isDeload: false, exercises: [
                        try ex(#"{"exerciseId": "row", "name": "Row", "slotType": "time_domain", "durationMinutes": 5}"#),
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

    func testPauseHoldsATimedStepAndTheActivitySaysSo() async throws {
        let s = try session()
        let e = engine(s)
        e.start(0, s.exercises[0], s.screen(for: s.exercises[0]))
        XCTAssertTrue(WorkoutLockScreen.state(e, session: s).canPause)
        XCTAssertFalse(WorkoutLockScreen.state(e, session: s).paused)

        WorkoutRemote.apply(.pauseResume, to: e, session: s)
        XCTAssertTrue(e.isTimerPaused)
        XCTAssertTrue(WorkoutLockScreen.state(e, session: s).paused)

        WorkoutRemote.apply(.pauseResume, to: e, session: s)
        XCTAssertFalse(e.isTimerPaused)
    }

    func testSkipFinishesTheStep() async throws {
        let s = try session()
        let e = engine(s)
        e.start(0, s.exercises[0], s.screen(for: s.exercises[0]))
        WorkoutRemote.apply(.skip, to: e, session: s)
        XCTAssertEqual(e.phase.exerciseIndex, 1, "the timed step left, the sets step current")
    }

    func testPauseDoesNothingOnASetAndSkipEndsItsRest() async throws {
        let s = try session()
        let e = engine(s)
        let squat = s.exercises[1]
        WorkoutRemote.apply(.skip, to: e, session: s)   // past the row
        XCTAssertEqual(e.phase.exerciseIndex, 1)

        WorkoutRemote.apply(.pauseResume, to: e, session: s)
        XCTAssertFalse(e.isTimerPaused, "a set has no clock to hold")
        XCTAssertFalse(WorkoutLockScreen.state(e, session: s).canPause)

        e.completeSet(WatchSetLog(setIndex: 0, repsActual: 5, weightKg: 100, rpe: nil, completed: true,
                                  durationSeconds: nil, startOffset: nil, endOffset: nil), for: squat.exerciseId)
        e.finishSet(1, squat, s.screen(for: squat))
        XCTAssertEqual(e.phase, .resting(exerciseIndex: 1, completedSet: 0, secondsRemaining: 120))

        WorkoutRemote.apply(.skip, to: e, session: s)
        XCTAssertEqual(e.phase, .active(exerciseIndex: 1, setIndex: 1), "the rest ended, the next set")
    }
}
