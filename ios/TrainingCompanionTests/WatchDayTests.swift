import XCTest
@testable import TrainingCompanion

/// What the phone forwards to the Apple Watch from today-session's
/// `progress`: `transferUserInfo` takes property-list types only, so a JSON
/// null (no program %, no headline yet) must not reach it.
final class WatchDayTests: XCTestCase {
    func testNullsAreDroppedAtEveryDepth() throws {
        let json = Data(#"{"week": {"number": 2, "of": 12, "done": 3, "due": 4, "sessions": 5},"#
                        .utf8) + Data(#" "program": {"done": 3, "due": 4, "pct": null}, "headline": null}"#.utf8)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let clean = APIClient.dropNulls(raw)
        XCTAssertNil(clean["headline"])
        let program = try XCTUnwrap(clean["program"] as? [String: Any])
        XCTAssertNil(program["pct"])
        XCTAssertEqual(program["done"] as? Int, 3)
        XCTAssertEqual((clean["week"] as? [String: Any])?["sessions"] as? Int, 5)
        XCTAssertTrue(PropertyListSerialization.propertyList(clean, isValidFor: .binary),
                      "what goes to the watch is a valid property list")
    }
}
