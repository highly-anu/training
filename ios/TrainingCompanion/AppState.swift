import Foundation
import Combine
import WidgetKit

/// Central state object for the iPhone app.
/// Injected into the view hierarchy as an @EnvironmentObject from ContentView.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Program

    @Published var serverProgram: ServerProgram? = nil
    @Published var isLoadingProgram = false
    @Published var programError: String? = nil
    /// Set when a save lost to a newer copy on the server (409). The program
    /// is re-pulled; this is what tells the user their last edit is gone,
    /// which used to happen silently.
    @Published var programSaveConflict: String? = nil

    /// Every plan this athlete has trained, newest first.
    ///
    /// Lives here with the rest of the program state; a second store for it
    /// (the old `ProgramStore`) only ever held a stale copy.
    @Published var programHistory: [ProgramHistoryEntry] = []
    @Published var isLoadingHistory = false

    /// Which archived version the loaded program is, or nil before history knows.
    var programVersionId: String? { serverProgram?.programVersionId }

    // MARK: - Profile

    @Published var profile: UserProfile = .default
    @Published var isLoadingProfile = false
    @Published var lastProfileSyncAt: Date? = nil

    private let logger = AppLogger.shared

    // MARK: - Session Logs (completion tracking)

    @Published var sessionLogs: [String: SessionLogEntry] = [:]

    // MARK: - FIT File Import

    @Published var pendingFITURL: URL? = nil

    // MARK: - Imported Workouts

    @Published var importedWorkouts: [ImportedWorkout] = []
    @Published var isLoadingWorkouts = false
    /// Confirmed `workout_matches` rows, keyed by imported workout id.
    @Published var workoutMatches: [String: WorkoutMatch] = [:]
    /// Weak server-side matches still waiting for a decision (Today card).
    @Published var matchSuggestions: [MatchSuggestion] = []

    // MARK: - Bio Logs (last 30 days)

    @Published var recentBioLogs: [DailyBioLog] = []
    @Published var readinessResult: ReadinessResult? = nil

    // MARK: - Progression

    @Published var progressionReview: ProgressionReview? = nil
    /// `GET /analytics/program` — the methodology scorecard (Analytics ▸ Program).
    @Published var programAnalytics: ProgramAnalytics? = nil
    @Published var isLoadingProgramAnalytics = false
    @Published var programAnalyticsError: String? = nil

    // MARK: - Catalog (lazy-loaded)

    @Published var benchmarks: [AppBenchmark] = []
    @Published var philosophies: [PhilosophyCard] = []
    @Published var injuryFlagDefs: [InjuryFlagDef] = []
    /// Every exercise the API knows, by id — the reference the exercise sheet
    /// and the swap list read names and prerequisites from.
    @Published var exerciseCatalog: [String: AppExercise] = [:]

    // MARK: - Training load (server-computed)

    /// The server's PMC and weekly TRIMP — the same numbers the web shows.
    /// nil until fetched, or when the request failed and the Overview falls
    /// back to the on-device engine.
    @Published var serverPMC: [PMCEntry]? = nil
    @Published var serverWeeklyLoad: [ServerWeeklyLoadEntry]? = nil

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
            group.addTask { await self.loadPerformanceLogs() }
            group.addTask { await self.loadRecentBioLogs() }
            group.addTask { await self.loadRecentSessionLogs() }
            group.addTask { await self.loadReadiness() }
            group.addTask { await self.loadWorkouts() }
            group.addTask { await self.loadProgressionReview() }
            group.addTask { await self.loadMatchSuggestions() }
        }
    }

    /// Called on first appear — loads everything the Today tab needs without fetching workouts,
    /// so there is no concurrent loadWorkouts() race with the post-sync loadAll().
    func loadAllExceptWorkouts() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProgram() }
            group.addTask { await self.loadProfile() }
            group.addTask { await self.loadPerformanceLogs() }
            group.addTask { await self.loadRecentBioLogs() }
            group.addTask { await self.loadRecentSessionLogs() }
            group.addTask { await self.loadReadiness() }
            group.addTask { await self.loadProgressionReview() }
        }
    }

    func loadWorkouts() async {
        guard let api else { return }
        isLoadingWorkouts = true
        defer { isLoadingWorkouts = false }
        do {
            // One snapshot carries both: the list, and the matches that come
            // from their own table rather than from session logs — see
            // `matchedSessionKey(for:)`.
            let snapshot = try await api.fetchHealthSnapshot()
            importedWorkouts = snapshot.workouts
            workoutMatches = APIClient.matchesByWorkout(snapshot.matches)
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            print("⚠️ loadWorkouts failed: \(error)")
        }
    }

    // MARK: - Match suggestions

    func loadMatchSuggestions() async {
        guard let api else { return }
        matchSuggestions = (try? await api.fetchMatchSuggestions()) ?? []
    }

    /// Forget a suggestion without deciding the workout; the server forgets it too.
    func dismissSuggestion(workoutId: String) async {
        matchSuggestions.removeAll { $0.importedWorkoutId == workoutId }
        try? await api?.dismissMatchSuggestion(workoutId: workoutId)
    }

    /// The planned session an imported workout is linked to, if any.
    ///
    /// The one place that answers this. It used to be derived at three call
    /// sites from `sessionLogs`, which the server populates by LEFT JOIN from
    /// session logs — so an auto-matched workout, which has no session log,
    /// read as unmatched on the phone while the web showed it linked.
    func matchedSessionKey(for workoutId: String) -> String? {
        if let key = workoutMatches[workoutId]?.sessionKey { return key }
        return sessionLogs.values.first { $0.matchedWorkoutId == workoutId }?.sessionKey
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
            writeWidgetData()
        } catch {
            programError = error.localizedDescription
        }
    }

    /// Load the program timeline. Never throws: the history is a view onto the
    /// past, and failing to fetch it must not disturb the program itself.
    func loadProgramHistory() async {
        guard let api else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        programHistory = (try? await api.fetchProgramHistory()) ?? []
    }

    /// Writes today's sessions to the shared App Group container so iPhone widgets can display them.
    func writeWidgetData() {
        let today = todayDayName
        let dateStr = dayFormatter.string(from: Date())
        guard let week = currentWeek else {
            WidgetDataStore.write(WidgetTodayData(date: dateStr, sessions: [], updatedAt: Date()))
            return
        }
        let sessions = (week.schedule[today] ?? []).enumerated().map { (i, s) -> WidgetSession in
            let key = makeSessionKey(weekNumber: week.weekNumber, dayName: today, index: i)
            let names = s.exercises.compactMap { $0.exercise?.name }.filter { _ in true }
            return WidgetSession(
                id: key,
                modalityId: s.modality,
                archetypeName: s.archetype?.name ?? s.modality,
                estimatedMinutes: s.archetype?.durationEstimateMinutes ?? 45,
                isDeload: s.isDeload,
                exerciseNames: Array(names.prefix(4))
            )
        }
        WidgetDataStore.write(WidgetTodayData(date: dateStr, sessions: sessions, updatedAt: Date()))
        rescheduleNotifications()
    }

    // MARK: - Session reminders

    /// Re-derive the local reminders from the stored program. Called from
    /// every path that changes the program (load, move, replace, swap, adjust)
    /// through `writeWidgetData`, and from Settings when the athlete changes
    /// the time. Does nothing while reminders are off, so neither the tests
    /// nor an athlete who never enabled them touch the notification center.
    func rescheduleNotifications() {
        let manager = NotificationManager.shared
        guard manager.isEnabled else { return }
        let program = serverProgram?.currentProgram
        let startDate = serverProgram?.programStartDate
        let completed = Set(sessionLogs.values.filter { $0.completedAt != nil }.map(\.sessionKey))
        Task { await manager.reschedule(program: program, startDate: startDate, completedKeys: completed) }
    }

    // MARK: - Profile

    func loadProfile() async {
        guard let api else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            let raw = try await api.fetchUserProfileRaw()
            logger.log("profile: GET /profile — raw: \(raw.prefix(200))")
            let p = try api.decodeUserProfile(from: raw)
            profile.trainingLevel  = p.trainingLevel
            profile.equipment      = p.equipment
            profile.injuryFlags    = p.injuryFlags
            profile.customInjuryFlags = p.customInjuryFlags
            profile.dateOfBirth    = p.dateOfBirth
            profile.weeklySchedule = p.weeklySchedule
            profile.sex            = p.sex
            profile.timezone       = p.timezone
            lastProfileSyncAt = Date()
            // The device knows its zone; the server needs it to date FIT files
            // that carry no local timestamp. Set once, never overwritten.
            if p.timezone == nil {
                profile.timezone = TimeZone.current.identifier
                try? await api.saveUserProfile(profile)
            }
            logger.log("profile: loaded — level:\(p.trainingLevel) equip:\(p.equipment.count) injuries:\(p.injuryFlags.count)")
            if let dob = p.dateOfBirth {
                UserDefaults.standard.set(dob, forKey: "dateOfBirth")
            }
        } catch {
            logger.log("profile: ERROR — \(error)")
        }
    }

    func loadPerformanceLogs() async {
        guard let api else { return }
        do {
            let logs = try await api.fetchPerformanceLogs()
            profile.performanceLogs = logs
            logger.log("profile: performance logs \(logs.count) benchmarks")
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            logger.log("profile: performance logs ERROR — \(error)")
        }
    }

    /// Records a PR through `POST /api/health/performance`, then re-reads the
    /// series so the list shows what the server kept — the optimistic entry the
    /// caller appended is replaced by the stored one, or dropped if the write
    /// failed. Returns whether the write succeeded.
    @discardableResult
    func savePerformanceEntry(benchmarkId: String, value: Double) async -> Bool {
        guard let api else { return false }
        var saved = false
        do {
            try await api.addPerformanceEntry(benchmarkId: benchmarkId, value: value,
                                              loggedAt: ISO8601DateFormatter().string(from: Date()))
            saved = true
        } catch {
            logger.log("profile: performance entry ERROR — \(error)")
        }
        await loadPerformanceLogs()
        return saved
    }

    func saveProfile() async {
        guard let api else { return }
        if profile.timezone == nil { profile.timezone = TimeZone.current.identifier }
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
            sessionLogs = Dictionary(logs.map { ($0.sessionKey, $0) }, uniquingKeysWith: { _, last in last })
            rescheduleNotifications()   // a session completed elsewhere cancels its reminder
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
        rescheduleNotifications()
    }

    /// Store what was done for one exercise of a session — sets, or the
    /// slot's currency — locally first, then through the API. A session that
    /// has no log yet gets one without a completion; completing it later
    /// keeps the sets (the server merges per exercise).
    func logExercise(sessionKey: String, exerciseId: String, performance: ExercisePerformanceLog) async {
        var entry = sessionLogs[sessionKey] ?? SessionLogEntry(
            sessionKey: sessionKey, completedAt: nil, source: "manual", notes: nil,
            fatigueRating: nil, avgHR: nil, peakHR: nil, matchedWorkoutId: nil)
        entry.exercises[exerciseId] = performance
        sessionLogs[sessionKey] = entry
        guard let api else { return }
        do {
            try await api.saveExerciseLog(sessionKey: sessionKey, exerciseId: exerciseId, performance: performance)
        } catch {
            AppLogger.shared.logFromBackground("session log: save failed — \(error.localizedDescription)")
        }
    }

    /// A planned session located by its key ("<week number>-<Day>-<index>"),
    /// for a deep link or a widget. The first week carrying that number wins,
    /// which is what every other reader of the key does.
    struct LocatedSession {
        let session: ProgramSession
        let key: String
        let weekIndex: Int
        let dayName: String
        let sessionIndex: Int
    }

    func locateSession(key: String) -> LocatedSession? {
        guard let weeks = serverProgram?.currentProgram?.weeks else { return nil }
        for (wi, week) in weeks.enumerated() {
            for (day, sessions) in week.schedule {
                for (si, session) in sessions.enumerated()
                where "\(week.weekNumber)-\(day)-\(si)" == key {
                    return LocatedSession(session: session, key: key, weekIndex: wi, dayName: day, sessionIndex: si)
                }
            }
        }
        return nil
    }

    func undoSessionComplete(sessionKey: String) async {
        sessionLogs.removeValue(forKey: sessionKey)
        // The server keeps the sets and notes and clears only the completion;
        // without this call the completion came back on the next sync.
        try? await api?.clearSessionCompletion(sessionKey: sessionKey)
        rescheduleNotifications()
    }

    // MARK: - Bio Logs

    func loadRecentBioLogs() async {
        guard let api else { return }
        do {
            recentBioLogs = try await api.fetchRecentBioLogs()
        } catch {
            // Ignore task cancellation (expected when SwiftUI .task cancels on view disappear)
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.shared.logFromBackground("bio: HTTP error — \(error.localizedDescription)")
        }
    }

    func loadReadiness() async {
        guard let api else { return }
        do {
            readinessResult = try await api.fetchReadiness()
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.shared.logFromBackground("readiness: fetch failed — \(error.localizedDescription)")
        }
    }

    /// The program analytics document. Loaded when the section is shown, and
    /// again on pull-to-refresh; the server recomputes only when the program
    /// or the logs changed.
    func loadProgramAnalytics(fresh: Bool = false) async {
        guard let api else { return }
        isLoadingProgramAnalytics = true
        defer { isLoadingProgramAnalytics = false }
        do {
            programAnalytics = try await api.fetchProgramAnalytics(fresh: fresh)
            programAnalyticsError = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            programAnalyticsError = error.localizedDescription
            AppLogger.shared.logFromBackground("analytics: program fetch failed — \(error.localizedDescription)")
        }
    }

    func loadProgressionReview() async {
        guard let api else { return }
        do {
            progressionReview = try await api.fetchProgressionReview()
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.shared.logFromBackground("progression: fetch failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Catalog (lazy)

    func loadBenchmarksIfNeeded() async {
        guard let api, benchmarks.isEmpty else { return }
        benchmarks = (try? await api.fetchBenchmarks(sex: profile.sex)) ?? []
    }

    func loadPhilosophiesIfNeeded() async {
        guard let api, philosophies.isEmpty else { return }
        philosophies = (try? await api.fetchPhilosophies()) ?? []
    }

    func loadInjuryFlagsIfNeeded() async {
        guard let api, injuryFlagDefs.isEmpty else { return }
        injuryFlagDefs = (try? await api.fetchInjuryFlags()) ?? []
    }

    func loadExercisesIfNeeded() async {
        guard let api, exerciseCatalog.isEmpty else { return }
        let list = (try? await api.fetchExercises()) ?? []
        exerciseCatalog = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Fetch the server's PMC and weekly load. On failure the previous values
    /// stay, or nil on the first load, and the Overview computes on-device.
    func loadLoadAnalytics() async {
        guard let api else { return }
        async let pmc = api.fetchLoadPMC()
        async let weekly = api.fetchLoadWeekly()
        if let entries = try? await pmc {
            serverPMC = entries.compactMap { $0.pmcEntry() }
        } else {
            AppLogger.shared.logFromBackground("load: server PMC unavailable — computing on device")
        }
        if let weeks = try? await weekly {
            serverWeeklyLoad = weeks
        }
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
        let days = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
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

    // MARK: - Program Mutations

    func replaceSession(weekIndex: Int, day: String, sessionIndex: Int, session: ProgramSession) {
        guard let sp = serverProgram,
              let program = sp.currentProgram else { return }
        var weeks = program.weeks
        guard weekIndex < weeks.count else { return }
        var week = weeks[weekIndex]
        var sessions = week.schedule[day] ?? []
        guard sessionIndex < sessions.count else { return }
        sessions[sessionIndex] = session
        var schedule = week.schedule
        schedule[day] = sessions
        week = ProgramWeek(weekNumber: week.weekNumber, weekInPhase: week.weekInPhase,
                           isDeload: week.isDeload, phase: week.phase, schedule: schedule,
                           extra: week.extra)
        weeks[weekIndex] = week
        commit(weeks: weeks, to: sp)
    }

    /// Swap one exercise for an alternative the server ranked for its slot —
    /// the smallest program edit. Saves through the revision-checked PUT like
    /// move and replace.
    func replaceExercise(weekIndex: Int, day: String, sessionIndex: Int,
                         exerciseIndex: Int, assignment: ProgramExerciseAssignment) {
        guard let sp = serverProgram, let program = sp.currentProgram else { return }
        var weeks = program.weeks
        guard weekIndex < weeks.count else { return }
        let week = weeks[weekIndex]
        var sessions = week.schedule[day] ?? []
        guard sessionIndex < sessions.count else { return }
        let session = sessions[sessionIndex]
        var exercises = session.exercises
        guard exerciseIndex < exercises.count else { return }
        exercises[exerciseIndex] = assignment
        sessions[sessionIndex] = ProgramSession(modality: session.modality, archetype: session.archetype,
                                                isDeload: session.isDeload, exercises: exercises,
                                                extra: session.extra)
        var schedule = week.schedule
        schedule[day] = sessions
        weeks[weekIndex] = ProgramWeek(weekNumber: week.weekNumber, weekInPhase: week.weekInPhase,
                                       isDeload: week.isDeload, phase: week.phase, schedule: schedule,
                                       extra: week.extra)
        commit(weeks: weeks, to: sp)
    }

    /// Store an edited copy of the weeks, keep the widgets and reminders in
    /// step, and save. The envelope's identity (`revision`,
    /// `programVersionId`) is carried over so the save is checked against the
    /// copy that was read.
    private func commit(weeks: [ProgramWeek], to sp: ServerProgram, extra: [String: JSONValue]? = nil) {
        serverProgram = ServerProgram(currentProgram: GeneratedProgram(weeks: weeks,
                                                                       extra: extra ?? sp.currentProgram?.extra ?? [:]),
                                      programStartDate: sp.programStartDate,
                                      eventDate: sp.eventDate, sourceGoalIds: sp.sourceGoalIds,
                                      sourceGoalWeights: sp.sourceGoalWeights,
                                      revision: sp.revision, programVersionId: sp.programVersionId,
                                      extra: sp.extra)
        writeWidgetData()
        Task { try? await saveProgramToServer() }
    }

    /// Ranked alternatives for one exercise of one planned session, under the
    /// program's methodology and the athlete's current profile.
    func substituteAlternatives(weekIndex: Int, day: String, sessionIndex: Int,
                                exerciseIndex: Int) async throws -> [ExerciseAlternative] {
        guard let api else { throw APIError.unauthenticated }
        guard let week = serverProgram?.currentProgram?.weeks[safe: weekIndex],
              let session = week.schedule[day]?[safe: sessionIndex],
              let archetype = session.archetype,
              let current = session.exercises[safe: exerciseIndex],
              let exercise = current.exercise,
              let slotRole = current.slotRole else {
            throw APIError.serverErrorDetail(404, "This exercise has no slot to swap within.")
        }
        let request = SubstituteRequest(
            archetypeId: archetype.id,
            slotRole: slotRole,
            exerciseId: exercise.id,
            modality: session.modality,
            constraints: SubstituteRequest.Constraints(
                trainingLevel: profile.trainingLevel,
                equipment: profile.equipment,
                injuryFlags: profile.injuryFlags,
                sessionTimeMinutes: archetype.durationEstimateMinutes ?? 60),
            philosophyIds: (serverProgram?.sourceGoalIds ?? []).filter { $0 != "_blended" },
            phase: week.phase,
            weekInPhase: week.weekInPhase ?? (weekIndex + 1),
            isDeload: week.isDeload,
            exclude: session.exercises.compactMap { $0.exercise?.id })
        return try await api.substituteExercise(request)
    }

    /// Apply one of the review's adjustments from the current calendar week
    /// on. The server edits the stored weeks under the revision check and
    /// returns the saved envelope, which replaces this copy. A 409 is handled
    /// like a stale save: reload, and say so.
    @discardableResult
    func applyAdjustment(_ adjustment: ProgressionAdjustment) async throws -> AppliedAdjustment {
        guard let api, let sp = serverProgram else { throw APIError.unauthenticated }
        let weekCount = sp.currentProgram?.weeks.count ?? 0
        let fromWeek = currentWeekIndex ?? max(0, weekCount - 1)
        let request = AdjustRequest(
            adjustment: AdjustRequest.Adjustment(type: adjustment.type, target: adjustment.target,
                                                 magnitude: adjustment.magnitude),
            fromWeekIndex: fromWeek,
            baseRevision: sp.revision)
        do {
            let result = try await api.applyAdjustment(request)
            if let program = result.program {
                serverProgram = program
                writeWidgetData()
            } else {
                await loadProgram()
            }
            programSaveConflict = nil
            return result.applied
        } catch is APIClient.StaleProgramRevision {
            await loadProgram()
            programSaveConflict = "Your program changed elsewhere — reloaded. Apply the adjustment again if it still fits."
            throw APIError.serverErrorDetail(409, "Your program changed elsewhere; it was reloaded.")
        }
    }

    func moveSession(weekIndex: Int, fromDay: String, toDay: String, sessionIndex: Int) {
        guard let sp = serverProgram,
              let program = sp.currentProgram else { return }
        var weeks = program.weeks
        guard weekIndex < weeks.count else { return }
        var week = weeks[weekIndex]
        var fromSessions = week.schedule[fromDay] ?? []
        guard sessionIndex < fromSessions.count else { return }
        let session = fromSessions.remove(at: sessionIndex)
        var toSessions = week.schedule[toDay] ?? []
        toSessions.append(session)
        var schedule = week.schedule
        schedule[fromDay] = fromSessions
        schedule[toDay] = toSessions
        week = ProgramWeek(weekNumber: week.weekNumber, weekInPhase: week.weekInPhase,
                           isDeload: week.isDeload, phase: week.phase, schedule: schedule,
                           extra: week.extra)
        weeks[weekIndex] = week
        commit(weeks: weeks, to: sp)
    }

    /// The stored program's `constraints` object, kept in the envelope's extras.
    var programConstraints: [String: JSONValue] {
        if case .object(let o)? = serverProgram?.currentProgram?.extra["constraints"] { return o }
        return [:]
    }

    /// Where the profile has moved on from what the program was built for.
    var constraintDifferences: [ConstraintDifference] {
        ProgramConstraintsDiff.differences(program: programConstraints, profile: profile)
    }

    /// Rebuild the remaining weeks from the current calendar week with the
    /// profile's current settings, keeping the weeks already behind the
    /// athlete; saved through the revision-checked PUT, so the old plan stays
    /// in history. Returns how many weeks were regenerated.
    @discardableResult
    func regenerateFromCurrentWeek() async throws -> Int {
        guard let api, let sp = serverProgram, let program = sp.currentProgram, !program.weeks.isEmpty else {
            throw APIError.serverErrorDetail(400, "No program to regenerate")
        }
        let start = min(currentWeekIndex ?? 0, program.weeks.count - 1)
        let remaining = program.weeks.count - start
        let ids = sp.sourceGoalIds.filter { $0 != "_blended" }
        guard !ids.isEmpty else {
            throw APIError.serverErrorDetail(400, "This program has no methodology to regenerate from")
        }
        let week = program.weeks[start]
        let constraints = ProgramConstraintsDiff.merged(program: programConstraints, profile: profile,
                                                        weekInPhase: week.weekInPhase, phase: week.phase)
        let request = GenerateProgramRequest(
            philosophyId: ids.count == 1 ? ids[0] : nil,
            philosophyIds: ids.count > 1 ? ids : nil,
            philosophyWeights: ids.count > 1 ? sp.sourceGoalWeights : nil,
            constraints: constraints, numWeeks: remaining, startDate: nil, eventDate: sp.eventDate,
            persist: false)
        let generated = try await api.generateProgramPreview(request)
        let spliced = Regeneration.splice(current: program, from: start, generated: generated)
        commit(weeks: spliced.weeks, to: sp, extra: spliced.extra)
        return remaining
    }

    func saveProgramToServer() async throws {
        guard let api, let sp = serverProgram else { return }
        let payload = UserProgramSavePayload(
            currentProgram: sp.currentProgram,
            programStartDate: sp.programStartDate,
            eventDate: sp.eventDate,
            sourceGoalIds: sp.sourceGoalIds,
            sourceGoalWeights: sp.sourceGoalWeights,
            baseRevision: sp.revision,
            extra: sp.extra
        )
        do {
            try await api.saveProgram(payload)
            programSaveConflict = nil
        } catch is APIClient.StaleProgramRevision {
            // Someone (the web) has newer work. Take theirs — and say so: the
            // move or replace the user just made is not in the copy we reload.
            await loadProgram()
            programSaveConflict = "Your program changed elsewhere — reloaded; your last edit was not saved."
        }
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

    /// Upload a .fit file through `POST /workouts/parse` and re-read the list.
    ///
    /// This used to parse on-device and upsert straight into Supabase, which
    /// skipped the server's dating, cross-source dedup and matcher — so a ride
    /// the Garmin webhook had already delivered appeared twice. The server
    /// may fold the upload into a row that was already there, under that
    /// row's id; the workout handed back is the one the list now shows.
    func importWorkoutFile(url: URL) async throws -> ImportedWorkout {
        guard let api else { throw APIError.unauthenticated }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let parsed = try await api.uploadFITFile(data: data, filename: url.lastPathComponent)
        guard let uploaded = parsed.first else {
            throw APIError.serverErrorDetail(422, "The file held no activity.")
        }
        await loadWorkouts()
        await loadMatchSuggestions()
        return canonicalWorkout(for: uploaded) ?? uploaded
    }

    /// The listed row an upload became: the same id, or — when the server
    /// merged it into another source's copy — the row that starts within five
    /// minutes of it on the same day, the dedup rule's own window.
    func canonicalWorkout(for uploaded: ImportedWorkout) -> ImportedWorkout? {
        if let exact = importedWorkouts.first(where: { $0.id == uploaded.id }) { return exact }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func parse(_ s: String?) -> Date? {
            guard let s else { return nil }
            return iso.date(from: s) ?? plain.date(from: s)
        }
        guard let start = parse(uploaded.startTime) else { return nil }
        return importedWorkouts.first { candidate in
            guard candidate.date == uploaded.date, let other = parse(candidate.startTime) else { return false }
            return abs(other.timeIntervalSince(start)) <= 5 * 60
        }
    }

    /// Link a recorded workout to a planned session and mark the session
    /// complete, through the API (which also clears any suggestion for it).
    func matchAndComplete(workout: ImportedWorkout, sessionKey: String) async throws {
        guard let api else { throw APIError.unauthenticated }
        let completedAt = workout.startTime ?? ISO8601DateFormatter().string(from: Date())
        try await api.linkWorkout(workoutId: workout.id, sessionKey: sessionKey)
        try await api.saveSessionWithWorkout(sessionKey: sessionKey, completedAt: completedAt,
                                             workoutId: workout.id,
                                             avgHR: workout.heartRate?.avg, peakHR: workout.heartRate?.max)
        workoutMatches[workout.id] = WorkoutMatch(workoutId: workout.id, sessionKey: sessionKey,
                                                  confidence: "manual")
        matchSuggestions.removeAll { $0.importedWorkoutId == workout.id }
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
