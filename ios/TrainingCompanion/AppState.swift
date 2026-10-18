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

    /// The active program's logs by session key — every completion mark and
    /// every logged set on the phone reads this. Only logs the server places in
    /// the active program (`inCurrentProgram`), because a key like "6-Monday-0"
    /// exists in every program the athlete has had.
    @Published var sessionLogs: [String: SessionLogEntry] = [:]
    /// Earlier programs' logs, for Log ▸ Sessions only.
    @Published var earlierSessionLogs: [SessionLogEntry] = []

    // MARK: - FIT File Import

    @Published var pendingFITURL: URL? = nil

    // MARK: - Imported Workouts

    @Published var importedWorkouts: [ImportedWorkout] = []
    @Published var isLoadingWorkouts = false
    /// Confirmed `workout_matches` rows, keyed by imported workout id.
    @Published var workoutMatches: [String: WorkoutMatch] = [:]
    /// Log ▸ Linking's day cards; nil until loaded.
    @Published var linking: LinkingDocument?
    /// Why the last Log ▸ Linking load failed, while there is no document to show.
    @Published var linkingError: String? = nil
    /// Weak server-side matches still waiting for a decision (Today card).
    @Published var matchSuggestions: [MatchSuggestion] = []
    /// The newly stored workout the "Workout complete" sheet is showing
    /// (`WorkoutCompletion`, design-system §6.30); nil when none.
    @Published var completedWorkout: ImportedWorkout? = nil

    // MARK: - Bio Logs (last 30 days)

    @Published var recentBioLogs: [DailyBioLog] = []
    @Published var readinessResult: ReadinessResult? = nil

    // MARK: - Progression

    @Published var progressionReview: ProgressionReview? = nil
    /// Analytics ▸ Progress's exercise cards (`/progression/exercises`).
    @Published var exerciseHistory: ExerciseHistoryResponse? = nil
    /// `GET /analytics/program` — the methodology scorecard (Analytics ▸ Program).
    @Published var programAnalytics: ProgramAnalytics? = nil
    @Published var isLoadingProgramAnalytics = false
    @Published var programAnalyticsError: String? = nil
    /// `GET /analytics/development` — every block, not just this one (Analytics ▸ Development).
    @Published var developmentAnalytics: DevelopmentAnalytics? = nil
    @Published var isLoadingDevelopment = false
    @Published var developmentError: String? = nil

    // MARK: - Catalog (lazy-loaded)

    @Published var benchmarks: [AppBenchmark] = []
    /// The load and recovery terms, by id (`trimp`, `tsb`, `hrv`…), for the
    /// About sections of Analytics' detail screens; empty until fetched.
    @Published var analyticsTerms: [String: AnalyticsTerm] = [:]
    /// The athlete's results on the standards (`GET /standards/results`).
    @Published var standardResults: StandardResults? = nil
    /// Results logged sessions suggest, waiting for the athlete (not results yet).
    @Published var standardSuggestions: [StandardSuggestion] = []
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
    /// Analytics ▸ Load's summary per period, from the server; a period with
    /// no entry falls back to `AnalyticsEngine`.
    @Published var loadSummaries: [AnalyticsPeriod: LoadSummary] = [:]
    /// Periods whose last summary request failed, so the screen can say its
    /// numbers are the phone's (not while a request is still in flight).
    @Published var loadSummaryFailed: Set<AnalyticsPeriod> = []

    // MARK: - Internal

    var api: APIClient?
    private let iso = ISO8601DateFormatter()
    /// Gregorian and POSIX: a phone set to the Buddhist or Japanese calendar
    /// would otherwise write "2569-10-13", which the server rejects.
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Configuration

    func configure(auth: AuthManager) {
        api = APIClient(auth: auth)
        isLoadingProgram = true  // show loading immediately, before the first async load starts
    }

    // MARK: - Initial Load

    /// When `loadAll` last finished — what `refreshIfStale` measures against.
    private(set) var lastFullLoad: Date? = nil
    /// A `loadAll` is running. The launch path already runs two loads back to
    /// back (`loadAllExceptWorkouts`, then `loadAll` after the sync); a
    /// foreground refresh on top would race them and could land last with
    /// older data.
    private var isLoadingAll = false

    func loadAll() async {
        isLoadingAll = true
        defer {
            isLoadingAll = false
            lastFullLoad = Date()
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProgram() }
            // Today's Development card is the program scorecard. It was loaded
            // once and refreshed only after the phone itself completed a
            // session, so matches from the watch, Garmin or the web, and a
            // program regenerated on the web, left it days old (0 % on a
            // week the server had at 100 %).
            group.addTask { await self.loadProgramAnalytics() }
            group.addTask { await self.loadProfile() }
            group.addTask { await self.loadStandardResults() }
            group.addTask { await self.loadStandardSuggestions() }
            group.addTask { await self.loadRecentBioLogs() }
            group.addTask { await self.loadRecentSessionLogs() }
            group.addTask { await self.loadReadiness() }
            group.addTask { await self.loadWorkouts() }
            group.addTask { await self.loadProgressionReview() }
            group.addTask { await self.loadMatchSuggestions() }
        }
        // Workouts, matches, suggestions and the program are all in: the
        // moment to notice a workout the phone has not shown yet.
        noticeCompletedWorkout()
    }

    /// What each section's load last ran against (`loadIfStale`).
    private var sectionLoads: [String: String] = [:]

    /// Run a section's load unless it already ran since the program's revision
    /// or the last full load changed. Sections are rebuilt on every switch
    /// (`AppSubTabScreen`), and their `.task`s used to refetch each time; a
    /// pull-to-refresh, a foreground refresh or a regenerate still reloads
    /// them the next time they are shown.
    func loadIfStale(_ key: String, _ load: () async -> Void) async {
        let stamp = "\(serverProgram?.revision ?? "-")|\(lastFullLoad?.timeIntervalSince1970 ?? 0)"
        guard sectionLoads[key] != stamp else { return }
        await load()
        sectionLoads[key] = stamp
    }

    /// Coming back to the foreground: reload what Today shows when the last
    /// full load is older than `maxAge`. The app had no foreground refresh,
    /// so a phone left in the background overnight opened on yesterday's
    /// readiness and scorecard.
    ///
    /// Nothing before the first full load has finished: at launch the scene
    /// turns active (and again after the HealthKit permission sheet) while the
    /// launch loads are still running.
    func refreshIfStale(maxAge: TimeInterval = 300, now: Date = Date()) async {
        guard !isLoadingAll, let last = lastFullLoad,
              now.timeIntervalSince(last) >= maxAge else { return }
        await loadAll()
    }

    /// Called on first appear — loads everything the Today tab needs without fetching workouts,
    /// so there is no concurrent loadWorkouts() race with the post-sync loadAll().
    func loadAllExceptWorkouts() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadProgram() }
            group.addTask { await self.loadProfile() }
            group.addTask { await self.loadStandardResults() }
            group.addTask { await self.loadStandardSuggestions() }
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

    // MARK: - Workout complete

    private static let seenWorkoutsKey = "workoutComplete.seen"

    /// Workouts the phone has already celebrated (or that arrived together
    /// with one it did, or that the athlete imported by hand). nil before the
    /// first load on this install or build.
    private var seenWorkoutIds: Set<String>? {
        get { UserDefaults.standard.stringArray(forKey: Self.seenWorkoutsKey).map(Set.init) }
        set { UserDefaults.standard.set(newValue.map(Array.init), forKey: Self.seenWorkoutsKey) }
    }

    /// The sheet is actually up — set by the sheet itself. A presentation
    /// SwiftUI drops (another sheet is open) leaves it false.
    var completedWorkoutOnScreen = false

    /// Workouts still to show after this one — `workout-complete?demo=1`
    /// lines up the newest eight so each can be looked at in turn.
    private var completedWorkoutQueue: [ImportedWorkout] = []

    /// Present the sheet for the newest workout not yet shown, if one ended
    /// recently enough to be a moment rather than history.
    ///
    /// The first load on an install (or on the build that brings the sheet)
    /// only records what is there: a workout from yesterday, long since
    /// linked on the web, is not news.
    func noticeCompletedWorkout(now: Date = Date()) {
        guard completedWorkout == nil, !importedWorkouts.isEmpty else { return }
        guard let seen = seenWorkoutIds else {
            seenWorkoutIds = Set(importedWorkouts.map(\.id))
            return
        }
        guard let workout = WorkoutCompletion.next(in: importedWorkouts, seen: seen, now: now) else { return }
        show(workout)
    }

    /// Show the sheet for a given workout, or the newest when `id` is nil,
    /// whether or not it was seen — `trainingcompanion://workout-complete[?id=…]`,
    /// so the simulator can be driven to the screen. An id not in the list
    /// shows nothing rather than some other workout.
    func presentCompletedWorkout(id: String?) {
        let pick = id.map { id in importedWorkouts.first { $0.id == id } }
            ?? importedWorkouts.max { (WorkoutCompletion.endDate(of: $0) ?? .distantPast)
                < (WorkoutCompletion.endDate(of: $1) ?? .distantPast) }
        if let pick { show(pick) }
    }

    func presentCompletedWorkoutDemo(count: Int = 8) {
        let newest = importedWorkouts.sorted {
            (WorkoutCompletion.endDate(of: $0) ?? .distantPast) > (WorkoutCompletion.endDate(of: $1) ?? .distantPast)
        }
        guard let first = newest.first else { return }
        completedWorkoutQueue = Array(newest.dropFirst().prefix(count - 1))
        show(first)
    }

    /// Set the sheet's workout, and take it back if the sheet never came up:
    /// SwiftUI drops a sheet presented over another, and a workout left set
    /// would block every later one. Not marked seen — the next load retries.
    private func show(_ workout: ImportedWorkout) {
        completedWorkoutOnScreen = false
        completedWorkout = workout
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.completedWorkout?.id == workout.id, !self.completedWorkoutOnScreen {
                self.completedWorkout = nil
                self.completedWorkoutQueue = []
            }
        }
    }

    /// The sheet closed: everything listed now is seen, so an older workout
    /// that arrived in the same sync does not pop up next.
    func finishCompletedWorkout() {
        // Only ids still listed need remembering — the list is the record —
        // unless the list failed to load, when forgetting would re-show them.
        var seen = importedWorkouts.isEmpty ? (seenWorkoutIds ?? []) : []
        seen.formUnion(importedWorkouts.map(\.id))
        if let id = completedWorkout?.id { seen.insert(id) }
        seenWorkoutIds = seen
        completedWorkout = nil
        completedWorkoutOnScreen = false
        // A demo's next workout, once this sheet is off the screen.
        if !completedWorkoutQueue.isEmpty {
            let next = completedWorkoutQueue.removeFirst()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                self.show(next)
            }
        }
    }

    /// Mark workouts seen without showing them (an import the athlete made).
    private func markSeen(_ ids: [String]) {
        seenWorkoutIds = (seenWorkoutIds ?? []).union(ids)
    }

    /// What the sheet offers to link the workout to.
    func completionMatch(for workout: ImportedWorkout) -> WorkoutCompletion.Match {
        let sameDay = sessionsForDate(workout.date).map {
            WorkoutCompletion.Candidate(key: $0.key, session: $0.session)
        }
        // Only a suggestion for a session of this program is confirmed here:
        // confirming writes a completion under its key, which for an earlier
        // program's session would tick this program's session of that name.
        // Those, and one whose session is not in the loaded program, are
        // decided in Log ▸ Linking.
        let pending = pendingMatchSuggestions().first { $0.workout.id == workout.id }?.suggestion
        let suggestion = pending.flatMap { s in
            WorkoutCompletion.isCurrentProgram(uid: s.sessionUid, versionId: programVersionId)
                && locateSession(key: s.sessionKey) != nil ? s : nil
        }
        // A match dated to an earlier block names a session of this program
        // too ("4-Monday-0"); it is linked, but not to anything shown here.
        let earlier = workoutMatches[workout.id]?.inCurrentProgram == false
        return WorkoutCompletion.match(
            matchedKey: matchedSessionKey(for: workout.id),
            suggestionKey: suggestion?.sessionKey,
            sameDay: sameDay,
            isComplete: { self.isSessionComplete($0) },
            session: { earlier ? nil : self.locateSession(key: $0)?.session })
    }

    // MARK: - Match suggestions

    func loadMatchSuggestions() async {
        guard let api else { return }
        matchSuggestions = (try? await api.fetchMatchSuggestions()) ?? []
    }

    /// Suggestions still to decide: the server's weak matches whose workout is
    /// in the list and has not been linked since. Today shows the first three,
    /// Log ▸ Suggestions all of them.
    func pendingMatchSuggestions() -> [(suggestion: MatchSuggestion, workout: ImportedWorkout)] {
        matchSuggestions.compactMap { suggestion in
            guard matchedSessionKey(for: suggestion.importedWorkoutId) == nil,
                  let workout = importedWorkouts.first(where: { $0.id == suggestion.importedWorkoutId })
            else { return nil }
            return (suggestion, workout)
        }
    }

    /// Forget a suggestion without deciding the workout; the server forgets it too.
    // MARK: - Log ▸ Linking

    /// Pairs waved away on this phone ("not this"), as the web keeps them per
    /// browser. Sent with every request so the day is re-suggested without them.
    @Published private(set) var dismissedLinks: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "linking.dismissed") ?? [])

    func loadLinking() async {
        guard let api else { return }
        let today = dayFormatter.string(from: Date())
        do {
            linking = try await api.fetchLinking(today: today, dismissed: dismissedLinks)
            linkingError = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            linkingError = error.localizedDescription
            AppLogger.logFromBackground("linking: fetch failed — \(error.localizedDescription)")
        }
    }

    /// Link a workout to a session on any day. A session of the current
    /// program is also marked complete; one of an earlier program is only
    /// linked — its key would tick this program's session of that name.
    func link(workoutId: String, to session: LinkSession) async {
        guard let api else { return }
        if let doc = linking { linking = Linking.applyingLink(doc, workoutId: workoutId, session: session) }
        if !session.historical, let workout = importedWorkouts.first(where: { $0.id == workoutId }) {
            try? await matchAndComplete(workout: workout, sessionKey: session.legacyKey ?? session.key,
                                        session: session)
        } else {
            try? await api.saveWorkoutMatch(Linking.linkPayload(workoutId: workoutId, session: session))
            workoutMatches[workoutId] = WorkoutMatch(workoutId: workoutId,
                                                     sessionKey: session.legacyKey ?? session.key,
                                                     confidence: "manual", inCurrentProgram: false)
            matchSuggestions.removeAll { $0.importedWorkoutId == workoutId }
        }
        await loadLinking()
    }

    func unlink(workoutId: String) async {
        guard let api else { return }
        if let doc = linking { linking = Linking.applyingUnlink(doc, workoutId: workoutId) }
        try? await api.saveWorkoutMatch(Linking.unlinkPayload(workoutId: workoutId))
        workoutMatches[workoutId] = WorkoutMatch(workoutId: workoutId, sessionKey: "", confidence: "rejected")
        await loadLinking()
    }

    func dismissLink(workoutId: String, sessionKey: String) async {
        dismissedLinks.insert(Linking.dismissKey(workoutId: workoutId, sessionKey: sessionKey))
        UserDefaults.standard.set(Array(dismissedLinks), forKey: "linking.dismissed")
        if let doc = linking { linking = Linking.applyingDismiss(doc, workoutId: workoutId, sessionKey: sessionKey) }
        await loadLinking()
    }

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

    /// The recorded workout linked to a planned session of the active
    /// program, if any — the reverse of `matchedSessionKey(for:)`. A match the
    /// server dated to an earlier block is skipped: its key is program-relative
    /// and names a session of this program too.
    func linkedWorkout(forSessionKey key: String) -> ImportedWorkout? {
        let matched = workoutMatches.values
            .filter { $0.sessionKey == key && $0.inCurrentProgram }
            .map(\.workoutId)
        let ids = matched.isEmpty ? [sessionLogs[key]?.matchedWorkoutId].compactMap { $0 } : matched
        // Several workouts can be linked to one session; show the longest.
        return importedWorkouts
            .filter { ids.contains($0.id) }
            .max { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }
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
        writeHomeWidgets()
    }

    /// The full-width home-screen widgets: the program week (Monday to
    /// Sunday, sessions and ticks) and the status row (Today · Readiness ·
    /// Adherence · Progress). Copies what the app already holds — the stored
    /// program, the session logs, the server's readiness and the
    /// `/analytics/program` document — so a widget never says other than the
    /// app. Called whenever any of those changes.
    func writeHomeWidgets() {
        let dateStr = dayFormatter.string(from: Date())
        var weekData: WidgetWeekData? = nil
        if let idx = currentWeekIndex, let program = serverProgram?.currentProgram,
           let startStr = serverProgram?.programStartDate, let start = dayFormatter.date(from: startStr) {
            let week = program.weeks[idx]
            let names = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
            let calendar = Calendar.current
            let days: [WidgetWeekData.Day] = (0..<7).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: idx * 7 + offset, to: calendar.startOfDay(for: start))
                else { return nil }
                let dayName = names[calendar.component(.weekday, from: date) - 1]
                let sessions = (week.schedule[dayName] ?? []).enumerated().map { i, s in
                    WidgetWeekData.Session(
                        modalityId: s.modality, name: s.archetype?.name ?? s.modality,
                        minutes: s.archetype?.durationEstimateMinutes ?? 45,
                        done: isSessionComplete(makeSessionKey(weekNumber: week.weekNumber, dayName: dayName, index: i)))
                }
                return WidgetWeekData.Day(dayName: dayName, date: dayFormatter.string(from: date), sessions: sessions)
            }
            weekData = WidgetWeekData(updatedAt: Date(), weekNumber: idx + 1, totalWeeks: program.weeks.count,
                                      phase: week.phase, isDeload: week.isDeload, days: days)
        }

        let todays = todaySessions
        let first = todays.first?.session
        // Inside the program only: after its last week there is no "today".
        let today: WidgetStatusData.Today? = currentWeekIndex == nil ? nil : WidgetStatusData.Today(
            date: dateStr, sessionCount: todays.count,
            doneCount: todays.filter { isSessionComplete($0.sessionKey) }.count,
            firstName: first.map { $0.archetype?.name ?? $0.modality }, firstModality: first?.modality,
            minutes: first.map { $0.archetype?.durationEstimateMinutes ?? 45 })
        let readiness = readinessResult.map { WidgetStatusData.Readiness(score: $0.score, status: $0.status) }
        var adherence: WidgetStatusData.Adherence? = nil
        if let sc = programAnalytics?.scorecard, (sc.plannedSessions ?? 0) > 0 {
            adherence = WidgetStatusData.Adherence(
                pct: Int((sc.overallPct ?? 0).rounded()), verdict: sc.headline,
                weekDone: sc.currentWeek?.completed, weekDue: sc.currentWeek?.due)
        }
        let progress = programAnalytics?.methodologies.first?.headlineSummary.map {
            WidgetStatusData.Progress(label: $0.label, text: $0.text, status: $0.status)
        }
        // A part not loaded yet keeps what is stored: the loads run in
        // parallel at launch, and the first to finish must not blank the
        // others (nor a failed program fetch blank the week).
        let previous = WidgetDataStore.readStatus()
        let loaded = serverProgram != nil
        WidgetDataStore.writeHome(
            week: loaded ? weekData : WidgetDataStore.readWeek(),
            status: WidgetStatusData(
                updatedAt: Date(),
                today: loaded ? today : previous?.today,
                readiness: readiness ?? previous?.readiness,
                adherence: programAnalytics != nil ? adherence : previous?.adherence,
                progress: programAnalytics != nil ? progress : previous?.progress,
                readinessAt: readinessResult != nil ? Date() : previous?.readinessAt))
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

    func loadStandardResults() async {
        guard let api else { return }
        do {
            standardResults = try await api.fetchStandardResults()
            logger.log("standards: \(standardResults?.standards.count ?? 0) with results")
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            logger.log("standards: results ERROR — \(error)")
        }
    }

    func loadStandardSuggestions() async {
        guard let api else { return }
        do {
            standardSuggestions = try await api.fetchStandardSuggestions()
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            logger.log("standards: suggestions ERROR — \(error)")
        }
    }

    /// Save a suggested result (optionally corrected as typed), dismiss it as
    /// "Not a test", or reopen it. Nil on success, else why not, in words.
    func decideSuggestion(id: Int, action: String, text: String? = nil) async -> String? {
        let failure = await standardsChange { try await $0.decideSuggestion(id: id, action: action, text: text) }
        await loadStandardSuggestions()
        return failure
    }

    /// Logs a result, then re-reads the results so every screen shows what the
    /// server kept, on the server's ladder. Returns nil on success, else the
    /// reason in words to show.
    func logResult(benchmarkId: String, text: String) async -> String? {
        await logResult(benchmarkId: benchmarkId, input: StandardResultInput(text: text))
    }

    func logResult(benchmarkId: String, input: StandardResultInput) async -> String? {
        await standardsChange { try await $0.addResult(benchmarkId: benchmarkId, input: input) }
    }

    /// Corrects one result (value, day or note). Nil on success, else why not.
    func updateResult(id: Int, input: StandardResultInput) async -> String? {
        await standardsChange { try await $0.updateResult(id: id, input: input) }
    }

    /// Deletes one result. Nil on success, else why not.
    func deleteResult(id: Int) async -> String? {
        await standardsChange { try await $0.deleteResult(id: id) }
    }

    private func standardsChange(_ work: (APIClient) async throws -> Void) async -> String? {
        guard let api else { return "Not connected." }
        do {
            try await work(api)
        } catch APIError.serverErrorDetail(_, let detail) {
            return detail
        } catch {
            logger.log("standards: change ERROR — \(error)")
            return error.localizedDescription
        }
        await loadStandardResults()
        // Progress and Blocks read results too.
        await loadProgramAnalytics()
        return nil
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
            let split = SessionLogScope.split(logs)
            sessionLogs = split.current
            earlierSessionLogs = split.earlier
            rescheduleNotifications()   // a session completed elsewhere cancels its reminder
            writeHomeWidgets()          // and ticks it on the week widget
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
        writeHomeWidgets()
        // Today's completion is the program scorecard's.
        await loadProgramAnalytics()
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
            let standards = try await api.saveExerciseLog(sessionKey: sessionKey, exerciseId: exerciseId,
                                                          performance: performance)
            // A test slot's outcome comes back as a suggestion to save.
            if standards != nil { await loadStandardSuggestions() }
            // A logged set moves the exercise into "With data" on Progress.
            if exerciseHistory != nil { await loadExerciseHistory() }
        } catch {
            AppLogger.logFromBackground("session log: save failed — \(error.localizedDescription)")
        }
    }

    /// A planned session located by its key ("<week number>-<Day>-<index>"),
    /// for a deep link or a widget. The first week carrying that number wins,
    /// which is what every other reader of the key does.
    struct LocatedSession: Identifiable {
        var id: String { key }
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
        await loadProgramAnalytics()
    }

    // MARK: - Bio Logs

    func loadRecentBioLogs() async {
        guard let api else { return }
        do {
            recentBioLogs = try await api.fetchRecentBioLogs()
        } catch {
            // Ignore task cancellation (expected when SwiftUI .task cancels on view disappear)
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.logFromBackground("bio: HTTP error — \(error.localizedDescription)")
        }
    }

    func loadReadiness() async {
        guard let api else { return }
        do {
            let result = try await api.fetchReadiness()
            readinessResult = result
            ReadinessInfo.storeForWatch(result)
            writeHomeWidgets()
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.logFromBackground("readiness: fetch failed — \(error.localizedDescription)")
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
            writeHomeWidgets()
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            programAnalyticsError = error.localizedDescription
            AppLogger.logFromBackground("analytics: program fetch failed — \(error.localizedDescription)")
        }
    }

    /// The development document. Loaded when the section is shown, and again
    /// on pull-to-refresh; the server recomputes only when the history changed.
    func loadDevelopmentAnalytics(fresh: Bool = false) async {
        guard let api else { return }
        isLoadingDevelopment = true
        defer { isLoadingDevelopment = false }
        do {
            developmentAnalytics = try await api.fetchDevelopmentAnalytics(fresh: fresh)
            developmentError = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            developmentError = error.localizedDescription
            AppLogger.logFromBackground("analytics: development fetch failed — \(error.localizedDescription)")
        }
    }

    func loadExerciseHistory() async {
        guard let api else { return }
        do {
            exerciseHistory = try await api.fetchExerciseHistory(today: dayFormatter.string(from: Date()))
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.logFromBackground("progression: exercises fetch failed — \(error.localizedDescription)")
        }
    }

    func loadProgressionReview() async {
        guard let api else { return }
        do {
            progressionReview = try await api.fetchProgressionReview()
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            AppLogger.logFromBackground("progression: fetch failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Catalog (lazy)

    func loadBenchmarksIfNeeded() async {
        guard let api, benchmarks.isEmpty else { return }
        benchmarks = (try? await api.fetchBenchmarks(sex: profile.sex)) ?? []
    }

    /// Fetched once, and again when a screen asks for a term this copy lacks
    /// — one the server added after the first fetch (a deploy while the app
    /// was open) would otherwise stay missing until a relaunch. A failed
    /// fetch keeps what there was.
    func loadAnalyticsTermsIfNeeded(_ ids: [String] = []) async {
        guard let api, analyticsTerms.isEmpty || ids.contains(where: { analyticsTerms[$0] == nil }) else { return }
        if let terms = try? await api.fetchAnalyticsTerms(), !terms.isEmpty { analyticsTerms = terms }
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
            AppLogger.logFromBackground("load: server PMC unavailable — computing on device")
        }
        if let weeks = try? await weekly {
            serverWeeklyLoad = weeks
        }
    }

    func loadLoadSummary(_ period: AnalyticsPeriod) async {
        guard let api else { return }
        do {
            loadSummaries[period] = try await api.fetchLoadSummary(period: period, today: dayFormatter.string(from: Date()))
            loadSummaryFailed.remove(period)
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            loadSummaries[period] = nil
            loadSummaryFailed.insert(period)
            AppLogger.logFromBackground("load: server summary unavailable — computing on device (\(error.localizedDescription))")
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
        Self.sessionKey(weekNumber: weekNumber, dayName: dayName, index: index)
    }

    /// "3-Monday-0": the program-relative key, for code with no `AppState`.
    nonisolated static func sessionKey(weekNumber: Int, dayName: String, index: Int) -> String {
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
            exclude: session.exercises.compactMap { $0.exercise?.id },
            phaseId: week.phaseId,
            frameworkId: week.frameworkId)
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

    /// The methodologies the stored program was generated from, as catalog
    /// cards, in the envelope's order; `_blended` is a marker, not a source.
    /// Empty until the philosophies are loaded or when none match.
    func programMethodologies() -> [PhilosophyCard] {
        guard let ids = serverProgram?.sourceGoalIds else { return [] }
        return ids.filter { $0 != "_blended" }.compactMap { id in philosophies.first { $0.id == id } }
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
                                                        weekInPhase: week.weekInPhase, phase: week.phase,
                                                        phaseId: week.phaseId, trackId: week.trackId)
        let request = GenerateProgramRequest(
            philosophyId: ids.count == 1 ? ids[0] : nil,
            philosophyIds: ids.count > 1 ? ids : nil,
            philosophyWeights: ids.count > 1 ? sp.sourceGoalWeights : nil,
            constraints: constraints, numWeeks: remaining, weekInProgram: start + 1,
            startDate: nil, eventDate: sp.eventDate, persist: false)
        let generated = try await api.generateProgramPreview(request)
        let today = DateFormatter()
        today.locale = Locale(identifier: "en_US_POSIX")
        today.dateFormat = "yyyy-MM-dd"
        // The days already behind the athlete this week stay as they are.
        let spliced = Regeneration.splice(current: program, from: start, generated: generated,
                                          programStartDate: sp.programStartDate,
                                          keepBefore: today.string(from: Date()))
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
            let summary = try await api.saveProgram(payload)
            programSaveConflict = nil
            // The summary of the weeks just saved (a move, a swap, a replaced
            // session), so Overview's phase changes follow the edit.
            if let summary, let now = serverProgram, let current = now.currentProgram {
                var extra = current.extra
                extra["phase_summary"] = summary
                serverProgram = ServerProgram(currentProgram: GeneratedProgram(weeks: current.weeks, extra: extra),
                                              programStartDate: now.programStartDate,
                                              eventDate: now.eventDate, sourceGoalIds: now.sourceGoalIds,
                                              sourceGoalWeights: now.sourceGoalWeights,
                                              revision: now.revision, programVersionId: now.programVersionId,
                                              extra: now.extra)
            }
        } catch is APIClient.StaleProgramRevision {
            // Someone (the web) has newer work. Take theirs — and say so: the
            // move or replace the user just made is not in the copy we reload.
            await loadProgram()
            programSaveConflict = "Your program changed elsewhere — reloaded; your last edit was not saved."
        }
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
        // The import sheet is its own confirmation; don't celebrate it twice —
        // marked before the reload, which a concurrent load could notice.
        markSeen([uploaded.id])
        await loadWorkouts()
        await loadMatchSuggestions()
        // A run's fastest mile can come back as a suggested result.
        await loadStandardSuggestions()
        let listed = canonicalWorkout(for: uploaded) ?? uploaded
        markSeen([listed.id])
        return listed
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
    ///
    /// `session` names the session exactly (Log ▸ Linking): its uid goes with
    /// the match, since the server otherwise resolves the key on the
    /// workout's own date and finds nothing for a link across days.
    func matchAndComplete(workout: ImportedWorkout, sessionKey: String,
                          session: LinkSession? = nil) async throws {
        guard let api else { throw APIError.unauthenticated }
        let completedAt = workout.startTime ?? ISO8601DateFormatter().string(from: Date())
        if let session {
            try await api.saveWorkoutMatch(Linking.linkPayload(workoutId: workout.id, session: session))
        } else {
            try await api.linkWorkout(workoutId: workout.id, sessionKey: sessionKey)
        }
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
        await loadProgramAnalytics()
    }
}
