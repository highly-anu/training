import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    enum ProgramState { case loading, ready, noProgram, programExpired, unavailable }

    @Published var todaySessions: [WatchSession] = []
    @Published var completedSessionIds: Set<String> = []
    @Published var maxHR: Int = 190
    @Published var programState: ProgramState = .loading
    @Published var weeklyOverview: [WeeklyOverviewDay] = []
    @Published var readiness: ReadinessInfo? = nil

    private let sessionsKey        = "watchTodaySessions"
    private let sessionsDayKey     = "watchTodaySessionsDay"  // "yyyy-MM-dd" of cached sessions
    private let maxHRKey           = "watchMaxHR"
    private let completedKey       = "watchCompletedSessions"
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

    func requestSync() {
        programState = .loading
        startLoadingTimeout()
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["type": "request_sync"], replyHandler: nil)
    }

    private func startLoadingTimeout() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, self.programState == .loading else { return }
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

    func markSessionComplete(_ sessionId: String) {
        completedSessionIds.insert(sessionId)
        let ids = Array(completedSessionIds)
        UserDefaults.standard.set(ids, forKey: completedKey)
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
        // Load cached readiness
        if let readData = UserDefaults.standard.data(forKey: readinessKey),
           let info = try? JSONDecoder().decode(ReadinessInfo.self, from: readData) {
            readiness = info
        }
        // Load completed sessions — reset if it's a new day
        let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let savedDate = UserDefaults.standard.string(forKey: completedKey + "_date") ?? ""
        if savedDate == todayStr, let ids = UserDefaults.standard.array(forKey: completedKey) as? [String] {
            completedSessionIds = Set(ids)
        } else {
            // New day — clear completed
            UserDefaults.standard.removeObject(forKey: completedKey)
            UserDefaults.standard.set(todayStr, forKey: completedKey + "_date")
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             didReceiveUserInfo userInfo: [String: Any]) {
        guard let type = userInfo["type"] as? String else { return }
        Task { @MainActor in
            switch type {
            case "today_sessions":
                // New day's sessions — clear yesterday's completed set
                if let incomingDate = userInfo["date"] as? String,
                   incomingDate != UserDefaults.standard.string(forKey: completedKey + "_date") {
                    completedSessionIds = []
                    UserDefaults.standard.removeObject(forKey: completedKey)
                    UserDefaults.standard.set(incomingDate, forKey: completedKey + "_date")
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
