import XCTest
@testable import TrainingCompanion

/// The two program-editing contracts: exercise substitution and applying a
/// progression adjustment. The server speaks snake_case for the request
/// bodies it defines and camelCase for the envelope it stores; a key in the
/// wrong case is a 400 or a silently ignored field, and nothing else here
/// would notice.
final class ProgramEditingCodableTests: XCTestCase {

    // MARK: - Substitute

    func testSubstituteRequestEncodesTheServersKeys() throws {
        let request = SubstituteRequest(
            archetypeId: "hlm", slotRole: "primary_squat", exerciseId: "front_squat",
            modality: "max_strength",
            constraints: SubstituteRequest.Constraints(trainingLevel: "intermediate",
                                                       equipment: ["barbell", "rack"],
                                                       injuryFlags: ["lumbar_disc"],
                                                       sessionTimeMinutes: 75),
            philosophyIds: ["starting_strength"], phase: "base", weekInPhase: 2,
            isDeload: false, exclude: ["front_squat", "press"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])

        XCTAssertEqual(json["archetype_id"] as? String, "hlm")
        XCTAssertEqual(json["slot_role"] as? String, "primary_squat")
        XCTAssertEqual(json["exercise_id"] as? String, "front_squat")
        XCTAssertEqual(json["philosophy_ids"] as? [String], ["starting_strength"])
        XCTAssertEqual(json["week_in_phase"] as? Int, 2)
        XCTAssertEqual(json["is_deload"] as? Bool, false)
        XCTAssertEqual(json["exclude"] as? [String], ["front_squat", "press"])
        XCTAssertEqual(json["limit"] as? Int, 8)
        let constraints = try XCTUnwrap(json["constraints"] as? [String: Any])
        XCTAssertEqual(constraints["training_level"] as? String, "intermediate")
        XCTAssertEqual(constraints["injury_flags"] as? [String], ["lumbar_disc"])
        XCTAssertEqual(constraints["session_time_minutes"] as? Int, 75)
        XCTAssertNil(json["archetypeId"], "camelCase would be ignored by the server")
    }

    func testAlternativesDecodeAsCompleteAssignments() throws {
        let body = """
        {"alternatives": [{
            "assignment": {
                "slot_index": 0, "slot_role": "primary_squat", "slot_type": "sets_reps",
                "exercise": {"id": "back_squat", "name": "Back Squat", "category": "barbell"},
                "load": {"sets": 3, "reps": 5, "weight_kg": 70.0},
                "load_note": "Establish baseline load"
            },
            "score": 1.0,
            "reasons": ["fits the squat pattern", "unlocks further movements"]
        }]}
        """
        let decoded = try JSONDecoder().decode(SubstituteResponse.self, from: Data(body.utf8))
        let alt = try XCTUnwrap(decoded.alternatives.first)
        XCTAssertEqual(alt.assignment.exercise?.id, "back_squat")
        XCTAssertEqual(alt.assignment.slotRole, "primary_squat")
        XCTAssertEqual(alt.assignment.load.weightKg, 70.0)
        XCTAssertEqual(alt.assignment.loadNote, "Establish baseline load")
        XCTAssertEqual(alt.reasons.count, 2)
        XCTAssertEqual(alt.id, "back_squat")
        // The server omits `meta` and `injury_skip` on an alternative; both
        // must default rather than fail the decode.
        XCTAssertFalse(alt.assignment.meta)
        XCTAssertFalse(alt.assignment.injurySkip)
    }

    // MARK: - Adjust

    func testAdjustRequestEncodesTheServersKeys() throws {
        let request = AdjustRequest(
            adjustment: AdjustRequest.Adjustment(type: "hold_load", target: "all", magnitude: nil),
            fromWeekIndex: 3, baseRevision: "rev-9")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])

        XCTAssertEqual(json["from_week_index"] as? Int, 3)
        XCTAssertEqual(json["baseRevision"] as? String, "rev-9", "same key as PUT /user/program")
        let adjustment = try XCTUnwrap(json["adjustment"] as? [String: Any])
        XCTAssertEqual(adjustment["type"] as? String, "hold_load")
        XCTAssertEqual(adjustment["target"] as? String, "all")
    }

    func testAdjustResultDecodesTheSavedEnvelope() throws {
        let body = """
        {
            "saved": true, "revision": "rev-10", "programVersionId": "v2",
            "applied": {"type": "hold_load", "from_week_index": 1, "weeks": [1, 2], "exercises": 6},
            "program": {
                "currentProgram": {"weeks": [
                    {"week_number": 1, "week_in_phase": 1, "is_deload": false, "phase": "base", "schedule": {}},
                    {"week_number": 2, "week_in_phase": 2, "is_deload": false, "phase": "base", "schedule": {}}
                ]},
                "programStartDate": "2026-09-28", "eventDate": null,
                "sourceGoalIds": ["starting_strength"], "sourceGoalWeights": {},
                "revision": "rev-10", "programVersionId": "v2"
            }
        }
        """
        let result = try JSONDecoder().decode(AdjustResult.self, from: Data(body.utf8))
        XCTAssertTrue(result.saved)
        XCTAssertEqual(result.applied.weeks, [1, 2])
        XCTAssertEqual(result.applied.exercises, 6)
        let program = try XCTUnwrap(result.program, "the envelope should replace the phone's copy")
        XCTAssertEqual(program.revision, "rev-10")
        XCTAssertEqual(program.programVersionId, "v2")
        XCTAssertEqual(program.currentProgram?.weeks.count, 2)
    }

    func testAdjustResultToleratesAnUndecodableProgram() throws {
        // A program the phone cannot decode is a reload, not a failed apply.
        let body = """
        {"saved": true, "revision": "r", "applied": {"type": "early_deload", "from_week_index": 0, "weeks": [0], "exercises": 3},
         "program": {"currentProgram": "not-a-program"}}
        """
        let result = try JSONDecoder().decode(AdjustResult.self, from: Data(body.utf8))
        XCTAssertNil(result.program)
        XCTAssertEqual(result.applied.exercises, 3)
    }

    func testAppliedSummaryUsesTheProgramsWeekNumbers() {
        let applied = AppliedAdjustment(type: "increase_increment", fromWeekIndex: 1, weeks: [2, 3], exercises: 4)
        // A regenerated block can number weeks[0...] as 16...; the summary
        // shows the number the athlete sees, not the array index.
        XCTAssertEqual(applied.summary { [16, 17, 18, 19][$0] },
                       "Applied to 4 exercises in weeks 18, 19.")
        XCTAssertEqual(applied.summary { _ in nil }, "Applied to 4 exercises in weeks 3, 4.")
        let one = AppliedAdjustment(type: "hold_load", fromWeekIndex: 0, weeks: [0], exercises: 1)
        XCTAssertEqual(one.summary { _ in nil }, "Applied to 1 exercise in week 1.")
        let none = AppliedAdjustment(type: "hold_load", fromWeekIndex: 0, weeks: [], exercises: 0)
        XCTAssertEqual(none.summary { _ in nil }, "Nothing in the remaining weeks matched this adjustment.")
    }

    func testOnlyPlanEditsAreAppliable() throws {
        func adjustment(_ type: String, target: String) throws -> ProgressionAdjustment {
            let json = """
            {"type": "\(type)", "target": "\(target)", "direction": "down", "reason": "r", "magnitude": null}
            """
            return try JSONDecoder().decode(ProgressionAdjustment.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try adjustment("hold_load", target: "all").isAppliable)
        XCTAssertTrue(try adjustment("early_deload", target: "Back Squat, Deadlift").isAppliable)
        XCTAssertFalse(try adjustment("rebuild_habit", target: "schedule").isAppliable,
                       "consistency is advice, not a plan edit")
        XCTAssertEqual(try adjustment("reduce_volume_10pct", target: "all").label, "Reduce volume 10%")
        XCTAssertNil(try adjustment("hold_load", target: "all").targetLabel)
        XCTAssertNil(try adjustment("rebuild_habit", target: "schedule").targetLabel)
        XCTAssertEqual(try adjustment("early_deload", target: "Back Squat, Deadlift").targetLabel,
                       "Back Squat, Deadlift")
    }

    // MARK: - AppState.replaceExercise

    @MainActor
    func testReplaceExerciseChangesOnlyThatSlot() async throws {
        let appState = AppState()
        appState.serverProgram = try XCTUnwrap(try? JSONDecoder().decode(ServerProgram.self, from: Data("""
        {
            "currentProgram": {"weeks": [{
                "week_number": 1, "week_in_phase": 1, "is_deload": false, "phase": "base",
                "schedule": {
                    "Monday": [{"modality": "max_strength", "is_deload": false,
                                "archetype": {"id": "hlm", "name": "Heavy"},
                                "exercises": [
                                    {"exercise": {"id": "front_squat", "name": "Front Squat"},
                                     "load": {"sets": 3, "reps": 5, "weight_kg": 55.0},
                                     "slot_role": "primary_squat", "slot_type": "sets_reps",
                                     "meta": false, "injury_skip": false},
                                    {"exercise": {"id": "press", "name": "Press"},
                                     "load": {"sets": 3, "reps": 5, "weight_kg": 40.0},
                                     "slot_role": "upper_press", "slot_type": "sets_reps",
                                     "meta": false, "injury_skip": false}
                                ]}],
                    "Wednesday": [{"modality": "aerobic_base", "is_deload": false, "exercises": []}]
                }
            }]},
            "programStartDate": "2026-09-28", "sourceGoalIds": ["starting_strength"],
            "revision": "rev-3", "programVersionId": "v1"
        }
        """.utf8)))

        let replacement = try JSONDecoder().decode(ProgramExerciseAssignment.self, from: Data("""
        {"slot_index": 0, "slot_role": "primary_squat", "slot_type": "sets_reps",
         "exercise": {"id": "back_squat", "name": "Back Squat"},
         "load": {"sets": 3, "reps": 5, "weight_kg": 70.0}}
        """.utf8))

        appState.replaceExercise(weekIndex: 0, day: "Monday", sessionIndex: 0,
                                 exerciseIndex: 0, assignment: replacement)

        let monday = try XCTUnwrap(appState.serverProgram?.currentProgram?.weeks[0].schedule["Monday"]?.first)
        XCTAssertEqual(monday.exercises.map { $0.exercise?.id }, ["back_squat", "press"])
        XCTAssertEqual(monday.exercises[0].load.weightKg, 70.0)
        XCTAssertEqual(monday.archetype?.id, "hlm", "the session keeps its archetype")
        XCTAssertEqual(appState.serverProgram?.currentProgram?.weeks[0].schedule["Wednesday"]?.first?.modality,
                       "aerobic_base", "other sessions are untouched")
        XCTAssertEqual(appState.serverProgram?.revision, "rev-3",
                       "the edit is saved against the revision that was read")
        XCTAssertEqual(appState.serverProgram?.programVersionId, "v1")
    }

    @MainActor
    func testReplaceExerciseIgnoresAnIndexOutOfRange() async throws {
        let appState = AppState()
        appState.serverProgram = try XCTUnwrap(try? JSONDecoder().decode(ServerProgram.self, from: Data("""
        {"currentProgram": {"weeks": [{"week_number": 1, "week_in_phase": 1, "is_deload": false, "phase": "base",
          "schedule": {"Monday": [{"modality": "max_strength", "is_deload": false, "exercises": []}]}}]},
         "programStartDate": "2026-09-28", "sourceGoalIds": []}
        """.utf8)))
        let assignment = try JSONDecoder().decode(ProgramExerciseAssignment.self, from: Data("""
        {"exercise": {"id": "x", "name": "X"}, "load": {}}
        """.utf8))
        appState.replaceExercise(weekIndex: 0, day: "Monday", sessionIndex: 0, exerciseIndex: 2, assignment: assignment)
        XCTAssertEqual(appState.serverProgram?.currentProgram?.weeks[0].schedule["Monday"]?.first?.exercises.count, 0)
    }
}
