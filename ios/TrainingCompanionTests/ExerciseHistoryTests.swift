import XCTest
@testable import TrainingCompanion

/// `GET /progression/exercises` on the phone: the Progress tab's exercise
/// cards. The fixture is the route's shape — history in the tracker's
/// snake_case, prescription and counts in camelCase.
final class ExerciseHistoryTests: XCTestCase {
    static let fixture = Data("""
    {"counts": {"inProgram": 3, "soFar": 2, "withData": 1},
     "exercises": [
       {"exerciseId": "back_squat", "name": "Back Squat", "metricType": "weight", "unit": "kg",
        "target": {"value": 105, "weekNumber": 2}, "scheduledSoFar": true,
        "expected": [{"week_number": 1, "week_index": 0, "expected_value": 102.5, "unit": "kg", "metric_type": "weight"}],
        "history": [
          {"date": "2026-10-12", "week_number": 1, "session_key": "1-Monday-0", "best_weight_kg": 100, "best_reps": 5,
           "duration_sec": null, "distance_km": null, "rounds_completed": null, "hr_avg": null, "hr_max": null},
          {"date": "2026-10-14", "week_number": 1, "session_key": "1-Wednesday-0", "best_weight_kg": 102.5, "best_reps": 5,
           "duration_sec": null, "distance_km": null, "rounds_completed": null, "hr_avg": 131, "hr_max": 160}]},
       {"exerciseId": "plank", "name": "Plank", "metricType": "time", "unit": "s",
        "target": {"value": 45, "weekNumber": 2}, "scheduledSoFar": true, "expected": [],
        "history": []},
       {"exerciseId": "run", "name": "Easy Run", "metricType": "time", "unit": "min", "target": null,
        "scheduledSoFar": false, "expected": [], "history": []},
       {"name": "no id"}]}
    """.utf8)

    func testDecodesHistoryPrescriptionAndCounts() throws {
        let r = try JSONDecoder().decode(ExerciseHistoryResponse.self, from: Self.fixture)
        XCTAssertEqual(r.exercises.map(\.exerciseId), ["back_squat", "plank", "run"], "a row without an id is dropped")
        XCTAssertEqual(r.resolvedCounts.soFar, 2)
        let squat = r.exercises[0]
        XCTAssertEqual(squat.target?.value, 105)
        XCTAssertEqual(squat.history.compactMap { $0.value(metric: "weight", unit: "kg") }, [100, 102.5])
        XCTAssertEqual(squat.history.last?.hrMax, 160)
        XCTAssertFalse(r.exercises[2].scheduledSoFar)
    }

    func testTimeReadsInTheUnitTheCardShows() throws {
        let point = try JSONDecoder().decode(ExerciseHistoryItem.Point.self,
                                             from: Data(#"{"duration_sec": 90}"#.utf8))
        XCTAssertEqual(point.value(metric: "time", unit: "s"), 90, "a hold in seconds")
        XCTAssertEqual(point.value(metric: "time", unit: "min"), 1.5, "a run in minutes")
    }

    func testCountsFallBackToTheRows() throws {
        let r = try JSONDecoder().decode(ExerciseHistoryResponse.self, from: Data("""
        {"exercises": [{"exerciseId": "a", "history": [{"best_weight_kg": 50}]}, {"exerciseId": "b", "scheduledSoFar": false}]}
        """.utf8))
        XCTAssertEqual(r.resolvedCounts.inProgram, 2)
        XCTAssertEqual(r.resolvedCounts.withData, 1)
        XCTAssertEqual(r.resolvedCounts.soFar, 1)
    }
}
