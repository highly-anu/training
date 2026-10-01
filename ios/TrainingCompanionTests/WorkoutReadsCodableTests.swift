import XCTest
@testable import TrainingCompanion

/// The phone reads workouts and matches from `GET /health/snapshot` and
/// `GET /health/workouts/<id>` now, not from PostgREST. These fixtures mirror
/// `health_store._row_to_workout` (summary and full) and `get_matches`.
final class WorkoutReadsCodableTests: XCTestCase {

    private let snapshot = """
    {
      "workouts": [
        {"id": "w1", "source": "garmin", "date": "2026-09-29", "startTime": "2026-09-29 06:30:00+00:00",
         "endTime": "2026-09-29 07:35:00+00:00", "durationMinutes": 65, "activityType": "run",
         "inferredModalityId": "aerobic_base",
         "heartRate": {"avg": 142, "max": 171, "min": 88, "samples": []},
         "calories": 612, "distance": {"value": 8.4, "unit": "km"}, "gpsTrack": null,
         "elevation": {"gain": 120, "loss": 118}, "rawData": {}},
        {"id": "w2", "source": "apple_watch_live", "date": "2026-09-28", "startTime": "2026-09-28 17:00:00+00:00",
         "endTime": "2026-09-28 18:00:00+00:00", "durationMinutes": 60.0, "activityType": "Heavy/Light/Medium",
         "inferredModalityId": null,
         "heartRate": {"avg": 131.0, "max": 160.0, "min": null, "samples": []},
         "calories": null, "distance": null, "gpsTrack": null, "elevation": null, "rawData": {}},
        {"id": 42, "source": "broken"}
      ],
      "matches": [
        {"importedWorkoutId": "w1", "sessionKey": "3-Monday-0", "sessionUid": "v1:w2-Monday-0",
         "matchConfidence": "auto", "matchedAt": "2026-09-29 08:00:00"},
        {"importedWorkoutId": "w2", "sessionKey": "2-Sunday-0", "sessionUid": null,
         "matchConfidence": 1.0, "matchedAt": "2026-09-28 18:01:00"},
        {"importedWorkoutId": "w3", "sessionKey": "1-Friday-0", "sessionUid": null,
         "matchConfidence": "rejected", "matchedAt": "2026-09-27 10:00:00"}
      ],
      "sessionLogs": [], "dailyBio": [],
      "performanceLogs": {"back_squat_1rm": [{"value": 140, "date": "2026-09-01"}]}
    }
    """.data(using: .utf8)!

    func testSnapshotListsSummariesAndDropsOnlyTheMalformedRow() throws {
        let s = try JSONDecoder().decode(APIClient.HealthSnapshot.self, from: snapshot)
        XCTAssertEqual(s.workouts.map(\.id), ["w1", "w2"], "a bad row is dropped, not the list")
        let w1 = s.workouts[0]
        XCTAssertEqual(w1.durationMinutes, 65)
        XCTAssertEqual(w1.heartRate?.avg, 142)
        XCTAssertEqual(w1.heartRate?.samples.count, 0, "a summary carries no samples")
        XCTAssertNil(w1.gpsTrack, "the track is fetched on demand")
        XCTAssertEqual(w1.distance?.value, 8.4)
        XCTAssertEqual(w1.elevation?.loss, 118)
        XCTAssertEqual(w1.inferredModalityId, "aerobic_base")
        let w2 = s.workouts[1]
        XCTAssertEqual(w2.heartRate?.avg, 131, "142.0-style numbers decode as whole beats")
        XCTAssertEqual(w2.heartRate?.max, 160)
        XCTAssertNil(w2.calories)
        XCTAssertNil(w2.inferredModalityId)
        XCTAssertEqual(s.performanceLogs["back_squat_1rm"]?.first?.value, 140)
    }

    func testMatchesKeyByWorkoutAndSkipRejected() throws {
        let s = try JSONDecoder().decode(APIClient.HealthSnapshot.self, from: snapshot)
        XCTAssertEqual(s.matches.count, 3)
        XCTAssertEqual(s.matches[1].matchConfidence, "1.0", "a numeric confidence reads as a string")
        XCTAssertEqual(s.matches[0].sessionUid, "v1:w2-Monday-0")
        let byWorkout = APIClient.matchesByWorkout(s.matches)
        XCTAssertEqual(byWorkout["w1"]?.sessionKey, "3-Monday-0")
        XCTAssertEqual(byWorkout["w1"]?.confidence, "auto")
        XCTAssertEqual(byWorkout["w2"]?.sessionKey, "2-Sunday-0")
        XCTAssertNil(byWorkout["w3"], "rejected is a decision, not a match")
    }

    func testAnEmptyOrPartialSnapshotStillDecodes() throws {
        let s = try JSONDecoder().decode(APIClient.HealthSnapshot.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(s.workouts.count, 0)
        XCTAssertEqual(s.matches.count, 0)
        XCTAssertEqual(s.performanceLogs.count, 0)
    }

    func testFullWorkoutDecodesTrackAndSamples() throws {
        let json = """
        {"id": "w1", "source": "fit_file", "date": "2026-09-29", "startTime": "2026-09-29 06:30:00+00:00",
         "endTime": "2026-09-29 07:35:00+00:00", "durationMinutes": 65, "activityType": "run",
         "inferredModalityId": null,
         "heartRate": {"avg": 142, "max": 171, "min": 88,
                       "samples": [{"timestamp": "2026-09-29T06:30:00Z", "bpm": 90},
                                   {"timestamp": "2026-09-29T06:31:00Z", "bpm": 131},
                                   {"timestamp": "bad"}]},
         "calories": 612, "distance": {"value": 8.4, "unit": "km"},
         "gpsTrack": [{"lat": 47.37, "lng": 8.54, "timestamp": "2026-09-29T06:30:00Z", "altitude": 410.5, "bpm": 90},
                      {"lat": 47.38, "lng": 8.55, "timestamp": "2026-09-29T06:31:00Z"}],
         "elevation": {"gain": 120, "loss": 118}, "rawData": {"sport": "running"}}
        """.data(using: .utf8)!
        let w = try JSONDecoder().decode(ImportedWorkout.self, from: json)
        XCTAssertEqual(w.gpsTrack?.count, 2)
        XCTAssertEqual(w.gpsTrack?[0].altitude, 410.5)
        XCTAssertEqual(w.gpsTrack?[0].bpm, 90)
        XCTAssertNil(w.gpsTrack?[1].altitude)
        XCTAssertEqual(w.heartRate?.samples.count, 2, "a sample without a bpm is dropped, the rest kept")
        XCTAssertEqual(w.heartRate?.samples[1].bpm, 131)
    }
}
