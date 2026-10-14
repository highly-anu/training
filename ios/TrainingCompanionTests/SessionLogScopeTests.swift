import XCTest
@testable import TrainingCompanion

/// Completion marks come only from logs the server places in the active
/// program. On 2026-10-14 an October program in its first week showed week 6
/// done because a March log was keyed "6-Monday-0" too.
final class SessionLogScopeTests: XCTestCase {

    private func decode(_ json: String) throws -> [SessionLogEntry] {
        try JSONDecoder().decode([SessionLogEntry].self, from: json.data(using: .utf8)!)
    }

    func testEarlierProgramsLogsDoNotCompleteThisOnesSessions() throws {
        // Newest first, as GET /health/sessions/recent returns them.
        let logs = try decode("""
        [
          {"session_key": "1-Tuesday-0", "completed_at": "2026-10-13 18:00:00+00:00",
           "session_uid": "b284:w0-Tuesday-0", "in_current_program": true},
          {"session_key": "6-Monday-0", "completed_at": "2026-04-06 20:09:11+00:00",
           "in_current_program": false},
          {"session_key": "1-Tuesday-0", "completed_at": "2026-03-31 10:00:00+00:00",
           "in_current_program": false},
          {"session_key": "2-Friday-0", "completed_at": "2026-10-02 07:00:00+00:00"}
        ]
        """)
        let split = SessionLogScope.split(logs)

        XCTAssertNil(split.current["6-Monday-0"], "the March log does not mark week 6 done")
        XCTAssertEqual(split.current["1-Tuesday-0"]?.completedAt, "2026-10-13 18:00:00+00:00",
                       "this program's log wins its key")
        XCTAssertNotNil(split.current["2-Friday-0"], "no verdict (an older server) stays current")
        XCTAssertEqual(split.earlier.map(\.sessionKey), ["6-Monday-0", "1-Tuesday-0"])
    }

    func testLogSessionsListsEarlierLogsAsEarlierProgram() throws {
        let logs = try decode("""
        [{"session_key": "6-Monday-0", "completed_at": "2026-04-06 20:09:11+00:00",
          "source": "manual", "in_current_program": false},
         {"session_key": "6-Monday-0", "completed_at": "2026-10-14 07:00:00+00:00",
          "source": "manual", "in_current_program": true}]
        """)
        var located: [String] = []
        let rows = LogSessions.rows(logs: logs, locate: { key in located.append(key); return nil })

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.id)).count, 2, "one key in two programs makes two distinct rows")
        XCTAssertEqual(located, ["6-Monday-0"], "only the current program's log is looked up in it")
        XCTAssertTrue(rows.last?.subtitle.contains("earlier program") == true, rows.last?.subtitle ?? "")
    }
}
