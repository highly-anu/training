import XCTest
@testable import TrainingCompanion

/// Log ▸ Workouts' filter: the menu sets it, the list and the scope line read it.
final class WorkoutListFilterTests: XCTestCase {
    private func workout(_ id: String, daysAgo: Int, type: String, minutes: Double) -> ImportedWorkout {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return ImportedWorkout(id: id, source: "garmin", date: f.string(from: d), startTime: nil, endTime: nil,
                               durationMinutes: minutes, activityType: type, inferredModalityId: nil,
                               heartRate: nil, calories: nil, distance: nil, gpsTrack: nil, elevation: nil)
    }

    private lazy var workouts = [
        workout("run", daysAgo: 2, type: "running", minutes: 30),
        workout("kb", daysAgo: 5, type: "KB Movement Skill Session", minutes: 45),
        workout("old", daysAgo: 60, type: "running", minutes: 90),
    ]

    func testDefaultIsThirtyDaysNewestFirst() {
        let f = WorkoutListFilter()
        XCTAssertTrue(f.isDefault)
        XCTAssertEqual(f.apply(to: workouts).map(\.id), ["run", "kb"])
    }

    func testActivityAndSortNarrow() {
        var f = WorkoutListFilter()
        f.sort = .duration
        XCTAssertFalse(f.isDefault)
        XCTAssertEqual(f.apply(to: workouts).map(\.id), ["kb", "run"])
        f.period = .all
        f.activity = "Running"
        XCTAssertEqual(f.apply(to: workouts).map(\.id), ["old", "run"])
    }

    func testActivitiesAreThePeriodsLabels() {
        XCTAssertEqual(WorkoutListFilter().activities(in: workouts), ["KB Movement Skill Session", "Running"])
    }
}
