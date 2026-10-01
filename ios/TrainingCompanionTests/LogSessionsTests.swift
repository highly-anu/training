import XCTest
@testable import TrainingCompanion

/// Log ▸ Sessions: what was logged across planned sessions, newest first.
final class LogSessionsTests: XCTestCase {

    private func entry(_ key: String, completedAt: String?, source: String? = "manual",
                       exercises: [String: ExercisePerformanceLog] = [:]) -> SessionLogEntry {
        SessionLogEntry(sessionKey: key, completedAt: completedAt, source: source, notes: nil,
                        fatigueRating: nil, avgHR: nil, peakHR: nil, matchedWorkoutId: nil, exercises: exercises)
    }

    private func set(_ reps: Int, _ kg: Double) -> WatchSetLog {
        WatchSetLog(setIndex: 0, repsActual: reps, weightKg: kg, rpe: nil, completed: true,
                    durationSeconds: nil, startOffset: nil, endOffset: nil)
    }

    func testServerTimestampsParse() {
        XCTAssertNotNil(LogSessions.parseServerDate("2026-09-28 18:00:00+02:00"), "Postgres str() form")
        XCTAssertNotNil(LogSessions.parseServerDate("2026-09-28T18:00:00Z"))
        XCTAssertNotNil(LogSessions.parseServerDate("2026-09-28T18:00:00.250Z"))
        XCTAssertNil(LogSessions.parseServerDate(nil))
        XCTAssertNil(LogSessions.parseServerDate("yesterday"))
    }

    func testRowsAreNewestFirstAndSayWhatWasLogged() throws {
        let program = try JSONDecoder().decode(ServerProgram.self, from: """
        {"currentProgram": {"weeks": [
            {"week_number": 2, "is_deload": false, "phase": "base", "schedule": {
                "Monday": [{"modality": "max_strength", "archetype": {"id": "hlm", "name": "Heavy/Light/Medium"},
                            "exercises": [{"exercise": {"id": "back_squat", "name": "Back Squat"}, "slot_type": "sets_reps", "load": {"sets": 3, "reps": 5}},
                                          {"exercise": {"id": "run_easy", "name": "Easy Run"}, "slot_type": "time_domain", "load": {"duration_minutes": 30}}]}]
            }}
        ]}, "programStartDate": "2026-09-21", "sourceGoalIds": ["starting_strength"]}
        """.data(using: .utf8)!)
        let state = ServerProgramHolder(program)

        let logs = [
            entry("2-Monday-0", completedAt: "2026-09-28 18:00:00+02:00",
                  exercises: ["back_squat": ExercisePerformanceLog(sets: [set(5, 80), set(5, 80), set(5, 80)]),
                              "run_easy": ExercisePerformanceLog(durationSec: 1800),
                              "untouched": ExercisePerformanceLog()]),
            entry("9-Friday-0", completedAt: "2026-09-30 07:00:00+02:00", source: "watch"),
            entry("1-Wednesday-0", completedAt: nil, exercises: ["press": ExercisePerformanceLog(sets: [set(5, 40)])]),
            entry("1-Thursday-0", completedAt: nil),
        ]
        let rows = LogSessions.rows(logs: logs, locate: state.locate, exerciseNames: ["press": "Press"])

        XCTAssertEqual(rows.map(\.key), ["9-Friday-0", "2-Monday-0", "1-Wednesday-0"],
                       "newest completion first, uncompleted-but-logged last, nothing-at-all dropped")
        let monday = rows[1]
        XCTAssertEqual(monday.title, "Heavy/Light/Medium", "named by the program when the key resolves")
        XCTAssertTrue(monday.isLocatable)
        XCTAssertTrue(monday.subtitle.contains("week 1 · Monday"))
        XCTAssertEqual(monday.lines, ["Back Squat — 3 sets · 3×5 @ 80 kg", "Easy Run — 30 min"],
                       "one line per exercise with content, named from the session, in id order")
        let friday = rows[0]
        XCTAssertEqual(friday.title, "Session 9-Friday-0", "a key outside the program keeps its key")
        XCTAssertFalse(friday.isLocatable)
        XCTAssertTrue(friday.subtitle.contains("watch"))
        let wednesday = rows[2]
        XCTAssertFalse(wednesday.isComplete)
        XCTAssertEqual(wednesday.lines, ["Press — 1 set · 1×5 @ 40 kg"], "named from the catalog when not in the program")
        XCTAssertTrue(wednesday.subtitle.contains("not completed"))
    }

    /// `AppState.locateSession` without an AppState: the same lookup over a decoded envelope.
    private struct ServerProgramHolder {
        let program: ServerProgram
        init(_ program: ServerProgram) { self.program = program }
        func locate(_ key: String) -> AppState.LocatedSession? {
            guard let weeks = program.currentProgram?.weeks else { return nil }
            for (wi, week) in weeks.enumerated() {
                for (day, sessions) in week.schedule {
                    for (si, session) in sessions.enumerated() where "\(week.weekNumber)-\(day)-\(si)" == key {
                        return AppState.LocatedSession(session: session, key: key, weekIndex: wi, dayName: day, sessionIndex: si)
                    }
                }
            }
            return nil
        }
    }
}
