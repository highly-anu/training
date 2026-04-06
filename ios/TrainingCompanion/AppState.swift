import Foundation
import Combine

/// Central state object for the iPhone app.
/// Injected into the view hierarchy as an @EnvironmentObject from ContentView.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Program

    @Published var serverProgram: ServerProgram? = nil
    @Published var isLoadingProgram = false
    @Published var programError: String? = nil

    // MARK: - Profile

    @Published var profile: UserProfile = .default
    @Published var isLoadingProfile = false

    // MARK: - Session Logs (completion tracking)

    @Published var sessionLogs: [String: SessionLogEntry] = [:]

    // MARK: - Bio Logs (last 30 days)

    @Published var recentBioLogs: [DailyBioLog] = []

    // MARK: - Catalog (lazy-loaded)

    @Published var goals: [GoalProfile] = []
    @Published var benchmarks: [AppBenchmark] = []
    @Published var philosophies: [PhilosophyCard] = []
    @Published var injuryFlagDefs: [InjuryFlagDef] = []

    // MARK: - Internal

    var api: APIClient?
    private let iso = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    // MARK: - Configuration

    func configure(auth: AuthManager) {
        api = APIClient(auth: auth)
        isLoadingProgram = true  // show loading immediately, before the first async load starts
    }

    // MARK: - Initial Load

    func loadAll() async {
        async let _ = loadProgram()
        async let _ = loadProfile()
        async let _ = loadRecentBioLogs()
        async let _ = loadRecentSessionLogs()
    }

    // MARK: - Program

    func loadProgram() async {
        guard let api else { return }
        isLoadingProgram = true
        programError = nil
        defer { isLoadingProgram = false }
        do {
            serverProgram = try await api.fetchProgram()
        } catch {
            programError = error.localizedDescription
        }
    }

    // MARK: - Profile

    func loadProfile() async {
        guard let api else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            let p = try await api.fetchUserProfile()
            profile = p
            if let dob = p.dateOfBirth {
                UserDefaults.standard.set(dob, forKey: "dateOfBirth")
            }
        } catch {
            // Keep default — user may not have a profile yet
        }
    }

    func saveProfile() async {
        guard let api else { return }
        try? await api.saveUserProfile(profile)
        // Keep dateOfBirth in UserDefaults for WatchSessionManager
        if let dob = profile.dateOfBirth {
            UserDefaults.standard.set(dob, forKey: "dateOfBirth")
        }
    }

    // MARK: - Session Logs

    func loadRecentSessionLogs() async {
        guard let api else { return }
        do {
            let logs = try await api.fetchRecentSessionLogs()
            sessionLogs = Dictionary(uniqueKeysWithValues: logs.map { ($0.sessionKey, $0) })
        } catch {}
    }

    func markSessionComplete(sessionKey: String) async {
        guard let api else { return }
        let completedAt = iso.string(from: Date())
        // Optimistic update
        sessionLogs[sessionKey] = SessionLogEntry(
            sessionKey: sessionKey,
            completedAt: completedAt,
            source: "manual",
            notes: nil,
            fatigueRating: nil,
            avgHR: nil,
            peakHR: nil
        )
        try? await api.saveSessionComplete(sessionKey: sessionKey, completedAt: completedAt)
    }

    func undoSessionComplete(sessionKey: String) {
        sessionLogs.removeValue(forKey: sessionKey)
        // Note: no undo API endpoint — the server keeps the log but completion is removed client-side
        // until next sync. A proper undo would call DELETE /health/sessions/:key which isn't in the
        // current API spec; for now optimistic removal is sufficient for the daily use case.
    }

    // MARK: - Bio Logs

    func loadRecentBioLogs() async {
        guard let api else { return }
        recentBioLogs = (try? await api.fetchRecentBioLogs()) ?? []
    }

    // MARK: - Catalog (lazy)

    func loadGoalsIfNeeded() async {
        guard let api, goals.isEmpty else { return }
        goals = (try? await api.fetchGoals()) ?? []
    }

    func loadBenchmarksIfNeeded() async {
        guard let api, benchmarks.isEmpty else { return }
        benchmarks = (try? await api.fetchBenchmarks()) ?? []
    }

    func loadPhilosophiesIfNeeded() async {
        guard let api, philosophies.isEmpty else { return }
        philosophies = (try? await api.fetchPhilosophies()) ?? []
    }

    func loadInjuryFlagsIfNeeded() async {
        guard let api, injuryFlagDefs.isEmpty else { return }
        injuryFlagDefs = (try? await api.fetchInjuryFlags()) ?? []
    }

    // MARK: - Helpers

    /// The current program week index (0-based) based on start date.
    var currentWeekIndex: Int? {
        guard let program = serverProgram?.currentProgram,
              let startDateStr = serverProgram?.programStartDate,
              let startDate = dayFormatter.date(from: startDateStr) else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: startDate)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let idx = days / 7
        return idx < program.weeks.count ? idx : nil
    }

    var currentWeek: ProgramWeek? {
        guard let idx = currentWeekIndex,
              let weeks = serverProgram?.currentProgram?.weeks else { return nil }
        return weeks[idx]
    }

    /// Returns the program week that contains `date`, or nil if out of range.
    func week(for date: Date) -> ProgramWeek? {
        guard let program = serverProgram?.currentProgram,
              let startDateStr = serverProgram?.programStartDate,
              let startDate = dayFormatter.date(from: startDateStr) else { return nil }
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        guard days >= 0 else { return nil }
        let idx = days / 7
        return idx < program.weeks.count ? program.weeks[idx] : nil
    }

    var todayDayName: String {
        let names = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        return names[Calendar.current.component(.weekday, from: Date()) - 1]
    }

    /// Returns today's sessions as (session, sessionKey) pairs.
    var todaySessions: [(session: ProgramSession, sessionKey: String)] {
        guard let week = currentWeek else { return [] }
        let sessions = week.schedule[todayDayName] ?? []
        return sessions.enumerated().map { (i, s) in
            (session: s, sessionKey: makeSessionKey(weekNumber: week.weekNumber, dayName: todayDayName, index: i))
        }
    }

    func makeSessionKey(weekNumber: Int, dayName: String, index: Int) -> String {
        "\(weekNumber)-\(dayName)-\(index)"
    }

    func isSessionComplete(_ key: String) -> Bool {
        sessionLogs[key]?.completedAt != nil
    }

    /// Computed readiness from most recent bio log: green/yellow/red based on HRV + resting HR.
    func readinessInfo(from bioLogs: [DailyBioLog]) -> ReadinessInfo? {
        guard let latest = bioLogs.first else { return nil }
        guard let hrv = latest.hrv else { return nil }
        // Simple heuristic: HRV > 50ms = green, 35–50 = yellow, <35 = red
        let signal: String
        let score: Double
        switch hrv {
        case let h where h >= 50:
            signal = "green"; score = min(1.0, h / 70.0)
        case let h where h >= 35:
            signal = "yellow"; score = h / 70.0
        default:
            signal = "red"; score = max(0.1, hrv / 70.0)
        }
        return ReadinessInfo(
            score: score,
            signal: signal,
            restingHR: latest.restingHR.map { Int($0) },
            hrv: Int(hrv)
        )
    }

    /// All weeks for the full program calendar.
    var allWeeks: [ProgramWeek] { serverProgram?.currentProgram?.weeks ?? [] }
}
