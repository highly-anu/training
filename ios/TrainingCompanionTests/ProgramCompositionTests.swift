import XCTest
@testable import TrainingCompanion

/// A program of several tracks (ProgramComposition.swift): the request, the
/// tracks read back from the round-tripped extras, and a regenerate that
/// resumes every track in its own phase.
final class ProgramCompositionTests: XCTestCase {

    private func composedProgram() throws -> GeneratedProgram {
        let json = """
        {"weeks": [
          {"week_number": 1, "week_in_phase": 1, "is_deload": false, "phase": "base", "phase_id": "transition",
           "schedule": {"Monday": [{"modality": "max_strength", "is_deload": false, "exercises": [],
                                    "lane_key": "starting_strength/texas_method", "phase": "build",
                                    "phase_id": "texas_method", "framework": "texas_method", "week_in_phase": 3}]},
           "lanes": [
             {"lane_key": "uphill_athlete/full_program", "track_id": "full_program", "phase": "base",
              "phase_id": "transition", "phase_name": "Transition", "week_in_phase": 1, "is_deload": false, "sessions": 4},
             {"lane_key": "starting_strength/texas_method", "track_id": "texas_method", "phase": "build",
              "phase_id": "texas_method", "week_in_phase": 3, "is_deload": false, "sessions": 3}]}],
         "composition": {"days": [1,2,3,4,5,6], "lanes": [
           {"key": "uphill_athlete/full_program", "kind": "contract", "philosophy_id": "uphill_athlete",
            "track_id": "full_program", "name": "Uphill Athlete", "weight": 0.6, "days": 4, "reserved_days": [2,4,6]},
           {"key": "starting_strength/texas_method", "kind": "contract", "philosophy_id": "starting_strength",
            "track_id": "texas_method", "name": "Starting Strength — Texas Method", "weight": 0.4, "days": 2,
            "reserved_days": [1,3,5]}]},
         "compromises": ["Uphill Athlete: General Strength 1 session a week fewer than the method's, to fit beside Starting Strength — Texas Method.",
                         "Uphill Athlete: Long Day: capped at your longest day."]}
        """
        return try JSONDecoder().decode(GeneratedProgram.self, from: Data(json.utf8))
    }

    func testACompositionRequestSendsItsTracks() throws {
        let request = GenerateProgramRequest(
            lanes: [ProgramLane(philosophyId: "uphill_athlete", trackId: nil, weight: 0.6, startPhase: "base"),
                    ProgramLane(philosophyId: "starting_strength", trackId: "texas_method", weight: 0.4)],
            constraints: GenerateConstraints(), numWeeks: 8, startDate: nil, eventDate: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let lanes = try XCTUnwrap(json["lanes"] as? [[String: Any]])
        XCTAssertEqual(lanes.count, 2)
        XCTAssertEqual(lanes[0]["philosophy_id"] as? String, "uphill_athlete")
        XCTAssertNil(lanes[0]["track_id"], "the level's track is the server's to pick")
        XCTAssertEqual(lanes[0]["start_phase"] as? String, "base")
        XCTAssertEqual(lanes[1]["track_id"] as? String, "texas_method")
        XCTAssertNil(json["philosophy_id"])
        XCTAssertEqual(request.sourceIds, ["uphill_athlete", "starting_strength"])
        XCTAssertEqual(request.sourceWeights["uphill_athlete"] ?? 0, 0.6, accuracy: 1e-9)
    }

    func testTheTracksAreReadBackFromTheProgram() throws {
        let program = try composedProgram()
        XCTAssertEqual(program.compositionLanes.map(\.key), ["uphill_athlete/full_program", "starting_strength/texas_method"])
        XCTAssertEqual(program.compositionLanes[1].reservedDays, [1, 3, 5])
        let week = try XCTUnwrap(program.weeks.first)
        XCTAssertEqual(week.lanes.map(\.phaseId), ["transition", "texas_method"])
        XCTAssertEqual(week.lanes[1].weekInPhase, 3)
        let session = try XCTUnwrap(week.schedule["Monday"]?.first)
        XCTAssertEqual(session.laneKey, "starting_strength/texas_method")
        XCTAssertEqual(session.lanePhaseId, "texas_method")
        XCTAssertEqual(session.laneFramework, "texas_method")
        // Only what a track gave up to fit beside the others, in its own words.
        XCTAssertEqual(program.cuts(of: program.compositionLanes[0]),
                       ["General Strength 1 session a week fewer than the method's, to fit beside Starting Strength — Texas Method."])
        // The extras round-trip: a save from the phone keeps the composition.
        let again = try JSONDecoder().decode(GeneratedProgram.self, from: JSONEncoder().encode(program))
        XCTAssertEqual(again.compositionLanes, program.compositionLanes)
    }

    func testARegenerateResumesEveryTrackInItsOwnPhase() throws {
        let lanes = try XCTUnwrap(try composedProgram().regenerateLanes(from: 0))
        XCTAssertEqual(lanes.map(\.startPhase), ["transition", "texas_method"])
        XCTAssertEqual(lanes.map(\.periodizationWeek), [1, 3])
        XCTAssertEqual(lanes.map(\.weight), [0.6, 0.4])
        let single = GeneratedProgram(weeks: [ProgramWeek(weekNumber: 1, weekInPhase: 1, isDeload: false,
                                                          phase: "base", schedule: [:])])
        XCTAssertNil(single.regenerateLanes(from: 0), "one track regenerates as before")
    }

    func testEveryTracksEntryRequirementsAreAsked() throws {
        let a = TrackEntryRequirements(trainingLevels: ["intermediate", "advanced"], masteredExercises: ["clean"],
                                       kettlebellCount: 1, startingLoads: [.init(id: "squat", name: "Squat")])
        let b = TrackEntryRequirements(trainingLevels: ["novice", "intermediate"], masteredExercises: ["press"],
                                       kettlebellCount: 2,
                                       startingLoads: [.init(id: "squat", name: "Squat"), .init(id: "deadlift", name: "Deadlift")])
        let merged = try XCTUnwrap(TrackEntryRequirements.merged([a, b], level: "intermediate"))
        XCTAssertEqual(merged.trainingLevels, ["intermediate"])
        XCTAssertEqual(merged.masteredExercises, ["clean", "press"])
        XCTAssertEqual(merged.kettlebellCount, 2)
        XCTAssertEqual(merged.startingLoads?.map(\.id), ["squat", "deadlift"])
        XCTAssertNil(TrackEntryRequirements.merged([], level: "intermediate"))
    }
}
