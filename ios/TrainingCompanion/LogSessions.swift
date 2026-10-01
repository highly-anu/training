import Foundation

/// The cross-session list of what was logged — the Log tab's Sessions
/// section. Pure: rows are built from the session logs the server returned
/// and a lookup into the current program, so a test can pin the order and
/// the wording without a view.
struct LogSessionRow: Identifiable, Equatable {
    let key: String
    let title: String
    let subtitle: String
    /// One line per exercise with something logged ("Back Squat — 3 sets · 3×5 @ 80 kg").
    let lines: [String]
    let isComplete: Bool
    let completedAt: Date?
    /// Whether the session is in the current program and can be opened.
    let isLocatable: Bool
    var id: String { key }
}

enum LogSessions {

    /// The server writes `completed_at` as "2026-09-28 18:00:00+02:00"; the
    /// phone's own completions are ISO 8601 with a "T".
    static func parseServerDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: value) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: value) { return d }
        for pattern in ["yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = pattern
            if pattern == "yyyy-MM-dd HH:mm:ss" || pattern == "yyyy-MM-dd" { f.timeZone = TimeZone.current }
            if let d = f.date(from: value) { return d }
        }
        return nil
    }

    static func rows(logs: [SessionLogEntry],
                     locate: (String) -> AppState.LocatedSession?,
                     exerciseNames: [String: String] = [:],
                     now: Date = Date()) -> [LogSessionRow] {
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium
        dateFmt.timeStyle = .short
        let built: [LogSessionRow] = logs.compactMap { log in
            let logged = log.exercises.filter { !$0.value.isEmpty }
            let isComplete = log.completedAt != nil
            guard isComplete || !logged.isEmpty else { return nil }
            let located = locate(log.sessionKey)
            let session = located?.session
            let title = session.map { $0.archetype?.name ?? ModalityStyle.label(for: $0.modality) }
                ?? "Session \(log.sessionKey)"
            let date = parseServerDate(log.completedAt)
            var parts: [String] = []
            if let date { parts.append(dateFmt.string(from: date)) } else if !isComplete { parts.append("not completed") }
            if let source = log.source, !source.isEmpty, source != "web", source != "manual" {
                parts.append(source.replacingOccurrences(of: "_", with: " "))
            }
            if let day = located?.dayName { parts.append("week \(located!.weekIndex + 1) · \(day)") }
            let lines: [String] = logged.keys.sorted().compactMap { id in
                guard let perf = logged[id] else { return nil }
                let assignment = session?.exercises.first { $0.exercise?.id == id }
                let slotType = assignment.map(LoadFormat.resolvedSlotType)
                    ?? (perf.sets.isEmpty ? "time_domain" : "sets_reps")
                guard let summary = SessionLogging.summary(perf, slotType: slotType) else { return nil }
                let name = assignment?.exercise?.name ?? exerciseNames[id]
                    ?? id.replacingOccurrences(of: "_", with: " ").capitalized
                return "\(name) — \(summary)"
            }
            return LogSessionRow(key: log.sessionKey, title: title, subtitle: parts.joined(separator: " · "),
                                 lines: lines, isComplete: isComplete, completedAt: date, isLocatable: located != nil)
        }
        return built.sorted { a, b in
            switch (a.completedAt, b.completedAt) {
            case let (x?, y?): return x > y
            case (nil, nil): return a.key < b.key
            case (nil, _): return false
            case (_, nil): return true
            }
        }
    }
}
