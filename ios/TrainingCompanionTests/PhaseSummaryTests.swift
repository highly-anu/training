import XCTest
@testable import TrainingCompanion

/// `currentProgram.phase_summary` on the phone: read from the program's
/// extras, one bad entry dropped alone, matched to phase segments by order.
final class PhaseSummaryTests: XCTestCase {

    private let fixture = """
    {
      "weeks": [
        {"week_number": 3, "week_in_phase": 1, "is_deload": false, "phase": "base", "phase_id": "base", "schedule": {}},
        {"week_number": 4, "week_in_phase": 1, "is_deload": false, "phase": "build", "phase_id": "build", "schedule": {}}
      ],
      "phase_summary": [
        {"phase_id": "base", "name": "Base", "kind": "base", "week_start": 3, "week_end": 3, "weeks": 1,
         "sessions_per_week": {"aerobic_base": 2.0, "max_strength": 1.5},
         "minutes_per_week": {"first": 300, "last": 330, "mean": 315},
         "archetypes": [{"id": "z2", "name": "Zone 2", "modality": "aerobic_base", "sessions": 2, "status": null}],
         "exercises": [], "lifts": [{"id": "back_squat", "name": "Back Squat", "first_kg": 100, "last_kg": 107.5}],
         "dropped": {"archetypes": [], "exercises": []}, "changes": []},
        {"phase_id": "build", "name": "Build", "kind": "build", "week_start": 4, "week_end": 4, "weeks": 2,
         "sessions_per_week": {"anaerobic_intervals": 1},
         "archetypes": [{"id": "z2", "name": "Zone 2", "modality": "aerobic_base", "sessions": 3, "status": "continued"},
                        {"id": "ant", "name": "AnT Intervals", "modality": "anaerobic_intervals", "sessions": 2, "status": "new"}],
         "dropped": {"archetypes": [{"id": "lift", "name": "Gym Strength", "modality": "max_strength"}]},
         "changes": ["Anaerobic intervals enters, 1×/week"]},
        {"name": "missing its id"}
      ]
    }
    """

    private func program() throws -> GeneratedProgram {
        try JSONDecoder().decode(GeneratedProgram.self, from: Data(fixture.utf8))
    }

    func testReadsTheSummaryFromTheProgramExtras() throws {
        let list = PhaseSummary.list(from: try program().extra)
        XCTAssertEqual(list.map(\.phaseId), ["base", "build"], "the malformed entry drops alone")
        let base = list[0]
        XCTAssertEqual(base.minutesMean, 315)
        XCTAssertEqual(base.shape.first?.modality, "aerobic_base")
        XCTAssertEqual(base.lifts.first?.lastKg, 107.5)
        XCTAssertNil(base.archetypes.first?.status)
    }

    func testMissingKeysDecodeEmpty() throws {
        let build = PhaseSummary.list(from: try program().extra)[1]
        XCTAssertEqual(build.minutesMean, 0)
        XCTAssertTrue(build.exercises.isEmpty)
        XCTAssertTrue(build.dropped.exercises.isEmpty)
        XCTAssertEqual(build.newArchetypes.map(\.id), ["ant"])
        XCTAssertEqual(build.dropped.archetypes.map(\.name), ["Gym Strength"])
        XCTAssertEqual(build.changes, ["Anaerobic intervals enters, 1×/week"])
    }

    func testPerWeekDividesByThePhaseLength() throws {
        let build = PhaseSummary.list(from: try program().extra)[1]
        XCTAssertEqual(build.perWeek("z2"), 1.5)
        XCTAssertNil(build.perWeek("lift"))
    }

    func testSegmentsMatchByOrderOnlyWhenTheCountsAgree() throws {
        let p = try program()
        let list = PhaseSummary.list(from: p.extra)
        let segments = PhaseSegment.segments(of: p.weeks)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(PhaseSummary.forSegment(1, of: list, segmentCount: segments.count)?.phaseId, "build")
        XCTAssertNil(PhaseSummary.forSegment(0, of: list, segmentCount: 3))
    }

    func testAProgramWithoutASummaryReadsEmpty() {
        XCTAssertTrue(PhaseSummary.list(from: [:]).isEmpty)
        XCTAssertTrue(PhaseSummary.list(from: nil).isEmpty)
    }
}
