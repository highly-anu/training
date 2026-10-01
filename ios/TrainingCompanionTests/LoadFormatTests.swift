import XCTest
@testable import TrainingCompanion

/// The one prescription formatter. The session sheet and the swap sheet both
/// print it, so a change here is visible in both — which is the point.
final class LoadFormatTests: XCTestCase {

    private func assignment(_ json: String) throws -> ProgramExerciseAssignment {
        try JSONDecoder().decode(ProgramExerciseAssignment.self, from: Data(json.utf8))
    }

    func testSetsAndRepsWithLoad() throws {
        XCTAssertEqual(LoadFormat.describe(try assignment("""
        {"exercise": {"id": "s", "name": "S"}, "slot_type": "sets_reps", "load": {"sets": 3, "reps": 5, "weight_kg": 80.0}}
        """)), "3×5 @ 80 kg", "a whole number never shows .0")
        XCTAssertEqual(LoadFormat.describe(try assignment("""
        {"exercise": {"id": "s", "name": "S"}, "slot_type": "sets_reps", "load": {"sets": 3, "reps": "8-10", "weight_kg": 82.5}}
        """)), "3×8-10 @ 82.5 kg")
        XCTAssertEqual(LoadFormat.describe(try assignment("""
        {"exercise": {"id": "s", "name": "S"}, "slot_type": "sets_reps", "load": {"sets": 4, "reps": 6, "target_rpe": 8}}
        """)), "4×6 @ RPE 8")
    }

    func testTimeRoundsAndHolds() throws {
        XCTAssertEqual(LoadFormat.describe(try assignment("""
        {"exercise": {"id": "r", "name": "R"}, "slot_type": "time_domain", "load": {"duration_minutes": 45, "zone_target": "Z2"}}
        """)), "45 min · Z2")
        XCTAssertEqual(LoadFormat.describe(try assignment("""
        {"exercise": {"id": "a", "name": "A"}, "slot_type": "amrap", "load": {"time_minutes": 12}}
        """)), "AMRAP 12 min")
        XCTAssertEqual(LoadFormat.describe(try assignment("""
        {"exercise": {"id": "h", "name": "H"}, "slot_type": "static_hold", "load": {"sets": 3, "hold_seconds": 30}}
        """)), "3×30s hold")
        XCTAssertEqual(LoadFormat.describe(try assignment("""
        {"exercise": {"id": "e", "name": "E"}, "slot_type": "emom", "load": {"time_minutes": 10, "target_rounds": 10}}
        """)), "10 min · 10 rounds")
    }

    func testSlotTypeIsInferredWhenAnArchetypeOmitsIt() throws {
        let distance = try assignment("""
        {"exercise": {"id": "d", "name": "D"}, "load": {"distance_km": 5.0}}
        """)
        XCTAssertEqual(LoadFormat.resolvedSlotType(distance), "distance")
        XCTAssertEqual(LoadFormat.describe(distance), "5 km")
        let plain = try assignment("""
        {"exercise": {"id": "p", "name": "P"}, "load": {"sets": 5, "reps": 5}}
        """)
        XCTAssertEqual(LoadFormat.resolvedSlotType(plain), "sets_reps")
        XCTAssertEqual(LoadFormat.describe(plain), "5×5")
    }

    func testSlotTypeLabels() {
        XCTAssertEqual(LoadFormat.slotTypeLabel("sets_reps"), "Sets × Reps")
        XCTAssertEqual(LoadFormat.slotTypeLabel("for_time"), "For Time")
        XCTAssertEqual(LoadFormat.slotTypeLabel("something_new"), "something_new")
    }
}
