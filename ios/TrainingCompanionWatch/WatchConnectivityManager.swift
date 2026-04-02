import Foundation
import WatchConnectivity

/// Receives today's sessions from the iPhone and persists them for the workout UI.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    @Published var todaySessions: [WatchSession] = []
    @Published var hasProgram: Bool = false
    @Published var programExpired: Bool = false
    @Published var lastSyncDate: String? = nil

    private let sessionsKey = "watchTodaySessions"
    private let syncDateKey  = "watchLastSyncDate"

    override init() {
        super.init()
        loadCached()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Manual sync request (from NoProgramView)

    func requestSync() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["type": "request_sync"], replyHandler: nil)
    }

    // MARK: - Persistence

    private func loadCached() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([WatchSession].self, from: data) else { return }
        todaySessions = sessions
        hasProgram = !sessions.isEmpty
        lastSyncDate = UserDefaults.standard.string(forKey: syncDateKey)
    }

    private func persist(_ sessions: [WatchSession], date: String) {
        todaySessions = sessions
        hasProgram = true
        programExpired = false
        lastSyncDate = date
        UserDefaults.standard.set(try? JSONEncoder().encode(sessions), forKey: sessionsKey)
        UserDefaults.standard.set(date, forKey: syncDateKey)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            guard let type = userInfo["type"] as? String else { return }

            switch type {
            case "today_sessions":
                guard let date = userInfo["date"] as? String,
                      let raw  = userInfo["sessions"],
                      let data = try? JSONSerialization.data(withJSONObject: raw),
                      let sessions = try? JSONDecoder().decode([WatchSession].self, from: data) else { return }
                persist(sessions, date: date)

                // Store profile for HR zone calc
                if let profile = userInfo["profile"] as? [String: Any] {
                    if let maxHR = profile["maxHR"] as? Int {
                        UserDefaults.standard.set(maxHR, forKey: "maxHR")
                    }
                    if let dob = profile["dateOfBirth"] as? String {
                        UserDefaults.standard.set(dob, forKey: "dateOfBirth")
                    }
                }

            case "no_program":
                hasProgram = false
                todaySessions = []

            case "program_expired":
                hasProgram = false
                programExpired = true
                todaySessions = []

            default:
                break
            }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}
