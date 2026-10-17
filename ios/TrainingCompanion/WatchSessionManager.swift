import Combine
import CoreLocation
import Foundation
import HealthKit
import WatchConnectivity

// MARK: - WatchSessionManager

/// Relays the server's day to the Watch (`GET /user/today-session`, the
/// payload the Garmin reads) and the Watch's workouts back to the API.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    /// Replaced, not the manager, when SyncManager is configured again.
    var api: APIClient
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Name and modality of every session a sync has sent, by sessionId, to
    /// label the workouts the Watch sends back — kept across days, so a
    /// workout that arrives after midnight still finds its session.
    private var sessionCache: [String: (modality: String, name: String)] = [:]

    init(api: APIClient) {
        self.api = api
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Program sync

    /// Sends the Watch the server's day, as the server wrote it. Returns what
    /// it sent, so a watch that asked can have it in the reply: a queued
    /// transfer can take minutes to arrive.
    ///
    /// The phone used to build the day itself from `/user/program` — its
    /// own week and day maths (which crashed on a program starting a week
    /// ahead), slot-type guesses, load wording, a max HR from a date of
    /// birth of its own and a week list — and borrowed only the done flags,
    /// last times and standards from this payload.
    @discardableResult
    func syncProgram() async -> [String: Any]? {
        let today = dayFormatter.string(from: Date())
        do {
            let json = try await api.fetchWatchDay(date: today)
            let day = try JSONDecoder().decode(WatchDay.self, from: json)
            for s in (day.sessions ?? []) + (day.days ?? []).flatMap(\.sessions) {
                sessionCache[s.sessionId] = (modality: s.modalityId, name: s.archetypeName)
            }
            guard let payload = WatchDayMessage.payload(json: json) else {
                AppLogger.logFromBackground("WCSession: could not pack the day for the Watch")
                return nil
            }
            UserDefaults.standard.set(Date(), forKey: "lastProgramSyncDate")
            let size = (payload["day"] as? Data)?.count ?? 0
            AppLogger.logFromBackground("WCSession: sent the day to Watch — \(day.status), "
                                        + "\(day.sessions?.count ?? 0) sessions, \(size) bytes")
            return send(payload)
        } catch {
            // Was a bare silent catch: a failed fetch left the Watch on cached
            // sessions with nothing anywhere saying why.
            AppLogger.logFromBackground("WCSession: syncProgram FAILED — \(error.localizedDescription)")
            return nil
        }
    }

    /// Queue a day for the watch. `transferUserInfo` reaches it even when
    /// it is not reachable now; "no program" used to go only to a reachable
    /// watch, so one that asked while out of range never heard it. A day
    /// still in the queue is replaced, not delivered after it.
    private func send(_ payload: [String: Any]) -> [String: Any] {
        for queued in WCSession.default.outstandingUserInfoTransfers
        where queued.userInfo["type"] as? String == WatchDayMessage.type {
            queued.cancel()
        }
        WCSession.default.transferUserInfo(payload)
        return payload
    }

    private func encodedJSON<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let obj  = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return obj
    }

    // MARK: - Local buffer (survives upload failures)

    /// Writes raw summary JSON to Documents/watch_buffer/<id>.json before attempting upload.
    /// Deleted on success. Lets us inspect or retry failed uploads without data loss.
    nonisolated static func bufferSummary(_ data: Data, id: String) {
        guard let dir = bufferDir else { return }
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        let url = dir.appendingPathComponent("\(safe).json")
        try? data.write(to: url, options: .atomic)
    }

    nonisolated static func clearBuffer(id: String) {
        guard let dir = bufferDir else { return }
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(safe).json"))
    }

    private nonisolated static var bufferDir: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("watch_buffer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - WCSessionDelegate (receive workout summaries from Watch)

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let type = userInfo["type"] as? String ?? "(no type)"
        AppLogger.logFromBackground("WCSession: received userInfo type=\(type)")

        if type == WatchUploadMessage.sessionDone {
            guard let sessionId = userInfo["sessionId"] as? String,
                  let markedAt = userInfo["markedAt"] as? String else { return }
            Task { await handleSessionMarkedComplete(sessionId: sessionId, markedAt: markedAt) }
            return
        }

        guard type == WatchUploadMessage.workout else { return }
        guard let summary = WatchUploadMessage.summary(from: userInfo) else {
            AppLogger.logFromBackground("WCSession: failed to decode WatchWorkoutSummary")
            return
        }
        Task { await receive(summary) }
    }

    /// Large workout payloads arrive via transferFile when > 50 KB.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["type"] as? String == "workout_complete_file" else { return }
        guard let data = try? Data(contentsOf: file.fileURL),
              let summary = try? JSONDecoder().decode(WatchWorkoutSummary.self, from: data) else {
            AppLogger.logFromBackground("WCSession: failed to decode large workout file")
            return
        }
        Task { await receive(summary) }
    }

    /// Keep the summary on the phone until the server has it, then store it;
    /// true when the server has the workout and its log.
    @discardableResult
    private func receive(_ summary: WatchWorkoutSummary) async -> Bool {
        if let data = try? JSONEncoder().encode(summary) {
            WatchSessionManager.bufferSummary(data, id: summary.sessionId + "_" + summary.startedAt)
        }
        let stored = await handleWorkoutComplete(summary)
        if stored { NotificationCenter.default.post(name: .watchWorkoutStored, object: summary.sessionId) }
        return stored
    }

    /// Stores a session from the watch: its log, the workout, the match.
    /// True when the server has the log and the workout — what the watch's
    /// live send waits for before it lets the queued copy go.
    private func handleWorkoutComplete(_ summary: WatchWorkoutSummary) async -> Bool {
        // Track upload for SyncStatusView
        let now = Date()
        UserDefaults.standard.set(now, forKey: "lastWatchUploadDate")
        let count = UserDefaults.standard.integer(forKey: "watchUploadCount") + 1
        UserDefaults.standard.set(count, forKey: "watchUploadCount")

        let sessionKey = summary.sessionId
        let cachedSession = sessionCache[sessionKey]
        let setLogSummary = summary.setLogs.map { "\($0.key):\($0.value.count)sets" }.joined(separator: ", ")
        AppLogger.logFromBackground("WCSession: decoded summary — session=\(sessionKey) duration=\(summary.durationMinutes)min exercises=\(summary.exercisesCompleted) setLogs=[\(setLogSummary)] avgHR=\(summary.avgHR.map{"\($0)"} ?? "nil")")

        // 1. Save session log (exercises, set data, outcomes, HR aggregates,
        //    and the Results answer given on the watch)
        var log = WatchUpload.sessionLog(summary: summary)
        if let timeline = summary.exerciseTimeline { log["exerciseTimeline"] = encodedJSON(timeline) }

        AppLogger.logFromBackground("API: saving workout log for \(sessionKey)…")
        var logSaved = false
        do {
            try await api.saveWorkoutLog(sessionKey: sessionKey, log: log)
            logSaved = true
            AppLogger.logFromBackground("API: saved workout log for \(sessionKey) ✓")
        } catch {
            AppLogger.logFromBackground("API: saveWorkoutLog FAILED — \(error.localizedDescription)")
        }

        // 2. Store the workout through the server. Elevation comes from the
        //    track's altitudes, copies of the same activity from other sources
        //    fold into one row, and a write that fails is reported rather
        //    than lost — none of which the raw Supabase upsert this path used
        //    to do could offer (see WatchUpload).
        guard let startDate = WatchUpload.parseStart(summary.startedAt) else {
            AppLogger.logFromBackground("API: saveWatchWorkout SKIPPED — could not parse startedAt: \(summary.startedAt)")
            return false
        }
        let workoutId = WatchUpload.workoutId(sessionKey: sessionKey, startedAt: summary.startedAt)
        let workout = WatchUpload.workoutPayload(summary: summary, workoutId: workoutId, startDate: startDate,
                                                 sessionName: cachedSession?.name, modality: cachedSession?.modality)
        do {
            try await api.saveWatchWorkouts([workout])
            AppLogger.logFromBackground("API: saved watch workout \(workoutId) ✓")
            // Safe to discard the local buffer now that the server has the row.
            WatchSessionManager.clearBuffer(id: sessionKey + "_" + summary.startedAt)
        } catch {
            AppLogger.logFromBackground("API: saveWatchWorkout FAILED — \(error.localizedDescription)")
            return false
        }

        // 3. Link the workout to the session. The server resolves the
        //    program version's session_uid and clears any suggestion. If dedup
        //    folded this upload into a copy that was already there, the match
        //    goes to that listed row, not to the hidden duplicate.
        let listed = (try? await api.fetchWorkouts()) ?? []
        let linkId = WatchUpload.canonicalId(for: workoutId, date: summary.date,
                                             startedAt: summary.startedAt, in: listed)
        do {
            try await api.saveWorkoutMatch(WatchUpload.matchPayload(workoutId: linkId, sessionKey: sessionKey))
            AppLogger.logFromBackground("API: saved workout match \(linkId) → \(sessionKey) ✓")
        } catch {
            AppLogger.logFromBackground("API: saveWorkoutMatch FAILED — \(error.localizedDescription)")
        }

        // 4. Async GPS enrichment: try to fetch the full HKWorkoutRoute after a short delay
        //    (HealthKit sync from Watch → iPhone takes ~5–30 s)
        let existingGPSCount = (workout["gpsTrack"] as? [[String: Any]])?.count ?? 0
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 s
            await enrichWorkoutWithHKRoute(workout: workout, startDate: startDate,
                                           existingGPSCount: existingGPSCount)
        }
        // A match that failed is not worth a second delivery: the workout and
        // its log are stored, and the matcher can still link them.
        return logSaved
    }

    @discardableResult
    private func handleSessionMarkedComplete(sessionId: String, markedAt: String) async -> Bool {
        AppLogger.logFromBackground("WCSession: session_marked_complete — \(sessionId) at \(markedAt)")
        do {
            try await api.saveSessionComplete(sessionKey: sessionId, completedAt: markedAt, source: "apple_watch_live")
            AppLogger.logFromBackground("API: marked session complete \(sessionId) ✓")
            NotificationCenter.default.post(name: .watchWorkoutStored, object: sessionId)
            return true
        } catch {
            AppLogger.logFromBackground("API: saveSessionComplete FAILED — \(error.localizedDescription)")
            return false
        }
    }

    private func enrichWorkoutWithHKRoute(workout: [String: Any], startDate: Date, existingGPSCount: Int) async {
        guard let hkWorkout = await HealthKitManager.shared.findHKWorkout(near: startDate) else {
            // Retry once at 60 s
            try? await Task.sleep(nanoseconds: 50_000_000_000)
            guard let hkWorkout = await HealthKitManager.shared.findHKWorkout(near: startDate) else { return }
            await uploadRoute(from: hkWorkout, workout: workout, existingGPSCount: existingGPSCount)
            return
        }
        await uploadRoute(from: hkWorkout, workout: workout, existingGPSCount: existingGPSCount)
    }

    private func uploadRoute(from hkWorkout: HKWorkout, workout: [String: Any], existingGPSCount: Int) async {
        let locations = await HealthKitManager.shared.fetchWorkoutRoute(for: hkWorkout)
        guard locations.count > existingGPSCount else { return }
        let iso = ISO8601DateFormatter()
        let gpsTrack: [[String: Any]] = locations.map { loc in
            var p: [String: Any] = [
                "lat": loc.coordinate.latitude,
                "lng": loc.coordinate.longitude,
                "timestamp": iso.string(from: loc.timestamp),
            ]
            if loc.altitude > 0 { p["altitude"] = loc.altitude }
            return p
        }
        let workoutId = workout["id"] as? String ?? "?"
        do {
            try await api.saveWatchWorkouts([WatchUpload.enriched(workout, gpsTrack: gpsTrack)])
            AppLogger.logFromBackground("API: enriched workout \(workoutId) with \(locations.count) GPS points ✓")
        } catch {
            AppLogger.logFromBackground("API: GPS enrichment FAILED — \(error.localizedDescription)")
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String, type == "request_sync" else { return }
        Task { await syncProgram() }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        // A session sent live: stored on the server before the reply, which
        // tells the watch whether it still needs to queue its copy.
        if let summary = WatchUploadMessage.summary(from: message) {
            AppLogger.logFromBackground("WCSession: received workout live — \(summary.sessionId)")
            Task { replyHandler(WatchUploadMessage.reply(stored: await receive(summary))) }
            return
        }
        if message["type"] as? String == WatchUploadMessage.sessionDone,
           let sessionId = message["sessionId"] as? String, let markedAt = message["markedAt"] as? String {
            Task {
                let stored = await handleSessionMarkedComplete(sessionId: sessionId, markedAt: markedAt)
                replyHandler(WatchUploadMessage.reply(stored: stored))
            }
            return
        }
        guard let type = message["type"] as? String, type == "request_sync" else {
            replyHandler([:])
            return
        }
        // The day itself is the reply; the same payload is queued too, for
        // when the reply cannot be delivered.
        Task {
            let payload = await syncProgram()
            replyHandler(payload ?? ["status": "failed"])
        }
    }

    /// Paired, installed, reachable: Settings reads these live and redraws on
    /// this notification. An app that has just been installed gets its day.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            NotificationCenter.default.post(name: .watchStateDidChange, object: nil)
            if installed { await syncProgram() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in NotificationCenter.default.post(name: .watchStateDidChange, object: nil) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { await syncProgram() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}


extension Notification.Name {
    /// The Apple Watch was paired, installed, removed or came in range.
    static let watchStateDidChange = Notification.Name("watchStateDidChange")
    /// The server has a session the Apple Watch recorded (object: its key).
    static let watchWorkoutStored = Notification.Name("watchWorkoutStored")
}
