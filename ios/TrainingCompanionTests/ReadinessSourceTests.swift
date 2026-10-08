import XCTest
@testable import TrainingCompanion

/// Readiness names where its resting HR came from, and Settings shows the
/// watch's last wellness reading — the phone's copies of the web's
/// `readinessSourceNote` and `wellnessSummary`, with the same words.
final class ReadinessSourceTests: XCTestCase {

    private func readiness(_ json: String) throws -> ReadinessResult {
        try JSONDecoder().decode(ReadinessResult.self, from: Data(json.utf8))
    }

    private let base = #""score": 72, "status": "green", "flags": [], "components": {"rhr": 30, "hrv": 20, "sleep": 10, "fatigue": 8}"#

    func testAnOlderServerWithoutSourcesStillDecodesAndShowsNoNote() throws {
        let r = try readiness("{\(base)}")
        XCTAssertNil(r.sources)
        XCTAssertNil(r.sourceNote)
    }

    func testOneSourceIsNamedOnce() throws {
        let r = try readiness(#"{\#(base), "sources": {"rhr": "daily_bio", "hrv": "daily_bio", "sleep": "daily_bio"}}"#)
        XCTAssertEqual(r.sourceNote, "Resting HR, HRV and sleep from Apple Health and check-ins.")
    }

    func testTheWatchIsNamedWhenItSuppliesRestingHR() throws {
        let r = try readiness(#"{\#(base), "sources": {"rhr": "garmin_ciq", "hrv": "daily_bio", "sleep": "daily_bio"}}"#)
        XCTAssertEqual(r.sourceNote,
                       "Resting HR from your Garmin watch's heart-rate low; HRV and sleep from Apple Health and check-ins.")
    }

    func testNothingScoredMeansNoNote() throws {
        let r = try readiness(#"{\#(base), "sources": {"rhr": null, "hrv": null, "sleep": null}}"#)
        XCTAssertNil(r.sourceNote)
    }

    func testTheWellnessLineListsWhatTheWatchRead() throws {
        let json = #"""
        {"latest": {"date": "2026-10-08", "source": "garmin_ciq", "resting_hr": 46,
            "resting_hr_7d_avg": 47, "hr_min": 47, "body_battery_max": 75, "recovery_time_h": 82,
            "read_at": "2026-10-08T05:20:00+00:00", "model": "fēnix 9 Pro 47 mm"}}
        """#
        struct Body: Decodable { let latest: WellnessReading? }
        let reading = try XCTUnwrap(try JSONDecoder().decode(Body.self, from: Data(json.utf8)).latest)
        XCTAssertEqual(reading.model, "fēnix 9 Pro 47 mm")
        XCTAssertEqual(reading.summary(timeZone: TimeZone(identifier: "Europe/Berlin")!),
                       "8 Oct, 07:20 · HR low\u{00A0}47 · 7-day resting HR\u{00A0}47 · Body Battery\u{00A0}75 · recovery\u{00A0}82\u{00A0}h")
    }

    func testTheProfileRestingHRIsNeverShown() {
        // resting_hr is the watch profile's zone setting; WellnessReading does
        // not even decode it.
        let reading = WellnessReading(date: "2026-10-08", recoveryTimeH: 0)
        XCTAssertEqual(reading.summary(timeZone: TimeZone(identifier: "UTC")!), "8 Oct · recovery\u{00A0}0\u{00A0}h")
    }
}
