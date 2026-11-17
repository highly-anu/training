import XCTest
@testable import TrainingCompanion

/// The line over a workout's charts: what was recorded at the moment under
/// the finger (design-system §6.10).
final class WorkoutScrubTests: XCTestCase {
    private func series() -> WorkoutScrub.Series {
        var s = WorkoutScrub.Series()
        s.hr = [(0, 100), (60, 120), (120, 141.6)]
        s.pace = [(0, 330), (120, 312)]
        s.altitude = [(0, 400), (600, 450)]
        return s
    }

    func testReadsEverySeriesAtTheMoment() {
        XCTAssertEqual(WorkoutScrub.readout(at: 118, in: series()), "1:58 · 142 bpm · 5:12 /km")
        XCTAssertEqual(WorkoutScrub.readout(at: 10, in: series()), "0:10 · 100 bpm · 5:30 /km · 400 m")
    }

    func testNothingTouchedReadsNothing() {
        XCTAssertNil(WorkoutScrub.readout(at: nil, in: series()))
    }

    func testAGapInTheRecordingIsNotItsLastValue() {
        XCTAssertNil(WorkoutScrub.value(at: 300, in: series().hr))
        XCTAssertEqual(WorkoutScrub.readout(at: 590, in: series()), "9:50 · 450 m")
    }

    func testClockTurnsToHours() {
        XCTAssertEqual(WorkoutScrub.clock(59.6), "1:00")
        XCTAssertEqual(WorkoutScrub.clock(3725), "1:02:05")
    }
}
