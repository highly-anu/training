import Foundation

/// A session's log saved on the phone and not yet taken by the server
/// (design-system §6.16): what the form wrote, a completion, or its undo.
///
/// The form closes on the local write. `AppState.flushSessionLogs` sends the
/// record in the background and lets it go once the server answered; until
/// then every reload of the logs lays it back over what the server has
/// (`SessionLogOutbox.overlay`), so nothing the athlete entered disappears
/// while the connection is down.
struct PendingSessionLog: Codable, Equatable, Identifiable {
    var id: String { sessionKey }
    let sessionKey: String
    /// The account it was logged under; another account never sends it.
    var owner: String?
    var exercises: [String: ExercisePerformanceLog] = [:]
    /// Mark the session complete at this time.
    var completedAt: String?
    /// "Mark Incomplete" not yet sent: clear the server's completion.
    var clearsCompletion = false
    var savedAt = Date()
    /// Moves on with every local change, so a send that was in flight while
    /// the athlete saved again does not take the newer values with it.
    var revision = 0
    var attempts = 0
    /// Why the last send failed, in words; nil while none has.
    var lastError: String?
    /// The server refused it (a 4xx): sending again will not help.
    var rejected = false

    var isEmpty: Bool { exercises.isEmpty && completedAt == nil && !clearsCompletion }
}

enum SessionLogOutbox {

    // MARK: - Changes (pure)

    /// The form's Save, a completion or its undo, folded into what is already
    /// waiting for that session. A new change makes a refused record worth
    /// another try.
    static func merging(_ pending: [PendingSessionLog], sessionKey: String, owner: String?,
                        exercises: [String: ExercisePerformanceLog] = [:],
                        completedAt: String? = nil, clearsCompletion: Bool = false,
                        now: Date = Date()) -> [PendingSessionLog] {
        var out = pending
        let at = out.firstIndex { $0.sessionKey == sessionKey && $0.owner == owner }
        var record = at.map { out[$0] } ?? PendingSessionLog(sessionKey: sessionKey, owner: owner)
        record.exercises.merge(exercises) { _, new in new }
        if let completedAt {
            record.completedAt = completedAt
            record.clearsCompletion = false
        } else if clearsCompletion {
            // An unsent completion is simply dropped; one the server may have
            // (or is being sent right now) is cleared there.
            record.completedAt = nil
            record.clearsCompletion = true
        }
        record.savedAt = now
        record.revision += 1
        record.attempts = 0
        record.lastError = nil
        record.rejected = false
        if let at { out[at] = record } else { out.append(record) }
        return out
    }

    /// After the server took `sent`: let it go, unless it changed meanwhile.
    static func removing(_ pending: [PendingSessionLog], sent: PendingSessionLog) -> [PendingSessionLog] {
        pending.filter { !($0.sessionKey == sent.sessionKey && $0.owner == sent.owner && $0.revision == sent.revision) }
    }

    /// After a send of `sent` failed: say why on the record, unless it changed meanwhile.
    static func failing(_ pending: [PendingSessionLog], sent: PendingSessionLog,
                        error: String, rejected: Bool) -> [PendingSessionLog] {
        pending.map { record in
            guard record.sessionKey == sent.sessionKey, record.owner == sent.owner,
                  record.revision == sent.revision else { return record }
            var r = record
            r.attempts += 1
            r.lastError = error
            r.rejected = rejected
            return r
        }
    }

    /// The server's logs with what is still waiting laid over them.
    static func overlay(_ pending: [PendingSessionLog], owner: String?,
                        on logs: [String: SessionLogEntry]) -> [String: SessionLogEntry] {
        var out = logs
        for record in pending where record.owner == owner {
            let base = out[record.sessionKey]
            let completedAt = record.completedAt ?? (record.clearsCompletion ? nil : base?.completedAt)
            var exercises = base?.exercises ?? [:]
            exercises.merge(record.exercises) { _, new in new }
            // An undone session with nothing logged has no entry, as before.
            if completedAt == nil && exercises.isEmpty && base?.notes == nil && base?.matchedWorkoutId == nil {
                out.removeValue(forKey: record.sessionKey)
                continue
            }
            out[record.sessionKey] = SessionLogEntry(
                sessionKey: record.sessionKey, completedAt: completedAt, source: base?.source ?? "manual",
                notes: base?.notes, fatigueRating: base?.fatigueRating, avgHR: base?.avgHR, peakHR: base?.peakHR,
                matchedWorkoutId: base?.matchedWorkoutId, exercises: exercises,
                plannedName: base?.plannedName, plannedModality: base?.plannedModality,
                plannedDate: base?.plannedDate, programVersionId: base?.programVersionId,
                weekIndex: base?.weekIndex, dayName: base?.dayName, inCurrentProgram: base?.inCurrentProgram)
        }
        return out
    }

    /// The server said no to the request itself; the same body again gets the
    /// same answer. Not signed in, a timeout and "slow down" pass.
    static func isRejection(_ error: Error) -> Bool {
        let code: Int
        switch error {
        case APIError.serverError(let c): code = c
        case APIError.serverErrorDetail(let c, _): code = c
        default: return false
        }
        return (400..<500).contains(code) && ![401, 408, 429].contains(code)
    }

    /// Why a send failed, short enough for the notice.
    static func describe(_ error: Error) -> String {
        switch error {
        case APIError.serverError(let code), APIError.serverErrorDetail(let code, _): return "code \(code)"
        case APIError.unauthenticated: return "not signed in"
        case is URLError: return "no connection"
        default: return "not sent"
        }
    }

    /// How long to wait before the next try by itself: 15 s, a minute, then
    /// five. Coming back to the app and a connection returning try at once.
    static func retryDelay(attempts: Int) -> TimeInterval {
        switch attempts {
        case ...1: return 15
        case 2: return 60
        default: return 300
        }
    }

    /// The notice's words (Today, the session): nil while nothing has failed
    /// to send. `sessionKey` narrows it to one session.
    static func notice(_ pending: [PendingSessionLog], owner: String?, sessionKey: String? = nil) -> Notice? {
        let failed = pending.filter {
            $0.owner == owner && $0.lastError != nil && (sessionKey == nil || $0.sessionKey == sessionKey)
        }
        guard !failed.isEmpty else { return nil }
        let rejected = failed.filter(\.rejected)
        if !rejected.isEmpty, rejected.count == failed.count {
            let what = sessionKey != nil ? "this log" : rejected.count == 1 ? "a session log" : "\(rejected.count) session logs"
            return Notice(message: "The server did not take \(what) (\(rejected[0].lastError ?? "refused")). It is still saved on this phone.",
                          canDiscard: true, keys: rejected.map(\.sessionKey))
        }
        let what = sessionKey != nil ? "This log is" : failed.count == 1 ? "A session log is" : "\(failed.count) session logs are"
        return Notice(message: "\(what) saved on this phone but not sent yet. It sends by itself when the connection is back.",
                      canDiscard: false, keys: failed.map(\.sessionKey))
    }

    struct Notice: Equatable {
        let message: String
        /// Only a refused log offers Discard; an unsent one keeps trying.
        let canDiscard: Bool
        let keys: [String]
    }

    // MARK: - File

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("session-log-outbox.json")
    }

    static func load(from url: URL?) -> [PendingSessionLog] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingSessionLog].self, from: data)) ?? []
    }

    /// Atomic, so a kill mid-write leaves the last good file.
    static func store(_ pending: [PendingSessionLog], to url: URL?) {
        guard let url else { return }
        if pending.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
