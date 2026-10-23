import XCTest
@testable import TrainingCompanion

/// Analytics ▸ Progress's one chart: `exerciseSeries` decoded on its own, and
/// `ProgressChartModel` lining it up as the web's `lib/progressChart.ts` does
/// (the same cases as `progressChart.test.ts`).
final class ProgressChartModelTests: XCTestCase {

    private let fixture = """
    {
      "status": "ok", "methodologies": [],
      "progress": [
        {"id": "rounds", "label": "Rounds", "primitive": "rounds", "philosophy": "p", "unit": "rounds",
         "series": [{"week": 1, "x": 1, "value": 7, "date": "2026-03-06", "isDeload": false}],
         "expected": [{"week": 1, "x": 1, "value": 8, "date": "2026-03-06"}, {"week": 2, "x": 2, "value": 8, "date": "2026-03-13"}],
         "status": "on_track", "coverage": {"inScope": 1, "measured": 1, "pct": 100, "reason": null}, "evidence": []},
        {"id": "ladder", "label": "Ladder", "primitive": "benchmark_level", "philosophy": "p", "unit": "level",
         "series": [], "expected": [], "status": "on_track", "evidence": []}
      ],
      "exerciseSeries": {
        "metrics": [{"id": "weight", "label": "Top set", "unit": "kg"}, {"id": "reps", "label": "Reps", "unit": "reps"}],
        "exercises": [
          {"exerciseId": "press", "name": "Press", "modality": "max_strength", "metrics": ["weight", "reps"],
           "defaultMetric": "weight", "scheduled": 1, "logged": 0, "points": []},
          {"exerciseId": "back_squat", "name": "Back squat", "modality": "max_strength", "metrics": ["weight", "reps"],
           "defaultMetric": "weight", "scheduled": 3, "logged": 1, "points": [
             {"date": "2026-03-02", "week": 1, "x": 1, "isDeload": false, "elapsed": true, "source": "log",
              "sessionName": "A", "done": {"weight": 100, "reps": 5, "rpe": null}, "prescribed": {"weight": 100, "reps": 5},
              "doneText": "100×5", "prescribedText": "3 × 5 @ 100 kg",
              "setsDone": [{"weightKg": 100, "reps": 5, "seconds": null, "rpe": null}]},
             {"date": "2026-03-09", "week": 2, "x": 2, "isDeload": true, "elapsed": true, "source": null,
              "sessionName": "A", "done": {}, "prescribed": {"weight": 80, "reps": 5}, "doneText": null,
              "prescribedText": "3 × 5 @ 80 kg", "setsDone": []},
             {"date": null, "week": 3, "x": 3, "isDeload": false, "elapsed": false, "source": null,
              "done": {}, "prescribed": {"weight": 105}, "setsDone": []}
          ]}
        ],
        "measures": [{"id": "rounds", "label": "Rounds", "unit": "rounds", "philosophy": "p", "primitive": "rounds"}]
      }
    }
    """

    private func doc(_ json: String? = nil) throws -> ProgramAnalytics {
        try JSONDecoder().decode(ProgramAnalytics.self, from: Data((json ?? fixture).utf8))
    }

    func testDecodesTheSection() throws {
        let d = try doc()
        let squat = try XCTUnwrap(d.exerciseSeries?.exercises.first { $0.exerciseId == "back_squat" })
        XCTAssertEqual(squat.points.count, 3)
        XCTAssertEqual(squat.points[0].done["weight"], 100)
        XCTAssertNil(squat.points[0].done["rpe"], "a null metric is dropped")
        XCTAssertEqual(squat.points[0].setsDone.first?.reps, 5)
        XCTAssertEqual(d.exerciseSeries?.metric("reps")?.unit, "reps")
        XCTAssertEqual(d.progress.first?.expected.last?.date, "2026-03-13", "expected points carry their day")
    }

    func testADocumentWithoutTheSectionStillDecodes() throws {
        let d = try doc(#"{"status": "ok", "methodologies": [], "progress": []}"#)
        XCTAssertNil(d.exerciseSeries)
        XCTAssertNil(ProgressChartModel.resolve(in: d))
        let failed = try doc(#"{"status": "ok", "methodologies": [], "progress": [], "exerciseSeries": {"error": "boom"}}"#)
        XCTAssertNil(failed.exerciseSeries)
        XCTAssertEqual(failed.sectionErrors["exerciseSeries"], "boom")
    }

    func testSelection() throws {
        let d = try doc()
        XCTAssertEqual(ProgressChartModel.resolve(in: d), .exercise(id: "back_squat", metric: "weight"),
                       "the first logged exercise, at its default metric")
        XCTAssertEqual(ProgressChartModel.resolve(exercise: "press", metric: "reps", in: d), .exercise(id: "press", metric: "reps"))
        XCTAssertEqual(ProgressChartModel.resolve(exercise: "press", metric: "distance", in: d), .exercise(id: "press", metric: "weight"),
                       "a metric the exercise lacks falls back to its default")
        XCTAssertEqual(ProgressChartModel.resolve(measure: "rounds", in: d), .measure(id: "rounds"))
        XCTAssertEqual(ProgressChartModel.resolve(measure: "ladder", in: d), .exercise(id: "back_squat", metric: "weight"),
                       "a measure the server does not name is not drawn")
    }

    func testExerciseSeriesIsDoneAgainstPrescribed() throws {
        let s = try XCTUnwrap(ProgressChartModel.series(.exercise(id: "back_squat", metric: "weight"), in: try doc()))
        XCTAssertEqual(s.unit, "kg")
        XCTAssertEqual(s.plannedLabel, "Prescribed")
        XCTAssertEqual(s.points.map(\.done), [100, nil], "a point without a day is left off")
        XCTAssertEqual(s.points.map(\.planned), [100, 80])
        XCTAssertTrue(s.points[1].isDeload)
    }

    func testMeasureSeriesIsJoinedBySession() throws {
        let s = try XCTUnwrap(ProgressChartModel.series(.measure(id: "rounds"), in: try doc()))
        XCTAssertEqual(s.plannedLabel, "Expected")
        XCTAssertEqual(s.points.map(\.done), [7, nil])
        XCTAssertEqual(s.points.map(\.planned), [8, 8])
    }
}
