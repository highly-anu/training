import Combine
import Foundation
import WatchConnectivity
import WidgetKit

/// The watch's side of the phone link. What it shows comes from one place:
/// the server's day (`WatchDay`, `GET /user/today-session?spec=1&week=1`),
/// which the phone relays as it is. The phone used to send a day of its own
/// making, with the server's done flags and progress beside it.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    /// `unavailable`: the iPhone cannot be reached. `syncFailed`: it was
    /// reached and could not get the day (no network, the server down).
    /// `notStarted`: the program begins on `startsOn`.
    enum ProgramState { case loading, ready, noProgram, notStarted, programExpired, unavailable, syncFailed }

    @Published var todaySessions: [WatchSession] = []
    @Published var completedSessionIds: Set<String> = []
    @Published var maxHR: Int = 190
    @Published var programState: ProgramState = .loading
    /// Today and the six days after it, inside the program.
    @Published var weekAhead: [WatchDayAhead] = []
    @Published var readiness: WatchReadiness? = nil
    /// This program week from the server's `progress`: done, and sessions in all.
    @Published var weekDone: (done: Int, sessions: Int)? = nil
    /// The first day of a program that has not started ("2026-10-20").
    @Published var startsOn: String? = nil
    /// Set by deep link (watch widget tap) to navigate directly to a specific session.
    @Published var pendingDeepLinkSessionId: String? = nil

    /// The server's JSON as the phone relayed it, and the watch's date it
    /// arrived on: the cache is the payload itself, decoded again on launch.
    private let dayKey       = "watchDay"
    private let dayDateKey   = "watchDayDate"
    private let maxHRKey     = "watchMaxHR"
    /// What this watch recorded as done today, beside the server's flags
    /// (a session finished here counts before the next sync says so).
    private let completedKey = "watchCompletedSessions"

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
                if WatchDayMessage.day(from: reply) != nil { self.apply(reply) }
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

    /// The session to the phone, which stores it on the server. Live while
    /// the phone is reachable, and the phone's answer says whether the
    /// server has it; only when it does not (or no answer comes) is the
    /// copy queued — the way every summary went before, delivered whenever
    /// the system got to it.
    func sendWorkoutSummary(_ summary: WatchWorkoutSummary) {
        guard let message = WatchUploadMessage.message(summary) else { return }
        let size = (try? JSONSerialization.data(withJSONObject: message))?.count ?? .max
        guard size <= WatchUploadMessage.maxMessageBytes else {
            queueLargeSummary(summary)
            return
        }
        deliver(message) {
            // Cancel any previously queued transfers for the same session so re-runs
            // during testing don't result in stale data being delivered after the new one.
            for pending in WCSession.default.outstandingUserInfoTransfers
            where pending.userInfo["type"] as? String == WatchUploadMessage.workout
               && pending.userInfo["sessionId"] as? String == summary.sessionId {
                pending.cancel()
            }
            WCSession.default.transferUserInfo(message)
        }
    }

    /// A long workout with many GPS/HR points goes as a file.
    private func queueLargeSummary(_ summary: WatchWorkoutSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout_\(summary.sessionId).json")
        try? data.write(to: tmpURL)
        WCSession.default.transferFile(
            tmpURL,
            metadata: ["type": "workout_complete_file", "sessionId": summary.sessionId]
        )
    }

    /// Live when the phone is reachable; `queue` runs when it is not, when
    /// the send fails, or when the phone answers that the server does not
    /// have it yet.
    private func deliver(_ message: [String: Any], queue: @escaping @MainActor () -> Void) {
        guard WCSession.default.isReachable else { queue(); return }
        WCSession.default.sendMessage(message, replyHandler: { reply in
            let stored = WatchUploadMessage.stored(reply)
            Task { @MainActor in if !stored { queue() } }
        }, errorHandler: { _ in
            Task { @MainActor in queue() }
        })
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

    /// `progress.week` → (done, sessions), plus today's sessions this watch
    /// finished that the server does not count yet — as the Garmin glance
    /// counts them — so the week's count and the list agree until the upload
    /// lands. Nil when the week holds none.
    static func weekDone(from progress: WatchProgress?, today: [WatchSession] = [],
                         recordedHere: Set<String> = []) -> (done: Int, sessions: Int)? {
        guard let week = progress?.week, week.sessions > 0 else { return nil }
        let pending = today.filter { !$0.completed && recordedHere.contains($0.sessionId) }.count
        return (min(week.done + pending, week.sessions), week.sessions)
    }

    /// The day's progress as last received, for recounting after a session
    /// is finished here.
    private var progress: WatchProgress? = nil

    func markSessionComplete(_ sessionId: String) {
        completedSessionIds.insert(sessionId)
        let ids = Array(completedSessionIds)
        UserDefaults.standard.set(ids, forKey: completedKey)
        // The complication shows the week and today's done state: count this
        // session in the week now rather than at the next sync, and redraw.
        if progress != nil {
            weekDone = Self.weekDone(from: progress, today: todaySessions, recordedHere: completedSessionIds)
        } else if let week = weekDone {
            weekDone = (min(week.done + 1, week.sessions), week.sessions)
        }
        writeWidgetData(sessions: todaySessions, date: todayDateString)
        // Notify iPhone so it can sync the completion to the API
        sendSessionMarkedComplete(sessionId)
    }

    private func sendSessionMarkedComplete(_ sessionId: String) {
        let message = WatchUploadMessage.sessionDone(sessionId)
        deliver(message) { WCSession.default.transferUserInfo(message) }
    }

    /// Today's day if the cache holds it; otherwise only what may stand in:
    /// the week's count while it is still the same week, and the max HR.
    private func loadCache() {
        let today = todayDateString
        let defaults = UserDefaults.standard
        // What builds before the relay cached, piece by piece.
        for key in ["watchTodaySessions", "watchTodaySessionsDay", "watchProgress", "watchProgress_date",
                    "watchWeeklyOverview", "watchReadiness"] {
            defaults.removeObject(forKey: key)
        }
        let savedMaxHR = defaults.integer(forKey: maxHRKey)
        if savedMaxHR > 0 { maxHR = savedMaxHR }
        // What this watch recorded, for today only. The stamp is the
        // yyyy-MM-dd; comparing it to a localized short date never matched,
        // so every relaunch forgot what was done.
        if defaults.string(forKey: completedKey + "_date") == today,
           let ids = defaults.array(forKey: completedKey) as? [String] {
            completedSessionIds = Set(ids)
        } else {
            defaults.removeObject(forKey: completedKey)
            defaults.set(today, forKey: completedKey + "_date")
        }
        guard let json = defaults.data(forKey: dayKey),
              let day = try? JSONDecoder().decode(WatchDay.self, from: json),
              let received = defaults.string(forKey: dayDateKey) else { return }
        if received == today {
            show(day, date: today)
        } else if Self.sameWeek(received, today) {
            // Last week's count must not stand in on a Monday before the
            // first sync: keep it only while it is from this week.
            weekDone = Self.weekDone(from: day.progress)
        }
    }

    /// The server's day on screen: its sessions and their done flags, the
    /// week ahead, readiness, progress, max HR — and its status, which says
    /// whether there is a day at all.
    private func show(_ day: WatchDay, date: String) {
        if let m = day.maxHR, m > 0 { maxHR = m }
        readiness = day.readiness
        progress = day.progress
        weekDone = Self.weekDone(from: day.progress)
        weekAhead = day.days ?? []
        startsOn = day.startsOn
        switch day.status {
        case "ok":
            todaySessions = day.sessions ?? []
            // Done on any device (a log or a matched workout), joined to what
            // this watch recorded itself.
            completedSessionIds.formUnion(todaySessions.filter(\.completed).map(\.sessionId))
            weekDone = Self.weekDone(from: day.progress, today: todaySessions, recordedHere: completedSessionIds)
            programState = .ready
        case "not_started":
            todaySessions = []
            programState = .notStarted
        case "program_expired":
            todaySessions = []
            programState = .programExpired
        default:
            todaySessions = []
            programState = .noProgram
        }
        writeWidgetData(sessions: todaySessions, date: date)
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
        data.readinessScore = readiness.map { Int($0.score.rounded()) }
        data.readinessSignal = readiness?.status
        WidgetDataStore.write(data)
    }
}

extension WatchConnectivityManager {
    /// The day from the phone, whether it came as the reply to a request or
    /// as a queued transfer. A day dated other than today — a transfer that
    /// sat in the queue past midnight — is not shown as today's.
    func apply(_ message: [String: Any]) {
        guard let received = WatchDayMessage.day(from: message) else { return }
        let (day, json) = received
        let today = todayDateString
        if let date = day.date, date != today { return }
        UserDefaults.standard.set(json, forKey: dayKey)
        UserDefaults.standard.set(today, forKey: dayDateKey)
        if let m = day.maxHR, m > 0 { UserDefaults.standard.set(m, forKey: maxHRKey) }
        // A new day: yesterday's recorded sessions are not today's.
        if UserDefaults.standard.string(forKey: completedKey + "_date") != today {
            completedSessionIds = []
            UserDefaults.standard.removeObject(forKey: completedKey)
            UserDefaults.standard.set(today, forKey: completedKey + "_date")
        }
        show(day, date: today)
        UserDefaults.standard.set(Array(completedSessionIds), forKey: completedKey)
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
            guard !self.hasTodaysDay else { return }
            requestSync()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            // Phone just came in range — refresh if the day is stale
            guard !self.hasTodaysDay else { return }
            requestSync()
        }
    }

    private var hasTodaysDay: Bool {
        UserDefaults.standard.string(forKey: dayDateKey) == todayDateString
    }
}
