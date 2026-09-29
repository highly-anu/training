import XCTest
@testable import TrainingCompanion

/// The formatting that decides what a history row says.
///
/// Two things here are easy to get wrong and invisible when they are:
/// dates are parsed as UTC (the server sends plain `yyyy-MM-dd`, and parsing
/// those in local time shifts them a day west of Greenwich), and a week's
/// stored number is not always its position — a program regenerated from an
/// event date is numbered by its absolute program week, so the same number can
/// appear at two positions.
final class ProgramHistoryFormatTests: XCTestCase {

    func testSpanOfAClosedBlock() {
        let entry = makeEntry(from: "2026-07-20", to: "2026-09-29", isActive: false)
        XCTAssertEqual(ProgramHistoryFormat.span(entry), "20 Jul 2026 — 29 Sep 2026")
    }

    func testSpanOfTheOpenBlock() {
        let entry = makeEntry(from: "2026-09-29", to: nil, isActive: true)
        XCTAssertEqual(ProgramHistoryFormat.span(entry), "29 Sep 2026 — now")
    }

    func testDatesDoNotShiftAcrossTimeZones() {
        // Parsed as UTC, so a date never lands on the day before.
        XCTAssertEqual(ProgramHistoryFormat.date("2026-01-01"), "1 Jan 2026")
        XCTAssertEqual(ProgramHistoryFormat.shortDate("2026-07-20"), "Mon 20 Jul")
        // A full timestamp is tolerated: only the date part is read.
        XCTAssertEqual(ProgramHistoryFormat.date("2026-07-20T09:00:00+00:00"), "20 Jul 2026")
    }

    func testUnparseableDatePassesThrough() {
        XCTAssertEqual(ProgramHistoryFormat.date("not-a-date"), "not-a-date")
    }

    func testWeekHeaderUsesThePositionWhenTheyAgree() {
        XCTAssertEqual(ProgramHistoryFormat.weekHeader(index: 0, stored: 1), "Week 1")
        XCTAssertEqual(ProgramHistoryFormat.weekHeader(index: 5, stored: 6), "Week 6")
    }

    func testWeekHeaderShowsBothWhenTheyDisagree() {
        // weeks[0] numbered 16: the tail of an earlier plan, spliced on.
        XCTAssertEqual(ProgramHistoryFormat.weekHeader(index: 0, stored: 16),
                       "Week 1 (numbered 16)")
    }

    func testWeekHeaderWithNoStoredNumber() {
        XCTAssertEqual(ProgramHistoryFormat.weekHeader(index: 2, stored: nil), "Week 3")
    }

    func testDisplayNamePrefersTheGoalName() {
        XCTAssertEqual(makeEntry(goalName: "Uphill Athlete").displayName, "Uphill Athlete")
    }

    func testDisplayNameFallsBackToTheSourceGoals() {
        let entry = makeEntry(goalName: nil, sourceGoalIds: ["wildman_kettlebell", "bjj"])
        XCTAssertEqual(entry.displayName, "Wildman Kettlebell + Bjj")
    }

    func testDisplayNameWithNothingToGoOn() {
        XCTAssertEqual(makeEntry(goalName: nil, sourceGoalIds: []).displayName, "Program")
    }

    // MARK: - Helpers

    private func makeEntry(from: String = "2026-07-20",
                           to: String? = nil,
                           isActive: Bool = true,
                           goalName: String? = "Test Plan",
                           sourceGoalIds: [String] = ["test"]) -> ProgramHistoryEntry {
        ProgramHistoryEntry(
            activationId: 1, versionId: "v1", lineageId: "l1", label: "",
            goalName: goalName, sourceGoalIds: sourceGoalIds,
            effectiveFrom: from, effectiveTo: to, isActive: isActive,
            startDate: from, weekCount: 8, sessionCount: 24,
            matchedCount: 0, loggedCount: 0)
    }
}
