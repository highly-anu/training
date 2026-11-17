import XCTest
@testable import TrainingCompanion

/// The day the phone relays to the Apple Watch is today-session's
/// `?spec=1&week=1` body as the server wrote it. `data/watch_day_fixture.json`
/// is that body for a hand-built week, written by the route itself
/// (`test_today_session.py --write`, which fails when the two part), so these
/// decode what the server sends rather than what the phone used to build.
@MainActor
final class WatchDayTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func fixture() throws -> Data {
        try Data(contentsOf: Self.repo.appendingPathComponent("data/watch_day_fixture.json"))
    }

    func testTheServersDayDecodes() throws {
        let day = try JSONDecoder().decode(WatchDay.self, from: fixture())
        XCTAssertEqual(day.status, "ok")
        XCTAssertEqual(day.date, "2026-10-12")
        XCTAssertEqual(day.maxHR, 186)
        XCTAssertEqual(day.readiness, WatchReadiness(score: 72, status: "green"))
        XCTAssertEqual(day.progress?.week.sessions, 5)
        XCTAssertEqual(day.progress?.headline?.label, "Load on the bar")
        XCTAssertEqual(day.days?.count, 7)
        XCTAssertEqual(day.days?.first?.title, "Strength A +3")

        let sessions = try XCTUnwrap(day.sessions)
        XCTAssertEqual(sessions.map(\.archetypeName), ["Strength A", "BJJ Class", "2 km Row Test", "Snatch Set"])
        XCTAssertEqual(sessions.map(\.completed), [true, false, false, false], "done on any device, from the server")
        XCTAssertEqual(sessions.map(\.sessionId), ["3-Monday-0", "3-Monday-1", "3-Monday-2", "3-Monday-3"])

        // The injury-skipped accessory never arrives; the squat keeps its
        // server wording, its last time, and an RPE of 7.5 read as 8.
        let squat = try XCTUnwrap(sessions[0].exercises.first)
        XCTAssertEqual(sessions[0].exercises.count, 1)
        XCTAssertEqual(squat.exerciseId, "back_squat")
        XCTAssertEqual(squat.loadDescription, "3×5 @ 102.5 kg")
        XCTAssertEqual(squat.targetRpe, 8)
        XCTAssertEqual(squat.lastTime, "100kg × 5")
        XCTAssertEqual(squat.restSeconds, 180)

        // A round with no exercise is a step, logged by its name (as the
        // Garmin logs it); the phone used to drop it.
        let round = sessions[1].exercises[0]
        XCTAssertTrue(round.isMeta)
        XCTAssertEqual(round.exerciseId, "Positional Sparring")
        XCTAssertEqual(round.slotType, "time_domain")
        let bike = sessions[1].exercises[1]
        XCTAssertEqual(bike.durationMinutes, 23, "22.5 minutes did not sink the day")
        XCTAssertEqual(bike.prescribedZoneLower, 1)
        XCTAssertEqual(bike.prescribedZoneUpper, 2)

        let row = try XCTUnwrap(sessions[2].exercises.first?.standard)
        XCTAssertEqual(row, WatchStandard(id: "row_2km_minutes", name: "2km Row", result: "duration",
                                          best: "7:48", target: "7:00 for advanced"))
        XCTAssertFalse(try XCTUnwrap(sessions[2].exercises.first).asksReps, "a test asks for its result")

        // A timed kettlebell set: its reps are asked at the end (`logs`).
        let snatch = try XCTUnwrap(sessions[3].exercises.first)
        XCTAssertEqual(snatch.logs, ["reps"])
        XCTAssertTrue(snatch.asksReps)
    }

    /// Compressed under one key, the day is a property list (the JSON's
    /// nulls could not be one) and well under a message's size, and the
    /// watch gets back exactly what the server wrote.
    func testTheDayCrossesTheLinkAsItIs() throws {
        let json = try fixture()
        let message = try XCTUnwrap(WatchDayMessage.payload(json: json))
        XCTAssertTrue(PropertyListSerialization.propertyList(message, isValidFor: .binary))
        XCTAssertLessThan((message["day"] as? Data)?.count ?? .max, 20_000)
        let received = try XCTUnwrap(WatchDayMessage.day(from: message))
        XCTAssertEqual(received.json, json)
        XCTAssertEqual(received.day.sessions?.count, 4)
        XCTAssertNil(WatchDayMessage.day(from: ["type": "no_program"]), "not a day")
    }

    func testADayWithoutSessionsSaysWhy() throws {
        let later = try JSONDecoder().decode(WatchDay.self,
                                             from: Data(#"{"status": "not_started", "startsOn": "2026-10-20"}"#.utf8))
        XCTAssertEqual(later.status, "not_started")
        XCTAssertEqual(later.startsOn, "2026-10-20")
        XCTAssertNil(later.sessions)
        let none = try JSONDecoder().decode(WatchDay.self, from: Data(#"{"status": "no_program"}"#.utf8))
        XCTAssertEqual(none.status, "no_program")
    }

    /// An odd block beside the sessions costs that block, not the day.
    func testABadBlockCostsOnlyItself() throws {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        raw["progress"] = ["week": "three"]
        raw["readiness"] = 72
        let day = try JSONDecoder().decode(WatchDay.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(day.progress)
        XCTAssertNil(day.readiness)
        XCTAssertEqual(day.sessions?.count, 4)
    }

    /// The Garmin's demo programmes are the server's session shape too
    /// (garmin/tools/gen_watch_demo.py): every one of their sessions decodes.
    func testTheGarminDemoSessionsDecode() throws {
        struct DemoDay: Decodable { let sessions: [WatchSession] }
        struct Demo: Decodable { let days: [DemoDay] }
        let dir = Self.repo.appendingPathComponent("garmin/TrainingCompanionCIQ/resources/jsonData")
        for name in ["demo_kb", "demo_sof", "demo_uphill"] {
            let demo = try JSONDecoder().decode(Demo.self,
                                                from: Data(contentsOf: dir.appendingPathComponent("\(name).json")))
            let exercises = demo.days.flatMap(\.sessions).flatMap(\.exercises)
            XCTAssertFalse(exercises.isEmpty, name)
            XCTAssertTrue(exercises.allSatisfy { !$0.exerciseId.isEmpty && !$0.slotType.isEmpty }, name)
        }
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
