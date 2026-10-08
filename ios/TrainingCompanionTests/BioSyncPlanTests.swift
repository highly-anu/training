import XCTest
@testable import TrainingCompanion

/// The days the Apple Health relay sends. Garmin Connect writes the watch's
/// exact daily resting HR to Apple Health whenever it syncs, so the relay has
/// to send today and keep re-sending the last few days; it used to stop before
/// today and never revisit a day the server had.
final class BioSyncPlanTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private lazy var fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func keys(today: Date, synced: Set<String>) -> [String] {
        BioSyncPlan.days(today: today, synced: synced, calendar: cal, key: fmt.string(from:))
            .map(fmt.string(from:))
    }

    func testTodayIsSent() {
        let all = Set((0...30).map { fmt.string(from: cal.date(byAdding: .day, value: -$0, to: date(2026, 10, 8))!) })
        XCTAssertTrue(keys(today: date(2026, 10, 8), synced: all).contains("2026-10-08"))
    }

    func testTheLastThreeDaysAreResentEvenWhenTheServerHasThem() {
        let all = Set((0...30).map { fmt.string(from: cal.date(byAdding: .day, value: -$0, to: date(2026, 10, 8))!) })
        XCTAssertEqual(keys(today: date(2026, 10, 8), synced: all),
                       ["2026-10-06", "2026-10-07", "2026-10-08"])
    }

    func testOlderDaysAreSentOnlyWhenTheServerLacksThem() {
        let synced: Set<String> = ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"]
        let sent = keys(today: date(2026, 10, 8), synced: synced)
        XCTAssertFalse(sent.contains("2026-10-03"))
        XCTAssertTrue(sent.contains("2026-09-30"))      // never synced
        XCTAssertEqual(sent.first, "2026-09-08")        // 30 days back
        XCTAssertEqual(sent.count, 31 - synced.count)
    }

    func testOldestFirstSoTheNewestIsCachedLast() {
        let sent = keys(today: date(2026, 10, 8, 23), synced: [])
        XCTAssertEqual(sent, sent.sorted())
        XCTAssertEqual(sent.last, "2026-10-08")
    }
}
