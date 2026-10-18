import XCTest
@testable import TrainingCompanion

/// How the Apple Watch walks a session's steps (WatchSteps, the Garmin's
/// Steps.mc and WorkoutController.nextStep): the "Next:" line, an AMRAP's
/// movements folded into its round, and each step's one-line prescription.
@MainActor
final class WatchStepsTests: XCTestCase {
    private func ex(_ json: String) throws -> WatchExercise {
        try JSONDecoder().decode(WatchExercise.self, from: Data(json.utf8))
    }

    private func session(_ exercises: [WatchExercise]) -> WatchSession {
        WatchSession(sessionId: "1-Monday-0", modalityId: "max_strength", archetypeName: "Strength",
                     estimatedMinutes: 60, isDeload: false, exercises: exercises)
    }

    private func squat() throws -> WatchExercise {
        try ex(#"{"exerciseId": "back_squat", "name": "Back Squat", "slotType": "sets_reps", "sets": 3, "reps": "5", "weightKg": 100, "restSeconds": 180}"#)
    }
    private func bench() throws -> WatchExercise {
        try ex(#"{"exerciseId": "bench", "name": "Bench Press", "slotType": "sets_reps", "sets": 3, "reps": "5", "weightKg": 70, "restSeconds": 120}"#)
    }

    func testTheNextLineWalksSetsRestsAndSteps() throws {
        let s = session([try squat(), try bench()])
        XCTAssertEqual(WatchSteps.nextStep(s, index: 0, setsDone: 0, resting: false).title, "Rest",
                       "a set is followed by its rest")
        XCTAssertEqual(WatchSteps.nextStep(s, index: 0, setsDone: 0, resting: false).value, "3:00")
        let overRest = WatchSteps.nextStep(s, index: 0, setsDone: 1, resting: true)
        XCTAssertEqual(overRest.title, "Back Squat")
        XCTAssertEqual(overRest.value, "Set 2/3  5 Reps @ 100 kg")
        let afterLast = WatchSteps.nextStep(s, index: 0, setsDone: 3, resting: true)
        XCTAssertEqual(afterLast.title, "Bench Press", "the last set's rest leads on")
        XCTAssertEqual(afterLast.value, "5 Reps @ 70 kg")
        // The last step: a rest while sets remain, then the session ends.
        XCTAssertEqual(WatchSteps.nextStep(s, index: 1, setsDone: 1, resting: false).title, "Rest")
        XCTAssertEqual(WatchSteps.nextStep(s, index: 1, setsDone: 2, resting: false).title, "Finish")
        XCTAssertEqual(WatchSteps.nextStep(session([try squat()]), index: 0, setsDone: 2, resting: false).title,
                       "Finish", "nothing after the last set of the last step")
    }

    func testAnAMRAPsMovementsAreItsRoundNotSteps() throws {
        let amrap = try ex(#"{"exerciseId": "cindy", "name": "Cindy", "slotType": "amrap", "slotRole": "metcon", "timeMinutes": 20}"#)
        let pull = try ex(#"{"exerciseId": "pull_up", "name": "Pull-up", "slotType": "amrap_movement", "slotRole": "c1", "parentSlotRole": "metcon", "repsPerRound": 5}"#)
        let push = try ex(#"{"exerciseId": "push_up", "name": "Push-up", "slotType": "amrap_movement", "slotRole": "c2", "parentSlotRole": "metcon", "repsPerRound": 10}"#)
        let s = session([amrap, pull, push, try bench()])
        XCTAssertEqual(WatchSteps.components(of: s, at: 0).map(\.name), ["Pull-up", "Push-up"])
        XCTAssertTrue(WatchSteps.isFolded(s, 1))
        XCTAssertTrue(WatchSteps.isFolded(s, 2))
        XCTAssertFalse(WatchSteps.isFolded(s, 3))
        XCTAssertEqual(WatchSteps.indexAfter(s, 0), 3, "the AMRAP moves on past its movements")
        let next = WatchSteps.nextStep(s, index: 0, setsDone: 0, resting: false)
        XCTAssertEqual(next.title, "Bench Press")
        XCTAssertEqual(WatchSteps.components(of: s, at: 3), [], "a set step has no round")
    }

    /// A payload from before parentSlotRole: the movements after the AMRAP.
    func testMovementsWithoutAParentFollowTheirAMRAP() throws {
        let amrap = try ex(#"{"exerciseId": "cindy", "name": "Cindy", "slotType": "amrap", "slotRole": "metcon", "timeMinutes": 20}"#)
        let pull = try ex(#"{"exerciseId": "pull_up", "name": "Pull-up", "slotType": "amrap_movement", "slotRole": "c1"}"#)
        let s = session([amrap, pull])
        XCTAssertEqual(WatchSteps.components(of: s, at: 0).map(\.name), ["Pull-up"])
        XCTAssertEqual(WatchSteps.indexAfter(s, 0), 2)
    }

    func testEachStepSaysItsPrescription() throws {
        let s = session([])
        func preview(_ json: String) throws -> String {
            let e = try ex(json)
            return WatchSteps.preview(e, s.screen(for: e))
        }
        XCTAssertEqual(try preview(#"{"exerciseId": "double_kb_press", "name": "Press", "slotType": "sets_reps", "category": "kettlebell", "bells": 2, "reps": "5", "weightKg": 24}"#),
                       "5 Reps @ 48 kg", "a double reads as the total in the Next line")
        XCTAssertEqual(try preview(#"{"exerciseId": "plank", "name": "Plank", "slotType": "static_hold", "holdSeconds": 45}"#), "Hold :45")
        XCTAssertEqual(try preview(#"{"exerciseId": "swing", "name": "Swing", "slotType": "emom", "targetRounds": 8, "workSec": 20, "intervalRestSec": 10}"#),
                       "8 x 0:20 / 0:10")
        XCTAssertEqual(try preview(#"{"exerciseId": "cindy", "name": "Cindy", "slotType": "amrap", "timeMinutes": 20}"#), "20 min AMRAP")
        XCTAssertEqual(try preview(#"{"exerciseId": "fran", "name": "Fran", "slotType": "for_time", "targetRounds": 3}"#), "3 Rounds for time")
        XCTAssertEqual(try preview(#"{"exerciseId": "ruck", "name": "Ruck", "slotType": "distance", "distanceKm": 8, "packLoadKg": 20}"#), "8 km  pack 20 kg")
        XCTAssertEqual(try preview(#"{"exerciseId": "carry", "name": "Carry", "slotType": "distance", "distanceM": 40, "weightKg": 32}"#), "40 m @ 32 kg")
        XCTAssertEqual(try preview(#"{"exerciseId": "bike", "name": "Bike", "slotType": "time_domain", "durationMinutes": 30, "prescribedZoneLower": 2}"#), "30:00  Z2")
    }

    /// The cues the clocks fire (WatchCues), as the Garmin's
    /// updateIntervalTiming: the hand switch at its second of the work, and a
    /// rest that ends once the heart rate has stayed under its target for 5 s.
    func testTheHandSwitchAndTheHeartRateGate() throws {
        let event = try ex(#"{"exerciseId": "wk_kb_half_snatch", "name": "Half Snatch", "slotType": "time_domain", "durationMinutes": 6, "switchAtSec": 180}"#)
        XCTAssertEqual((1...360).filter { WatchCues.switchDue(event, workSecond: $0) }, [180],
                       "one switch, at 3:00 of the work")
        XCTAssertFalse(WatchCues.switchDue(try squat(), workSecond: 180), "no switch without switchAtSec")

        var gate = WatchCues.RestGate()
        let readings: [Int?] = [140, 128, 127, nil, 126, 125, 124, 123, 122]
        let over = readings.map { gate.tick(heartRate: $0, target: 129) }
        XCTAssertEqual(over, [false, false, false, false, false, false, false, false, true],
                       "five seconds under in a row; a lost reading starts the count again")
        var noStrap = WatchCues.RestGate()
        XCTAssertFalse((0..<120).contains { _ in noStrap.tick(heartRate: 0, target: 129) },
                       "without a heart rate the rest runs to its cap")
    }

    func testAnHRGatedIntervalIsPreviewedWithItsZone() throws {
        let swing = try ex(#"{"exerciseId": "wk_kb_half_snatch", "name": "Half Snatch", "slotType": "emom", "targetRounds": 20, "workSec": 15, "intervalRestSec": 90, "restUntilHr": 126, "prescribedZoneLower": 1, "prescribedZoneUpper": 2}"#)
        let s = session([swing])
        XCTAssertEqual(WatchSteps.preview(swing, s.screen(for: swing)), "20 x 0:15  Z1-2",
                       "as the Garmin's Steps list: the work and its zone")
    }
}
