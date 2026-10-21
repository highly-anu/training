import XCTest
@testable import TrainingCompanion

final class TrainingContractTests: XCTestCase {
    func testTrackReadinessDecodesAndIsSentWithGeneration() throws {
        // As APIClient.fetchPhilosophies decodes: a plain JSONDecoder, no key strategy.
        let decoder = JSONDecoder()
        let data = Data(#"{"id":"doubles","name":"Doubles","phases":[],"entry_requirements":{"training_levels":["intermediate"],"mastered_exercises":["kb_clean_double"],"mastered_exercises_by_level":{"intermediate":["kb_clean_double"]},"kettlebell_count":2}}"#.utf8)
        let track = try decoder.decode(PhilosophyTrack.self, from: data)
        XCTAssertEqual(track.entryRequirements?.kettlebellCount, 2)
        XCTAssertEqual(track.entryRequirements?.masteredExercisesByLevel?["intermediate"], ["kb_clean_double"])
        var constraints = GenerateConstraints()
        constraints.masteredExercises = ["kb_clean_double"]
        constraints.kettlebellCount = 2
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(constraints)) as? [String: Any])
        XCTAssertEqual(object["mastered_exercises"] as? [String], ["kb_clean_double"])
        XCTAssertEqual(object["kettlebell_count"] as? Int, 2)
    }
    func testTrackReadinessNamesMovementsFromTheServer() throws {
        // The builder's toggle reads the server's name; it used to strip one
        // package's id prefix (`wk_kb_`), which a new package's ids never had.
        let data = Data(#"{"id":"doubles","name":"Doubles","phases":[],"entry_requirements":{"training_levels":["intermediate"],"mastered_exercises":["kb_clean_double"],"exercise_names":{"kb_clean_double":"Double Kettlebell Clean"},"kettlebell_count":2}}"#.utf8)
        let track = try JSONDecoder().decode(PhilosophyTrack.self, from: data)
        XCTAssertEqual(track.entryRequirements?.exerciseNames?["kb_clean_double"], "Double Kettlebell Clean")
        let older = Data(#"{"training_levels":["novice"],"mastered_exercises":[],"kettlebell_count":1}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(TrackEntryRequirements.self, from: older).exerciseNames,
                     "a server before the names decodes as before")
    }
    func testModulePrescriptionSurvivesRoundTripAndShowsRepetitions() throws {
        let data = Data(#"""
        {"exercise":{"id":"swing","name":"Swing","category":"kettlebell"},
         "slot_role":"swing_main","slot_type":"emom","meta":false,"injury_skip":false,
         "load":{"duration_minutes":10,"time_minutes":10,"target_rounds":10,
                 "reps_per_round":6,"work_sec":60,"weight_kg":16,
                 "module_id":"swing","forecast_step":0,"conditional":false,
                 "progression_model":"density_cycle","prescription_version":1,"elapsed_sec":600}}
        """#.utf8)
        let assignment = try JSONDecoder().decode(ProgramExerciseAssignment.self, from: data)
        XCTAssertTrue(LoadFormat.describe(assignment).contains("6 reps/round"))
        XCTAssertTrue(LoadFormat.describe(assignment).contains("16 kg"))
        let recovered = try JSONDecoder().decode(ProgramExerciseAssignment.self,
                                                from: JSONEncoder().encode(assignment))
        XCTAssertEqual(recovered.load.extra["module_id"], .string("swing"))
        XCTAssertEqual(recovered.load.extra["forecast_step"], .int(0))
        XCTAssertEqual(recovered.load.extra["elapsed_sec"], .int(600))
    }

    func testModuleOutcomePreservesBellQualityAndEffort() throws {
        let data = Data(#"{"sets":[],"rounds":10,"rpe":6,"clean":true,"weightKg":16}"#.utf8)
        let outcome = try JSONDecoder().decode(ExercisePerformanceLog.self, from: data)
        XCTAssertEqual(outcome.weightKg, 16)
        XCTAssertEqual(outcome.rpe, 6)
        XCTAssertEqual(outcome.clean, true)
        let recovered = try JSONDecoder().decode(ExercisePerformanceLog.self,
                                                from: JSONEncoder().encode(outcome))
        XCTAssertEqual(recovered, outcome)
    }
}
