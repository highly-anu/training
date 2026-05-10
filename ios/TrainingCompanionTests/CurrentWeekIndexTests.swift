import XCTest
@testable import TrainingCompanion

/// Tests for AppState.currentWeekIndex — the calculation that maps today's date
/// to a week index in the program. Edge cases here cause crashes or wrong content.
final class CurrentWeekIndexTests: XCTestCase {

    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    @MainActor
    private func makeAppState(startDate: Date, weekCount: Int) -> AppState {
        let state = AppState()
        let weeks = (0..<weekCount).map { i in
            ProgramWeek(
                weekNumber: i + 1, weekInPhase: i + 1,
                isDeload: false, phase: "base",
                schedule: [:]
            )
        }
        state.serverProgram = ServerProgram(
            currentProgram: GeneratedProgram(weeks: weeks),
            programStartDate: dayFmt.string(from: startDate),
            eventDate: nil,
            sourceGoalIds: []
        )
        return state
    }

    @MainActor
    func testCurrentWeekIndexReturnsZeroForProgramStartingToday() {
        let state = makeAppState(startDate: Date(), weekCount: 4)
        XCTAssertEqual(state.currentWeekIndex, 0)
    }

    @MainActor
    func testCurrentWeekIndexReturnsZeroForFutureStartDate() {
        // Program starts next week — must not return negative or crash
        let futureStart = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        let state = makeAppState(startDate: futureStart, weekCount: 4)
        XCTAssertEqual(state.currentWeekIndex, 0,
                       "Future start date should clamp to week 0, not negative or nil")
    }

    @MainActor
    func testCurrentWeekIndexReturnsCorrectWeekMidProgram() {
        // Program started 14 days ago → should be week index 2
        let start = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let state = makeAppState(startDate: start, weekCount: 6)
        XCTAssertEqual(state.currentWeekIndex, 2)
    }

    @MainActor
    func testCurrentWeekIndexReturnsNilWhenProgramEnded() {
        // Program started 8 weeks ago, only 4 weeks long → past the end
        let start = Calendar.current.date(byAdding: .day, value: -56, to: Date())!
        let state = makeAppState(startDate: start, weekCount: 4)
        XCTAssertNil(state.currentWeekIndex,
                     "Expired program should return nil, not an out-of-bounds index")
    }

    @MainActor
    func testCurrentWeekIndexNilWhenNoProgramStartDate() {
        let state = AppState()
        state.serverProgram = ServerProgram(
            currentProgram: GeneratedProgram(weeks: [
                ProgramWeek(weekNumber: 1, weekInPhase: 1, isDeload: false, phase: "base", schedule: [:])
            ]),
            programStartDate: nil,  // no start date set
            eventDate: nil,
            sourceGoalIds: []
        )
        XCTAssertNil(state.currentWeekIndex)
    }

    @MainActor
    func testCurrentWeekNeverReturnsNegativeIndex() {
        // Safety: currentWeekIndex must never return a value that would crash weeks[idx]
        let futureStart = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let state = makeAppState(startDate: futureStart, weekCount: 4)
        if let idx = state.currentWeekIndex {
            let weeks = state.serverProgram?.currentProgram?.weeks ?? []
            XCTAssertGreaterThanOrEqual(idx, 0, "Index must not be negative")
            XCTAssertLessThan(idx, weeks.count, "Index must be within bounds")
        }
    }
}
