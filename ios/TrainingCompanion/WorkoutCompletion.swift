import Foundation

/// The "Workout complete" moment (design-system §6.30): which newly stored
/// workout the phone celebrates, what it can be linked to, and the line that
/// cheers it. Pure, so every choice is tested without a screen
/// (`WorkoutCompletionTests`); `AppState` holds the seen set and the
/// presented workout, `WorkoutCompleteSheet` lays it out.
enum WorkoutCompletion {
    /// A workout that ended longer ago than this is history, not a moment —
    /// it is linked from Log ▸ Linking instead. A day and a half covers an
    /// evening session first synced the next morning.
    static let maxAge: TimeInterval = 36 * 3600

    /// What the workout is, or could be, linked to.
    enum Match: Equatable {
        /// Already linked — by the server's matcher on import, the watch, or
        /// another client. `session` is nil when the key is not in the loaded
        /// program (a match dated to an earlier block).
        case linked(key: String, session: ProgramSession?)
        /// The server's weak match, waiting for the athlete's word; the other
        /// sessions still open that day are offered beside it.
        case suggested(key: String, session: ProgramSession?, others: [Candidate])
        /// No suggestion, but sessions planned that day are still open.
        case candidates([Candidate])
        /// Nothing planned and open on the day: extra work.
        case unplanned

        static func == (lhs: Match, rhs: Match) -> Bool {
            switch (lhs, rhs) {
            case let (.linked(a, _), .linked(b, _)): return a == b
            case let (.suggested(a, _, x), .suggested(b, _, y)): return a == b && x == y
            case let (.candidates(x), .candidates(y)): return x == y
            case (.unplanned, .unplanned): return true
            default: return false
            }
        }
    }

    /// A planned session the workout could be linked to.
    struct Candidate: Equatable, Identifiable {
        let key: String
        let session: ProgramSession
        var id: String { key }

        static func == (lhs: Candidate, rhs: Candidate) -> Bool { lhs.key == rhs.key }
    }

    // MARK: - Which workout

    /// When the workout ended: its end time, else start + duration, else the
    /// end of its day (a record with neither still belongs to that day).
    static func endDate(of workout: ImportedWorkout, calendar: Calendar = .current) -> Date? {
        if let end = parseInstant(workout.endTime) { return end }
        if let start = parseInstant(workout.startTime) {
            return start.addingTimeInterval((workout.durationMinutes ?? 0) * 60)
        }
        // The date is the athlete's day: read it in the calendar's zone.
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let day = f.date(from: workout.date) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
    }

    /// The workout to celebrate: the most recently finished one the phone
    /// has not shown, recorded something, and ended within `maxAge` of `now`.
    /// Several new at once (a morning sync after two sessions) show only the
    /// newest; the rest are marked seen with it and wait in Log ▸ Linking.
    static func next(in workouts: [ImportedWorkout], seen: Set<String>,
                     now: Date = Date()) -> ImportedWorkout? {
        workouts
            .filter { !seen.contains($0.id) && recordedSomething($0) }
            .compactMap { w -> (ImportedWorkout, Date)? in
                guard let end = endDate(of: w) else { return nil }
                // An end ahead of now is today's (a date-only record ends at
                // midnight) or a watch's clock running fast: still a moment.
                guard now.timeIntervalSince(end) <= maxAge else { return nil }
                return (w, end)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// A started-and-abandoned watch session records nothing worth a cheer.
    static func recordedSomething(_ workout: ImportedWorkout) -> Bool {
        (workout.durationMinutes ?? 0) >= 1
            || workout.distance?.isMeaningful == true
            || workout.heartRate?.avg != nil
    }

    // MARK: - What it links to

    /// Linked first, then the server's suggestion, then the day's open
    /// sessions. `sameDay` is the current program's sessions on the
    /// workout's date in order; `isComplete` says which are already done.
    static func match(matchedKey: String?, suggestionKey: String?,
                      sameDay: [Candidate], isComplete: (String) -> Bool,
                      session: (String) -> ProgramSession?) -> Match {
        if let key = matchedKey, !key.isEmpty {
            return .linked(key: key, session: session(key))
        }
        let open = sameDay.filter { !isComplete($0.key) }
        if let key = suggestionKey {
            return .suggested(key: key, session: session(key),
                              others: open.filter { $0.key != key })
        }
        return open.isEmpty ? .unplanned : .candidates(open)
    }

    // MARK: - The cheer

    /// One line under the title. Chosen from the situation — on plan, a long
    /// day, a week finished, extra work — and, within it, by a hash of the
    /// workout's id, so one workout always reads the same while a run of
    /// workouts does not repeat itself.
    static func cheer(for workout: ImportedWorkout, linked: Bool, planned: Bool,
                      weekDone: Int, weekTotal: Int) -> String {
        let lines: [String]
        if linked, weekTotal > 0, weekDone >= weekTotal {
            lines = ["Every session this week — done.",
                     "Week complete. That's how it's built.",
                     "The whole week, in the bank."]
        } else if (workout.durationMinutes ?? 0) >= 90 {
            lines = ["Big day. Eat well and sleep long.",
                     "A long one, finished. Recovery starts now.",
                     "That's real volume. Well earned."]
        } else if linked {
            lines = ["Right on plan.",
                     "One more session in the bank.",
                     "That's the plan, done.",
                     "Consistency is the whole game. Nice work."]
        } else if planned {
            lines = ["Nice work. Link it to the plan to count it.",
                     "Good session. Does it match the plan?"]
        } else {
            lines = ["Extra work counts too.",
                     "Off-plan, still on purpose. Good job.",
                     "Every session adds up."]
        }
        return lines[stableIndex(workout.id, count: lines.count)]
    }

    /// `String.hashValue` is seeded per launch; this is not.
    static func stableIndex(_ s: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = s.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return sum % count
    }

    // MARK: - The week

    /// The program week's sessions in day order, each with whether it is done
    /// — the row of dots under the match.
    struct WeekDot: Equatable, Identifiable {
        let key: String
        let modality: String
        let done: Bool
        var id: String { key }
    }

    static let dayOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func weekDots(_ week: ProgramWeek, isComplete: (String) -> Bool) -> [WeekDot] {
        dayOrder.flatMap { day in
            (week.schedule[day] ?? []).enumerated().map { i, s in
                let key = "\(week.weekNumber)-\(day)-\(i)"
                return WeekDot(key: key, modality: s.modality, done: isComplete(key))
            }
        }
    }

    // MARK: - Parsing

    /// ISO 8601 with or without fractional seconds, and with a space for the
    /// `T` — the snapshot sends Postgres's own text, "2026-10-17 08:10:00+02:00".
    static func parseInstant(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.count > 10 && raw[raw.index(raw.startIndex, offsetBy: 10)] == " "
            ? raw.replacingCharacters(in: raw.index(raw.startIndex, offsetBy: 10)...raw.index(raw.startIndex, offsetBy: 10), with: "T")
            : raw
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
