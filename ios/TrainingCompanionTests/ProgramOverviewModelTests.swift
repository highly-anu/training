import XCTest
@testable import TrainingCompanion

/// Program ▸ Overview's two readings of the stored program: the priority mix
/// as shares of `goal.priorities`, and each phase row's span of weeks.
final class ProgramOverviewModelTests: XCTestCase {

    func testPriorityMixIsSharesOfTheWeightsHeaviestFirst() {
        let extra: [String: JSONValue] = ["goal": .object(["priorities": .object([
            "aerobic_base": .double(0.6),
            "max_strength": .int(3),
            "mobility": .double(0),
            "durability": .double(0.6),
            "note": .string("not a weight"),
        ])])]
        let shares = ProgramPriorities.shares(from: extra)
        XCTAssertEqual(shares.map(\.id), ["max_strength", "aerobic_base", "durability"],
                       "heaviest first, ties by id, zero and non-numeric weights left out")
        XCTAssertEqual(shares.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
        XCTAssertEqual(shares.map(\.percent), [71, 14, 14])
    }

    func testPriorityMixIsEmptyWithoutAGoal() {
        XCTAssertEqual(ProgramPriorities.shares(from: nil), [])
        XCTAssertEqual(ProgramPriorities.shares(from: ["goal": .object([:])]), [])
        XCTAssertEqual(ProgramPriorities.shares(from: ["goal": .object(["priorities": .object(["mobility": .int(0)])])]), [])
    }

    func testOneModalityHoldsTheWholeMix() {
        let extra: [String: JSONValue] = ["goal": .object(["priorities": .object(["max_strength": .double(1)])])]
        XCTAssertEqual(ProgramPriorities.shares(from: extra), [.init(id: "max_strength", share: 1)])
    }

    func testAPhaseRowNamesItsWeeksByTheProgramsOwnNumbers() {
        // A program regenerated from an event date numbers its weeks absolutely.
        let weeks = (16...19).map { n in
            ProgramWeek(weekNumber: n, weekInPhase: 1, isDeload: false, phase: n < 19 ? "base" : "taper", schedule: [:])
        }
        let segments = PhaseSegment.segments(of: weeks)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].shortRange(in: weeks), "Wk 16–18")
        XCTAssertEqual(segments[0].range(in: weeks), "Weeks 16–18")
        XCTAssertEqual(segments[1].shortRange(in: weeks), "Wk 19")
        XCTAssertEqual(segments[1].range(in: weeks), "Week 19")
    }
}
