import Foundation

/// Log ▸ Linking, as `GET /health/linking` lays it out: one card per day,
/// workouts beside the sessions planned that day — the current program's and
/// every earlier program's — with the links already made and same-day
/// suggestions. Built on the server (`src/linking.py`, the copy of the web's
/// `lib/linking.ts`) because the phone has no matcher of its own.
struct LinkingDocument: Decodable, Equatable {
    let today: String
    let programVersionId: String?
    var days: [LinkingDay]
}

struct LinkingDay: Decodable, Equatable, Identifiable {
    var id: String { date }
    let date: String
    /// The day belongs to a program that is no longer active.
    let historical: Bool
    let programVersionId: String?
    let programLabel: String?
    var links: [LinkPair]
    var suggestions: [LinkSuggestion]
    /// This day's workouts in neither a link nor a suggestion.
    var workouts: [LinkWorkout]
    /// This day's sessions in neither a link nor a suggestion.
    var sessions: [LinkSession]
    /// Workouts linked to a session the page has no row for.
    var elsewhere: [LinkElsewhere]
    /// Workouts the athlete said belong to no session.
    var declined: [LinkWorkout]
    /// An unlinked workout, or a suggestion, is waiting.
    var needsAttention: Bool
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
            // As every other list names it ("Running", "Cross Country Skiing");
            // until 1.39 this screen alone read "running".
            return ImportedWorkout.activityLabel(activityType)
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
    /// Its workout icon (src/session_icon.py), for both lines of a pair.
    var icon: String? = nil
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
    /// One planned session of a day with its recording, if it has one.
    struct SessionRow: Equatable, Identifiable {
        /// A session holding two recordings is a row for each.
        var id: String { linked.map { "\(session.key)|\($0.id)" } ?? session.key }
        let session: LinkSession
        let linked: LinkWorkout?
        let suggested: LinkWorkout?
    }

    /// A workout offered for a session, with why it is not simply free.
    struct Candidate: Equatable, Identifiable {
        var id: String { workout.id }
        let workout: LinkWorkout
        let note: String?
    }

    struct Candidates: Equatable {
        let sameDay: [Candidate]
        let otherDays: [Candidate]
        var isEmpty: Bool { sameDay.isEmpty && otherDays.isEmpty }
    }

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

    /// The days the list shows: only days with a planned session, since the
    /// screen's job is to give a session its recording — those with something
    /// to link, or all of them. A workout on a day with no session is reached
    /// from a session's picker (`candidates`).
    static func visible(_ days: [LinkingDay], showAll: Bool) -> [LinkingDay] {
        days.filter { !rows(for: $0).isEmpty && (showAll || toLink($0)) }
    }

    /// A day waits on the athlete: a suggestion to answer, or a session still
    /// open on a day a workout was recorded.
    static func toLink(_ day: LinkingDay) -> Bool {
        !day.suggestions.isEmpty || (!day.sessions.isEmpty && !day.workouts.isEmpty)
    }

    /// A day's sessions, each with the workout linked to it or suggested for
    /// it: what waits for an answer first, then the open ones, then the linked.
    /// A pair made across days shows on the session's day only.
    static func rows(for day: LinkingDay) -> [SessionRow] {
        var seen = Set<String>()
        var out: [SessionRow] = []
        for s in day.suggestions where seen.insert(s.session.key).inserted {
            out.append(SessionRow(session: s.session, linked: nil, suggested: s.workout))
        }
        for s in day.sessions where seen.insert(s.key).inserted {
            out.append(SessionRow(session: s, linked: nil, suggested: nil))
        }
        for p in day.links where p.session.date == day.date {
            out.append(SessionRow(session: p.session, linked: p.workout, suggested: nil))
        }
        return out
    }

    /// The workouts a session may be linked to by hand: every other workout
    /// of its own day (one linked elsewhere says so), then the unlinked ones
    /// of the week either side, nearest day first.
    static func candidates(_ doc: LinkingDocument, for row: SessionRow) -> Candidates {
        var same: [Candidate] = []
        var other: [(Int, Candidate)] = []
        for d in doc.days {
            var free = d.suggestions.map(\.workout).map { Candidate(workout: $0, note: nil) }
            free += d.workouts.map { Candidate(workout: $0, note: nil) }
            free += d.declined.map { Candidate(workout: $0, note: "Set aside") }
            if d.date == row.session.date {
                same += free
                same += d.links.filter { $0.session.key != row.session.key }
                    .map { Candidate(workout: $0.workout, note: "Linked to \($0.session.name)") }
                same += d.elsewhere.map { Candidate(workout: $0.workout, note: "Linked to another session") }
            } else if let gap = dayGap(d.date, row.session.date), gap <= 7 {
                other += free.map { (gap, $0) }
            }
        }
        var seen: Set<String> = row.linked.map { [$0.id] } ?? []
        let unique = { (c: Candidate) in seen.insert(c.workout.id).inserted }
        let sameDay = same.filter(unique)
        let nearby = other.sorted { $0.0 < $1.0 }.map(\.1).filter(unique)
        return Candidates(sameDay: sameDay, otherDays: nearby)
    }

    private static func dayGap(_ a: String, _ b: String) -> Int? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let x = f.date(from: a), let y = f.date(from: b) else { return nil }
        return abs(Int((x.timeIntervalSince(y) / 86_400).rounded()))
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

    // MARK: - Applied on the phone at once

    /// A tap shows at once; the server's reload, which takes a couple of
    /// seconds, then replaces the document. Each mirrors what
    /// `src/linking.py` would lay out after the write.

    /// The workout is linked: it leaves every suggestion and unlinked list,
    /// the session leaves its day's, and the pair shows on the workout's day
    /// and, across days, on the session's too.
    static func applyingLink(_ doc: LinkingDocument, workoutId: String, session: LinkSession) -> LinkingDocument {
        guard let workout = findWorkout(doc, id: workoutId) else { return doc }
        let pair = LinkPair(workout: workout, session: session)
        var out = doc
        for i in out.days.indices {
            var d = out.days[i]
            // A suggestion that loses its workout or its session frees the other half.
            for s in d.suggestions where (s.workout.id == workoutId) != (s.session.key == session.key) {
                if s.workout.id != workoutId { d.workouts.append(s.workout) }
                if s.session.key != session.key { d.sessions.append(s.session) }
            }
            d.suggestions.removeAll { $0.workout.id == workoutId || $0.session.key == session.key }
            d.workouts.removeAll { $0.id == workoutId }
            d.declined.removeAll { $0.id == workoutId }
            d.elsewhere.removeAll { $0.workout.id == workoutId }
            d.links.removeAll { $0.workout.id == workoutId }
            // Another workout the session held is set aside, as an unlink leaves it.
            for old in d.links where old.session.key == session.key {
                if d.date == old.workout.date, !d.declined.contains(where: { $0.id == old.workout.id }) {
                    d.declined.append(old.workout)
                }
            }
            d.links.removeAll { $0.session.key == session.key }
            d.sessions.removeAll { $0.key == session.key }
            if d.date == workout.date || d.date == session.date { d.links.append(pair) }
            d.needsAttention = !d.suggestions.isEmpty || !d.workouts.isEmpty
            out.days[i] = d
        }
        return out
    }

    /// "Not this": the pair is no longer offered; both halves are left unlinked.
    static func applyingDismiss(_ doc: LinkingDocument, workoutId: String, sessionKey: String) -> LinkingDocument {
        var out = doc
        for i in out.days.indices {
            var d = out.days[i]
            guard let s = d.suggestions.first(where: { $0.workout.id == workoutId && $0.session.key == sessionKey })
            else { continue }
            d.suggestions.removeAll { $0.id == s.id }
            d.workouts.append(s.workout)
            d.sessions.append(s.session)
            d.needsAttention = true
            out.days[i] = d
        }
        return out
    }

    /// Unlinked: the workout belongs to no session, the session is open again.
    static func applyingUnlink(_ doc: LinkingDocument, workoutId: String) -> LinkingDocument {
        var out = doc
        let pairs = doc.days.flatMap(\.links).filter { $0.workout.id == workoutId }
        guard let pair = pairs.first else { return doc }
        for i in out.days.indices {
            var d = out.days[i]
            d.links.removeAll { $0.workout.id == workoutId }
            if d.date == pair.workout.date { d.declined.append(pair.workout) }
            if d.date == pair.session.date, !d.sessions.contains(where: { $0.key == pair.session.key }) {
                d.sessions.append(pair.session)
            }
            d.needsAttention = !d.suggestions.isEmpty || !d.workouts.isEmpty
            out.days[i] = d
        }
        return out
    }

    private static func findWorkout(_ doc: LinkingDocument, id: String) -> LinkWorkout? {
        for d in doc.days {
            if let w = d.workouts.first(where: { $0.id == id })
                ?? d.suggestions.first(where: { $0.workout.id == id })?.workout
                ?? d.declined.first(where: { $0.id == id })
                ?? d.elsewhere.first(where: { $0.workout.id == id })?.workout
                ?? d.links.first(where: { $0.workout.id == id })?.workout { return w }
        }
        return nil
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
