import XCTest
@testable import TrainingCompanion

/// Tests that the program save payload encodes camelCase keys and that
/// ServerProgram can round-trip through encode → decode without data loss.
///
/// The bug this caught: UserProgramSavePayload previously had snake_case
/// CodingKeys ("current_program", "program_start_date"), while ServerProgram
/// has no CodingKeys and expects camelCase. Every save was silently corrupting
/// the stored program, causing the next fetch to decode as nil.
final class ProgramCodableTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a minimal GeneratedProgram from JSON so the round-trip test
    /// exercises real decode paths rather than hand-crafted structs.
    private func makeMinimalProgram() throws -> GeneratedProgram {
        let json = """
        {
            "weeks": [{
                "week_number": 1,
                "week_in_phase": 1,
                "is_deload": false,
                "phase": "base",
                "schedule": {
                    "Monday": [{
                        "modality": "strength",
                        "is_deload": false,
                        "exercises": [{
                            "exercise": {"id": "squat", "name": "Back Squat", "category": "strength"},
                            "load": {"sets": 3, "reps": 5, "weight_kg": 80.0},
                            "slot_role": "primary",
                            "slot_type": "sets_reps",
                            "meta": false,
                            "injury_skip": false
                        }]
                    }]
                }
            }]
        }
        """
        return try JSONDecoder().decode(GeneratedProgram.self, from: json.data(using: .utf8)!)
    }

    // MARK: - UserProgramSavePayload encodes camelCase

    func testSavePayloadEncodesCamelCaseTopLevelKeys() throws {
        let payload = UserProgramSavePayload(
            currentProgram: try makeMinimalProgram(),
            programStartDate: "2025-01-06",
            eventDate: nil,
            sourceGoalIds: ["strength_base"],
            sourceGoalWeights: ["strength_base": 1.0]
        )
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Top-level keys must be camelCase — any snake_case here breaks ServerProgram decode
        XCTAssertNotNil(json["currentProgram"],    "expected 'currentProgram', got snake_case or missing")
        XCTAssertNotNil(json["programStartDate"],  "expected 'programStartDate'")
        XCTAssertNotNil(json["sourceGoalIds"],     "expected 'sourceGoalIds'")
        XCTAssertNotNil(json["sourceGoalWeights"], "expected 'sourceGoalWeights'")

        // Old snake_case keys must NOT be present
        XCTAssertNil(json["current_program"],     "snake_case 'current_program' breaks ServerProgram decode")
        XCTAssertNil(json["program_start_date"],  "snake_case 'program_start_date' breaks decode")
        XCTAssertNil(json["source_goal_ids"],     "snake_case 'source_goal_ids' breaks decode")
    }

    // MARK: - ServerProgram round-trip

    func testServerProgramRoundTrip() throws {
        let payload = UserProgramSavePayload(
            currentProgram: try makeMinimalProgram(),
            programStartDate: "2025-01-06",
            eventDate: "2025-06-01",
            sourceGoalIds: ["strength_base"],
            sourceGoalWeights: ["strength_base": 1.0]
        )
        // Simulate: iOS encodes → server stores → server returns → iOS decodes
        let encoded = try JSONEncoder().encode(payload)
        let decoded = try XCTUnwrap(
            try? JSONDecoder().decode(ServerProgram.self, from: encoded),
            "ServerProgram decode returned nil — likely a camelCase/snake_case mismatch in save payload"
        )

        XCTAssertEqual(decoded.programStartDate, "2025-01-06")
        XCTAssertEqual(decoded.eventDate, "2025-06-01")
        XCTAssertEqual(decoded.sourceGoalIds, ["strength_base"])
        XCTAssertEqual(decoded.currentProgram?.weeks.count, 1)
        XCTAssertEqual(decoded.currentProgram?.weeks.first?.weekNumber, 1)
        XCTAssertEqual(decoded.currentProgram?.weeks.first?.phase, "base")
        XCTAssertFalse(decoded.currentProgram?.weeks.first?.isDeload ?? true)
    }

    // MARK: - ProgramWeek encodes snake_case inner keys

    func testProgramWeekEncodesSnakeCaseKeys() throws {
        let week = ProgramWeek(
            weekNumber: 2, weekInPhase: 2,
            isDeload: true, phase: "build",
            schedule: [:]
        )
        let data = try JSONEncoder().encode(week)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Inner week fields must be snake_case (matching web frontend WeekData shape)
        XCTAssertNotNil(json["week_number"],  "expected snake_case 'week_number'")
        XCTAssertNotNil(json["is_deload"],    "expected snake_case 'is_deload'")
        XCTAssertNil(json["weekNumber"],      "'weekNumber' would break web frontend decode")
        XCTAssertNil(json["isDeload"],        "'isDeload' would break web frontend decode")
        XCTAssertEqual(json["week_number"] as? Int,  2)
        XCTAssertEqual(json["is_deload"]    as? Bool, true)
    }

    // MARK: - ServerProgram decodes web-frontend camelCase format

    func testServerProgramDecodesWebFrontendFormat() throws {
        // This is the format the web frontend writes to the server
        let webJson = """
        {
            "currentProgram": {
                "weeks": [
                    {
                        "week_number": 1,
                        "week_in_phase": 1,
                        "is_deload": false,
                        "phase": "base",
                        "schedule": {}
                    }
                ]
            },
            "programStartDate": "2025-01-06",
            "eventDate": null,
            "sourceGoalIds": ["strength_base"]
        }
        """
        let data = webJson.data(using: .utf8)!
        let decoded = try XCTUnwrap(
            try? JSONDecoder().decode(ServerProgram.self, from: data),
            "ServerProgram failed to decode web-frontend camelCase format"
        )
        XCTAssertEqual(decoded.programStartDate, "2025-01-06")
        XCTAssertEqual(decoded.currentProgram?.weeks.count, 1)
        XCTAssertEqual(decoded.currentProgram?.weeks.first?.phase, "base")
    }

    // MARK: - AppState.replaceSession preserves all other weeks and sessions

    @MainActor
    func testAppStateReplaceSessionUpdatesCorrectSlot() throws {
        let appState = AppState()
        appState.serverProgram = try serverProgramFixture("""
        {
            "currentProgram": {
                "weeks": [{
                    "week_number": 1, "week_in_phase": 1,
                    "is_deload": false, "phase": "base",
                    "schedule": {
                        "Monday":    [{"modality":"strength",    "is_deload":false,"exercises":[]}],
                        "Wednesday": [{"modality":"aerobic_base","is_deload":false,"exercises":[]}]
                    }
                }]
            },
            "programStartDate": "2025-01-06",
            "sourceGoalIds": []
        }
        """)

        let replacement = try sessionFixture(modality: "kettlebell")
        appState.replaceSession(weekIndex: 0, day: "Monday", sessionIndex: 0, session: replacement)

        let updated = appState.serverProgram?.currentProgram?.weeks[0]
        XCTAssertEqual(updated?.schedule["Monday"]?.first?.modality, "kettlebell",
                       "Monday session should be replaced")
        XCTAssertEqual(updated?.schedule["Wednesday"]?.first?.modality, "aerobic_base",
                       "Wednesday session must be untouched")
    }

    // MARK: - AppState.moveSession

    @MainActor
    func testAppStateMoveSessionRelocatesSession() throws {
        let appState = AppState()
        appState.serverProgram = try serverProgramFixture("""
        {
            "currentProgram": {
                "weeks": [{
                    "week_number": 1, "week_in_phase": 1,
                    "is_deload": false, "phase": "base",
                    "schedule": {
                        "Monday":  [{"modality":"strength","is_deload":false,"exercises":[]}],
                        "Tuesday": []
                    }
                }]
            },
            "programStartDate": "2025-01-06",
            "sourceGoalIds": []
        }
        """)

        appState.moveSession(weekIndex: 0, fromDay: "Monday", toDay: "Tuesday", sessionIndex: 0)

        let updated = appState.serverProgram?.currentProgram?.weeks[0]
        XCTAssertTrue(updated?.schedule["Monday"]?.isEmpty ?? false,
                      "Monday should be empty after move")
        XCTAssertEqual(updated?.schedule["Tuesday"]?.first?.modality, "strength",
                       "Tuesday should have the moved session")
    }

    // MARK: - Helpers

    private func serverProgramFixture(_ json: String) throws -> ServerProgram {
        try XCTUnwrap(try? JSONDecoder().decode(ServerProgram.self, from: json.data(using: .utf8)!),
                      "Fixture JSON failed to decode as ServerProgram")
    }

    private func sessionFixture(modality: String) throws -> ProgramSession {
        let json = """
        {"modality":"\(modality)","is_deload":false,"exercises":[]}
        """
        return try XCTUnwrap(try? JSONDecoder().decode(ProgramSession.self, from: json.data(using: .utf8)!))
    }
}
