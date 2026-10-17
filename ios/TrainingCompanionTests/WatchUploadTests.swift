import XCTest
@testable import TrainingCompanion

/// The watch upload goes through `POST /api/health/workouts` and
/// `POST /api/health/matches` now, not straight into Supabase. The server
/// reads the camelCase `ImportedWorkout` keys; a snake_case column name here
/// would be a silently dropped field, and nothing else would notice.
final class WatchUploadTests: XCTestCase {

    private func summary(gps: Bool = true) -> WatchWorkoutSummary {
        WatchWorkoutSummary(
            sessionId: "3-Tuesday-0", date: "2026-09-29",
            startedAt: "2026-09-29T06:30:00Z", endedAt: "2026-09-29T07:35:00Z",
            durationMinutes: 65, avgHR: 142, peakHR: 171,
            setLogs: ["back_squat": [WatchSetLog(setIndex: 0, repsActual: 5, weightKg: 100, rpe: 8,
                                                  completed: true, durationSeconds: 40,
                                                  startOffset: 600, endOffset: 640)]],
            exercisesCompleted: 1, source: "apple_watch_live",
            hrSamples: [HRSamplePoint(t: 0, b: 90), HRSamplePoint(t: 60, b: 131)],
            gpsTrack: gps ? [GPSTrackPoint(lat: 47.37, lng: 8.54, alt: 410, t: 0, b: 90),
                             GPSTrackPoint(lat: 47.38, lng: 8.55, alt: nil, t: 60, b: nil)] : nil,
            distanceMeters: 8400, elevationGainMeters: 120.6,
            cadenceAvg: nil, paceSecsPerKm: nil, exerciseTimeline: nil)
    }

    func testWorkoutIdIsTheHistoricFormula() {
        // workout_matches.imported_workout_id references ids minted this way —
        // colons percent-encoded, as every stored watch id has them.
        XCTAssertEqual(WatchUpload.workoutId(sessionKey: "3-Tuesday-0", startedAt: "2026-09-29T06:30:00Z"),
                       "watch_live_3-Tuesday-0_2026-09-29T06%3A30%3A00Z")
    }

    func testWorkoutPayloadUsesTheImportedWorkoutKeys() throws {
        let start = try XCTUnwrap(WatchUpload.parseStart("2026-09-29T06:30:00Z"))
        let w = WatchUpload.workoutPayload(summary: summary(), workoutId: "wid", startDate: start,
                                           sessionName: "Heavy/Light/Medium", modality: "max_strength")

        XCTAssertEqual(w["id"] as? String, "wid")
        XCTAssertEqual(w["source"] as? String, "apple_watch_live")
        XCTAssertEqual(w["date"] as? String, "2026-09-29")
        XCTAssertEqual(w["startTime"] as? String, "2026-09-29T06:30:00Z")
        XCTAssertEqual(w["endTime"] as? String, "2026-09-29T07:35:00Z", "workouts.end_time is NOT NULL")
        XCTAssertEqual(w["durationMinutes"] as? Int, 65)
        XCTAssertEqual(w["activityType"] as? String, "Heavy/Light/Medium")
        XCTAssertEqual(w["inferredModalityId"] as? String, "max_strength")

        let hr = try XCTUnwrap(w["heartRate"] as? [String: Any])
        XCTAssertEqual(hr["avg"] as? Int, 142)
        XCTAssertEqual(hr["max"] as? Int, 171)
        let samples = try XCTUnwrap(hr["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[1]["timestamp"] as? String, "2026-09-29T06:31:00Z")
        XCTAssertEqual(samples[1]["bpm"] as? Int, 131)

        let gps = try XCTUnwrap(w["gpsTrack"] as? [[String: Any]])
        XCTAssertEqual(gps[0]["altitude"] as? Double, 410)
        XCTAssertEqual(gps[0]["bpm"] as? Int, 90)
        XCTAssertNil(gps[1]["altitude"])
        XCTAssertEqual(gps[1]["timestamp"] as? String, "2026-09-29T06:31:00Z")

        let distance = try XCTUnwrap(w["distance"] as? [String: Any])
        XCTAssertEqual(distance["value"] as? Double, 8.4)
        XCTAssertEqual(distance["unit"] as? String, "km")
        let elevation = try XCTUnwrap(w["elevation"] as? [String: Any])
        XCTAssertEqual(elevation["gain"] as? Int, 120)
        XCTAssertEqual(elevation["loss"] as? Int, 0, "loss 0 is the server's cue to recompute from the track")

        for column in ["start_time", "duration_minutes", "activity_type", "hr_avg", "gps_track", "user_id"] {
            XCTAssertNil(w[column], "\(column) is a column, not a key the server reads")
        }
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: ["workouts": [w]]))
    }

    func testIndoorSessionSendsNoTrackOrDistance() throws {
        let start = try XCTUnwrap(WatchUpload.parseStart("2026-09-29T06:30:00Z"))
        let indoor = WatchWorkoutSummary(
            sessionId: "s", date: "2026-09-29", startedAt: "2026-09-29T06:30:00Z",
            endedAt: "2026-09-29T07:00:00Z", durationMinutes: 30, avgHR: nil, peakHR: nil,
            setLogs: [:], exercisesCompleted: 0, source: "apple_watch_live",
            hrSamples: nil, gpsTrack: nil, distanceMeters: nil, elevationGainMeters: nil,
            cadenceAvg: nil, paceSecsPerKm: nil, exerciseTimeline: nil)
        let w = WatchUpload.workoutPayload(summary: indoor, workoutId: "wid", startDate: start,
                                           sessionName: nil, modality: nil)
        XCTAssertNil(w["gpsTrack"]); XCTAssertNil(w["distance"]); XCTAssertNil(w["elevation"])
        XCTAssertNil(w["inferredModalityId"])
        XCTAssertEqual(w["activityType"] as? String, "apple_watch_live", "falls back to the source")
        let hr = try XCTUnwrap(w["heartRate"] as? [String: Any])
        XCTAssertNil(hr["avg"])
        XCTAssertEqual((hr["samples"] as? [[String: Any]])?.count, 0)
    }

    func testEnrichedUploadKeepsEverythingButTheTrackAndElevation() throws {
        let start = try XCTUnwrap(WatchUpload.parseStart("2026-09-29T06:30:00Z"))
        let original = WatchUpload.workoutPayload(summary: summary(), workoutId: "wid", startDate: start,
                                                  sessionName: "Long run", modality: "aerobic_base")
        let route: [[String: Any]] = (0..<50).map { i in
            ["lat": 47.0 + Double(i) * 0.001, "lng": 8.0, "timestamp": "2026-09-29T06:3\(i % 10):00Z", "altitude": 400.0 + Double(i)]
        }
        let enriched = WatchUpload.enriched(original, gpsTrack: route)

        XCTAssertEqual((enriched["gpsTrack"] as? [[String: Any]])?.count, 50)
        XCTAssertNil(enriched["elevation"], "dropped so the server recomputes gain and loss from the new track")
        // The server's upsert replaces every column: the first upload's heart
        // rate and name must travel again or they are wiped.
        XCTAssertEqual(enriched["id"] as? String, "wid")
        XCTAssertEqual(enriched["activityType"] as? String, "Long run")
        XCTAssertEqual(enriched["inferredModalityId"] as? String, "aerobic_base")
        XCTAssertEqual((enriched["heartRate"] as? [String: Any])?["avg"] as? Int, 142)
        XCTAssertEqual(((enriched["heartRate"] as? [String: Any])?["samples"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((enriched["distance"] as? [String: Any])?["value"] as? Double, 8.4)
    }

    /// The session log keeps what a step produced beside its sets — a 2 km
    /// row's clock, an AMRAP's rounds — and the Results answer, in the keys
    /// the server reads (src/standard_results.read_result).
    func testSessionLogCarriesOutcomesAndTheResultsAnswer() throws {
        var s = summary(gps: false)
        s.outcomes = ["row_2km_test": WatchOutcome(durationSec: 452), "pull_up": WatchOutcome(rounds: 19)]
        s.standardResults = ["row_2km_minutes": "save"]
        let log = WatchUpload.sessionLog(summary: s)
        let ex = try XCTUnwrap(log["exercises"] as? [String: [String: Any]])
        XCTAssertEqual(ex["row_2km_test"]?["durationSec"] as? Int, 452)
        XCTAssertEqual((ex["row_2km_test"]?["sets"] as? [Any])?.count, 0, "an outcome alone has no sets")
        XCTAssertEqual(ex["pull_up"]?["rounds"] as? Int, 19)
        let set = try XCTUnwrap((ex["back_squat"]?["sets"] as? [[String: Any]])?.first)
        XCTAssertEqual(set["repsActual"] as? Int, 5)
        XCTAssertEqual(set["completed"] as? Bool, true)
        XCTAssertEqual((log["standardResults"] as? [String: [String: String]])?["row_2km_minutes"]?["decision"], "save")
        XCTAssertEqual(log["sessionKey"] as? String, "3-Tuesday-0")
        XCTAssertNil(WatchUpload.sessionLog(summary: summary())["standardResults"], "no answer, no key")
    }

    /// A test step's value is read as the server reads it; a count entered
    /// on the watch is its one set.
    func testResultsReadLikeTheServer() {
        func ex(_ slot: String, _ kind: String) -> WatchExercise {
            WatchExercise(exerciseId: "x", name: "X", slotType: slot, slotRole: "r", isMeta: false,
                          loadDescription: "", loadNote: nil, coachingCue: nil, sets: nil, reps: nil, weightKg: 24,
                          targetRpe: nil, durationMinutes: 6, zoneTarget: nil, timeMinutes: nil, targetRounds: nil,
                          emomFormat: nil, holdSeconds: nil, distanceKm: nil, restSeconds: nil,
                          prescribedZoneLower: nil, prescribedZoneUpper: nil,
                          standard: WatchStandard(id: "s", name: "S", result: kind))
        }
        func set(_ reps: Int?, hold: Int? = nil) -> WatchSetLog {
            WatchSetLog(setIndex: 0, repsActual: reps, weightKg: nil, rpe: nil, completed: true,
                        durationSeconds: hold, startOffset: nil, endOffset: nil)
        }
        let row = ex("for_time", "duration")
        XCTAssertEqual(WatchResults.value(row, sets: [], outcome: WatchOutcome(durationSec: 452)), 452)
        XCTAssertEqual(WatchResults.text(row, value: 452), "7:32")
        XCTAssertNil(WatchResults.value(row, sets: [], outcome: nil))
        let clean = ex("time_domain", "reps")
        XCTAssertEqual(WatchResults.value(clean, sets: [set(70), set(32)], outcome: nil), 102, "reps in a window add up")
        XCTAssertEqual(WatchResults.text(clean, value: 102), "102 reps")
        XCTAssertEqual(WatchResults.value(ex("sets_reps", "reps"), sets: [set(12), set(9)], outcome: nil), 12)
        XCTAssertEqual(WatchResults.value(ex("static_hold", "hold"), sets: [set(nil, hold: 35), set(nil, hold: 42)],
                                          outcome: nil), 42)
        XCTAssertEqual(WatchResults.text(ex("amrap", "rounds"), value: 1), "1 round")
    }

    func testMatchPayloadIsAManualMatch() {
        let m = WatchUpload.matchPayload(workoutId: "wid", sessionKey: "3-Tuesday-0",
                                         matchedAt: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(m["importedWorkoutId"] as? String, "wid")
        XCTAssertEqual(m["sessionKey"] as? String, "3-Tuesday-0")
        XCTAssertEqual(m["matchConfidence"] as? String, "manual")
        XCTAssertEqual(m["matchedAt"] as? String, "2026-09-21T14:13:20Z")
        XCTAssertNil(m["imported_workout_id"])
    }

    private func listed(_ id: String, date: String = "2026-09-29", start: String) -> ImportedWorkout {
        ImportedWorkout(id: id, source: "garmin", date: date, startTime: start, endTime: nil,
                        durationMinutes: 65, activityType: "run", inferredModalityId: nil,
                        heartRate: nil, calories: nil, distance: nil, gpsTrack: nil, elevation: nil)
    }

    func testCanonicalIdIsTheUploadWhenListed() {
        let id = WatchUpload.canonicalId(for: "wid", date: "2026-09-29", startedAt: "2026-09-29T06:30:00Z",
                                         in: [listed("other", start: "2026-09-29T06:31:00Z"),
                                              listed("wid", start: "2026-09-29T06:30:00Z")])
        XCTAssertEqual(id, "wid")
    }

    func testCanonicalIdFollowsADedupFoldWithinFiveMinutes() {
        let id = WatchUpload.canonicalId(for: "wid", date: "2026-09-29", startedAt: "2026-09-29T06:30:00Z",
                                         in: [listed("far", start: "2026-09-29T05:00:00Z"),
                                              listed("garmin_copy", start: "2026-09-29T06:32:30Z"),
                                              listed("yesterday", date: "2026-09-28", start: "2026-09-28T06:30:00Z")])
        XCTAssertEqual(id, "garmin_copy")
    }

    func testCanonicalIdStandsWhenNothingIsListedOrNear() {
        XCTAssertEqual(WatchUpload.canonicalId(for: "wid", date: "2026-09-29", startedAt: "2026-09-29T06:30:00Z", in: []),
                       "wid", "a failed listing must not lose the match")
        XCTAssertEqual(WatchUpload.canonicalId(for: "wid", date: "2026-09-29", startedAt: "2026-09-29T06:30:00Z",
                                               in: [listed("far", start: "2026-09-29T07:00:00Z")]),
                       "wid")
    }

    func testParseStartAcceptsFractionalSeconds() {
        XCTAssertNotNil(WatchUpload.parseStart("2026-09-29T06:30:00Z"))
        XCTAssertNotNil(WatchUpload.parseStart("2026-09-29T06:30:00.250Z"))
        XCTAssertNil(WatchUpload.parseStart("yesterday"))
    }
}
