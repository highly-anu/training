import XCTest
@testable import TrainingCompanion

/// A save from the phone must put back everything the server stored, not
/// just the keys this app models. Until it did, every move, swap or
/// completion stripped the goal, constraints, coverage report, each
/// exercise's slot and the blend's weights.
final class ProgramRoundTripTests: XCTestCase {

    private let stored = """
    {
      "currentProgram": {
        "goal": {"id": "_phil_starting_strength", "name": "Starting Strength", "priorities": {"max_strength": 1.0}},
        "constraints": {"training_level": "intermediate", "days_per_week": 3, "equipment": ["barbell", "rack"]},
        "validation": {"valid": true, "errors": [], "warnings": []},
        "coverage_report": {"unfilled_sessions": [], "unfilled_slots": [], "borrowed_sessions": []},
        "volume_summary": [{"total_minutes": 210}],
        "weeks": [{
          "week_number": 1, "week_in_phase": 1, "is_deload": false, "phase": "base", "framework_id": "linear_progression",
          "schedule": {"Monday": [{
            "modality": "max_strength", "is_deload": false, "provenance": "starting_strength", "unfilled_slots": [],
            "archetype": {"id": "hlm", "name": "Heavy/Light/Medium", "duration_estimate_minutes": 70, "modality": "max_strength",
                          "slots": [{"role": "primary_squat", "slot_type": "sets_reps", "sets": 3, "reps": 5}]},
            "exercises": [{
              "slot_index": 0, "slot_role": "primary_squat", "slot_type": "sets_reps", "meta": false, "injury_skip": false,
              "slot": {"role": "primary_squat", "slot_type": "sets_reps", "sets": 3, "reps": 5,
                       "exercise_filter": {"movement_pattern": "squat"}},
              "exercise": {"id": "back_squat", "name": "Back Squat", "category": "barbell",
                           "movement_patterns": ["squat"], "equipment": ["barbell", "rack"],
                           "starting_load_kg": 60, "weekly_increment_kg": 2.5},
              "load": {"sets": 3, "reps": 5, "weight_kg": 80.0, "focus": "bar speed"},
              "load_note": "Establish baseline load"
            }]
          }]}
        }]
      },
      "programStartDate": "2026-09-21", "eventDate": null,
      "sourceGoalIds": ["starting_strength", "wildman_kettlebell"],
      "sourceGoalWeights": {"starting_strength": 0.6, "wildman_kettlebell": 0.4},
      "revision": "r1", "programVersionId": "v1", "activeGoalId": "legacy"
    }
    """.data(using: .utf8)!

    private func payload(for sp: ServerProgram) -> UserProgramSavePayload {
        UserProgramSavePayload(currentProgram: sp.currentProgram, programStartDate: sp.programStartDate,
                               eventDate: sp.eventDate, sourceGoalIds: sp.sourceGoalIds,
                               sourceGoalWeights: sp.sourceGoalWeights, baseRevision: sp.revision, extra: sp.extra)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSavePayloadCarriesEverythingTheServerStored() throws {
        let sp = try JSONDecoder().decode(ServerProgram.self, from: stored)
        let json = try object(try JSONEncoder().encode(payload(for: sp)))

        let cp = try XCTUnwrap(json["currentProgram"] as? [String: Any])
        XCTAssertEqual((cp["goal"] as? [String: Any])?["id"] as? String, "_phil_starting_strength")
        XCTAssertEqual((cp["constraints"] as? [String: Any])?["days_per_week"] as? Int, 3)
        XCTAssertNotNil(cp["validation"]); XCTAssertNotNil(cp["coverage_report"]); XCTAssertNotNil(cp["volume_summary"])

        let week = try XCTUnwrap((cp["weeks"] as? [[String: Any]])?.first)
        XCTAssertEqual(week["framework_id"] as? String, "linear_progression")
        XCTAssertEqual(week["week_number"] as? Int, 1, "modelled keys keep their snake_case names")

        let session = try XCTUnwrap(((week["schedule"] as? [String: Any])?["Monday"] as? [[String: Any]])?.first)
        XCTAssertEqual(session["provenance"] as? String, "starting_strength")
        XCTAssertNotNil(session["unfilled_slots"])
        let archetype = try XCTUnwrap(session["archetype"] as? [String: Any])
        XCTAssertEqual((archetype["slots"] as? [[String: Any]])?.count, 1, "the swap endpoint reads the slots")
        XCTAssertEqual(archetype["modality"] as? String, "max_strength")

        let ex = try XCTUnwrap((session["exercises"] as? [[String: Any]])?.first)
        XCTAssertEqual(ex["slot_index"] as? Int, 0)
        XCTAssertEqual(((ex["slot"] as? [String: Any])?["exercise_filter"] as? [String: Any])?["movement_pattern"] as? String, "squat")
        XCTAssertEqual(ex["load_note"] as? String, "Establish baseline load")
        let exercise = try XCTUnwrap(ex["exercise"] as? [String: Any])
        XCTAssertEqual(exercise["movement_patterns"] as? [String], ["squat"])
        XCTAssertEqual(exercise["weekly_increment_kg"] as? Double, 2.5)
        XCTAssertEqual((ex["load"] as? [String: Any])?["focus"] as? String, "bar speed")
        XCTAssertEqual((ex["load"] as? [String: Any])?["weight_kg"] as? Double, 80)

        XCTAssertEqual(json["sourceGoalWeights"] as? [String: Double], ["starting_strength": 0.6, "wildman_kettlebell": 0.4],
                       "a blend's weights used to be sent as [:]")
        XCTAssertEqual(json["activeGoalId"] as? String, "legacy", "unknown envelope keys travel back")
        XCTAssertEqual(json["baseRevision"] as? String, "r1")
        XCTAssertNil(json["revision"]); XCTAssertNil(json["programVersionId"], "response-only keys are never echoed")
    }

    func testIntegersStayIntegers() throws {
        let sp = try JSONDecoder().decode(ServerProgram.self, from: stored)
        let text = String(decoding: try JSONEncoder().encode(payload(for: sp)), as: UTF8.self)
        XCTAssertTrue(text.contains("\"slot_index\":0"), "0, not 0.0 — the version skeleton hash reads these")
        XCTAssertTrue(text.contains("\"starting_load_kg\":60"))
        XCTAssertFalse(text.contains("\"starting_load_kg\":60.0"))
        XCTAssertTrue(text.contains("\"days_per_week\":3"))
    }

    func testJSONValueRoundTrip() throws {
        let data = #"{"a": 1, "b": 1.5, "c": true, "d": null, "e": [1, "x"], "f": {"g": 2}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)
        XCTAssertEqual(decoded["a"], .int(1))
        XCTAssertEqual(decoded["b"], .double(1.5))
        XCTAssertEqual(decoded["c"], .bool(true))
        XCTAssertEqual(decoded["d"], .null)
        XCTAssertEqual(decoded["e"], .array([.int(1), .string("x")]))
        XCTAssertEqual(decoded["f"], .object(["g": .int(2)]))
        let again = try JSONDecoder().decode([String: JSONValue].self, from: try JSONEncoder().encode(decoded))
        XCTAssertEqual(again, decoded)
    }

    @MainActor
    func testEditsKeepTheExtras() async throws {
        let appState = AppState()
        appState.serverProgram = try JSONDecoder().decode(ServerProgram.self, from: stored)

        let alternative = ProgramExerciseAssignment(
            exercise: ProgramExercise(id: "front_squat", name: "Front Squat", category: "barbell", notes: nil,
                                      extra: ["movement_patterns": .array([.string("squat")])]),
            load: ProgramLoad(sets: 3, reps: AnyCodable(intValue: 5), weightKg: 70, targetRpe: nil, durationMinutes: nil,
                              zoneTarget: nil, timeMinutes: nil, targetRounds: nil, format: nil, holdSeconds: nil,
                              distanceKm: nil, intensity: nil),
            slotRole: "primary_squat", slotType: "sets_reps", restSec: nil, meta: false, injurySkip: false,
            loadNote: nil, notes: nil, extra: ["slot_index": .int(0)])
        appState.replaceExercise(weekIndex: 0, day: "Monday", sessionIndex: 0, exerciseIndex: 0, assignment: alternative)

        let sp = try XCTUnwrap(appState.serverProgram)
        XCTAssertNotNil(sp.currentProgram?.extra["goal"], "the program's goal survives a swap")
        XCTAssertNotNil(sp.currentProgram?.extra["coverage_report"])
        let week = try XCTUnwrap(sp.currentProgram?.weeks.first)
        XCTAssertEqual(week.extra["framework_id"], .string("linear_progression"))
        let session = try XCTUnwrap(week.schedule["Monday"]?.first)
        XCTAssertEqual(session.extra["provenance"], .string("starting_strength"))
        XCTAssertEqual(session.exercises.first?.exercise?.id, "front_squat")
        XCTAssertEqual(session.exercises.first?.extra["slot_index"], .int(0))
        XCTAssertEqual(sp.sourceGoalWeights["wildman_kettlebell"], 0.4)
        XCTAssertEqual(sp.extra["activeGoalId"], .string("legacy"))

        appState.moveSession(weekIndex: 0, fromDay: "Monday", toDay: "Tuesday", sessionIndex: 0)
        let moved = try XCTUnwrap(appState.serverProgram?.currentProgram?.weeks.first)
        XCTAssertEqual(moved.extra["framework_id"], .string("linear_progression"), "a move rebuilds the week with its extras")
        XCTAssertEqual(moved.schedule["Tuesday"]?.first?.extra["provenance"], .string("starting_strength"))
    }
}
