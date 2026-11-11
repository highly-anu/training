import XCTest
@testable import TrainingCompanion

/// What a screen shows before, instead of and after its content (§6.3):
/// a failed load is never "empty", and content on screen is never replaced.
final class AppLoadPhaseTests: XCTestCase {

    func testContentWinsOverAReloadAndItsFailure() {
        XCTAssertEqual(AppLoadPhase.resolve(hasContent: true, isLoading: true, error: nil), .content)
        XCTAssertEqual(AppLoadPhase.resolve(hasContent: true, isLoading: false, error: "offline"), .content)
    }

    func testAFirstLoadIsLoadingEvenAfterAnEarlierFailure() {
        XCTAssertEqual(AppLoadPhase.resolve(hasContent: false, isLoading: true, error: nil), .loading)
        XCTAssertEqual(AppLoadPhase.resolve(hasContent: false, isLoading: true, error: "offline"), .loading)
    }

    func testAFailedLoadIsNotEmpty() {
        XCTAssertEqual(AppLoadPhase.resolve(hasContent: false, isLoading: false, error: "offline"),
                       .failed("offline"))
    }

    func testOnlyAFinishedLoadThatFoundNothingIsEmpty() {
        XCTAssertEqual(AppLoadPhase.resolve(hasContent: false, isLoading: false, error: nil), .empty)
    }
}
