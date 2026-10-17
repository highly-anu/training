import Combine
import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    /// `unavailable`: the iPhone cannot be reached. `syncFailed`: it was
    /// reached and could not get the day (no network, the server down).
    enum ProgramState { case loading, ready, noProgram, programExpired, unavailable, syncFailed }

    @Published var todaySessions: [WatchSession] = []
    @Published var completedSessionIds: Set<String> = []
    @Published var maxHR: Int = 190
    @Published var programState: ProgramState = .loading
    @Published var weeklyOverview: [WeeklyOverviewDay] = []
    @Published var readiness: ReadinessInfo? = nil
    /// This program week from the server's `progress`: done, and sessions in all.
    @Published var weekDone: (done: Int, sessions: Int)? = nil
    /// Set by deep link (watch widget tap) to navigate directly to a specific session.
    @Published var pendingDeepLinkSessionId: String? = nil

    private let sessionsKey        = "watchTodaySessions"
    private let sessionsDayKey     = "watchTodaySessionsDay"  // "yyyy-MM-dd" of cached sessions
    private let maxHRKey           = "watchMaxHR"
    private let completedKey       = "watchCompletedSessions"
    /// The server's `progress` block (week done/due, program %, headline) as
    /// JSON, for the week ring and the complication.
    private let progressKey        = "watchProgress"
    private let weeklyOverviewKey  = "watchWeeklyOverview"
    private let readinessKey       = "watchReadiness"
    private var completedDate: String = ""

    private var todayDateString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    override init() {
        super.init()
        loadCache()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        if programState == .loading {
            startLoadingTimeout()
        }
    }

    /// Ask the iPhone for today. The day comes back in the reply; the same
    /// day is also queued with `transferUserInfo`, which can take minutes. A
    /// state already known (a day, no program) stays on screen meanwhile —
    /// asking used to put every screen back to "Syncing…" and then, ten
    /// seconds on, to "iPhone unreachable" while the phone's answer was
    /// still in its queue.
    func requestSync() {
        if programState == .unavailable || programState == .syncFailed { programState = .loading }
        if programState == .loading { startLoadingTimeout() }
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["type": "request_sync"], replyHandler: { reply in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if reply["type"] != nil { self.apply(reply) }
                else if self.programState == .loading { self.programState = .syncFailed }
            }
        }, errorHandler: { _ in
            Task { @MainActor [weak self] in
                guard let self, self.programState == .loading else { return }
                self.programState = WCSession.default.isReachable ? .syncFailed : .unavailable
            }
        })
    }

    /// Unreachable only when the phone is: a reachable phone answers the
    /// request, or its error handler says why not.
    private func startLoadingTimeout() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.programState == .loading, !WCSession.default.isReachable else { return }
            self.programState = .unavailable
        }
    }

    func sendWorkoutSummary(_ summary: WatchWorkoutSummary) {
        guard let data = try? JSONEncoder().encode(summary),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        dict["type"] = "workout_complete"

        // Cancel any previously queued transfers for the same session so re-runs
        // during testing don't result in stale data being delivered after the new one.
        for pending in WCSession.default.outstandingUserInfoTransfers
        where pending.userInfo["type"] as? String == "workout_complete"
           && pending.userInfo["sessionId"] as? String == summary.sessionId {
            pending.cancel()
        }

        // transferUserInfo has a ~65 KB limit. Re-serialise to check size.
        let payloadData = (try? JSONSerialization.data(withJSONObject: dict)) ?? data
        if payloadData.count <= 50_000 {
            WCSession.default.transferUserInfo(dict)
        } else {
            // Large payload (long workout with many GPS/HR points) — use file transfer
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("workout_\(summary.sessionId).json")
            try? payloadData.write(to: tmpURL)
            WCSession.default.transferFile(
                tmpURL,
                metadata: ["type": "workout_complete_file", "sessionId": summary.sessionId]
            )
        }
    }

    /// Two yyyy-MM-dd dates in the same Monday-based week.
    nonisolated static func sameWeek(_ a: String, _ b: String) -> Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        guard let da = f.date(from: a), let db = f.date(from: b),
              let wa = cal.dateInterval(of: .weekOfYear, for: da), let wb = cal.dateInterval(of: .weekOfYear, for: db)
        else { return false }
        return wa.start == wb.start
    }

    /// `progress.week` → (done, sessions); nil when the week holds none.
    nonisolated static func weekDone(from progress: [String: Any]) -> (done: Int, sessions: Int)? {
        guard let week = progress["week"] as? [String: Any],
              let done = week["done"] as? Int, let sessions = week["sessions"] as? Int, sessions > 0
        else { return nil }
        return (done, sessions)
    }

    func markSessionComplete(_ sessionId: String) {
        let isNew = !completedSessionIds.contains(sessionId)
        completedSessionIds.insert(sessionId)
        let ids = Array(completedSessionIds)
        UserDefaults.standard.set(ids, forKey: completedKey)
        // The complication shows the week and today's done state: count this
        // session in the week now rather than at the next sync, and redraw.
        if isNew, let week = weekDone { weekDone = (min(week.done + 1, week.sessions), week.sessions) }
        writeWidgetData(sessions: todaySessions, date: todayDateString)
        // Notify iPhone so it can sync the completion to the API
        sendSessionMarkedComplete(sessionId)
    }

    private func sendSessionMarkedComplete(_ sessionId: String) {
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "type":      "session_marked_complete",
            "sessionId": sessionId,
            "markedAt":  iso.string(from: Date()),
        ]
        // Use transferUserInfo (queued, reliable delivery)
        WCSession.default.transferUserInfo(payload)
    }

    private func loadCache() {
        let today = todayDateString
        let cachedDay = UserDefaults.standard.string(forKey: sessionsDayKey) ?? ""
        if cachedDay == today,
           let data = UserDefaults.standard.data(forKey: sessionsKey),
           let sessions = try? JSONDecoder().decode([WatchSession].self, from: data) {
            todaySessions = sessions
            let mhr = UserDefaults.standard.integer(forKey: maxHRKey)
            maxHR = mhr > 0 ? mhr : 190
            programState = .ready
        } else {
            // Stale — clear so we don't show yesterday's workout until fresh data arrives
            todaySessions = []
            programState = .loading
        }
        // Load cached weekly overview (persists across days)
        if let overviewData = UserDefaults.standard.data(forKey: weeklyOverviewKey),
           let overview = try? JSONDecoder().decode([WeeklyOverviewDay].self, from: overviewData) {
            weeklyOverview = overview
        }
        // Last week's count must not stand in on a Monday before the first sync:
        // keep it only while it is from this week (program weeks start Monday).
        if let data = UserDefaults.standard.data(forKey: progressKey),
           let saved = UserDefaults.standard.string(forKey: progressKey + "_date"),
           Self.sameWeek(saved, todayDateString),
           let progress = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            weekDone = Self.weekDone(from: progress)
        }
        // Load cached readiness
        if let readData = UserDefaults.standard.data(forKey: readinessKey),
           let info = try? JSONDecoder().decode(ReadinessInfo.self, from: readData) {
            readiness = info
        }
        // Load completed sessions — reset if it's a new day. The stamp is the
        // yyyy-MM-dd the phone sends with the day; comparing it to a localized
        // short date never matched, so every relaunch forgot what was done.
        let todayStr = todayDateString
        let savedDate = UserDefaults.standard.string(forKey: completedKey + "_date") ?? ""
        if savedDate == todayStr, let ids = UserDefaults.standard.array(forKey: completedKey) as? [String] {
            completedSessionIds = Set(ids)
        } else {
            // New day — clear completed
            UserDefaults.standard.removeObject(forKey: completedKey)
            UserDefaults.standard.set(todayStr, forKey: completedKey + "_date")
        }
    }

    // MARK: - Widget Data

    /// Writes today's sessions to the shared App Group container so the watch widget can display them.
    private func writeWidgetData(sessions: [WatchSession], date: String) {
        let widgetSessions = sessions.map { s in
            WidgetSession(
                id: s.sessionId,
                modalityId: s.modalityId,
                archetypeName: s.archetypeName,
                estimatedMinutes: s.estimatedMinutes,
                isDeload: s.isDeload,
                exerciseNames: Array(s.exercises.prefix(4).map { $0.name })
            )
        }
        var data = WidgetTodayData(date: date, sessions: widgetSessions, updatedAt: Date())
        data.completedIds = Array(completedSessionIds)
        data.weekDone = weekDone?.done
        data.weekSessions = weekDone?.sessions
        data.readinessScore = readiness.map { Int(($0.score * 100).rounded()) }
        data.readinessSignal = readiness?.signal
        WidgetDataStore.write(data)
    }
}

extension WatchConnectivityManager {
    /// One day from the phone, whether it came as the reply to a request or
    /// as a queued transfer.
    func apply(_ userInfo: [String: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        switch type {
        case "today_sessions":
            // New day's sessions — clear yesterday's completed set
            if let incomingDate = userInfo["date"] as? String,
               incomingDate != UserDefaults.standard.string(forKey: completedKey + "_date") {
                completedSessionIds = []
                UserDefaults.standard.removeObject(forKey: completedKey)
                UserDefaults.standard.set(incomingDate, forKey: completedKey + "_date")
            }
            // Sessions the server says are done (logged or matched on any
            // device), joined to what this watch recorded.
            if let ids = userInfo["completedIds"] as? [String], !ids.isEmpty {
                completedSessionIds.formUnion(ids)
                UserDefaults.standard.set(Array(completedSessionIds), forKey: completedKey)
            }
            if let progress = userInfo["progress"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: progress) {
                UserDefaults.standard.set(data, forKey: progressKey)
                UserDefaults.standard.set(todayDateString, forKey: progressKey + "_date")
                weekDone = Self.weekDone(from: progress)
            }
            if let profile = userInfo["profile"] as? [String: Any],
               let mhr = profile["maxHR"] as? Int {
                maxHR = mhr
                UserDefaults.standard.set(mhr, forKey: maxHRKey)
            }
            if let raw = userInfo["sessions"],
               let data = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode([WatchSession].self, from: data) {
                todaySessions = decoded
                if let saved = try? JSONEncoder().encode(decoded) {
                    UserDefaults.standard.set(saved, forKey: sessionsKey)
                }
                // Record the date these sessions are for so loadCache can detect staleness
                let sessionDate = (userInfo["date"] as? String) ?? todayDateString
                UserDefaults.standard.set(sessionDate, forKey: sessionsDayKey)
            } else {
                todaySessions = []
                UserDefaults.standard.removeObject(forKey: sessionsDayKey)
            }
            // Decode weekly overview
            if let raw = userInfo["weeklyOverview"],
               let data = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode([WeeklyOverviewDay].self, from: data) {
                weeklyOverview = decoded
                UserDefaults.standard.set(data, forKey: weeklyOverviewKey)
            }

            // Decode readiness
            if let raw = userInfo["readiness"],
               let data = try? JSONSerialization.data(withJSONObject: raw),
               let decoded = try? JSONDecoder().decode(ReadinessInfo.self, from: data) {
                readiness = decoded
                UserDefaults.standard.set(data, forKey: readinessKey)
            }

            programState = .ready
            writeWidgetData(sessions: todaySessions, date: (userInfo["date"] as? String) ?? todayDateString)

        case "no_program":
            todaySessions = []
            programState = .noProgram

        case "program_expired":
            todaySessions = []
            programState = .programExpired

        default:
            break
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.apply(userInfo) }
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            // If we're showing stale (or no) sessions, ask the phone for today's data
            let cachedDay = UserDefaults.standard.string(forKey: sessionsDayKey) ?? ""
            guard cachedDay != todayDateString else { return }
            requestSync()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            // Phone just came in range — refresh if sessions are stale
            let cachedDay = UserDefaults.standard.string(forKey: sessionsDayKey) ?? ""
            guard cachedDay != todayDateString else { return }
            requestSync()
        }
    }
}
