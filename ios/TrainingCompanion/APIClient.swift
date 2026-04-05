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
    let source: String = "apple_watch"
}

enum APIError: LocalizedError {
    case unauthenticated
    case serverError(Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .unauthenticated:     return "Not signed in."
        case .serverError(let c):  return "Server error \(c)."
        case .decodingError:       return "Failed to decode response."
        }
    }
}

final class APIClient {
    // Loaded from Info.plist (set at build time)
    private static let baseURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        ?? "https://training-api.fly.dev/api"

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

    func fetchProgram() async throws -> ServerProgram? {
        let data = try await get("/user/program")
        return try? JSONDecoder().decode(ServerProgram.self, from: data)
    }

    func saveWorkoutLog(sessionKey: String, log: [String: Any]) async throws {
        guard let body = try? JSONSerialization.data(withJSONObject: log) else { return }
        _ = try await putRaw("/health/sessions/\(sessionKey)", body: body)
    }

    func saveWatchWorkouts(_ workouts: [[String: Any]]) async throws {
        guard let body = try? JSONSerialization.data(withJSONObject: ["workouts": workouts]) else { return }
        _ = try await postRaw("/health/workouts", body: body)
    }

    func saveWorkoutMatch(_ match: [String: Any]) async throws {
        guard let body = try? JSONSerialization.data(withJSONObject: match) else { return }
        _ = try await postRaw("/health/matches", body: body)
    }

    // MARK: - User Profile

    func fetchUserProfile() async throws -> UserProfile {
        let data = try await get("/userdata/profile")
        let decoder = JSONDecoder()
        return try decoder.decode(UserProfile.self, from: data)
    }

    func saveUserProfile(_ profile: UserProfile) async throws {
        _ = try await put("/userdata/profile", body: profile)
    }

    // MARK: - Goals / Catalog

    func fetchGoals() async throws -> [GoalProfile] {
        let data = try await get("/goals")
        return (try? JSONDecoder().decode([GoalProfile].self, from: data)) ?? []
    }

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

    func fetchBenchmarks() async throws -> [AppBenchmark] {
        let data = try await get("/benchmarks")
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
            let sessionKey: String
            let completedAt: String
            let source: String
            enum CodingKeys: String, CodingKey {
                case sessionKey = "session_key"
                case completedAt = "completed_at"
                case source
            }
        }
        _ = try await put(
            "/health/sessions/\(sessionKey)",
            body: Body(sessionKey: sessionKey, completedAt: completedAt, source: "manual")
        )
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

    // MARK: - Bio Logs

    func fetchRecentBioLogs() async throws -> [DailyBioLog] {
        let data = try await get("/health/bio/recent")
        return (try? JSONDecoder().decode([DailyBioLog].self, from: data)) ?? []
    }

    // MARK: - Program Generation

    /// POSTs to /programs/generate. On success the server stores the program;
    /// call fetchProgram() afterwards to load the result into AppState.
    func generateProgram(_ request: GenerateProgramRequest) async throws {
        let body = try JSONEncoder().encode(request)
        _ = try await postRaw("/programs/generate", body: body)
    }

    // MARK: - Private

    private func get(_ path: String) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
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
