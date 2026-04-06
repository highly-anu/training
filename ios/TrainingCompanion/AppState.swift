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

    // MARK: - FIT File Import

    @Published var pendingFITURL: URL? = nil

    // MARK: - Imported Workouts

    @Published var importedWorkouts: [ImportedWorkout] = []
    @Published var isLoadingWorkouts = false

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
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProgram() }
            group.addTask { await self.loadProfile() }
            group.addTask { await self.loadRecentBioLogs() }
            group.addTask { await self.loadRecentSessionLogs() }
            group.addTask { await self.loadWorkouts() }
        }
    }

    /// Called on first appear — loads everything the Today tab needs without fetching workouts,
    /// so there is no concurrent loadWorkouts() race with the post-sync loadAll().
    func loadAllExceptWorkouts() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProgram() }
            group.addTask { await self.loadProfile() }
            group.addTask { await self.loadRecentBioLogs() }
            group.addTask { await self.loadRecentSessionLogs() }
        }
    }

    func loadWorkouts() async {
        guard let api else { return }
        isLoadingWorkouts = true
        defer { isLoadingWorkouts = false }
        do {
            importedWorkouts = try await api.fetchWorkouts()
        } catch {
            print("⚠️ loadWorkouts failed: \(error)")
        }
    }

    func deleteWorkout(id: String) async throws {
        guard let api else { throw APIError.unauthenticated }
        try await api.deleteWorkout(id: id)
        importedWorkouts.removeAll { $0.id == id }
        // Clear matched_workout_id from any local session log entry
        for (key, log) in sessionLogs where log.matchedWorkoutId == id {
            sessionLogs[key] = SessionLogEntry(
                sessionKey: log.sessionKey,
                completedAt: log.completedAt,
                source: log.source,
                notes: log.notes,
                fatigueRating: log.fatigueRating,
                avgHR: log.avgHR,
                peakHR: log.peakHR,
                matchedWorkoutId: nil
            )
        }
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
            peakHR: nil,
            matchedWorkoutId: nil
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

    // MARK: - FIT Import

    /// Returns sessions scheduled on a given YYYY-MM-DD date, using the same
    /// array-index approach as `week(for:)` so weekNumber offset doesn't matter.
    func sessionsForDate(_ dateStr: String) -> [(session: ProgramSession, key: String)] {
        guard let program = serverProgram?.currentProgram,
              let startDateStr = serverProgram?.programStartDate else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let targetDate = df.date(from: dateStr),
              let startDate = df.date(from: startDateStr) else { return [] }
        let cal = Calendar.current
        let target = cal.startOfDay(for: targetDate)
        let programStart = cal.startOfDay(for: startDate)
        let days = cal.dateComponents([.day], from: programStart, to: target).day ?? 0
        guard days >= 0 else { return [] }
        let weekIdx = days / 7
        guard weekIdx < program.weeks.count else { return [] }
        let week = program.weeks[weekIdx]
        let dayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        let weekdayIdx = cal.component(.weekday, from: target) - 1  // 0=Sunday
        let dayName = dayNames[weekdayIdx]
        guard let sessions = week.schedule[dayName] else { return [] }
        return sessions.enumerated().map { i, session in
            (session: session, key: makeSessionKey(weekNumber: week.weekNumber, dayName: dayName, index: i))
        }
    }

    /// All sessions across the entire program as (session, key, dateLabel) for manual matching.
    func allSessionPairs() -> [(session: ProgramSession, key: String, dateLabel: String)] {
        guard let weeks = serverProgram?.currentProgram?.weeks,
              let startDateStr = serverProgram?.programStartDate else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let startDate = df.date(from: startDateStr) else { return [] }
        let cal = Calendar.current
        let programStart = cal.startOfDay(for: startDate)
        let dayNames = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        var results: [(session: ProgramSession, key: String, dateLabel: String)] = []
        for (wIdx, week) in weeks.enumerated() {
            let weekStart = cal.date(byAdding: .day, value: wIdx * 7, to: programStart)!
            let weekStartWeekday = cal.component(.weekday, from: weekStart) - 1
            for dayName in ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"] {
                guard let sessions = week.schedule[dayName],
                      let targetIdx = dayNames.firstIndex(of: dayName) else { continue }
                var offset = targetIdx - weekStartWeekday
                if offset < 0 { offset += 7 }
                let sessionDate = cal.date(byAdding: .day, value: offset, to: weekStart)!
                let label = out.string(from: sessionDate)
                for (i, session) in sessions.enumerated() {
                    let key = makeSessionKey(weekNumber: week.weekNumber, dayName: dayName, index: i)
                    results.append((session: session, key: key, dateLabel: label))
                }
            }
        }
        return results
    }

    /// Parse a .fit file on-device and save the workout directly to Supabase.
    /// No server round-trip required.
    func parseFITFile(url: URL) async throws -> ImportedWorkout {
        guard let api else { throw APIError.unauthenticated }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let (session, records) = try FITFileParser.parse(data: data)
        let workout = FITFileParser.toImportedWorkout(session: session, records: records)
        try await api.saveWorkoutDirect(workout)
        // Add/update in local list (prepend if new, replace if existing)
        if let idx = importedWorkouts.firstIndex(where: { $0.id == workout.id }) {
            importedWorkouts[idx] = workout
        } else {
            importedWorkouts.insert(workout, at: 0)
        }
        return workout
    }

    /// Save match + mark session complete directly to Supabase.
    func matchAndComplete(workout: ImportedWorkout, sessionKey: String) async throws {
        guard let api else { throw APIError.unauthenticated }
        try await api.saveMatchDirect(workout: workout, sessionKey: sessionKey)
        let completedAt = workout.startTime ?? ISO8601DateFormatter().string(from: Date())
        // Optimistic local update
        sessionLogs[sessionKey] = SessionLogEntry(
            sessionKey: sessionKey,
            completedAt: completedAt,
            source: "fit_file",
            notes: nil,
            fatigueRating: nil,
            avgHR: workout.heartRate?.avg,
            peakHR: workout.heartRate?.max,
            matchedWorkoutId: workout.id
        )
    }
}
