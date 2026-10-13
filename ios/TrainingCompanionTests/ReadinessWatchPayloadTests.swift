import XCTest
@testable import TrainingCompanion

/// The Apple Watch shows the server's readiness — the score Today and
/// Recovery show — not the phone's old HRV rule (≥ 50 ms green), which could
/// call a day green that the server scored red.
final class ReadinessWatchPayloadTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "ReadinessWatchPayloadTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testTodaysServerScoreIsSentWithTheLatestReadings() {
        let d = defaults()
        let now = Date()
        d.set(["score": 42, "status": "red", "date": ISO8601DateFormatter().string(from: now)],
              forKey: ReadinessInfo.storageKey)
        d.set(72.0, forKey: "lastHRV")      // the old rule would have said green
        d.set(51.0, forKey: "lastRestingHR")
        let info = ReadinessInfo.fromStoredServerScore(defaults: d, now: now)
        XCTAssertEqual(info?.signal, "red")
        XCTAssertEqual(info?.score ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertEqual(info?.hrv, 72)
        XCTAssertEqual(info?.restingHR, 51)
    }

    func testYesterdaysScoreIsNotSent() {
        let d = defaults()
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        d.set(["score": 80, "status": "green", "date": ISO8601DateFormatter().string(from: yesterday)],
              forKey: ReadinessInfo.storageKey)
        XCTAssertNil(ReadinessInfo.fromStoredServerScore(defaults: d, now: now))
    }

    func testNothingStoredSendsNothing() {
        XCTAssertNil(ReadinessInfo.fromStoredServerScore(defaults: defaults()))
    }
}
