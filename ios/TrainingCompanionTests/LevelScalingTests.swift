import XCTest
@testable import TrainingCompanion

/// A prescription done at the athlete's share of what is written
/// (src/level_scaling.py): the server's `rx` and `scaled_from_name`, worded
/// as the web's lib/levelScaling.ts words them.
final class LevelScalingTests: XCTestCase {

    private func assignment(_ json: String) throws -> ProgramExerciseAssignment {
        try JSONDecoder().decode(ProgramExerciseAssignment.self, from: Data(json.utf8))
    }

    private let fran = """
    {"exercise": {"id": "thruster", "name": "Thruster"}, "slot_type": "for_time",
     "load": {"rep_scheme": [11, 8, 5], "target_rounds": 3, "weight_kg": 15.0,
              "rx": {"rep_scheme": [21, 15, 9], "weight_kg": 30.0},
              "level_scaled": {"level": "novice", "from": "elite",
                               "shares": {"load": 0.5, "volume": 0.5, "time": 0.5, "distance": 0.5},
                               "sources": {"load": "track", "volume": "track", "time": "track", "distance": "track"}}},
     "scaled_standard": "wod_fran_minutes"}
    """

    func testAScaledPrescriptionSaysTheLevelAndTheRx() throws {
        let ea = try assignment(fran)
        XCTAssertEqual(LoadFormat.describe(ea), "11-8-5 reps for time @ 15 kg")
        XCTAssertEqual(LoadFormat.scaledText(ea), "Scaled for Novice · Rx 21-15-9 reps · 30 kg")
        XCTAssertNil(LoadFormat.scaledFromText(ea))
    }

    func testAScaledMovementNamesWhatItStandsFor() throws {
        let ea = try assignment("""
        {"exercise": {"id": "jumping_pull_up", "name": "Jumping Pull-Up"}, "slot_type": "amrap_movement",
         "load": {"rep_scheme": [11, 8, 5]}, "scaled_from": "pull_up", "scaled_from_name": "Pull-Up (Overhand)",
         "scale_cause": "level"}
        """)
        XCTAssertEqual(LoadFormat.scaledFromText(ea), "In place of Pull-Up (Overhand)")
        XCTAssertNil(LoadFormat.scaledText(ea), "nothing scaled in the load")
    }

    func testATrackSaysWhenItIsScaledToTheAthlete() throws {
        let track = try JSONDecoder().decode(PhilosophyTrack.self, from: Data("""
        {"id": "t", "name": "T", "phases": [], "authored_level": "elite"}
        """.utf8))
        XCTAssertEqual(track.scaledFor(level: "novice"), "Written for Elite · scaled for Novice")
        XCTAssertNil(track.scaledFor(level: "elite"))
        let plain = try JSONDecoder().decode(PhilosophyTrack.self, from: Data(#"{"id": "t", "name": "T", "phases": []}"#.utf8))
        XCTAssertNil(plain.scaledFor(level: "novice"))
    }

    func testALadderAndAnIntervalSayWhatWasWritten() throws {
        let ladder = try assignment("""
        {"exercise": {"id": "bench_press", "name": "Bench Press"}, "slot_type": "sets_reps",
         "load": {"sets": 5, "reps": "13-10-8-5-3", "rx": {"reps": "25-20-15-10-5"},
                  "level_scaled": {"level": "novice", "from": "elite"}}}
        """)
        XCTAssertEqual(LoadFormat.scaledText(ladder), "Scaled for Novice · Rx 25-20-15-10-5 reps")
        let interval = try assignment("""
        {"exercise": {"id": "push_up", "name": "Push-Up"}, "slot_type": "emom",
         "load": {"target_rounds": 50, "work_sec": 30, "time_minutes": 25,
                  "rx": {"target_rounds": 100, "time_minutes": 50},
                  "level_scaled": {"level": "novice", "from": "elite"}}}
        """)
        XCTAssertEqual(LoadFormat.scaledText(interval), "Scaled for Novice · Rx 100 rounds · 50 min")
    }

    func testTheScaleSurvivesARoundTrip() throws {
        // The phone saves the program back through the revision-checked PUT:
        // what it does not model rides in `extra` and must come back intact.
        let ea = try assignment(fran)
        let again = try JSONDecoder().decode(ProgramExerciseAssignment.self, from: JSONEncoder().encode(ea))
        XCTAssertEqual(LoadFormat.scaledText(again), LoadFormat.scaledText(ea))
        XCTAssertEqual(again.extra["scaled_standard"], .string("wod_fran_minutes"))
    }
}
