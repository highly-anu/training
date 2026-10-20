import Foundation

struct DailyBioPayload: Encodable {
    let restingHR: Double?
    let hrv: Double?
    let sleepDurationMin: Int?
    let deepSleepMin: Int?
    let remSleepMin: Int?
    let lightSleepMin: Int?
    let awakeMins: Int?
    let sleepStart: String?  // ISO 8601
    let sleepEnd: String?
    let spo2Avg: Double?
    let respiratoryRateAvg: Double?
    /// Free text from the manual check-in; the relay never sets it.
    var notes: String? = nil
    /// "apple_watch" for the HealthKit relay, "manual" for a check-in. The relay
    /// uses the stored source to decide which days it has already pushed.
    var source: String = "apple_watch"
}

/// A watch/companion device paired to the account. Server truncates deviceToken.
struct PairedDevice: Decodable, Identifiable {
    let deviceToken: String
    let deviceName: String?
    let claimedAt: String?
    let lastUsedAt: String?
    var id: String { deviceToken }
}

enum APIError: LocalizedError {
    case unauthenticated
    case serverError(Int)
    case serverErrorDetail(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .unauthenticated:              return "Not signed in."
        case .serverError(let c):           return "Server error \(c)."
        case .serverErrorDetail(let c, let body): return "Error \(c): \(body)"
        case .decodingError:                return "Failed to decode response."
        }
    }
}

final class APIClient {
    /// Production from Info.plist, or the developer's override (`APITarget`).
    /// Read per request so a target change needs no new client.
    private static var baseURL: String { APITarget.baseURL }

    private let auth: AuthManager
    private let iso = ISO8601DateFormatter()

    init(auth: AuthManager) {
        self.auth = auth
    }

    func getSyncedDates() async throws -> [String] {
        let data = try await get("/health/bio/synced-dates")
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func pushBio(date: String, payload: DailyBioPayload) async throws {
        _ = try await put("/health/bio/\(date)", body: payload)
    }

    /// The athlete's day as the server words it for both watches — today's
    /// sessions with their screens, done flags, last times and test
    /// standards, the week ahead, tomorrow, readiness, progress, max HR
    /// (docs/watch.md). Raw: the phone forwards it to the Apple Watch as it is.
    func fetchWatchDay(date: String) async throws -> Data {
        try await get("/user/today-session?date=\(date)&spec=1&week=1")
    }

    func fetchTodaySessionStatus() async throws -> String {
        let data = try await get("/user/today-session")
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (json["status"] as? String) ?? "unknown"
    }

    // MARK: - Program history
    //
    // Which plan was in force when, and what it planned each day. The server
    // keeps one current program per athlete and overwrites it, so before this
    // a replaced block left nothing behind.

    func fetchProgramHistory() async throws -> [ProgramHistoryEntry] {
        let data = try await get("/programs/history")
        return (try? JSONDecoder().decode([ProgramHistoryEntry].self, from: data)) ?? []
    }

    func fetchProgramVersion(_ versionId: String) async throws -> ProgramHistoryDetail? {
        let escaped = versionId.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? versionId
        let data = try await get("/programs/history/\(escaped)")
        return try? JSONDecoder().decode(ProgramHistoryDetail.self, from: data)
    }

    func fetchProgram() async throws -> ServerProgram? {
        let data = try await get("/user/program")
        if let program = try? JSONDecoder().decode(ServerProgram.self, from: data) {
            return program
        }
        // Decode failed — log a snippet so we can diagnose key-casing mismatches
        let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "(unreadable)"
        AppLogger.logFromBackground("program: decode failed — raw: \(snippet)")
        return nil
    }

    func fetchArchetypes() async throws -> [AppArchetype] {
        let data = try await get("/archetypes")
        return (try? JSONDecoder().decode([AppArchetype].self, from: data)) ?? []
    }

    func saveWorkoutLog(sessionKey: String, log: [String: Any]) async throws {
        guard let body = try? JSONSerialization.data(withJSONObject: log) else { return }
        _ = try await putRaw("/health/sessions/\(sessionKey)", body: body)
    }

    /// Store workouts the watch recorded (`WatchUpload.workoutPayload`). No
    /// `autoMatch`: the watch knows which session it ran, and the match is
    /// posted explicitly with `saveWorkoutMatch`. The server recomputes
    /// elevation from the track and folds duplicates from other sources.
    func saveWatchWorkouts(_ workouts: [[String: Any]]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["workouts": workouts])
        _ = try await postRaw("/health/workouts", body: body)
    }

    /// `POST /health/matches` with a `WatchUpload.matchPayload`.
    func saveWorkoutMatch(_ match: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: match)
        _ = try await postRaw("/health/matches", body: body)
    }

    /// Upload automatically imported workouts.
    ///
    /// Goes through Flask rather than a Supabase REST upsert on purpose: this
    /// endpoint recomputes elevation from the GPS track, folds together copies
    /// of the same activity from other sources, and runs the server-side
    /// matcher. Writing straight to Supabase skips all three — and this app
    /// has no matcher of its own. (The .fit import used to do exactly that;
    /// it goes through `uploadFITFile` now.)
    @discardableResult
    func saveImportedWorkouts(_ workouts: [ImportedWorkout]) async throws -> Int {
        guard !workouts.isEmpty else { return 0 }
        struct Payload: Encodable {
            let workouts: [ImportedWorkout]
            let autoMatch: Bool
        }
        let body = try JSONEncoder().encode(Payload(workouts: workouts, autoMatch: true))
        _ = try await postRaw("/health/workouts", body: body)
        return workouts.count
    }

    // MARK: - User Profile

    func fetchUserProfile() async throws -> UserProfile {
        let data = try await get("/userdata/profile")
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }

    /// Returns the raw JSON string for debug logging, then the caller decodes separately.
    func fetchUserProfileRaw() async throws -> String {
        let data = try await get("/userdata/profile")
        return String(data: data, encoding: .utf8) ?? "(unreadable)"
    }

    func decodeUserProfile(from raw: String) throws -> UserProfile {
        guard let data = raw.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }

    func saveUserProfile(_ profile: UserProfile) async throws {
        _ = try await put("/userdata/profile", body: profile)
    }

    /// Logs a result on a standard, or a bodyweight (`bodyweight_kg`, the series
    /// the ×BW standards read): text as typed ("4:58"), or for a ×BW standard the
    /// kg and reps lifted, with the athlete's day and a note. The server reads
    /// and converts it, so the phone and the web read input the same way. A 422
    /// (not a value) or 503 (not saved) comes back as the server's own words.
    /// (PRs used to ride on the profile PUT, whose merge whitelist drops them.)
    func addResult(benchmarkId: String, input: StandardResultInput) async throws {
        struct Body: Encodable {
            let benchmarkId: String
            let loggedAt: String
            let input: StandardResultInput
            func encode(to encoder: Encoder) throws {
                try input.encode(to: encoder)
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(benchmarkId, forKey: .benchmarkId)
                try c.encode(loggedAt, forKey: .loggedAt)
            }
            enum Keys: String, CodingKey { case benchmarkId, loggedAt }
        }
        let body = try JSONEncoder().encode(Body(benchmarkId: benchmarkId,
                                                 loggedAt: ISO8601DateFormatter().string(from: Date()), input: input))
        try await sendExpectingSuccess("POST", "/standards/results", body: body, fallback: "Could not save the result")
    }

    /// Corrects one result: value, day or note — only the fields set.
    func updateResult(id: Int, input: StandardResultInput) async throws {
        let body = try JSONEncoder().encode(input)
        try await sendExpectingSuccess("PATCH", "/standards/results/\(id)", body: body, fallback: "Could not save the change")
    }

    /// Deletes one result — never the standard's whole history.
    func deleteResult(id: Int) async throws {
        try await sendExpectingSuccess("DELETE", "/standards/results/\(id)", body: nil, fallback: "Could not delete the result")
    }

    private func sendExpectingSuccess(_ method: String, _ path: String, body: Data?, fallback: String) async throws {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try await addAuth(to: &request)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIError.unauthenticated }
        guard (200...299).contains(status) else {
            throw APIError.serverErrorDetail(status, Self.detail(from: data) ?? fallback)
        }
    }

    /// Results logged sessions suggest, waiting for a decision.
    func fetchStandardSuggestions() async throws -> [StandardSuggestion] {
        let data = try await get("/standards/suggestions")
        return try JSONDecoder().decode(StandardSuggestionList.self, from: data).suggestions
    }

    /// Save a suggestion as a result (`confirm`, with `text` when the athlete
    /// corrected it), "Not a test" (`dismiss`) or undo that (`reopen`).
    func decideSuggestion(id: Int, action: String, text: String? = nil) async throws {
        var body: [String: String] = ["via": "ios"]
        if let text { body["text"] = text }
        try await sendExpectingSuccess("POST", "/standards/suggestions/\(id)/\(action)",
                                       body: try JSONEncoder().encode(body), fallback: "Could not save the result")
    }

    /// The athlete's results, each placed on its ladder by the server.
    func fetchStandardResults() async throws -> StandardResults {
        let data = try await get("/standards/results")
        return try JSONDecoder().decode(StandardResults.self, from: data)
    }

    // MARK: - Catalog

    func fetchExercises(search: String? = nil, category: String? = nil) async throws -> [AppExercise] {
        var path = "/exercises"
        var params: [String] = []
        if let s = search, !s.isEmpty {
            let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
            params.append("search=\(encoded)")
        }
        if let c = category { params.append("category=\(c)") }
        if !params.isEmpty { path += "?" + params.joined(separator: "&") }
        let data = try await get(path)
        return (try? JSONDecoder().decode([AppExercise].self, from: data)) ?? []
    }

    /// The standards. `sex` picks the tables; the endpoint serves the male ones
    /// otherwise. Each row decodes on its own, so one malformed standard can
    /// never blank the list again.
    func fetchBenchmarks(sex: String? = nil) async throws -> [AppBenchmark] {
        var path = "/standards"
        if let sex, sex == "male" || sex == "female" { path += "?sex=\(sex)" }
        let data = try await get(path)
        return try JSONDecoder().decode([Lossy<AppBenchmark>].self, from: data).compactMap(\.value)
    }

    /// The load and recovery terms in words (`GET /analytics/vocabulary`),
    /// for the About sections of Analytics' detail screens. Static.
    func fetchAnalyticsTerms() async throws -> [String: AnalyticsTerm] {
        try Self.analyticsTerms(from: try await get("/analytics/vocabulary"))
    }

    /// Term by term: one the phone cannot read is left out, not every one.
    static func analyticsTerms(from data: Data) throws -> [String: AnalyticsTerm] {
        struct Body: Decodable { let terms: [String: Lossy<AnalyticsTerm>]? }
        return (try JSONDecoder().decode(Body.self, from: data).terms ?? [:]).compactMapValues(\.value)
    }

    func fetchPhilosophies() async throws -> [PhilosophyCard] {
        let data = try await get("/philosophies")
        return (try? JSONDecoder().decode([PhilosophyCard].self, from: data)) ?? []
    }

    func fetchInjuryFlags() async throws -> [InjuryFlagDef] {
        let data = try await get("/constraints/injury-flags")
        return (try? JSONDecoder().decode([InjuryFlagDef].self, from: data)) ?? []
    }

    func fetchEquipmentProfiles() async throws -> [EquipmentProfileDef] {
        let data = try await get("/constraints/equipment-profiles")
        return (try? JSONDecoder().decode([EquipmentProfileDef].self, from: data)) ?? []
    }

    // MARK: - Session Logs

    func fetchRecentSessionLogs() async throws -> [SessionLogEntry] {
        let data = try await get("/health/sessions/recent")
        return (try? JSONDecoder().decode([SessionLogEntry].self, from: data)) ?? []
    }

    /// `source` is the log's: a session ticked on the phone is `manual`; the
    /// Apple Watch's done mark keeps its log `apple_watch_live` (it used to
    /// overwrite it with `manual`, after the workout's log had just said it).
    func saveSessionComplete(sessionKey: String, completedAt: String, source: String = "manual") async throws {
        struct Body: Encodable {
            let completedAt: String
            let source: String
        }
        _ = try await put(
            "/health/sessions/\(sessionKey)",
            body: Body(completedAt: completedAt, source: source)
        )
    }

    /// Log what was done for one exercise. The server merges `exercises` per
    /// key and keeps the completion, notes and fatigue it already has, so a
    /// log before "Mark Session Complete" is fine and so is one after.
    /// What the save says about the standards: a test slot's outcome comes
    /// back as a suggestion (`standards.pending`), nil when the log bears on
    /// no standard.
    @discardableResult
    func saveExerciseLog(sessionKey: String, exerciseId: String,
                         performance: ExercisePerformanceLog) async throws -> SessionLogStandards? {
        struct Body: Encodable {
            let exercises: [String: ExercisePerformanceLog]
            let source: String
        }
        struct Saved: Decodable { let standards: SessionLogStandards? }
        let escaped = sessionKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionKey
        let data = try await put("/health/sessions/\(escaped)",
                                 body: Body(exercises: [exerciseId: performance], source: "manual"))
        return (try? JSONDecoder().decode(Saved.self, from: data))?.standards
    }

    /// "Done as written" for a training-contract session: the server writes
    /// each progressing exercise's prescribed rounds with `clean` and `rpe`,
    /// merged into the log (`POST /health/sessions/<key>/confirm`). A
    /// watch-recorded or linked session logs no per-exercise outcome, so this
    /// is what lets a regenerate count it.
    func confirmSession(sessionKey: String, clean: Bool, rpe: Int?) async throws {
        struct Body: Encodable { let clean: Bool; let rpe: Int? }
        let escaped = sessionKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionKey
        _ = try await postRaw("/health/sessions/\(escaped)/confirm",
                              body: try JSONEncoder().encode(Body(clean: clean, rpe: rpe)))
    }

    func saveSessionNotes(sessionKey: String, notes: String, fatigueRating: Int?) async throws {
        struct Body: Encodable {
            let sessionKey: String
            let notes: String
            let fatigueRating: Int?
            enum CodingKeys: String, CodingKey {
                case sessionKey = "session_key"
                case notes
                case fatigueRating = "fatigue_rating"
            }
        }
        _ = try await put(
            "/health/sessions/\(sessionKey)/notes",
            body: Body(sessionKey: sessionKey, notes: notes, fatigueRating: fatigueRating)
        )
    }

    /// Un-completes a session: clears `completed_at` and keeps sets and notes.
    /// Un-doing used to be client-only because the log upsert keeps the later
    /// of the two timestamps, so the completion came back on the next sync.
    func clearSessionCompletion(sessionKey: String) async throws {
        _ = try await deleteRaw("/health/sessions/\(sessionKey)/completion")
    }

    // MARK: - Match suggestions

    /// Workouts the server-side importers (Garmin webhook, Apple Health relay)
    /// matched too weakly to confirm alone. Deciding the workout either way
    /// through `POST /health/matches` clears its suggestion.
    func fetchMatchSuggestions() async throws -> [MatchSuggestion] {
        let data = try await get("/health/matches/suggestions")
        return (try? JSONDecoder().decode([MatchSuggestion].self, from: data)) ?? []
    }

    /// Log ▸ Linking's day cards (`GET /health/linking`, `Linking.query`).
    func fetchLinking(today: String, dismissed: Set<String>) async throws -> LinkingDocument {
        let data = try await get("/health/linking?" + Linking.query(today: today, dismissed: dismissed))
        return try JSONDecoder().decode(LinkingDocument.self, from: data)
    }

    func dismissMatchSuggestion(workoutId: String) async throws {
        let encoded = workoutId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workoutId
        _ = try await deleteRaw("/health/matches/suggestions/\(encoded)")
    }

    // MARK: - Bio Logs

    func fetchRecentBioLogs() async throws -> [DailyBioLog] {
        let data = try await get("/health/bio/recent")
        do {
            let logs = try JSONDecoder().decode([DailyBioLog].self, from: data)
            AppLogger.logFromBackground("bio: fetched \(logs.count) recent logs")
            return logs
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "(nil)"
            AppLogger.logFromBackground("bio: decode FAILED — \(error) | raw: \(raw.prefix(200))")
            return []
        }
    }

    func fetchReadiness() async throws -> ReadinessResult {
        let data = try await get("/health/readiness")
        return try JSONDecoder().decode(ReadinessResult.self, from: data)
    }

    // MARK: - Progression

    /// Each exercise of the program with its history and prescription; `today`
    /// is the athlete's date, which decides what is "so far".
    func fetchExerciseHistory(today: String) async throws -> ExerciseHistoryResponse? {
        let data = try await get("/progression/exercises?today=\(today)")
        return try? JSONDecoder().decode(ExerciseHistoryResponse.self, from: data)
    }

    func fetchProgressionReview(period: String = "weekly") async throws -> ProgressionReview? {
        let data = try await get("/progression/review?period=\(period)")
        return try? JSONDecoder().decode(ProgressionReview.self, from: data)
    }

    // MARK: - Program Generation

    /// POSTs to /programs/generate. On success the server stores the program;
    /// call fetchProgram() afterwards to load the result into AppState.
    func generateProgram(_ request: GenerateProgramRequest) async throws {
        let body = try JSONEncoder().encode(request)
        _ = try await postRaw("/programs/generate", body: body)
    }

    /// Generate without persisting and hand the result back — the tail of a
    /// partial regenerate, which the caller splices onto the kept weeks and
    /// saves through the revision-checked PUT.
    func generateProgramPreview(_ request: GenerateProgramRequest) async throws -> GeneratedProgram {
        var preview = request
        preview.persist = false
        let body = try JSONEncoder().encode(preview)
        let data = try await postRaw("/programs/generate", body: body)
        return try JSONDecoder().decode(GeneratedProgram.self, from: data)
    }

    // MARK: - Workout file import

    /// Upload a .fit file through `POST /workouts/parse` — the same path the
    /// web uses. The server parses, dates the activity by the athlete's zone,
    /// folds duplicates from other sources into the row already there and runs
    /// the matcher; the on-device parser plus a raw Supabase upsert skipped
    /// all of that. Returns every activity the file held (a FIT file holds
    /// one). The server's async job accepts only Apple Health XML, so a FIT
    /// upload is always synchronous; the timeout covers a long GPS track.
    func uploadFITFile(data: Data, filename: String) async throws -> [ImportedWorkout] {
        let boundary = UUID().uuidString
        let url = URL(string: APIClient.baseURL + "/workouts/parse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = multipartBody(data: data, filename: filename, mimeType: "application/octet-stream", boundary: boundary)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverErrorDetail(http.statusCode, Self.detail(from: responseData) ?? "Upload failed")
        }
        return try JSONDecoder().decode([ImportedWorkout].self, from: responseData)
    }

    /// Link a recorded workout to a planned session. Deciding a workout this
    /// way also clears any suggestion the server had for it.
    func linkWorkout(workoutId: String, sessionKey: String) async throws {
        struct Body: Encodable {
            let importedWorkoutId: String
            let sessionKey: String
            let matchConfidence: String
            let matchedAt: String
        }
        let body = try JSONEncoder().encode(Body(importedWorkoutId: workoutId, sessionKey: sessionKey,
                                                 matchConfidence: "manual",
                                                 matchedAt: ISO8601DateFormatter().string(from: Date())))
        _ = try await postRaw("/health/matches", body: body)
    }

    // MARK: - Program analytics (the methodology scorecard, server-computed)

    /// How the athlete is doing against what the program is for. The server
    /// caches the document by program revision and log digest; `fresh` forces
    /// a recompute.
    func fetchProgramAnalytics(fresh: Bool = false) async throws -> ProgramAnalytics {
        let data = try await get(fresh ? "/analytics/program?fresh=1" : "/analytics/program")
        return try JSONDecoder().decode(ProgramAnalytics.self, from: data)
    }

    /// How the athlete has developed across programs — the history tables
    /// read as one document. Twelve months by default; `fresh` forces a
    /// recompute.
    func fetchDevelopmentAnalytics(fresh: Bool = false) async throws -> DevelopmentAnalytics {
        let data = try await get(fresh ? "/analytics/development?fresh=1" : "/analytics/development")
        return try JSONDecoder().decode(DevelopmentAnalytics.self, from: data)
    }

    // MARK: - Training load (server-computed, the same numbers the web shows)

    func fetchLoadPMC() async throws -> [ServerPMCEntry] {
        let data = try await get("/health/load/pmc")
        return try JSONDecoder().decode([ServerPMCEntry].self, from: data)
    }

    func fetchLoadWeekly() async throws -> [ServerWeeklyLoadEntry] {
        let data = try await get("/health/load/weekly")
        return try JSONDecoder().decode([ServerWeeklyLoadEntry].self, from: data)
    }

    /// `today` is the phone's own date — the server's is UTC.
    func fetchLoadSummary(period: AnalyticsPeriod, today: String) async throws -> LoadSummary {
        let data = try await get("/health/load/summary?period=\(LoadSummary.query(period))&today=\(today)")
        return try JSONDecoder().decode(LoadSummary.self, from: data)
    }

    // MARK: - Exercise reference

    /// The package's media for one exercise: demo, description, cues, errors.
    /// An exercise without media answers `{}`, which decodes to an empty entry.
    func fetchExerciseMedia(id: String) async throws -> ExerciseMedia? {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let data = try await get("/exercises/\(escaped)/media")
        let media = try JSONDecoder().decode(ExerciseMedia.self, from: data)
        return media.isEmpty ? nil : media
    }

    // MARK: - Program editing

    /// Ranked alternatives for one slot. 422 — nothing fits — is an empty
    /// list with the server's reason, not an error.
    func substituteExercise(_ request: SubstituteRequest) async throws -> [ExerciseAlternative] {
        let body = try JSONEncoder().encode(request)
        let (data, status) = try await postForStatus("/exercises/substitute", body: body)
        switch status {
        case 200..<300:
            return try JSONDecoder().decode(SubstituteResponse.self, from: data).alternatives
        case 422:
            return []
        default:
            throw APIError.serverErrorDetail(status, Self.detail(from: data) ?? "Could not find alternatives")
        }
    }

    /// Apply one of the review's adjustments to the stored weeks. 409 means
    /// the stored program moved on since this copy was read — the same
    /// contract as `saveProgram`.
    func applyAdjustment(_ request: AdjustRequest) async throws -> AdjustResult {
        let body = try JSONEncoder().encode(request)
        let (data, status) = try await postForStatus("/programs/adjust", body: body)
        switch status {
        case 200..<300:
            return try JSONDecoder().decode(AdjustResult.self, from: data)
        case 409:
            AppLogger.logFromBackground("program: adjust rejected (stale revision) — re-pulling")
            throw StaleProgramRevision()
        default:
            throw APIError.serverErrorDetail(status, Self.detail(from: data) ?? "Could not apply the adjustment")
        }
    }

    /// The `detail` string the API puts in an error body, when there is one.
    private static func detail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = json["detail"] as? String, !detail.isEmpty else { return nil }
        return detail
    }

    // MARK: - Workouts (the server's list, detail, matches and delete)

    /// What `GET /health/snapshot` carries that this app reads. Workouts are
    /// summaries — no track, no samples — the detail is fetched on demand.
    struct HealthSnapshot: Decodable {
        let workouts: [ImportedWorkout]
        let matches: [WorkoutMatchRecord]
        let performanceLogs: [String: [PerformanceEntry]]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // One malformed row must not blank the whole list.
            workouts = ((try? c.decodeIfPresent([Lossy<ImportedWorkout>].self, forKey: .workouts)) ?? [])?
                .compactMap(\.value) ?? []
            matches = ((try? c.decodeIfPresent([Lossy<WorkoutMatchRecord>].self, forKey: .matches)) ?? [])?
                .compactMap(\.value) ?? []
            performanceLogs = (try? c.decodeIfPresent([String: [PerformanceEntry]].self, forKey: .performanceLogs)) ?? [:]
        }

        private enum CodingKeys: String, CodingKey { case workouts, matches, performanceLogs }
    }

    /// The server's view of the athlete's recorded training. This app used to
    /// read `workouts` and `workout_matches` straight from PostgREST, with its
    /// own `canonical_id` filter and column-by-column decoding; the server
    /// list applies the dedup filter itself and speaks the same camelCase
    /// shape every other client reads.
    func fetchHealthSnapshot() async throws -> HealthSnapshot {
        let data = try await get("/health/snapshot")
        return try JSONDecoder().decode(HealthSnapshot.self, from: data)
    }

    /// Workout summaries — GPS track and HR samples are loaded on demand by
    /// `fetchWorkout(id:)`. Rows dedup folded into another source's copy are
    /// already hidden by the server.
    func fetchWorkouts() async throws -> [ImportedWorkout] {
        try await fetchHealthSnapshot().workouts
    }

    /// Workout → planned session, keyed by workout id; a rejected decision is
    /// not a match. Read from `workout_matches` (not inferred from session
    /// logs): the server-side matcher writes only that table, so an
    /// auto-matched workout has no log and would read as unmatched.
    func fetchWorkoutMatches() async throws -> [String: WorkoutMatch] {
        Self.matchesByWorkout(try await fetchHealthSnapshot().matches)
    }

    static func matchesByWorkout(_ records: [WorkoutMatchRecord]) -> [String: WorkoutMatch] {
        var result: [String: WorkoutMatch] = [:]
        for record in records {
            guard let match = record.asMatch else { continue }
            result[match.workoutId] = match
        }
        return result
    }

    /// The full workout: GPS track, HR samples, elevation.
    func fetchWorkout(id: String) async throws -> ImportedWorkout {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let data = try await get("/health/workouts/\(escaped)")
        return try JSONDecoder().decode(ImportedWorkout.self, from: data)
    }

    /// Delete a workout; the server removes its match with it.
    func deleteWorkout(id: String) async throws {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await deleteRaw("/health/workouts/\(escaped)")
    }

    /// Mark a session complete with workout HR data and link to imported workout.
    func saveSessionWithWorkout(
        sessionKey: String,
        completedAt: String,
        workoutId: String,
        avgHR: Int?,
        peakHR: Int?
    ) async throws {
        // Keys must be camelCase — upsert_session_log reads completedAt, avgHR, peakHR
        var log: [String: Any] = [
            "completedAt": completedAt,
            "source": "fit_file",
        ]
        if let avg = avgHR { log["avgHR"] = avg }
        if let peak = peakHR { log["peakHR"] = peak }
        guard let body = try? JSONSerialization.data(withJSONObject: log) else { return }
        _ = try await putRaw("/health/sessions/\(sessionKey)", body: body)
    }

    func generateSession(_ request: GenerateSessionRequest) async throws -> ProgramSession {
        return try await post("/sessions/generate", body: request)
    }

    /// Thrown when the server rejects a program write as based on a stale read.
    struct StaleProgramRevision: Error {}

    /// Returns the server's `phaseSummary` of the weeks just saved (nil from an
    /// older server), so the Overview shows what this edit changed.
    @discardableResult
    func saveProgram(_ payload: UserProgramSavePayload) async throws -> JSONValue? {
        let url = URL(string: APIClient.baseURL + "/user/program")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        // 409 means the stored program moved on since this copy was read — the
        // web generated something newer. Surface it so the caller re-pulls
        // instead of overwriting work it has never seen.
        if let http = response as? HTTPURLResponse, http.statusCode == 409 {
            AppLogger.logFromBackground("program: save rejected (stale revision) — re-pulling")
            throw StaleProgramRevision()
        }
        try validateStatus(response)
        struct Saved: Decodable { let phaseSummary: JSONValue? }
        return (try? JSONDecoder().decode(Saved.self, from: data))?.phaseSummary
    }

    // MARK: - Watch device pairing (Garmin / future companions)

    /// Bind a watch's 6-character pairing code to the signed-in account.
    func claimDevice(code: String) async throws {
        struct Body: Encodable { let code: String }
        let body = try JSONEncoder().encode(Body(code: code.trimmingCharacters(in: .whitespaces).uppercased()))
        do {
            _ = try await postRaw("/devices/claim", body: body)
        } catch APIError.serverError(404) {
            // Backend returns 404 {claimed:false} for an unknown/expired code.
            throw APIError.serverErrorDetail(404, "That code is invalid or has expired. Generate a new one on your watch.")
        }
    }

    /// The newest wellness reading a paired Connect IQ watch sent; nil before
    /// the first, or from a server without the route.
    func fetchLatestWellness() async -> WellnessReading? {
        struct Body: Decodable { let latest: WellnessReading? }
        guard let data = try? await get("/health/wellness/latest") else { return nil }
        return (try? JSONDecoder().decode(Body.self, from: data))?.latest
    }

    /// List devices already paired to the signed-in account (tokens are truncated by the server).
    func fetchDevices() async throws -> [PairedDevice] {
        let data = try await get("/devices")
        return (try? JSONDecoder().decode([PairedDevice].self, from: data)) ?? []
    }

    // MARK: - Account

    /// Deletes the account and everything stored for it (App Store 5.1.1(v)).
    /// The server removes the rows, then the Supabase user; the caller
    /// forgets the session afterwards.
    func deleteAccount() async throws {
        do {
            _ = try await deleteRaw("/account")
        } catch APIError.serverError(503) {
            throw APIError.serverErrorDetail(503, "Account deletion isn't available right now. Try again later.")
        }
    }

    // MARK: - Private

    private func multipartBody(data: Data, filename: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        let boundaryPrefix = "--\(boundary)\(crlf)"
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"workout_file\"; filename=\"\(filename)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(data)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        return body
    }

    private func get(_ path: String) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        try await addAuth(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        return data
    }

    private func deleteRaw(_ path: String) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        try await addAuth(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        return data
    }

    private func postRaw(_ path: String, body: Data) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        return data
    }

    /// Like `postRaw`, but returns the status instead of throwing on it, for
    /// endpoints whose non-2xx answers carry meaning (409 stale, 422 nothing fits).
    private func postForStatus(_ path: String, body: Data) async throws -> (Data, Int) {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func putRaw(_ path: String, body: Data) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        return data
    }

    private func post<T: Encodable, R: Decodable>(_ path: String, body: T) async throws -> R {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        guard let result = try? JSONDecoder().decode(R.self, from: data) else {
            throw APIError.decodingError
        }
        return result
    }

    private func put<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        return data
    }

    private func addAuth(to request: inout URLRequest) async throws {
        // The local server runs with Supabase unset and answers as
        // local-dev-user; a token would be ignored and there is none to send.
        if APITarget.isLocal { return }
        await auth.refreshIfNeeded()
        guard let token = auth.accessToken else { throw APIError.unauthenticated }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validateStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError(http.statusCode)
        }
    }
}
