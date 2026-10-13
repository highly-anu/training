import XCTest
@testable import TrainingCompanion

/// Philosophies own their phases (server: src/phases.py). The phone decodes a
/// methodology's tracks, labels weeks with the methodology's own phase names,
/// keeps two phases of one kind apart, and resumes a regenerated tail in the
/// week's own track and phase.
final class PhaseTrackTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let wildman = #"""
    {"id": "wildman_kettlebell", "name": "Mark Wildman Kettlebell",
     "primary_track_id": "general_practice",
     "tracks": [
       {"id": "general_practice", "name": "General Practice", "description": "For the non-competitor.",
        "phases": [
          {"id": "foundations", "name": "Foundations", "kind": "base", "weeks": 6,
           "framework_id": "kb_general_practice", "focus": "Deadlift, swing and get-up groove",
           "description": "The bottom of the ladder.", "adaptations": ["Hinge mechanics"], "intensity": "Anti-glycolic"},
          {"id": "ladder", "name": "The Ladder", "kind": "build", "weeks": 6, "framework_id": "kb_general_practice"},
          {"id": "practice", "name": "Practice", "kind": "maintenance", "weeks": 4, "repeatable": true,
           "framework_id": "kb_general_practice"}]},
       {"id": "pentathlon", "name": "Pentathlon Prep",
        "phases": [
          {"id": "event_technique", "name": "Event Technique", "kind": "base", "weeks": 4, "framework_id": "kb_pentathlon"},
          {"id": "competition", "name": "Competition", "kind": "peak", "weeks": 2, "framework_id": "kb_pentathlon"}]}]}
    """#

    func testAPhilosophyDecodesItsTracksAndPhases() throws {
        let card = try decode(PhilosophyCard.self, wildman)
        XCTAssertEqual(card.tracks?.map(\.id), ["general_practice", "pentathlon"])
        XCTAssertEqual(card.primaryTrack?.id, "general_practice")
        XCTAssertEqual(card.track("pentathlon")?.name, "Pentathlon Prep")
        XCTAssertEqual(card.track("nope")?.id, "general_practice", "an unknown id falls back to the primary track")
        XCTAssertEqual(card.track(nil)?.totalWeeks, 16)
        let first = try XCTUnwrap(card.primaryTrack?.phases.first)
        XCTAssertEqual(first.name, "Foundations")
        XCTAssertEqual(first.kind, "base")
        XCTAssertEqual(first.frameworkId, "kb_general_practice")
        XCTAssertEqual(first.adaptations, ["Hinge mechanics"])
        XCTAssertEqual(card.primaryTrack?.phases.last?.repeatable, true)

        let old = try decode(PhilosophyCard.self, #"{"id": "x", "name": "X"}"#)
        XCTAssertNil(old.tracks, "a server that predates tracks still decodes")
        XCTAssertNil(old.primaryTrack)
    }

    private func week(_ n: Int, kind: String, phaseId: String? = nil, name: String? = nil,
                      track: String? = nil) throws -> ProgramWeek {
        var keys = [#""week_number": \#(n)"#, #""phase": "\#(kind)""#, #""schedule": {}"#]
        if let phaseId { keys.append(#""phase_id": "\#(phaseId)""#) }
        if let name { keys.append(#""phase_name": "\#(name)""#) }
        if let track { keys.append(#""track_id": "\#(track)""#) }
        return try decode(ProgramWeek.self, "{" + keys.joined(separator: ", ") + "}")
    }

    func testAWeekIsLabelledWithItsMethodologysPhaseName() throws {
        let w = try week(1, kind: "base", phaseId: "foundations", name: "Foundations", track: "general_practice")
        XCTAssertEqual(w.phaseLabel, "Foundations")
        XCTAssertEqual(w.phaseId, "foundations")
        XCTAssertEqual(w.trackId, "general_practice")
        XCTAssertEqual(w.phase, "base", "the kind stays the colour key")

        let old = try week(1, kind: "post_op")
        XCTAssertEqual(old.phaseLabel, "Post Op", "a week from before phase names shows its kind")
        XCTAssertNil(old.phaseId)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w)) as? [String: Any])
        XCTAssertEqual(json["phase_id"] as? String, "foundations", "the keys round-trip through a save")
        XCTAssertEqual(json["track_id"] as? String, "general_practice")
    }

    func testSegmentsKeepTwoPhasesOfOneKindApart() throws {
        let weeks = [
            try week(1, kind: "base", phaseId: "accumulation", name: "Accumulation"),
            try week(2, kind: "base", phaseId: "accumulation", name: "Accumulation"),
            try week(3, kind: "base", phaseId: "consolidation", name: "Consolidation"),
            try week(4, kind: "build", phaseId: "ladder", name: "The Ladder"),
        ]
        let segments = PhaseSegment.segments(of: weeks)
        XCTAssertEqual(segments.map(\.label), ["Accumulation", "Consolidation", "The Ladder"])
        XCTAssertEqual(segments.map(\.weekIndices), [[0, 1], [2], [3]])
        XCTAssertEqual(segments.map(\.kind), ["base", "base", "build"])
        XCTAssertEqual(Set(segments.map(\.id)).count, 3, "ids stay unique")

        let legacy = PhaseSegment.segments(of: [try week(1, kind: "base"), try week(2, kind: "base"),
                                                try week(3, kind: "build")])
        XCTAssertEqual(legacy.map(\.label), ["Base", "Build"], "weeks without ids group by kind")
    }

    func testATailRegenerateResumesInTheWeeksOwnTrackAndPhase() throws {
        let merged = ProgramConstraintsDiff.merged(
            program: ["training_phase": .string("base"), "days_per_week": .int(4)],
            profile: UserProfile.default, weekInPhase: 3, phase: "build",
            phaseId: "timed_sets", trackId: "pentathlon")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as? [String: Any])
        XCTAssertEqual(json["start_phase"] as? String, "timed_sets")
        XCTAssertEqual(json["track_id"] as? String, "pentathlon",
                       "without it the server falls back to the primary track")
        XCTAssertEqual(json["periodization_week"] as? Int, 3)
        XCTAssertEqual(json["training_phase"] as? String, "build", "the kind still goes, for older servers")

        let stored = ProgramConstraintsDiff.merged(
            program: ["track_id": .string("pentathlon")], profile: UserProfile.default,
            weekInPhase: 1, phase: "base")
        XCTAssertEqual(stored.trackId, "pentathlon", "the program's stored track when the week has none")
        XCTAssertNil(stored.startPhase)
    }

    func testAPlainRequestSendsNoTrackOrStartPhase() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(GenerateConstraints())) as? [String: Any])
        XCTAssertNil(json["track_id"], "nil is the primary track")
        XCTAssertNil(json["start_phase"], "nil is the track's first phase")
        XCTAssertNil(json["training_phase"], "no 'base' default")
    }

    func testTheAnalyticsPhaseUsesItsOwnName() throws {
        let named = try decode(ProgramAnalytics.Frame.Phase.self, #"""
        {"name": "build", "id": "ladder", "label": "The Ladder", "weekInPhase": 2, "weekInProgram": 8,
         "totalWeeks": 16, "focus": "Clean, press, snatch and jerk", "description": "Move up.", "isDeload": false}
        """#)
        XCTAssertEqual(named.displayName, "The Ladder")
        XCTAssertEqual(named.description, "Move up.")
        let old = try decode(ProgramAnalytics.Frame.Phase.self, #"""
        {"name": "post_op", "weekInPhase": 1, "weekInProgram": 1, "totalWeeks": 4, "focus": null, "isDeload": false}
        """#)
        XCTAssertEqual(old.displayName, "Post Op")
    }
}
