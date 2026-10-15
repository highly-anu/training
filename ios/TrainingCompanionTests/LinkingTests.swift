import XCTest
@testable import TrainingCompanion

/// Log ▸ Linking: the server's day cards decode, a link carries its
/// session_uid (without it a link across days resolves to nothing), and the
/// request names the athlete's date and the pairs waved away.
final class LinkingTests: XCTestCase {
    /// Trimmed from a real `GET /health/linking` against the local dev program.
    private let sample = """
    {"today": "2026-10-15", "programVersionId": "daa6", "days": [
     {"date": "2026-10-13", "historical": false, "programVersionId": "daa6", "programLabel": "Mark Wildman Kettlebell",
      "links": [], "suggestions": [],
      "workouts": [{"id": "boxstep", "date": "2026-10-13", "startTime": "2026-10-13 20:00:00+02:00", "source": "garmin",
                    "activityType": "Weighted Box Step-Ups (ME)", "durationMinutes": 40, "inferredModalityId": "max_strength", "distance": null}],
      "sessions": [], "elsewhere": [], "declined": [], "needsAttention": true},
     {"date": "2026-10-12", "historical": false, "programVersionId": "daa6", "programLabel": "Mark Wildman Kettlebell",
      "links": [{"workout": {"id": "kbpower", "date": "2026-10-12", "startTime": "2026-10-12T07:30:00Z", "source": "garmin",
                             "activityType": "KB Ballistic Power Session (Wildman)", "durationMinutes": 35, "inferredModalityId": "power"},
                 "session": {"key": "4-Monday-0", "legacyKey": "4-Monday-0", "uid": "daa6:w1-Monday-0", "date": "2026-10-12",
                             "weekNumber": 4, "dayName": "Monday", "index": 0, "modality": "power", "name": "KB Ballistic Power",
                             "durationMinutes": 31, "historical": false, "programVersionId": "daa6", "completedAt": null}}],
      "suggestions": [], "workouts": [], "sessions": [], "elsewhere": [], "declined": [], "needsAttention": false},
     {"date": "2026-10-09", "historical": true, "programVersionId": "1236", "programLabel": "Marcus Filly / Functional Bodybuilding",
      "links": [], "suggestions": [], "workouts": [],
      "sessions": [{"key": "1236:w0-Friday-0", "legacyKey": "1-Friday-0", "uid": "1236:w0-Friday-0", "date": "2026-10-09",
                    "weekNumber": 1, "dayName": "Friday", "index": 0, "modality": "mobility", "name": "Positional Mobility",
                    "durationMinutes": 25, "historical": true, "programVersionId": "1236", "completedAt": null}],
      "elsewhere": [], "declined": [], "needsAttention": false}]}
    """

    private func doc() throws -> LinkingDocument {
        try JSONDecoder().decode(LinkingDocument.self, from: Data(sample.utf8))
    }

    func testDecodesTheServersDays() throws {
        let d = try doc()
        XCTAssertEqual(d.days.map(\.date), ["2026-10-13", "2026-10-12", "2026-10-09"])
        XCTAssertEqual(d.days[0].workouts.first?.title, "Weighted Box Step-Ups (ME)")
        XCTAssertEqual(d.days[1].links.first?.session.uid, "daa6:w1-Monday-0")
        XCTAssertTrue(d.days[2].historical)
        XCTAssertEqual(d.days[2].programLabel, "Marcus Filly / Functional Bodybuilding")
    }

    func testVisibleKeepsDaysWaitingUnlessAll() throws {
        let days = try doc().days
        XCTAssertEqual(Linking.visible(days, showAll: false).map(\.date), ["2026-10-13"])
        XCTAssertEqual(Linking.visible(days, showAll: true).count, 3)
    }

    func testLinkCarriesTheSessionUidAndLegacyKey() throws {
        let earlier = try doc().days[2].sessions[0]
        let body = Linking.linkPayload(workoutId: "boxstep", session: earlier)
        XCTAssertEqual(body["sessionUid"] as? String, "1236:w0-Friday-0")
        XCTAssertEqual(body["sessionKey"] as? String, "1-Friday-0", "the legacy key, never the page key")
        XCTAssertEqual(body["matchConfidence"] as? String, "manual")
    }

    func testUnlinkIsARejectedMatch() {
        let body = Linking.unlinkPayload(workoutId: "kbpower")
        XCTAssertEqual(body["matchConfidence"] as? String, "rejected")
        XCTAssertEqual(body["sessionKey"] as? String, "")
    }

    func testQueryEscapesDismissedPairs() {
        let q = Linking.query(today: "2026-10-15", dismissed: ["b|1-Monday-0", "a|x:w0-Friday-0"])
        XCTAssertEqual(q, "today=2026-10-15&dismissed=a%7Cx:w0-Friday-0&dismissed=b%7C1-Monday-0")
        XCTAssertNotNil(URL(string: "https://x/api/health/linking?" + q))
    }

    func testStartTimesInBothServerSpellings() {
        XCTAssertNotNil(LogLinkingTab.instant("2026-10-13 20:00:00+02:00"))
        XCTAssertNotNil(LogLinkingTab.instant("2026-10-12T07:30:00Z"))
        XCTAssertNotNil(LogLinkingTab.instant("2026-10-12T07:30:00.123Z"))
        XCTAssertEqual(LogLinkingTab.instant("2026-10-13 20:00:00+02:00"), LogLinkingTab.instant("2026-10-13T18:00:00Z"))
    }
}
