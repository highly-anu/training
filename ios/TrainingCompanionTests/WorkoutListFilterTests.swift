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

    // MARK: - Log ▸ Activity: workouts and session logs in one list

    private func session(_ key: String, daysAgo: Int?) -> LogSessionRow {
        let done = daysAgo.map { Calendar.current.date(byAdding: .hour, value: -24 * $0 + 1, to: Date())! }
        return LogSessionRow(id: key, key: key, title: key, subtitle: "", lines: [], isComplete: done != nil,
                             completedAt: done, isLocatable: false)
    }

    private lazy var sessions = [session("squat", daysAgo: 2), session("open", daysAgo: nil),
                                 session("swing", daysAgo: 4), session("ancient", daysAgo: 90)]

    private func ids(_ entries: [LogEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .workout(let w): return w.id
            case .session(let row): return row.key
            }
        }
    }

    func testActivityMergesNewestFirstWithTheOpenLogLast() {
        let f = WorkoutListFilter()
        // A workout with no start time counts from its day's midnight; the
        // squat log was completed later on the run's day.
        XCTAssertEqual(ids(f.entries(workouts: workouts, sessions: sessions)), ["squat", "run", "swing", "kb", "open"])
    }

    func testShowKeepsOneTypeAndAnActivityKeepsWorkouts() {
        var f = WorkoutListFilter()
        f.show = .sessions
        XCTAssertFalse(f.isDefault)
        XCTAssertEqual(ids(f.entries(workouts: workouts, sessions: sessions)), ["squat", "swing", "open"])
        f.show = .workouts
        XCTAssertEqual(ids(f.entries(workouts: workouts, sessions: sessions)), ["run", "kb"])
        f = WorkoutListFilter()
        f.activity = "Running"
        XCTAssertEqual(ids(f.entries(workouts: workouts, sessions: sessions)), ["run"])
    }

    func testAnotherSortLeadsWithWorkoutsThenSessionsNewestFirst() {
        var f = WorkoutListFilter()
        f.sort = .duration
        XCTAssertEqual(ids(f.entries(workouts: workouts, sessions: sessions)), ["kb", "run", "squat", "swing", "open"])
        XCTAssertEqual(WorkoutFilterScopeLine.counts(f.entries(workouts: workouts, sessions: sessions), filter: f),
                       "2 workouts · 3 sessions")
    }
}
