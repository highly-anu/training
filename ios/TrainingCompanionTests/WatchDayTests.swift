import XCTest
@testable import TrainingCompanion

/// What the phone forwards to the Apple Watch from today-session's
/// `progress`: `transferUserInfo` takes property-list types only, so a JSON
/// null (no program %, no headline yet) must not reach it.
final class WatchDayTests: XCTestCase {
    func testNullsAreDroppedAtEveryDepth() throws {
        let json = Data(#"{"week": {"number": 2, "of": 12, "done": 3, "due": 4, "sessions": 5},"#
                        .utf8) + Data(#" "program": {"done": 3, "due": 4, "pct": null}, "headline": null}"#.utf8)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let clean = APIClient.dropNulls(raw)
        XCTAssertNil(clean["headline"])
        let program = try XCTUnwrap(clean["program"] as? [String: Any])
        XCTAssertNil(program["pct"])
        XCTAssertEqual(program["done"] as? Int, 3)
        XCTAssertEqual((clean["week"] as? [String: Any])?["sessions"] as? Int, 5)
        XCTAssertTrue(PropertyListSerialization.propertyList(clean, isValidFor: .binary),
                      "what goes to the watch is a valid property list")
    }
}

/// The complication's data: what the watch app writes to the App Group, and
/// what an older write (no week, no completion) still decodes to.
final class WidgetTodayDataTests: XCTestCase {
    private func session(_ id: String) -> WidgetSession {
        WidgetSession(id: id, modalityId: "max_strength", archetypeName: "Strength", estimatedMinutes: 50,
                      isDeload: false, exerciseNames: [])
    }

    func testOlderDataDecodesWithoutTheWeek() throws {
        let old = WidgetTodayData(date: "2026-10-16", sessions: [session("2-Friday-0")], updatedAt: Date())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["completedIds", "weekDone", "weekSessions", "readinessScore", "readinessSignal"] {
            json.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(WidgetTodayData.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.weekDone)
        XCTAssertFalse(decoded.allDone)
    }

    func testAllDoneOnlyWhenEverySessionIs() {
        var data = WidgetTodayData(date: "2026-10-16", sessions: [session("2-Friday-0"), session("2-Friday-1")],
                                   updatedAt: Date())
        data.completedIds = ["2-Friday-0"]
        XCTAssertFalse(data.allDone)
        data.completedIds = ["2-Friday-0", "2-Friday-1"]
        XCTAssertTrue(data.allDone)
        XCTAssertFalse(WidgetTodayData(date: "2026-10-16", sessions: [], updatedAt: Date()).allDone,
                       "a rest day is not done")
    }
}

/// The exercise the phone hands the watch carries its last time when the
/// server knows one, and a payload without it (an older phone) still decodes.
final class WatchExerciseLastTimeTests: XCTestCase {
    func testLastTimeIsOptionalOnTheWire() throws {
        let json = Data("""
        {"exerciseId": "squat", "name": "Back Squat", "slotType": "sets_reps", "slotRole": "main", "isMeta": false,
         "loadDescription": "5×5 @ 105 kg", "sets": 5, "reps": "5", "weightKg": 105}
        """.utf8)
        var ex = try JSONDecoder().decode(WatchExercise.self, from: json)
        XCTAssertNil(ex.lastTime)
        ex.lastTime = "102.5kg × 5"
        let round = try JSONDecoder().decode(WatchExercise.self, from: JSONEncoder().encode(ex))
        XCTAssertEqual(round.lastTime, "102.5kg × 5")
    }
}
