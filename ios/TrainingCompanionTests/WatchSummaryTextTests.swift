import XCTest
@testable import TrainingCompanion

/// The end of a session on the Apple Watch reads like the Garmin's
/// (WatchSummaryText): the package's pages in its order, sets and volume,
/// and what each step logged.
@MainActor
final class WatchSummaryTextTests: XCTestCase {
    private func ex(_ json: String) throws -> WatchExercise {
        try JSONDecoder().decode(WatchExercise.self, from: Data(json.utf8))
    }

    private func set(_ reps: Int?, _ kg: Double?, hold: Int? = nil) -> WatchSetLog {
        WatchSetLog(setIndex: 0, repsActual: reps, weightKg: kg, rpe: nil, completed: true,
                    durationSeconds: hold, startOffset: nil, endOffset: nil)
    }

    func testThePackagesPagesInItsOrder() throws {
        let plain = WatchSession(sessionId: "s", modalityId: "m", archetypeName: "A", estimatedMinutes: 30,
                                 isDeload: false, exercises: [])
        XCTAssertEqual(WatchSummaryText.pages(plain), ["summary", "heart_rate", "exercises"],
                       "the vocabulary's default: HR zones is the heart-rate page, training effect and status left to the Garmin")
        var custom = plain
        custom.watch = WatchIdentity(summary: .init(pages: ["hr_zones", "summary", "training_status"]))
        XCTAssertEqual(WatchSummaryText.pages(custom), ["heart_rate", "summary"],
                       "HR zones alone still draws the heart-rate page, which has the zones")
        custom.watch = WatchIdentity(summary: .init(pages: ["exercises", "training_effect", "summary"]))
        XCTAssertEqual(WatchSummaryText.pages(custom), ["exercises", "summary"])
        custom.watch = WatchIdentity(summary: .init(pages: ["training_effect"]))
        XCTAssertEqual(WatchSummaryText.pages(custom), ["summary"], "never an empty end")
    }

    func testSetsVolumeAndWhatEachStepLogged() throws {
        let squat = try ex(#"{"exerciseId": "back_squat", "name": "Back Squat", "slotType": "sets_reps", "weightKg": 100}"#)
        let press = try ex(#"{"exerciseId": "double_kb_press", "name": "Double KB Press", "slotType": "sets_reps", "category": "kettlebell", "bells": 2, "weightKg": 24}"#)
        let plank = try ex(#"{"exerciseId": "plank", "name": "Plank", "slotType": "static_hold"}"#)
        let cindy = try ex(#"{"exerciseId": "cindy", "name": "Cindy", "slotType": "amrap", "slotRole": "metcon", "timeMinutes": 20}"#)
        let pull = try ex(#"{"exerciseId": "pull_up", "name": "Pull-up", "slotType": "amrap_movement", "parentSlotRole": "metcon"}"#)
        let row = try ex(#"{"exerciseId": "row", "name": "Row", "slotType": "for_time"}"#)
        let session = WatchSession(sessionId: "s", modalityId: "m", archetypeName: "A", estimatedMinutes: 60,
                                   isDeload: false, exercises: [squat, press, plank, cindy, pull, row])
        let logs = ["back_squat": [set(5, 100), set(5, 100), set(4, 102.5)],
                    "double_kb_press": [set(5, 24)],
                    "plank": [set(nil, nil, hold: 45), set(nil, nil, hold: 40)]]
        XCTAssertEqual(WatchSummaryText.totalSets(logs), 6)
        XCTAssertEqual(WatchSummaryText.volumeKg(session, logs), 500 + 500 + 410 + 240,
                       "a double's bells both count")

        let lines = WatchSummaryText.exerciseLines(session, logs: logs,
                                                   outcomes: ["cindy": WatchOutcome(rounds: 7),
                                                              "row": WatchOutcome(durationSec: 452)])
        XCTAssertEqual(lines.map(\.name), ["Back Squat", "Double KB Press", "Plank", "Cindy", "Row"],
                       "the AMRAP's movement is part of its round")
        XCTAssertEqual(lines.map(\.logged), ["3x4 @ 102.5", "1x5 @ 2x24", "2x-", "7 rounds", "7:32"])
    }
}
