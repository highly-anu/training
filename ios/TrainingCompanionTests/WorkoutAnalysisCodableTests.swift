import XCTest
@testable import TrainingCompanion

/// `GET /health/workouts/<id>` carries the server's `analysis`
/// (src/analytics/workout_analysis.py); the detail screen shows it instead of
/// computing its own. The fixture is what the server returns for
/// data/workout_analysis_fixture.json's run at max HR 180
/// (test_workout_analysis.py).
final class WorkoutAnalysisCodableTests: XCTestCase {

    private let detail = """
    {"id": "w1", "source": "garmin", "date": "2026-10-01", "startTime": "2026-10-01T07:00:00Z",
     "endTime": "2026-10-01T08:00:00Z", "durationMinutes": 60, "activityType": "run",
     "heartRate": {"avg": 143, "max": 172, "samples": []}, "gpsTrack": null, "rawData": {},
     "analysis": {"version": 2, "maxHr": 180, "maxHrSource": "override",
       "zoneBoundaries": [0.65, 0.78, 0.87, 0.93], "zoneBoundariesSource": "shared",
       "zones": {"method": "samples", "pct": [0, 44, 31, 21, 4], "minutes": [0, 26.4, 18.6, 12.6, 2.4]},
       "trimp": 125, "trainingEffect": "Aerobic Capacity", "recoveryHours": 36,
       "decoupling": {"pct": 10.79, "label": "high"},
       "bestEfforts": [{"label": "1 km", "km": 1.0, "seconds": 310.0, "secPerKm": 310.0},
                       {"label": "5 km", "km": 5.0, "seconds": 1580.0, "secPerKm": 316.0}]}}
    """.data(using: .utf8)!

    func testDetailDecodesTheServersAnalysis() throws {
        let w = try JSONDecoder().decode(ImportedWorkout.self, from: detail)
        let a = try XCTUnwrap(w.analysis)
        XCTAssertEqual(a.maxHr, 180)
        XCTAssertEqual(a.distribution?.z2, 44)
        XCTAssertEqual(a.distribution?.method, "samples")
        XCTAssertEqual(a.trimp, 125)
        XCTAssertEqual(a.effect, .aerobicCapacity)
        XCTAssertEqual(a.recoveryHours, 36)
        XCTAssertEqual(a.decouplingResult?.label, "high")
        XCTAssertEqual(a.efforts.map(\.paceStr), ["5:10 /km", "5:16 /km"])
    }

    func testAWorkoutWithoutAnalysisStillDecodesAndEncodesWithoutIt() throws {
        let bare = """
        {"id": "w2", "source": "manual", "date": "2026-10-01", "activityType": "run"}
        """.data(using: .utf8)!
        let w = try JSONDecoder().decode(ImportedWorkout.self, from: bare)
        XCTAssertNil(w.analysis)
        let out = try JSONSerialization.jsonObject(with: JSONEncoder().encode(w)) as? [String: Any]
        XCTAssertNil(out?["analysis"], "the phone never sends an analysis back")
    }

    func testNoHeartRateMeansNoZones() throws {
        let json = """
        {"maxHr": 190, "maxHrSource": "default", "zoneBoundaries": [0.65, 0.78, 0.87, 0.93],
         "zones": null, "trimp": null, "trainingEffect": null, "recoveryHours": null,
         "decoupling": null, "bestEfforts": []}
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode(WorkoutAnalysis.self, from: json)
        XCTAssertNil(a.distribution)
        XCTAssertNil(a.effect)
        XCTAssertTrue(a.efforts.isEmpty)
    }
}

/// `GET /health/load/summary` (src/analytics/load_summary.py), decoded into
/// the models the Load section already draws.
final class LoadSummaryCodableTests: XCTestCase {
    private let json = """
    {"period": "30d", "from": "2026-09-13", "to": "2026-10-13", "maxHr": 190,
     "totals": {"sessions": 3, "minutes": 180.0, "distanceKm": 25.0, "elevationGainM": 100,
                "elevationLossM": 100, "calories": 600},
     "prior": {"sessions": 1, "minutes": 45.0, "distanceKm": 8.0, "elevationGainM": null,
               "elevationLossM": null, "calories": null},
     "modalities": [{"id": "aerobic_base", "minutes": 150.0, "pct": 83}, {"id": null, "minutes": 30.0, "pct": 17}],
     "activities": [{"activityType": "Running", "minutes": 150.0, "sessions": 2, "modalityId": "aerobic_base"}],
     "consistency": [{"weekStart": "2026-10-05", "sessions": 0}, {"weekStart": "2026-10-12", "sessions": 1}],
     "zones": {"minutes": [10, 80, 50, 8, 2], "workoutsMeasured": 1, "workoutsEstimated": 1},
     "focus28d": {"base": 90.0, "threshold": 50.0, "anaerobic": 10.0}}
    """.data(using: .utf8)!

    @MainActor func testDecodesIntoTheLoadSectionsModels() throws {
        let s = try JSONDecoder().decode(LoadSummary.self, from: json)
        XCTAssertEqual(s.stats.sessions, 3)
        XCTAssertEqual(s.stats.totalDistanceKm, 25)
        XCTAssertEqual(s.stats.prevMinutes, 45)
        XCTAssertEqual(s.loadFocus.total, 150)
        XCTAssertEqual(s.modalityShares.map(\.label), ["Aerobic Base", "Unclassified"])
        XCTAssertEqual(s.activityEntries.first?.hours, 2.5)
        XCTAssertEqual(s.consistencyEntries.map(\.sessionCount), [0, 1])
        XCTAssertEqual(LoadSummary.query(.all), "all")
        XCTAssertEqual(LoadSummary.query(.threeMonths), "3m")
    }
}
