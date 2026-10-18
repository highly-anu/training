import XCTest
@testable import TrainingCompanion

/// Analytics ▸ Recovery's readings: sleep durations and the week's debt, the
/// HRV and resting-HR trends (which way is better differs), and the
/// readiness parts the detail screen lays out.
final class RecoveryModelTests: XCTestCase {

    /// Days newest first, as the snapshot gives them.
    private func logs(_ rows: [(hrv: Double?, rhr: Double?, sleep: Int?)]) throws -> [DailyBioLog] {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17))!
        let json = rows.enumerated().map { i, r -> [String: Any] in
            let day = Calendar.current.date(byAdding: .day, value: -i, to: start)!
            var d: [String: Any] = ["date": day.formatted(.iso8601.year().month().day())]
            if let v = r.hrv { d["hrv"] = v }
            if let v = r.rhr { d["resting_hr"] = v }
            if let v = r.sleep { d["sleep_duration_min"] = v }
            return d
        }
        return try JSONDecoder().decode([DailyBioLog].self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testSleepDurationsAndTheWeeksDebt() throws {
        XCTAssertEqual(SleepFormat.duration(432), "7h 12m")
        XCTAssertEqual(SleepFormat.duration(480), "8h")
        XCTAssertEqual(SleepFormat.duration(45), "45m")
        let week = try logs([(nil, nil, 420), (nil, nil, 480), (nil, nil, nil), (nil, nil, 360)]
                            + Array(repeating: (nil, nil, 480), count: 6))
        let debt = SleepFormat.Debt(logs: week)
        XCTAssertEqual(debt.nights, 6, "the first seven days, only those that recorded sleep")
        XCTAssertEqual(debt.hours, 3.0, accuracy: 0.001, "1 h + 2 h short of 8 h a night")
        XCTAssertEqual(SleepFormat.Debt(logs: []).nights, 0)
    }

    func testARisingHRVIsBetterAndARisingRestingHRWorse() throws {
        // Newest first: both readings climb over the last week.
        let rising = try logs((0..<10).map { i in (hrv: 60 - Double(i), rhr: 52 - Double(i) / 2, sleep: nil) })
        let hrv = try XCTUnwrap(RecoveryTrendChartView.trend(rising, metric: .hrv))
        let rhr = try XCTUnwrap(RecoveryTrendChartView.trend(rising, metric: .restingHR))
        XCTAssertGreaterThan(hrv.delta, 0)
        XCTAssertTrue(hrv.isBetter)
        XCTAssertGreaterThan(rhr.delta, 0)
        XCTAssertFalse(rhr.isBetter, "a resting heart rate going up is the worse way")
        XCTAssertNil(RecoveryTrendChartView.trend(try logs([(50, 50, nil)]), metric: .hrv), "under seven readings, no trend")
        let points = RecoveryTrendChartView.points(rising, metric: .hrv)
        XCTAssertEqual(points.first?.value, 51, "oldest first")
        XCTAssertEqual(points.last?.value, 60)
    }

    func testReadinessCarriesItsPartsWhenTheServerSendsThem() throws {
        let json = Data("""
        {"score": 32, "status": "red", "flags": ["recovery_pending"],
         "components": {"rhr": 30, "hrv": 18, "sleep": 10, "fatigue": 8, "tsb": 5},
         "parts": [{"id": "rhr", "label": "Resting heart rate", "points": 30, "max": 35},
                   {"id": "hrv", "label": "Body Battery and recovery", "points": 18, "max": 35}],
         "cappedAt": 32}
        """.utf8)
        let result = try JSONDecoder().decode(ReadinessResult.self, from: json)
        XCTAssertEqual(result.parts?.map(\.label), ["Resting heart rate", "Body Battery and recovery"])
        XCTAssertEqual(result.parts?.last?.max, 35)
        XCTAssertEqual(result.cappedAt, 32)
        let older = try JSONDecoder().decode(ReadinessResult.self, from: Data("""
        {"score": 61, "status": "yellow", "flags": [], "components": {"rhr": 20, "hrv": 17, "sleep": 10, "fatigue": 8}}
        """.utf8))
        XCTAssertNil(older.parts, "an older server sends none; the screen shows no Score section")
    }

    func testTheTermsAreReadOneByOne() throws {
        let terms = try APIClient.analyticsTerms(from: Data("""
        {"primitives": {}, "terms": {"tsb": {"label": "TSB · form", "text": "Fitness minus fatigue."},
                                     "future": {"label": "No text yet"}}}
        """.utf8))
        XCTAssertEqual(Array(terms.keys), ["tsb"], "a term the phone cannot read is left out, not every term")
        XCTAssertEqual(try APIClient.analyticsTerms(from: Data(#"{"primitives": {}}"#.utf8)), [:],
                       "an older server sends no terms")
    }
}
