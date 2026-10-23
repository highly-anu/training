import XCTest
@testable import TrainingCompanion

/// A finding's value and unit: symbols attach, words get a space — the
/// server's rule for its change line, so "0exercises" never shows again.
final class ProgressionUnitTests: XCTestCase {
    func testWordsAreSpacedSymbolsAttach() {
        XCTAssertEqual(AnalyticsProgressTab.withUnit("0", "exercises"), "0 exercises")
        XCTAssertEqual(AnalyticsProgressTab.withUnit("4", "rounds"), "4 rounds")
        XCTAssertEqual(AnalyticsProgressTab.withUnit("80", "kg"), "80kg")
        XCTAssertEqual(AnalyticsProgressTab.withUnit("45", "s"), "45s")
        XCTAssertEqual(AnalyticsProgressTab.withUnit("12", ""), "12")
    }
}
