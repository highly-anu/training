import XCTest
@testable import TrainingCompanion

/// Returning to the foreground reloads Today only when the last full load is
/// old, and never before the launch load has finished. Async: an `AppState`
/// must deinit inside a Task (see `CurrentWeekIndexTests`).
@MainActor
final class RefreshIfStaleTests: XCTestCase {
    func testNothingBeforeTheFirstFullLoad() async {
        let state = AppState()
        await state.refreshIfStale()
        XCTAssertNil(state.lastFullLoad, "a foreground refresh must not race the launch loads")
    }

    func testOnlyWhenTheLastLoadIsOld() async throws {
        let state = AppState()
        await state.loadAll()
        let first = try XCTUnwrap(state.lastFullLoad)

        await state.refreshIfStale(now: first.addingTimeInterval(60))
        XCTAssertEqual(state.lastFullLoad, first, "a minute later is not stale")

        await state.refreshIfStale(now: first.addingTimeInterval(301))
        XCTAssertGreaterThan(try XCTUnwrap(state.lastFullLoad), first, "five minutes later reloads")
    }

    /// A section shown again does not refetch; after a full load it does.
    func testASectionLoadsOncePerFullLoad() async {
        let state = AppState()
        var runs = 0
        await state.loadIfStale("section") { runs += 1 }
        await state.loadIfStale("section") { runs += 1 }
        XCTAssertEqual(runs, 1, "switching back must not refetch")
        await state.loadIfStale("other") { runs += 1 }
        XCTAssertEqual(runs, 2, "each section keeps its own record")
        await state.loadAll()
        await state.loadIfStale("section") { runs += 1 }
        XCTAssertEqual(runs, 3, "a full load makes it stale again")
    }
}
