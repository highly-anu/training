import XCTest
@testable import TrainingCompanion

/// The session log form's draft and the outbox its Save writes to
/// (design-system §6.16): one save for the whole session, kept on the phone
/// until the server took it.
final class SessionLogOutboxTests: XCTestCase {

    private func perf(_ reps: Int, kg: Double = 80) -> ExercisePerformanceLog {
        ExercisePerformanceLog(sets: [WatchSetLog(setIndex: 0, repsActual: reps, weightKg: kg, rpe: nil, completed: true,
                                                  durationSeconds: nil, startOffset: nil, endOffset: nil)])
    }

    private func session() throws -> ProgramSession {
        try JSONDecoder().decode(ProgramSession.self, from: """
        {"modality": "max_strength", "exercises": [
            {"exercise": {"id": "back_squat", "name": "Back Squat"}, "load": {"sets": 3, "reps": 5, "weight_kg": 80}},
            {"exercise": {"id": "bench_press", "name": "Bench Press"}, "load": {"sets": 3, "reps": 5, "weight_kg": 60}},
            {"exercise": {"id": "back_squat", "name": "Back Squat"}, "load": {"sets": 1, "reps": 5}}
        ]}
        """.data(using: .utf8)!)
    }

    // MARK: - Draft

    func testOnlyTickedExercisesAreSaved() throws {
        var drafts = SessionLogDraft.exercises(of: try session(), log: nil)
        XCTAssertEqual(drafts.map(\.exerciseId), ["back_squat", "bench_press"], "a movement listed twice is one entry")
        XCTAssertEqual(drafts[0].values.sets.count, 3, "prefilled from the prescription")
        XCTAssertTrue(SessionLogDraft.performances(drafts).isEmpty, "a prescription nobody touched is not a result")

        drafts[1].values.sets[0].reps = 4
        drafts[1].included = true
        let saved = SessionLogDraft.performances(drafts)
        XCTAssertEqual(Array(saved.keys), ["bench_press"])
        XCTAssertEqual(saved["bench_press"]?.sets.map(\.repsActual), [4, 5, 5])
        XCTAssertEqual(saved["bench_press"]?.sets.first?.weightKg, 60)
    }

    func testOpenedExerciseAndLoggedOnesStartTicked() throws {
        let log = SessionLogEntry(sessionKey: "1-Monday-0", completedAt: nil, source: "manual", notes: nil,
                                  fatigueRating: nil, avgHR: nil, peakHR: nil, matchedWorkoutId: nil,
                                  exercises: ["back_squat": perf(3, kg: 100)], plannedName: nil, plannedModality: nil,
                                  plannedDate: nil, programVersionId: nil, weekIndex: nil, dayName: nil,
                                  inCurrentProgram: nil)
        let drafts = SessionLogDraft.exercises(of: try session(), log: log, openAt: "bench_press")
        XCTAssertEqual(drafts.map(\.included), [true, true])
        XCTAssertEqual(drafts[0].values.sets.map(\.reps), [3], "what was logged, not the prescription")
        XCTAssertEqual(drafts[0].values.sets.first?.kg, 100)
    }

    // MARK: - Outbox

    func testSavesMergeIntoOneRecordPerSession() {
        var pending = SessionLogOutbox.merging([], sessionKey: "1-Monday-0", owner: "u", exercises: ["a": perf(5)])
        pending = SessionLogOutbox.merging(pending, sessionKey: "1-Monday-0", owner: "u",
                                           exercises: ["b": perf(8)], completedAt: "2026-11-12T10:00:00Z")
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(Set(pending[0].exercises.keys), ["a", "b"])
        XCTAssertEqual(pending[0].completedAt, "2026-11-12T10:00:00Z")
        XCTAssertEqual(pending[0].revision, 2)

        pending = SessionLogOutbox.merging(pending, sessionKey: "1-Monday-0", owner: "u", clearsCompletion: true)
        XCTAssertNil(pending[0].completedAt)
        XCTAssertTrue(pending[0].clearsCompletion)
        XCTAssertEqual(Set(pending[0].exercises.keys), ["a", "b"], "undoing keeps what was logged")
    }

    func testASendDoesNotTakeANewerSaveWithIt() {
        let first = SessionLogOutbox.merging([], sessionKey: "k", owner: nil, exercises: ["a": perf(5)])
        let inFlight = first[0]
        let second = SessionLogOutbox.merging(first, sessionKey: "k", owner: nil, exercises: ["a": perf(6)])
        XCTAssertEqual(SessionLogOutbox.removing(second, sent: inFlight), second, "the newer save still waits")
        XCTAssertEqual(SessionLogOutbox.failing(second, sent: inFlight, error: "no connection", rejected: false), second)
        XCTAssertTrue(SessionLogOutbox.removing(second, sent: second[0]).isEmpty)
    }

    func testOverlayLaysPendingOverTheServersLogs() {
        let server = ["k": SessionLogEntry(sessionKey: "k", completedAt: "2026-11-11T09:00:00Z", source: "manual",
                                           notes: "felt fine", fatigueRating: nil, avgHR: nil, peakHR: nil,
                                           matchedWorkoutId: nil, exercises: ["a": perf(5)], plannedName: nil,
                                           plannedModality: nil, plannedDate: nil, programVersionId: nil,
                                           weekIndex: nil, dayName: nil, inCurrentProgram: nil)]
        var pending = SessionLogOutbox.merging([], sessionKey: "k", owner: "u", exercises: ["b": perf(8)])
        var shown = SessionLogOutbox.overlay(pending, owner: "u", on: server)
        XCTAssertEqual(Set(shown["k"]!.exercises.keys), ["a", "b"])
        XCTAssertEqual(shown["k"]?.completedAt, "2026-11-11T09:00:00Z")
        XCTAssertEqual(shown["k"]?.notes, "felt fine")

        pending = SessionLogOutbox.merging(pending, sessionKey: "k", owner: "u", clearsCompletion: true)
        shown = SessionLogOutbox.overlay(pending, owner: "u", on: server)
        XCTAssertNil(shown["k"]?.completedAt)

        let other = SessionLogOutbox.overlay(pending, owner: "someone-else", on: server)
        XCTAssertEqual(other["k"]?.completedAt, "2026-11-11T09:00:00Z", "another account never sees it")
        XCTAssertEqual(other["k"].map { Set($0.exercises.keys) }, ["a"])
    }

    func testNoticeSpeaksOnlyAfterAFailedSend() {
        let waiting = SessionLogOutbox.merging([], sessionKey: "k", owner: nil, exercises: ["a": perf(5)])
        XCTAssertNil(SessionLogOutbox.notice(waiting, owner: nil), "a save on its way is not a problem yet")

        let offline = SessionLogOutbox.failing(waiting, sent: waiting[0], error: "no connection", rejected: false)
        let notice = SessionLogOutbox.notice(offline, owner: nil)
        XCTAssertEqual(notice?.canDiscard, false)
        XCTAssertEqual(notice?.keys, ["k"])
        XCTAssertNil(SessionLogOutbox.notice(offline, owner: nil, sessionKey: "other"))

        let refused = SessionLogOutbox.failing(waiting, sent: waiting[0], error: "code 422", rejected: true)
        XCTAssertEqual(SessionLogOutbox.notice(refused, owner: nil, sessionKey: "k")?.canDiscard, true)

        XCTAssertTrue(SessionLogOutbox.isRejection(APIError.serverError(422)))
        XCTAssertFalse(SessionLogOutbox.isRejection(APIError.serverError(503)))
        XCTAssertFalse(SessionLogOutbox.isRejection(APIError.serverError(401)))
        XCTAssertFalse(SessionLogOutbox.isRejection(URLError(.notConnectedToInternet)))
    }

    func testTheFileSurvivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = SessionLogOutbox.merging([], sessionKey: "k", owner: "u", exercises: ["a": perf(5)],
                                               completedAt: "2026-11-12T10:00:00Z")
        SessionLogOutbox.store(pending, to: url)
        XCTAssertEqual(SessionLogOutbox.load(from: url), pending)
        SessionLogOutbox.store([], to: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - AppState

    /// Save answers at once, with no server: the log shows, is kept on disk
    /// and is laid back over whatever the next launch loads.
    @MainActor
    func testSaveIsLocalAndComesBackAfterARelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let appState = AppState()
        appState.useSessionLogOutbox(at: url)
        appState.saveSessionLog(sessionKey: "1-Monday-0", exercises: ["a": perf(5)],
                                completedAt: "2026-11-12T10:00:00Z")
        XCTAssertTrue(appState.isSessionComplete("1-Monday-0"))
        XCTAssertEqual(appState.sessionLogs["1-Monday-0"]?.exercises["a"], perf(5))
        XCTAssertEqual(appState.pendingSessionLogs.count, 1)

        let relaunched = AppState()
        relaunched.useSessionLogOutbox(at: url)
        XCTAssertTrue(relaunched.isSessionComplete("1-Monday-0"))
        XCTAssertEqual(relaunched.sessionLogs["1-Monday-0"]?.exercises["a"], perf(5))

        relaunched.undoSessionComplete(sessionKey: "1-Monday-0")
        XCTAssertFalse(relaunched.isSessionComplete("1-Monday-0"))
        XCTAssertEqual(relaunched.sessionLogs["1-Monday-0"]?.exercises["a"], perf(5), "the sets stay")
    }
}
