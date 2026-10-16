import XCTest
@testable import TrainingCompanion

/// A finding's value and unit: symbols attach, words get a space — the
/// server's rule for its change line, so "0exercises" never shows again.
final class ProgressionUnitTests: XCTestCase {
    func testWordsAreSpacedSymbolsAttach() {
        XCTAssertEqual(ProgressionView.withUnit("0", "exercises"), "0 exercises")
        XCTAssertEqual(ProgressionView.withUnit("4", "rounds"), "4 rounds")
        XCTAssertEqual(ProgressionView.withUnit("80", "kg"), "80kg")
        XCTAssertEqual(ProgressionView.withUnit("45", "s"), "45s")
        XCTAssertEqual(ProgressionView.withUnit("12", ""), "12")
    }
}
