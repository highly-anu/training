import XCTest
@testable import TrainingCompanion

/// The facts on the builder's methodology cards (`/philosophies/glance`).
final class PhilosophyGlanceTests: XCTestCase {
    private func decode(_ json: String) throws -> PhilosophyGlance {
        try JSONDecoder().decode(PhilosophyGlance.self, from: Data(json.utf8))
    }

    func testFactsAreTheIdealOfEach() throws {
        let g = try decode("""
        {"id": "atg", "levels": ["novice"], "weeks": {"min": 4, "ideal": 12},
         "daysPerWeek": {"min": 3, "ideal": 3}, "sessionMinutes": {"min": 30, "ideal": 30},
         "mix": [{"modality": "durability", "share": 1.0}]}
        """)
        XCTAssertEqual(g.facts, ["12 wk", "3 days/wk", "30 min"])
    }

    func testAMissingFactIsLeftOut() throws {
        let g = try decode(#"{"id": "x", "weeks": {"min": 4, "ideal": null}, "daysPerWeek": {"ideal": 1}}"#)
        XCTAssertEqual(g.facts, ["1 day/wk"])
    }
}
