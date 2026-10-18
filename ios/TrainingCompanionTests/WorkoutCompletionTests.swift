import XCTest
@testable import TrainingCompanion

/// `WorkoutCompletion` — which newly stored workout the "Workout complete"
/// sheet celebrates, what it offers to link it to, and its cheer — and the
/// `AppState` seen set around it. Async where an `AppState` goes out of
/// scope (see `CurrentWeekIndexTests`).
@MainActor
final class WorkoutCompletionTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-17T18:00:00Z")!

    private func workout(_ id: String, end: String?, minutes: Double? = 45, date: String = "2026-10-17",
                         avgHR: Int? = 140) -> ImportedWorkout {
        ImportedWorkout(id: id, source: "garmin", date: date, startTime: nil, endTime: end,
                        durationMinutes: minutes, activityType: "running",
                        inferredModalityId: "aerobic_base",
                        heartRate: avgHR.map { WorkoutHRData(avg: $0, max: nil, samples: []) },
                        calories: nil, distance: nil, gpsTrack: nil, elevation: nil)
    }

    private func session(_ modality: String = "aerobic_base") -> ProgramSession {
        ProgramSession(modality: modality, archetype: nil, isDeload: false, exercises: [])
    }

    // MARK: - Which workout

    func testNewestUnseenRecentWorkoutWins() {
        let list = [workout("a", end: "2026-10-17T07:00:00Z"),
                    workout("b", end: "2026-10-17T17:30:00Z"),
                    workout("c", end: "2026-10-16T19:00:00Z")]
        XCTAssertEqual(WorkoutCompletion.next(in: list, seen: [], now: now)?.id, "b")
        XCTAssertEqual(WorkoutCompletion.next(in: list, seen: ["b"], now: now)?.id, "a")
    }

    func testOldWorkoutIsHistoryNotAMoment() {
        let list = [workout("old", end: "2026-10-15T06:00:00Z")]
        XCTAssertNil(WorkoutCompletion.next(in: list, seen: [], now: now))
    }

    func testEmptyRecordIsNotCelebrated() {
        let list = [workout("blank", end: "2026-10-17T17:00:00Z", minutes: 0, avgHR: nil)]
        XCTAssertNil(WorkoutCompletion.next(in: list, seen: [], now: now))
    }

    func testParsesTheSnapshotsPostgresText() {
        XCTAssertEqual(LogSessions.parseServerDate("2026-10-17 08:10:00+02:00"),
                       ISO8601DateFormatter().date(from: "2026-10-17T06:10:00Z"))
        // Python's str(datetime) with microseconds.
        XCTAssertEqual(LogSessions.parseServerDate("2026-10-17 08:10:00.123000+02:00")?.timeIntervalSince1970 ?? 0,
                       ISO8601DateFormatter().date(from: "2026-10-17T06:10:00Z")!.timeIntervalSince1970 + 0.123,
                       accuracy: 0.001)
    }

    func testDateOnlyWorkoutToday() {
        // Ends at midnight tonight — ahead of now, and still today's moment.
        let list = [workout("d", end: nil, date: "2026-10-17")]
        XCTAssertEqual(WorkoutCompletion.next(in: list, seen: [], now: now)?.id, "d")
    }

    func testDateOnlyWorkoutEndsAtTheEndOfItsDay() {
        // No times at all: yesterday's still counts the next evening.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let w = workout("d", end: nil, date: "2026-10-17")
        XCTAssertEqual(WorkoutCompletion.endDate(of: w, calendar: cal),
                       ISO8601DateFormatter().date(from: "2026-10-18T00:00:00Z"))
    }

    // MARK: - What it links to

    func testLinkedBeatsSuggestion() {
        let m = WorkoutCompletion.match(matchedKey: "3-Friday-0", suggestionKey: "3-Friday-1",
                                        sameDay: [], isComplete: { _ in false }, session: { _ in nil })
        XCTAssertEqual(m, .linked(key: "3-Friday-0", session: nil))
    }

    func testRejectedMatchIsNotALink() {
        // An unlink leaves `sessionKey: ""` behind.
        let m = WorkoutCompletion.match(matchedKey: "", suggestionKey: nil, sameDay: [],
                                        isComplete: { _ in false }, session: { _ in nil })
        XCTAssertEqual(m, .unplanned)
    }

    func testSuggestionOffersTheDaysOtherOpenSessions() {
        let day = [WorkoutCompletion.Candidate(key: "3-Friday-0", session: session()),
                   WorkoutCompletion.Candidate(key: "3-Friday-1", session: session("mobility")),
                   WorkoutCompletion.Candidate(key: "3-Friday-2", session: session("power"))]
        let m = WorkoutCompletion.match(matchedKey: nil, suggestionKey: "3-Friday-0", sameDay: day,
                                        isComplete: { $0 == "3-Friday-2" }, session: { _ in nil })
        XCTAssertEqual(m, .suggested(key: "3-Friday-0", session: nil,
                                     others: [WorkoutCompletion.Candidate(key: "3-Friday-1",
                                                                          session: session("mobility"))]))
    }

    func testOpenSessionsWithoutSuggestion() {
        let day = [WorkoutCompletion.Candidate(key: "3-Friday-0", session: session())]
        XCTAssertEqual(WorkoutCompletion.match(matchedKey: nil, suggestionKey: nil, sameDay: day,
                                               isComplete: { _ in false }, session: { _ in nil }),
                       .candidates(day))
        XCTAssertEqual(WorkoutCompletion.match(matchedKey: nil, suggestionKey: nil, sameDay: day,
                                               isComplete: { _ in true }, session: { _ in nil }),
                       .unplanned)
    }

    // MARK: - The cheer

    func testCheerIsStablePerWorkoutAndFitsTheSituation() {
        let w = workout("abc", end: nil)
        let first = WorkoutCompletion.cheer(for: w, linked: true, planned: true, weekDone: 2, weekTotal: 5)
        XCTAssertEqual(first, WorkoutCompletion.cheer(for: w, linked: true, planned: true,
                                                      weekDone: 2, weekTotal: 5))
        let weekDone = WorkoutCompletion.cheer(for: w, linked: true, planned: true, weekDone: 5, weekTotal: 5)
        XCTAssertTrue(["Every session this week — done.", "Week complete. That's how it's built.",
                       "The whole week, in the bank."].contains(weekDone))
        let extra = WorkoutCompletion.cheer(for: w, linked: false, planned: false, weekDone: 0, weekTotal: 0)
        XCTAssertTrue(["Extra work counts too.", "Off-plan, still on purpose. Good job.",
                       "Every session adds up."].contains(extra))
    }

    // MARK: - Route

    private func fix(_ lat: Double, _ lng: Double) -> GPSPoint {
        GPSPoint(lat: lat, lng: lng, altitude: nil, timestamp: "2026-10-17T06:10:00Z", bpm: nil, speed: nil)
    }

    func testNoTrackNoMap() {
        XCTAssertFalse(WorkoutRoute.hasRoute([]))
        XCTAssertFalse(WorkoutRoute.hasRoute([fix(47.3779, 8.5402)]))
    }

    func testNoFixIsNotARoute() {
        // A device without a fix writes 0,0.
        XCTAssertFalse(WorkoutRoute.hasRoute([fix(0, 0), fix(0, 0), fix(47.3779, 8.5402)]))
    }

    func testGymSessionInOneSpotIsNotARoute() {
        // A strength session on a watch: a few metres of drift.
        XCTAssertFalse(WorkoutRoute.hasRoute([fix(47.37790, 8.54020), fix(47.37795, 8.54028), fix(47.37788, 8.54015)]))
    }

    func testARunIsARoute() {
        XCTAssertTrue(WorkoutRoute.hasRoute([fix(47.3779, 8.5402), fix(47.3712, 8.5240), fix(0, 0)]))
        XCTAssertEqual(WorkoutRoute.fixes([fix(47.3779, 8.5402), fix(0, 0)]).count, 1)
    }

    // MARK: - The week

    func testWeekDotsRunMondayToSunday() {
        let week = ProgramWeek(weekNumber: 3, weekInPhase: 1, isDeload: false, phase: "base",
                               schedule: ["Sunday": [session("mobility")],
                                          "Monday": [session(), session("power")]])
        let dots = WorkoutCompletion.weekDots(week) { $0 == "3-Monday-1" }
        XCTAssertEqual(dots.map(\.key), ["3-Monday-0", "3-Monday-1", "3-Sunday-0"])
        XCTAssertEqual(dots.map(\.done), [false, true, false])
    }

    // MARK: - AppState

    func testFirstLoadOnlyRecordsWhatIsThere() async {
        UserDefaults.standard.removeObject(forKey: "workoutComplete.seen")
        defer { UserDefaults.standard.removeObject(forKey: "workoutComplete.seen") }
        let state = AppState()
        state.workoutsLoaded = true
        state.importedWorkouts = [workout("old", end: "2026-10-17T07:00:00Z")]
        state.noticeCompletedWorkout(now: now)
        XCTAssertNil(state.completedWorkout)
        state.importedWorkouts.append(workout("new", end: "2026-10-17T17:30:00Z"))
        state.noticeCompletedWorkout(now: now)
        XCTAssertEqual(state.completedWorkout?.id, "new")
    }

    /// An athlete with no workouts yet: the empty first load is the one that
    /// records history, so their very first workout — from the watch, say —
    /// is news. It used to wait for a non-empty list and swallow that one.
    func testTheFirstWorkoutEverIsNews() async {
        let saved = UserDefaults.standard.stringArray(forKey: "workoutComplete.seen")
        UserDefaults.standard.removeObject(forKey: "workoutComplete.seen")
        defer { UserDefaults.standard.set(saved, forKey: "workoutComplete.seen") }
        let state = AppState()
        state.noticeCompletedWorkout(now: now)
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "workoutComplete.seen"),
                     "nothing is recorded before the list has loaded")
        state.workoutsLoaded = true
        state.noticeCompletedWorkout(now: now)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "workoutComplete.seen"), [])
        state.importedWorkouts = [workout("watch_live_1-Saturday-0", end: "2026-10-17T17:43:20Z")]
        state.noticeCompletedWorkout(now: now)
        XCTAssertEqual(state.completedWorkout?.id, "watch_live_1-Saturday-0")
    }

    func testUnknownIdShowsNothing() async {
        let state = AppState()
        state.importedWorkouts = [workout("a", end: "2026-10-17T07:00:00Z")]
        state.presentCompletedWorkout(id: "typo")
        XCTAssertNil(state.completedWorkout)
        state.presentCompletedWorkout(id: nil)
        XCTAssertEqual(state.completedWorkout?.id, "a")
    }

    func testSuggestionOfAnotherProgramVersion() {
        XCTAssertTrue(WorkoutCompletion.isCurrentProgram(uid: "v2:w1-Monday-0", versionId: "v2"))
        XCTAssertFalse(WorkoutCompletion.isCurrentProgram(uid: "v1:w1-Monday-0", versionId: "v2"))
        XCTAssertTrue(WorkoutCompletion.isCurrentProgram(uid: nil, versionId: "v2"))
    }

    func testClosingMarksEveryListedWorkoutSeen() async {
        UserDefaults.standard.set([String](), forKey: "workoutComplete.seen")
        defer { UserDefaults.standard.removeObject(forKey: "workoutComplete.seen") }
        let state = AppState()
        state.workoutsLoaded = true
        state.importedWorkouts = [workout("a", end: "2026-10-17T07:00:00Z"),
                                  workout("b", end: "2026-10-17T17:30:00Z")]
        state.noticeCompletedWorkout(now: now)
        XCTAssertEqual(state.completedWorkout?.id, "b")
        state.finishCompletedWorkout()
        XCTAssertNil(state.completedWorkout)
        // "a" arrived in the same sync; it waits in Log ▸ Linking, not in a second sheet.
        state.noticeCompletedWorkout(now: now)
        XCTAssertNil(state.completedWorkout)
    }

    func testEarlierProgramsMatchShowsNoSessionOfThisProgram() async {
        let state = AppState()
        let w = workout("old", end: "2026-10-17T07:00:00Z")
        state.importedWorkouts = [w]
        state.workoutMatches = ["old": WorkoutMatch(workoutId: "old", sessionKey: "4-Monday-0",
                                                    confidence: "auto", inCurrentProgram: false)]
        guard case .linked(let key, let session) = state.completionMatch(for: w) else {
            return XCTFail("expected linked")
        }
        XCTAssertEqual(key, "4-Monday-0")
        XCTAssertNil(session)
    }

    func testDeepLinkParses() {
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://workout-complete")!), .workoutComplete(nil))
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://workout-complete?id=w1")!),
                       .workoutComplete("w1"))
        XCTAssertEqual(DeepLink.parse(URL(string: "trainingcompanion://workout-complete?demo=1")!),
                       .workoutCompleteDemo)
    }
}
