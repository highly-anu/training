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
        AppLogger.shared.logFromBackground("program: decode failed — raw: \(snippet)")
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

    func fetchPerformanceLogs() async throws -> [String: [PerformanceEntry]] {
        try await fetchHealthSnapshot().performanceLogs
    }

    /// Logs a benchmark value — a PR, or the `bodyweight_kg` series the ×BW
    /// standards need. PRs used to be appended to `profile.performanceLogs`
    /// and sent with the profile, which the server's merge whitelist drops,
    /// so every PR entered on the phone vanished on the next snapshot load.
    /// This is the route the web app has always used.
    func addPerformanceEntry(benchmarkId: String, value: Double, loggedAt: String) async throws {
        struct Body: Encodable { let benchmarkId: String; let value: Double; let loggedAt: String }
        let body = try JSONEncoder().encode(Body(benchmarkId: benchmarkId, value: value, loggedAt: loggedAt))
        _ = try await postRaw("/health/performance", body: body)
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

    /// `sex` picks the standards table; the endpoint serves the male one otherwise.
    func fetchBenchmarks(sex: String? = nil) async throws -> [AppBenchmark] {
        var path = "/benchmarks"
        if let sex, sex == "male" || sex == "female" { path += "?sex=\(sex)" }
        let data = try await get(path)
        return (try? JSONDecoder().decode([AppBenchmark].self, from: data)) ?? []
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

    func saveSessionComplete(sessionKey: String, completedAt: String) async throws {
        struct Body: Encodable {
            let completedAt: String
            let source: String
        }
        _ = try await put(
            "/health/sessions/\(sessionKey)",
            body: Body(completedAt: completedAt, source: "manual")
        )
    }

    /// Log what was done for one exercise. The server merges `exercises` per
    /// key and keeps the completion, notes and fatigue it already has, so a
    /// log before "Mark Session Complete" is fine and so is one after.
    func saveExerciseLog(sessionKey: String, exerciseId: String,
                         performance: ExercisePerformanceLog) async throws {
        struct Body: Encodable {
            let exercises: [String: ExercisePerformanceLog]
            let source: String
        }
        let escaped = sessionKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionKey
        _ = try await put("/health/sessions/\(escaped)",
                          body: Body(exercises: [exerciseId: performance], source: "manual"))
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

    func dismissMatchSuggestion(workoutId: String) async throws {
        let encoded = workoutId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workoutId
        _ = try await deleteRaw("/health/matches/suggestions/\(encoded)")
    }

    // MARK: - Bio Logs

    func fetchRecentBioLogs() async throws -> [DailyBioLog] {
        let data = try await get("/health/bio/recent")
        do {
            let logs = try JSONDecoder().decode([DailyBioLog].self, from: data)
            AppLogger.shared.logFromBackground("bio: fetched \(logs.count) recent logs")
            return logs
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "(nil)"
            AppLogger.shared.logFromBackground("bio: decode FAILED — \(error) | raw: \(raw.prefix(200))")
            return []
        }
    }

    func fetchReadiness() async throws -> ReadinessResult {
        let data = try await get("/health/readiness")
        return try JSONDecoder().decode(ReadinessResult.self, from: data)
    }

    // MARK: - Progression

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
            AppLogger.shared.logFromBackground("program: adjust rejected (stale revision) — re-pulling")
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

    func saveProgram(_ payload: UserProgramSavePayload) async throws {
        let url = URL(string: APIClient.baseURL + "/user/program")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await URLSession.shared.data(for: request)
        // 409 means the stored program moved on since this copy was read — the
        // web generated something newer. Surface it so the caller re-pulls
        // instead of overwriting work it has never seen.
        if let http = response as? HTTPURLResponse, http.statusCode == 409 {
            AppLogger.shared.logFromBackground("program: save rejected (stale revision) — re-pulling")
            throw StaleProgramRevision()
        }
        try validateStatus(response)
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

    /// List devices already paired to the signed-in account (tokens are truncated by the server).
    func fetchDevices() async throws -> [PairedDevice] {
        let data = try await get("/devices")
        return (try? JSONDecoder().decode([PairedDevice].self, from: data)) ?? []
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
