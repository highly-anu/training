import XCTest
@testable import TrainingCompanion

/// Which pages Today and the Calendar offer, and where a chevron lands
/// (design-system §6.49).
final class PagingTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // MARK: - Days

    func testWithoutAProgramAWeekEitherWay() {
        XCTAssertEqual(Paging.dayRange(today: day(2026, 11, 11), programStart: nil, weeks: 0, calendar: calendar), -7...7)
        XCTAssertEqual(Paging.dayRange(today: day(2026, 11, 11), programStart: day(2026, 11, 2), weeks: 0, calendar: calendar), -7...7)
    }

    func testTheProgramsSpan() {
        // Started nine days ago, four weeks long: day 0 of 28 is offset -9.
        let range = Paging.dayRange(today: day(2026, 11, 11), programStart: day(2026, 11, 2), weeks: 4, calendar: calendar)
        XCTAssertEqual(range, -9...18)
    }

    func testTheTimeOfDayDoesNotMoveTheSpan() {
        let late = Paging.dayRange(today: day(2026, 11, 11, hour: 23), programStart: day(2026, 11, 2, hour: 0),
                                   weeks: 4, calendar: calendar)
        XCTAssertEqual(late, -9...18)
    }

    func testALongProgramIsClampedToItsReach() {
        let range = Paging.dayRange(today: day(2026, 11, 11), programStart: day(2026, 6, 1), weeks: 52, calendar: calendar)
        XCTAssertEqual(range, -56...56)
        let near = Paging.dayRange(today: day(2026, 11, 11), programStart: day(2026, 6, 1), weeks: 52,
                                   calendar: calendar, reach: 3)
        XCTAssertEqual(near, -3...3)
    }

    func testTodayIsAlwaysAPage() {
        // A program that starts next week: today is before it.
        let ahead = Paging.dayRange(today: day(2026, 11, 11), programStart: day(2026, 11, 16), weeks: 2, calendar: calendar)
        XCTAssertEqual(ahead, 0...18)
        // A program that ended last week: today is after it.
        let behind = Paging.dayRange(today: day(2026, 11, 11), programStart: day(2026, 10, 19), weeks: 2, calendar: calendar)
        XCTAssertEqual(behind, -23...0)
    }

    // MARK: - Weeks

    func testTheWeekRunsMondayToSunday() {
        // 2026-11-11 is a Wednesday.
        XCTAssertEqual(Paging.week(around: 0, today: day(2026, 11, 11), calendar: calendar), [-2, -1, 0, 1, 2, 3, 4])
        // Monday and Sunday are the week's own ends.
        XCTAssertEqual(Paging.week(around: 0, today: day(2026, 11, 9), calendar: calendar), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(Paging.week(around: 0, today: day(2026, 11, 15), calendar: calendar), [-6, -5, -4, -3, -2, -1, 0])
    }

    func testAnotherDaysWeek() {
        // Five days on is next Monday; three days back is last Sunday.
        XCTAssertEqual(Paging.week(around: 5, today: day(2026, 11, 11), calendar: calendar), [5, 6, 7, 8, 9, 10, 11])
        XCTAssertEqual(Paging.week(around: -3, today: day(2026, 11, 11), calendar: calendar), [-9, -8, -7, -6, -5, -4, -3])
    }

    func testEveryDayOfAWeekNamesTheSameWeek() {
        let today = day(2026, 11, 11)
        let week = Paging.week(around: 0, today: today, calendar: calendar)
        for offset in week {
            XCTAssertEqual(Paging.week(around: offset, today: today, calendar: calendar), week)
        }
    }

    // MARK: - Steps

    func testAStepStopsAtTheEnds() {
        XCTAssertEqual(Paging.step(0, by: 1, in: -2...2), 1)
        XCTAssertEqual(Paging.step(0, by: -1, in: -2...2), -1)
        XCTAssertNil(Paging.step(2, by: 1, in: -2...2))
        XCTAssertNil(Paging.step(-2, by: -1, in: -2...2))
        XCTAssertEqual(Paging.step(0, by: 7, in: -9...18), 7)
        XCTAssertNil(Paging.step(0, by: -14, in: -9...18))
    }
}
