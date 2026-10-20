import XCTest
@testable import TrainingCompanion

/// Starting Strength's lifts confirmed made or missed (LiftConfirmation), the
/// same body the web's LiftProgress sends, and the builder's level-aware track
/// and starting weights.
final class LiftConfirmationTests: XCTestCase {
    private func session() throws -> ProgramSession {
        let data = Data(#"""
        {"modality":"max_strength","is_deload":false,
         "archetype":{"id":"3x5_linear","name":"Workout A"},
         "exercises":[
          {"exercise":{"id":"back_squat","name":"Back Squat"},"slot_role":"novice_lp_squat","slot_type":"sets_reps","meta":false,
           "load":{"sets":3,"reps":5,"weight_kg":70,"lift":"back_squat","advances_module":true,"progression_model":"load_per_exposure"}},
          {"exercise":{"id":"strict_press","name":"Press"},"slot_role":"novice_lp_press","slot_type":"sets_reps","meta":false,
           "load":{"sets":3,"reps":5,"work_up":true,"lift":"strict_press","advances_module":true,"progression_model":"load_per_exposure"}},
          {"exercise":{"id":"chin_up","name":"Chin-Up"},"slot_role":"novice_lp_chin_ups","slot_type":"sets_reps","meta":false,
           "load":{"sets":3,"reps":"max","advances_module":false,"progression_model":"load_per_exposure"}}]}
        """#.utf8)
        return try JSONDecoder().decode(ProgramSession.self, from: data)
    }

    func testTheLoadedLiftsAreWhatItAsksAbout() throws {
        let lifts = LiftConfirmation.lifts(of: try session())
        XCTAssertEqual(lifts.map(\.id), ["back_squat", "strict_press"], "chin-ups carry no lift")
        XCTAssertEqual(lifts[0].weightKg, 70)
        XCTAssertNil(lifts[1].weightKg, "a work-up has no weight until it is recorded")
    }

    func testOnlyWhatWentOtherwiseIsSent() throws {
        let lifts = LiftConfirmation.lifts(of: try session())
        let allMade = LiftConfirmation.payload(lifts, answers: [:], allMade: true)
        XCTAssertTrue(allMade.clean)
        XCTAssertNil(allMade.lifts)
        XCTAssertTrue(LiftConfirmation.unweighed(lifts, answers: [:], allMade: true),
                      "a work-up made needs its weight")
        XCTAssertFalse(LiftConfirmation.unweighed(lifts, answers: ["strict_press": .init(made: false, kg: "")], allMade: false),
                       "a missed work-up needs none")
        XCTAssertFalse(LiftConfirmation.unweighed(lifts, answers: ["strict_press": .init(made: true, kg: "32,5")], allMade: true))
        let workUp = LiftConfirmation.payload(lifts, answers: ["strict_press": .init(made: true, kg: "32,5")], allMade: true)
        XCTAssertEqual(workUp.lifts, ["strict_press": APIClient.LiftOutcome(made: true, weightKg: 32.5)])
        let missed = LiftConfirmation.payload(lifts, answers: ["back_squat": .init(made: false, kg: "")], allMade: false)
        XCTAssertFalse(missed.clean)
        XCTAssertEqual(missed.lifts, ["back_squat": APIClient.LiftOutcome(made: false, weightKg: nil)])
    }

    func testTheVerdictReadsEachLiftBack() throws {
        let lifts = LiftConfirmation.lifts(of: try session())
        var entry = SessionLogEntry(sessionKey: "1-Monday-0", completedAt: "x", source: "web", notes: nil,
                                    fatigueRating: nil, avgHR: nil, peakHR: nil, matchedWorkoutId: nil)
        XCTAssertNil(LiftConfirmation.verdict(lifts, log: entry))
        var squat = ExercisePerformanceLog()
        squat.made = false
        var press = ExercisePerformanceLog()
        press.made = true
        entry.exercises = ["back_squat": squat, "strict_press": press]
        XCTAssertEqual(LiftConfirmation.verdict(lifts, log: entry), ["back_squat": false, "strict_press": true])
        let recovered = try JSONDecoder().decode(ExercisePerformanceLog.self, from: JSONEncoder().encode(squat))
        XCTAssertEqual(recovered.made, false, "made survives the round trip")
    }

    func testTheBuilderPicksTheLevelsTrackAndSendsStartingWeights() throws {
        let data = Data(#"""
        {"id":"starting_strength","name":"Starting Strength","primary_track_id":"linear_progression",
         "track_for_level":{"novice":"linear_progression","intermediate":"texas_method"},
         "tracks":[{"id":"linear_progression","name":"Linear Progression Program","phases":[],
                    "entry_requirements":{"training_levels":["novice"],"mastered_exercises":[],"kettlebell_count":1,
                                          "starting_loads":[{"id":"back_squat","name":"Back Squat"}]}},
                   {"id":"texas_method","name":"Texas Method","phases":[]}]}
        """#.utf8)
        let card = try JSONDecoder().decode(PhilosophyCard.self, from: data)
        XCTAssertEqual(card.track(nil, level: "intermediate")?.id, "texas_method")
        XCTAssertEqual(card.track(nil, level: "novice")?.id, "linear_progression")
        XCTAssertEqual(card.track("linear_progression", level: "intermediate")?.id, "linear_progression")
        XCTAssertEqual(card.track(nil)?.entryRequirements?.startingLoads?.first?.name, "Back Squat")
        var constraints = GenerateConstraints()
        constraints.startingLoadsKg = ["back_squat": 60]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(constraints)) as? [String: Any])
        XCTAssertEqual(object["starting_loads_kg"] as? [String: Double], ["back_squat": 60])
    }
}
