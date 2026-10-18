import XCTest
@testable import TrainingCompanion

/// The Apple Watch's Today list says what the Garmin's menus say
/// (WatchListText): the Week, Progress and Sync rows, the week's days and
/// tomorrow under a rest day.
@MainActor
final class WatchListTextTests: XCTestCase {
    private func progress(_ json: String) throws -> WatchProgress {
        try JSONDecoder().decode(WatchProgress.self, from: Data(json.utf8))
    }

    func testTheProgressRowAndPage() throws {
        let p = try progress(#"""
        {"week": {"number": 2, "of": 12, "done": 3, "due": 4, "sessions": 5},
         "program": {"done": 2, "due": 7, "pct": 29},
         "headline": {"label": "Load on the bar", "text": "Back squat 102.5kg", "trendText": "+1.2% per session"}}
        """#)
        XCTAssertEqual(WatchListText.progressLine(p), "3/5 this week · 29%")
        let rows = WatchListText.progressRows(p)
        XCTAssertEqual(rows.map(\.label), ["This week", "Programme", "Load on the bar", "Trend"])
        XCTAssertEqual(rows.map(\.value), ["3 of 5 done · 4 due", "2 of 7 done · 29%",
                                           "Back squat 102.5kg", "+1.2% per session"])
        // A first week with nothing measured yet.
        let early = try progress(#"{"week": {"number": 1, "of": 12, "done": 0, "due": 0, "sessions": 3}, "program": {"done": 0, "due": 0}, "headline": {"label": "Load on the bar"}}"#)
        XCTAssertEqual(WatchListText.progressLine(early), "0/3 this week")
        XCTAssertEqual(WatchListText.progressRows(early).map(\.value), ["0 of 3 done · 0 due", "Not measured yet"])
    }

    func testTheWeekAndItsDays() throws {
        let day = try JSONDecoder().decode(WatchDay.self, from: Data(#"{"status": "ok", "weekNumber": 3, "phase": "build"}"#.utf8))
        XCTAssertEqual(WatchListText.weekTitle(day), "Week 3  Build")
        XCTAssertEqual(WatchListText.weekTitle(nil), "Week")

        let ahead = try JSONDecoder().decode([WatchDayAhead].self, from: Data(#"""
        [{"offset": 0, "date": "2026-10-19", "title": "Strength A +1", "sessions": [
            {"sessionId": "3-Monday-0", "modalityId": "max_strength", "archetypeName": "Strength A", "estimatedMinutes": 60, "isDeload": false, "exercises": []},
            {"sessionId": "3-Monday-1", "modalityId": "mobility", "archetypeName": "Mobility", "estimatedMinutes": 20, "isDeload": false, "exercises": []}]},
         {"offset": 1, "date": "2026-10-20", "title": "Rest", "sessions": []}]
        """#.utf8))
        XCTAssertEqual(WatchListText.dayName(ahead[0]), "Today")
        XCTAssertEqual(WatchListText.dayName(ahead[1]), "Tue 20")
        XCTAssertEqual(WatchListText.dayLine(ahead[0]), "Strength A +1  80 min")
        XCTAssertEqual(WatchListText.dayLine(ahead[1]), "Rest day")
        XCTAssertEqual(WatchListText.sessionLine(ahead[0].sessions[0]), "60 min  0 exercises")
    }

    func testTomorrowUnderARestDay() throws {
        func t(_ json: String) throws -> WatchTomorrow { try JSONDecoder().decode(WatchTomorrow.self, from: Data(json.utf8)) }
        XCTAssertEqual(WatchListText.tomorrowLine(try t(#"{"dayName": "Tuesday", "sessionCount": 1, "archetypeName": "Ruck", "estimatedMinutes": 90}"#)),
                       "Ruck  90 min")
        XCTAssertEqual(WatchListText.tomorrowLine(try t(#"{"dayName": "Tuesday", "sessionCount": 2, "archetypeName": "Ruck", "estimatedMinutes": 90}"#)),
                       "Ruck  90 min +1")
        XCTAssertEqual(WatchListText.tomorrowLine(try t(#"{"dayName": "Sunday", "sessionCount": 0}"#)), "Rest")
        XCTAssertNil(WatchListText.tomorrowLine(nil), "the program ends today")
    }

    func testTheSyncLine() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 18; c.hour = 7; c.minute = 41
        let at = Calendar.current.date(from: c)!
        XCTAssertEqual(WatchListText.syncLine(ok: true, at: at, reason: nil), "ok 07:41")
        XCTAssertEqual(WatchListText.syncLine(ok: false, at: at, reason: "No phone"), "failed 07:41 · No phone")
        XCTAssertNil(WatchListText.syncLine(ok: true, at: nil, reason: nil))
    }
}
