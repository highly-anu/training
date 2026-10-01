import XCTest
@testable import TrainingCompanion

/// Session logging on the phone: the fields a slot type offers (the web's
/// table), the payload the server merges, what reads back, and the session
/// deep link the detail screen is reached through.
final class SessionLoggingTests: XCTestCase {

    func testOutcomeFieldsMirrorTheWebsTable() {
        XCTAssertEqual(SessionLogging.outcomeFields(for: "time_domain"), [.minutes, .km])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "skill_practice"), [.minutes])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "for_time"), [.minutes])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "distance"), [.km, .minutes])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "amrap"), [.rounds, .reps])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "emom"), [.rounds])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "rounds_for_time"), [.minutes, .rounds])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "amrap_movement"), [.reps])
        XCTAssertEqual(SessionLogging.outcomeFields(for: "sets_reps"), [])
        XCTAssertEqual(SessionLogging.outcomeFields(for: nil), [])
        XCTAssertTrue(SessionLogging.logsSets("sets_reps"))
        XCTAssertTrue(SessionLogging.logsSets("static_hold"))
        XCTAssertFalse(SessionLogging.logsSets("amrap"))
    }

    func testPerformanceEncodesTheKeysTheEngineReads() throws {
        let perf = ExercisePerformanceLog(
            sets: [WatchSetLog(setIndex: 0, repsActual: 5, weightKg: 80, rpe: 8, completed: true,
                               durationSeconds: nil, startOffset: nil, endOffset: nil)],
            rounds: nil, durationSec: 1800, distanceKm: 8.4)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(perf)) as? [String: Any])
        let set = try XCTUnwrap((json["sets"] as? [[String: Any]])?.first)
        XCTAssertEqual(set["setIndex"] as? Int, 0)
        XCTAssertEqual(set["repsActual"] as? Int, 5)
        XCTAssertEqual(set["weightKg"] as? Double, 80)
        XCTAssertEqual(set["rpe"] as? Int, 8)
        XCTAssertEqual(set["completed"] as? Bool, true)
        XCTAssertEqual(json["durationSec"] as? Int, 1800)
        XCTAssertEqual(json["distanceKm"] as? Double, 8.4)
        XCTAssertNil(json["rounds"], "nil is omitted, not sent as null")
        XCTAssertNil(json["duration_sec"], "camelCase, as the web writes and progression_tracker reads")
    }

    func testRecentLogRowDecodesWithItsExercises() throws {
        let row = """
        {"session_key": "2-Monday-0", "session_uid": "v1:w1-Monday-0", "completed_at": "2026-09-28 18:00:00",
         "source": "manual", "notes": "", "fatigue_rating": null, "avg_hr": 131.0, "peak_hr": 160,
         "matched_workout_id": null,
         "exercises": {
           "back_squat": {"sets": [{"setIndex": 0, "repsActual": 5, "weightKg": 80.0, "completed": true},
                                   {"setIndex": 1, "repsActual": "five", "completed": true},
                                   {"setIndex": 2, "repsActual": 4, "weightKg": 82.5, "rpe": 9, "completed": true}]},
           "run_easy": {"sets": [], "durationSec": 1800.0, "distanceKm": 5.2},
           "broken": "not an object"
         }}
        """.data(using: .utf8)!
        let entry = try JSONDecoder().decode(SessionLogEntry.self, from: row)
        XCTAssertEqual(entry.exercises.count, 2, "a malformed exercise is dropped, not the row")
        let squat = try XCTUnwrap(entry.exercises["back_squat"])
        XCTAssertEqual(squat.sets.count, 2, "a set whose reps are not a number is dropped")
        XCTAssertEqual(squat.sets.last?.weightKg, 82.5)
        XCTAssertEqual(entry.exercises["run_easy"]?.durationSec, 1800, "1800.0 reads as whole seconds")
        XCTAssertEqual(entry.exercises["run_easy"]?.distanceKm, 5.2)
        XCTAssertEqual(entry.completedAt, "2026-09-28 18:00:00")

        let legacy = try JSONDecoder().decode(SessionLogEntry.self,
                                              from: #"{"session_key": "1-Monday-0", "completed_at": null}"#.data(using: .utf8)!)
        XCTAssertEqual(legacy.exercises.count, 0, "a row without exercises still decodes")
    }

    func testSummariesReadBack() {
        func set(_ i: Int, _ reps: Int?, _ kg: Double?, done: Bool = true, secs: Int? = nil) -> WatchSetLog {
            WatchSetLog(setIndex: i, repsActual: reps, weightKg: kg, rpe: nil, completed: done,
                        durationSeconds: secs, startOffset: nil, endOffset: nil)
        }
        XCTAssertEqual(SessionLogging.summary(ExercisePerformanceLog(sets: [set(0, 5, 80), set(1, 5, 80), set(2, 5, 80)]),
                                              slotType: "sets_reps"), "3 sets · 3×5 @ 80 kg")
        XCTAssertEqual(SessionLogging.summary(ExercisePerformanceLog(sets: [set(0, 5, 80), set(1, 5, 82.5), set(2, 4, 82.5)]),
                                              slotType: "sets_reps"), "3 sets · 5×80, 5×82.5, 4×82.5 kg")
        XCTAssertEqual(SessionLogging.summary(ExercisePerformanceLog(sets: [set(0, 8, nil), set(1, 8, nil, done: false)]),
                                              slotType: "sets_reps"), "1 set · 1×8")
        XCTAssertNil(SessionLogging.summary(ExercisePerformanceLog(sets: [set(0, 5, 80, done: false)]), slotType: "sets_reps"))
        XCTAssertEqual(SessionLogging.summary(ExercisePerformanceLog(sets: [set(0, nil, nil, secs: 30), set(1, nil, nil, secs: 30)]),
                                              slotType: "static_hold"), "2×30 s hold")
        XCTAssertEqual(SessionLogging.summary(ExercisePerformanceLog(durationSec: 1920, distanceKm: 8.4), slotType: "time_domain"),
                       "32 min · 8.4 km")
        XCTAssertEqual(SessionLogging.summary(ExercisePerformanceLog(sets: [set(0, 48, nil)], rounds: 7), slotType: "amrap"),
                       "7 rounds · 48 reps")
        XCTAssertNil(SessionLogging.summary(ExercisePerformanceLog(), slotType: "amrap"))
    }

    func testSessionDeepLink() {
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://session?key=2-Monday-0")!), .session("2-Monday-0"))
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://session")!), .tab(.dashboard))
    }

    @MainActor
    func testLocateSessionByKeyAndLogIntoAFreshEntry() async throws {
        let appState = AppState()
        appState.serverProgram = try JSONDecoder().decode(ServerProgram.self, from: """
        {"currentProgram": {"weeks": [
            {"week_number": 1, "is_deload": false, "phase": "base", "schedule": {"Monday": [{"modality": "max_strength", "exercises": []}]}},
            {"week_number": 2, "is_deload": false, "phase": "base", "schedule": {
                "Monday": [{"modality": "max_strength", "exercises": [{"exercise": {"id": "back_squat", "name": "Back Squat"}, "load": {"sets": 3, "reps": 5}}]}],
                "Wednesday": [{"modality": "aerobic_base", "exercises": []}, {"modality": "mobility", "exercises": []}]
            }}
        ]}, "programStartDate": "2026-09-21", "sourceGoalIds": ["starting_strength"]}
        """.data(using: .utf8)!)

        let found = try XCTUnwrap(appState.locateSession(key: "2-Wednesday-1"))
        XCTAssertEqual(found.weekIndex, 1)
        XCTAssertEqual(found.dayName, "Wednesday")
        XCTAssertEqual(found.sessionIndex, 1)
        XCTAssertEqual(found.session.modality, "mobility")
        XCTAssertNil(appState.locateSession(key: "9-Monday-0"))

        let perf = ExercisePerformanceLog(sets: [WatchSetLog(setIndex: 0, repsActual: 5, weightKg: 80, rpe: nil, completed: true,
                                                             durationSeconds: nil, startOffset: nil, endOffset: nil)])
        await appState.logExercise(sessionKey: "2-Monday-0", exerciseId: "back_squat", performance: perf)
        let entry = try XCTUnwrap(appState.sessionLogs["2-Monday-0"])
        XCTAssertNil(entry.completedAt, "logging a set does not complete the session")
        XCTAssertEqual(entry.exercises["back_squat"], perf)
        XCTAssertFalse(appState.isSessionComplete("2-Monday-0"))
    }
}
