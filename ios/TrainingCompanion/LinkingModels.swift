import Foundation

/// Log ▸ Linking, as `GET /health/linking` lays it out: one card per day,
/// workouts beside the sessions planned that day — the current program's and
/// every earlier program's — with the links already made and same-day
/// suggestions. Built on the server (`src/linking.py`, the copy of the web's
/// `lib/linking.ts`) because the phone has no matcher of its own.
struct LinkingDocument: Decodable, Equatable {
    let today: String
    let programVersionId: String?
    let days: [LinkingDay]
}

struct LinkingDay: Decodable, Equatable, Identifiable {
    var id: String { date }
    let date: String
    /// The day belongs to a program that is no longer active.
    let historical: Bool
    let programVersionId: String?
    let programLabel: String?
    let links: [LinkPair]
    let suggestions: [LinkSuggestion]
    /// This day's workouts in neither a link nor a suggestion.
    let workouts: [LinkWorkout]
    /// This day's sessions in neither a link nor a suggestion.
    let sessions: [LinkSession]
    /// Workouts linked to a session the page has no row for.
    let elsewhere: [LinkElsewhere]
    /// Workouts the athlete said belong to no session.
    let declined: [LinkWorkout]
    /// An unlinked workout, or a suggestion, is waiting.
    let needsAttention: Bool
}

/// A recorded workout, summarised — the series stay on the server.
struct LinkWorkout: Decodable, Equatable, Identifiable {
    let id: String
    let date: String
    let startTime: String?
    let source: String?
    let activityType: String?
    let name: String?
    let durationMinutes: Double?
    let inferredModalityId: String?

    var title: String {
        if let name, !name.isEmpty { return name }
        if let activityType, !activityType.isEmpty {
            // Raw HealthKit / Garmin identifiers ("cross_country_skiing") read as words.
            guard activityType.contains("_") else { return activityType }
            let words = activityType.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
        return ModalityStyle.label(for: inferredModalityId ?? "")
    }
}

/// One planned session, of the current program or an earlier one.
struct LinkSession: Decodable, Equatable, Identifiable {
    var id: String { key }
    /// Unique on the page: the legacy key for the current program, the uid for an earlier one.
    let key: String
    /// "3-Monday-0" — what a match stores as `sessionKey`.
    let legacyKey: String?
    /// What a match stores as `sessionUid`; nil when the program is not archived yet.
    let uid: String?
    let date: String
    let modality: String?
    let name: String
    let durationMinutes: Double?
    let historical: Bool
    let programVersionId: String?
    let completedAt: String?
}

struct LinkPair: Decodable, Equatable, Identifiable {
    var id: String { workout.id }
    let workout: LinkWorkout
    let session: LinkSession
}

struct LinkSuggestion: Decodable, Equatable, Identifiable {
    var id: String { "\(workout.id)|\(session.key)" }
    let workout: LinkWorkout
    let session: LinkSession
    let score: Int
    /// From the server's importers rather than scored for this page.
    let fromPending: Bool
}

struct LinkElsewhere: Decodable, Equatable, Identifiable {
    var id: String { workout.id }
    let workout: LinkWorkout
    let sessionKey: String?
}

/// The phone's side of Linking, pure so it is tested without a server.
enum Linking {
    /// `"<workoutId>|<session key>"`, the web's `dismissKey`.
    static func dismissKey(workoutId: String, sessionKey: String) -> String {
        "\(workoutId)|\(sessionKey)"
    }

    /// The request: the athlete's own date (the server's is UTC) and the
    /// pairs waved away on this phone, sorted so the URL is stable.
    static func query(today: String, dismissed: Set<String>) -> String {
        var items = [URLQueryItem(name: "today", value: today)]
        items += dismissed.sorted().map { URLQueryItem(name: "dismissed", value: $0) }
        var c = URLComponents()
        c.queryItems = items
        // `|` is legal in a query but URL(string:) rejects it unescaped.
        return (c.percentEncodedQuery ?? "").replacingOccurrences(of: "|", with: "%7C")
    }

    /// The days the list shows: those waiting on the athlete, or all of them.
    static func visible(_ days: [LinkingDay], showAll: Bool) -> [LinkingDay] {
        showAll ? days : days.filter(\.needsAttention)
    }

    /// The `POST /health/matches` body for a link: the session's uid always
    /// when it has one — without it the server resolves the legacy key on the
    /// workout's own date, which finds nothing across days.
    static func linkPayload(workoutId: String, session: LinkSession, matchedAt: Date = Date()) -> [String: Any] {
        var body = WatchUpload.matchPayload(workoutId: workoutId,
                                            sessionKey: session.legacyKey ?? session.key,
                                            matchedAt: matchedAt)
        if let uid = session.uid { body["sessionUid"] = uid }
        return body
    }

    /// Unlinking records a decision, as the web does: a rejected match with no session.
    static func unlinkPayload(workoutId: String, matchedAt: Date = Date()) -> [String: Any] {
        [
            "importedWorkoutId": workoutId,
            "sessionKey":        "",
            "matchConfidence":   "rejected",
            "matchedAt":         ISO8601DateFormatter().string(from: matchedAt),
        ]
    }
}
