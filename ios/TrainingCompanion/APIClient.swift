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

    // MARK: - Private

    private func get(_ path: String) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        try addAuth(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        return data
    }

    private func postRaw(_ path: String, body: Data) async throws -> Data {
        let url = URL(string: APIClient.baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try addAuth(to: &request)
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
        try addAuth(to: &request)
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
        try addAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        return data
    }

    private func addAuth(to request: inout URLRequest) throws {
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
