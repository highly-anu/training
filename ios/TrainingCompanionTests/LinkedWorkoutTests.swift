import XCTest
@testable import TrainingCompanion

/// `AppState.linkedWorkout(forSessionKey:)` — the workout a Today card's link
/// icon and the session detail's Recorded Workout section show. Async because
/// an `AppState` going out of scope must deinit inside a Task (see
/// `CurrentWeekIndexTests`).
@MainActor
final class LinkedWorkoutTests: XCTestCase {
    private func workout(_ id: String, minutes: Double = 40) -> ImportedWorkout {
        ImportedWorkout(id: id, source: "garmin", date: "2026-10-12", startTime: nil, endTime: nil,
                        durationMinutes: minutes, activityType: "KB Ballistic Power Session",
                        inferredModalityId: "power", heartRate: nil, calories: nil, distance: nil,
                        gpsTrack: nil, elevation: nil)
    }

    func testMatchLinksTheSession() async {
        let state = AppState()
        state.importedWorkouts = [workout("w1")]
        state.workoutMatches = ["w1": WorkoutMatch(workoutId: "w1", sessionKey: "4-Monday-0", confidence: "manual")]
        XCTAssertEqual(state.linkedWorkout(forSessionKey: "4-Monday-0")?.id, "w1")
        XCTAssertNil(state.linkedWorkout(forSessionKey: "4-Wednesday-0"))
    }

    func testEarlierProgramsMatchDoesNotLink() async {
        let state = AppState()
        state.importedWorkouts = [workout("old")]
        state.workoutMatches = ["old": WorkoutMatch(workoutId: "old", sessionKey: "4-Monday-0",
                                                    confidence: "auto", inCurrentProgram: false)]
        XCTAssertNil(state.linkedWorkout(forSessionKey: "4-Monday-0"))
    }

    func testSessionLogLinkIsTheFallback() async {
        let state = AppState()
        state.importedWorkouts = [workout("w2")]
        state.sessionLogs["4-Monday-0"] = SessionLogEntry(
            sessionKey: "4-Monday-0", completedAt: nil, source: nil, notes: nil,
            fatigueRating: nil, avgHR: nil, peakHR: nil, matchedWorkoutId: "w2")
        XCTAssertEqual(state.linkedWorkout(forSessionKey: "4-Monday-0")?.id, "w2")
    }

    func testLongestOfSeveralWins() async {
        let state = AppState()
        state.importedWorkouts = [workout("short", minutes: 10), workout("long", minutes: 50)]
        state.workoutMatches = [
            "short": WorkoutMatch(workoutId: "short", sessionKey: "4-Monday-0", confidence: "manual"),
            "long": WorkoutMatch(workoutId: "long", sessionKey: "4-Monday-0", confidence: "manual"),
        ]
        XCTAssertEqual(state.linkedWorkout(forSessionKey: "4-Monday-0")?.id, "long")
    }

    func testDecodesTheServersScopeFlag() throws {
        let json = #"[{"importedWorkoutId":"a","sessionKey":"6-Monday-0","matchConfidence":"auto","inCurrentProgram":false}]"#
        let records = try JSONDecoder().decode([WorkoutMatchRecord].self, from: Data(json.utf8))
        XCTAssertEqual(APIClient.matchesByWorkout(records)["a"]?.inCurrentProgram, false)
    }
}
