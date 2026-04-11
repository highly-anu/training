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
            let completedAt: String
            let source: String
        }
        _ = try await put(
            "/health/sessions/\(sessionKey)",
            body: Body(completedAt: completedAt, source: "manual")
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

    // MARK: - Program Generation

    /// POSTs to /programs/generate. On success the server stores the program;
    /// call fetchProgram() afterwards to load the result into AppState.
    func generateProgram(_ request: GenerateProgramRequest) async throws {
        let body = try JSONEncoder().encode(request)
        _ = try await postRaw("/programs/generate", body: body)
    }

    // MARK: - Direct Supabase writes (bypasses Python backend for .fit import)

    private static let supabaseURL = AuthManager.supabaseURL
    private static let anonKey     = AuthManager.supabaseAnonKey

    /// Decode the user ID from the JWT `sub` claim.
    var userId: String? {
        guard let token = auth.accessToken else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1])
        b64 = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - b64.count % 4) % 4
        b64 += String(repeating: "=", count: pad)
        guard let d = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return json["sub"] as? String
    }

    /// Upsert a workout row directly to Supabase (no server round-trip).
    func saveWorkoutDirect(_ workout: ImportedWorkout) async throws {
        guard let uid = userId else { throw APIError.unauthenticated }

        var row: [String: Any] = [
            "id":            workout.id,
            "user_id":       uid,
            "source":        workout.source,
            "date":          workout.date,
            "activity_type": workout.activityType,
        ]
        if let s = workout.startTime {
            row["start_time"] = s
            if let d = workout.durationMinutes {
                let isoFmt = DateFormatter()
                isoFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
                isoFmt.timeZone = TimeZone(identifier: "UTC")
                if let startDate = isoFmt.date(from: s) {
                    let endDate = startDate.addingTimeInterval(d * 60)
                    row["end_time"] = isoFmt.string(from: endDate)
                }
            }
        }
        if let d = workout.durationMinutes    { row["duration_minutes"]     = Int(d.rounded()) }
        if let m = workout.inferredModalityId { row["inferred_modality_id"] = m }
        if let c = workout.calories           { row["calories"]             = Int(c) }
        if let hr = workout.heartRate {
            if let avg = hr.avg { row["hr_avg"] = avg }
            if let max = hr.max { row["hr_max"] = max }
            // jsonb column — send as array of objects, not a string
            if !hr.samples.isEmpty {
                row["hr_samples"] = hr.samples.map { ["timestamp": $0.timestamp, "bpm": $0.bpm] }
            }
        }
        if let dist = workout.distance {
            row["distance_value"] = dist.value
            row["distance_unit"]  = dist.unit
        }
        if let elev = workout.elevation {
            if let g = elev.gain { row["elevation_gain"] = Int(g.rounded()) }
            if let l = elev.loss { row["elevation_loss"] = Int(l.rounded()) }
        }
        if let gps = workout.gpsTrack {
            // jsonb column — send as array of objects, not a string
            row["gps_track"] = gps.map { pt -> [String: Any] in
                var d: [String: Any] = ["lat": pt.lat, "lng": pt.lng, "timestamp": pt.timestamp]
                if let a = pt.altitude { d["altitude"] = a }
                if let b = pt.bpm     { d["bpm"] = b }
                if let s = pt.speed   { d["speed"] = s }
                return d
            }
        }

        try await supabaseUpsert(table: "workouts", onConflict: "id,user_id", body: row)
    }

    /// Save match + mark session complete directly to Supabase.
    func saveMatchDirect(workout: ImportedWorkout, sessionKey: String) async throws {
        guard let uid = userId else { throw APIError.unauthenticated }

        let now = ISO8601DateFormatter().string(from: Date())
        let completedAt = workout.startTime ?? now

        // 1. workout_matches
        let matchRow: [String: Any] = [
            "imported_workout_id": workout.id,
            "user_id":             uid,
            "session_key":         sessionKey,
            "match_confidence":    1.0,
            "matched_at":          now,
        ]
        try await supabaseUpsert(table: "workout_matches",
                                 onConflict: "imported_workout_id,user_id", body: matchRow)

        // 2. session_logs — exercises is jsonb, send as object not string
        var logRow: [String: Any] = [
            "session_key":  sessionKey,
            "user_id":      uid,
            "completed_at": completedAt,
            "source":       "fit_file",
            "exercises":    [String: Any](),  // empty jsonb object
        ]
        if let avg = workout.heartRate?.avg { logRow["avg_hr"]  = avg }
        if let max = workout.heartRate?.max { logRow["peak_hr"] = max }
        try await supabaseUpsert(table: "session_logs",
                                 onConflict: "session_key,user_id", body: logRow)
    }

    /// Save a watch workout dict directly to Supabase (maps camelCase keys → snake_case columns).
    /// Called from WatchSessionManager so Flask doesn't need to be running.
    func saveWatchWorkoutDirect(_ w: [String: Any]) async throws {
        guard let uid = userId else { throw APIError.unauthenticated }
        var row: [String: Any] = [
            "id":            w["id"] as? String ?? "",
            "user_id":       uid,
            "source":        w["source"] as? String ?? "watch",
            "date":          w["date"] as? String ?? "",
            "activity_type": w["activityType"] as? String ?? "watch",
        ]
        if let m = w["inferredModalityId"] as? String { row["inferred_modality_id"] = m }
        if let s = w["startTime"]       as? String { row["start_time"]       = s }
        if let e = w["endTime"]         as? String { row["end_time"]         = e }
        if let d = w["durationMinutes"] as? Int        { row["duration_minutes"] = d }
        else if let d = w["durationMinutes"] as? Double { row["duration_minutes"] = Int(d.rounded()) }
        if let c = w["calories"]        as? Double { row["calories"]         = Int(c) }
        if let c = w["calories"]        as? Int    { row["calories"]         = c }
        if let hr = w["heartRate"] as? [String: Any] {
            if let avg     = hr["avg"]     as? Int  { row["hr_avg"] = avg }
            if let mx      = hr["max"]     as? Int  { row["hr_max"] = mx }
            if let samples = hr["samples"] as? [[String: Any]], !samples.isEmpty {
                row["hr_samples"] = samples
            }
        }
        if let dist = w["distance"] as? [String: Any] {
            if let v = dist["value"] as? Double { row["distance_value"] = v }
            if let u = dist["unit"]  as? String { row["distance_unit"]  = u }
        }
        if let elev = w["elevation"] as? [String: Any] {
            if let g = elev["gain"] as? Int { row["elevation_gain"] = g }
            if let l = elev["loss"] as? Int { row["elevation_loss"] = l }
        }
        if let gps = w["gpsTrack"] as? [[String: Any]], !gps.isEmpty {
            row["gps_track"] = gps
        }
        try await supabaseUpsert(table: "workouts", onConflict: "id,user_id", body: row)
    }

    /// Save a watch workout_match + session_log row directly to Supabase.
    func saveWatchMatchDirect(workoutId: String, sessionKey: String, startTime: String,
                               avgHR: Int?, peakHR: Int?, exercises: [String: Any]) async throws {
        guard let uid = userId else { throw APIError.unauthenticated }
        let now = ISO8601DateFormatter().string(from: Date())

        let matchRow: [String: Any] = [
            "imported_workout_id": workoutId,
            "user_id":             uid,
            "session_key":         sessionKey,
            "match_confidence":    1.0,
            "matched_at":          now,
        ]
        try await supabaseUpsert(table: "workout_matches",
                                 onConflict: "imported_workout_id,user_id", body: matchRow)

        var logRow: [String: Any] = [
            "session_key":  sessionKey,
            "user_id":      uid,
            "completed_at": startTime,
            "source":       "watch",
            "exercises":    exercises,
        ]
        if let avg  = avgHR  { logRow["avg_hr"]  = avg }
        if let peak = peakHR { logRow["peak_hr"] = peak }
        try await supabaseUpsert(table: "session_logs",
                                 onConflict: "session_key,user_id", body: logRow)
    }

    private func supabaseUpsert(table: String, onConflict: String, body: [String: Any]) async throws {
        let urlStr = "\(APIClient.supabaseURL)/rest/v1/\(table)?on_conflict=\(onConflict)"
        guard let url = URL(string: urlStr) else { throw APIError.decodingError }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(APIClient.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
        request.httpBody = bodyData
        print("⬆️ supabaseUpsert \(table) body:\n\(String(data: bodyData, encoding: .utf8) ?? "(nil)")")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
            print("❌ supabaseUpsert \(table) → \(http.statusCode): \(bodyStr)")
            throw APIError.serverErrorDetail(http.statusCode, bodyStr)
        }
    }

    // MARK: - FIT File Import

    /// Upload a .fit file via multipart POST /workouts/parse.
    /// Returns the first parsed workout (saved to DB by the server).
    func uploadFITFile(data: Data, filename: String) async throws -> ImportedWorkout {
        let boundary = UUID().uuidString
        let url = URL(string: APIClient.baseURL + "/workouts/parse")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try await addAuth(to: &request)
        request.httpBody = multipartBody(data: data, filename: filename, mimeType: "application/octet-stream", boundary: boundary)
        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validateStatus(response)
        let decoder = JSONDecoder()
        let workouts = try decoder.decode([ImportedWorkout].self, from: responseData)
        guard let first = workouts.first else { throw APIError.decodingError }
        return first
    }

    /// Fetch full workout details (GPS track + HR samples) directly from Supabase.
    func fetchWorkout(id: String) async throws -> ImportedWorkout {
        guard let uid = userId else { throw APIError.unauthenticated }
        let urlStr = "\(APIClient.supabaseURL)/rest/v1/workouts?id=eq.\(id)&user_id=eq.\(uid)&select=*"
        guard let url = URL(string: urlStr) else { throw APIError.decodingError }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        // Supabase returns an array even for single-row queries
        let rows = try JSONDecoder().decode([[String: SupabaseValue]].self, from: data)
        guard let row = rows.first else { throw APIError.decodingError }
        return try workoutFromSupabaseRow(row)
    }

    private enum SupabaseValue: Decodable {
        case string(String), int(Int), double(Double), bool(Bool)
        case array([[String: SupabaseValue]]), dict([String: SupabaseValue]), null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil()                               { self = .null; return }
            if let v = try? c.decode(Bool.self)            { self = .bool(v); return }
            if let v = try? c.decode(Int.self)             { self = .int(v); return }
            if let v = try? c.decode(Double.self)          { self = .double(v); return }
            if let v = try? c.decode(String.self)          { self = .string(v); return }
            if let v = try? c.decode([[String: SupabaseValue]].self) { self = .array(v); return }
            if let v = try? c.decode([String: SupabaseValue].self)   { self = .dict(v); return }
            self = .null
        }

        var stringValue: String?  { if case .string(let s) = self { return s }; return nil }
        var intValue:    Int?     { if case .int(let i) = self { return i }; if case .double(let d) = self { return Int(d) }; return nil }
        var doubleValue: Double?  { if case .double(let d) = self { return d }; if case .int(let i) = self { return Double(i) }; return nil }
        var dictValue:   [String: SupabaseValue]? { if case .dict(let d) = self { return d }; return nil }
        var arrayValue:  [[String: SupabaseValue]]? { if case .array(let a) = self { return a }; return nil }
    }

    /// Parse a SupabaseValue that may be either a native JSONB array or a JSON-encoded string.
    /// Supabase/Flask sometimes stores jsonb columns as text (stringified JSON), so we handle both.
    private func supabaseArray(_ val: SupabaseValue?) -> [[String: SupabaseValue]]? {
        if let arr = val?.arrayValue { return arr }
        guard let str = val?.stringValue,
              let data = str.data(using: .utf8),
              let arr = try? JSONDecoder().decode([[String: SupabaseValue]].self, from: data)
        else { return nil }
        return arr
    }

    private func workoutFromSupabaseRow(_ row: [String: SupabaseValue]) throws -> ImportedWorkout {
        guard let id   = row["id"]?.stringValue,
              let src  = row["source"]?.stringValue,
              let date = row["date"]?.stringValue,
              let type = row["activity_type"]?.stringValue
        else { throw APIError.decodingError }

        let hrAvg  = row["hr_avg"]?.intValue
        let hrMax  = row["hr_max"]?.intValue

        // hr_samples: may be a native JSONB array or a JSON-encoded string
        let hrSamples: [HRSample] = (supabaseArray(row["hr_samples"]) ?? []).compactMap { s in
            guard let ts = s["timestamp"]?.stringValue, let bpm = s["bpm"]?.intValue else { return nil }
            return HRSample(timestamp: ts, bpm: bpm)
        }

        // gps_track: may be a native JSONB array or a JSON-encoded string
        let gpsTrack: [GPSPoint]? = supabaseArray(row["gps_track"]).map { pts in
            pts.compactMap { p -> GPSPoint? in
                guard let lat = p["lat"]?.doubleValue, let lng = p["lng"]?.doubleValue,
                      let ts = p["timestamp"]?.stringValue else { return nil }
                return GPSPoint(lat: lat, lng: lng, altitude: p["altitude"]?.doubleValue,
                                timestamp: ts, bpm: p["bpm"]?.intValue,
                                speed: p["speed"]?.doubleValue)
            }
        }.flatMap { $0.isEmpty ? nil : $0 }

        let dist: WorkoutDistance? = {
            guard let v = row["distance_value"]?.doubleValue else { return nil }
            return WorkoutDistance(value: v, unit: row["distance_unit"]?.stringValue ?? "km")
        }()

        let elev: WorkoutElevation? = {
            let g = row["elevation_gain"]?.doubleValue
            let l = row["elevation_loss"]?.doubleValue
            guard g != nil || l != nil else { return nil }
            return WorkoutElevation(gain: g, loss: l)
        }()

        return ImportedWorkout(
            id: id,
            source: src,
            date: date,
            startTime: row["start_time"]?.stringValue,
            durationMinutes: row["duration_minutes"]?.doubleValue,
            activityType: type,
            inferredModalityId: row["inferred_modality_id"]?.stringValue,
            heartRate: WorkoutHRData(avg: hrAvg, max: hrMax, samples: hrSamples),
            calories: row["calories"]?.doubleValue,
            distance: dist,
            gpsTrack: gpsTrack,
            elevation: elev
        )
    }

    /// Fetch all workouts for the current user directly from Supabase.
    func fetchWorkouts() async throws -> [ImportedWorkout] {
        guard let uid = userId else { throw APIError.unauthenticated }
        // Fetch metadata only — GPS track and HR samples are loaded on demand in the detail sheet.
        // Fetching select=* for large GPS tracks causes payload timeouts that silently drop the list.
        let cols = "id,source,date,start_time,end_time,duration_minutes,activity_type,inferred_modality_id,hr_avg,hr_max,calories,distance_value,distance_unit,elevation_gain,elevation_loss"
        let urlStr = "\(APIClient.supabaseURL)/rest/v1/workouts?user_id=eq.\(uid)&select=\(cols)&order=date.desc,start_time.desc"
        guard let url = URL(string: urlStr) else { throw APIError.decodingError }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(APIClient.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        let rows = try JSONDecoder().decode([[String: SupabaseValue]].self, from: data)
        print("📋 fetchWorkouts: \(rows.count) rows from Supabase")
        let decoded = rows.compactMap { row -> ImportedWorkout? in
            do { return try workoutFromSupabaseRow(row) }
            catch { print("⚠️ workoutFromSupabaseRow dropped row \(row["id"]?.stringValue ?? "?"): \(error)"); return nil }
        }
        print("📋 fetchWorkouts: \(decoded.count) decoded successfully")
        return decoded
    }

    /// Delete a workout (and its match) directly from Supabase.
    func deleteWorkout(id: String) async throws {
        guard let uid = userId else { throw APIError.unauthenticated }
        // Delete match first (no cascade in all environments)
        let matchURL = "\(APIClient.supabaseURL)/rest/v1/workout_matches?imported_workout_id=eq.\(id)&user_id=eq.\(uid)"
        try await supabaseDelete(urlStr: matchURL)
        // Then delete the workout row
        let workoutURL = "\(APIClient.supabaseURL)/rest/v1/workouts?id=eq.\(id)&user_id=eq.\(uid)"
        try await supabaseDelete(urlStr: workoutURL)
        // Clear matched_workout_id on any session_log that references this workout
        let logPatch: [String: Any?] = ["matched_workout_id": nil]
        let patchURL = "\(APIClient.supabaseURL)/rest/v1/session_logs?matched_workout_id=eq.\(id)&user_id=eq.\(uid)"
        if let body = try? JSONSerialization.data(withJSONObject: logPatch) {
            var req = URLRequest(url: URL(string: patchURL)!)
            req.httpMethod = "PATCH"
            req.setValue(APIClient.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(auth.accessToken ?? "")", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    private func supabaseDelete(urlStr: String) async throws {
        guard let url = URL(string: urlStr) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(APIClient.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverErrorDetail(http.statusCode, body)
        }
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
