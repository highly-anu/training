import Foundation

/// The words of the Apple Watch's Today list, the Garmin's (ActivityMenu.mc,
/// SessionListView.mc, SyncManager.mc) line for line: the Week, Progress and
/// Sync rows, the week's days, tomorrow on a rest day. Pure, and compiled
/// into the app and the watch so TrainingCompanionTests reads them.
enum WatchListText {

    // MARK: - Progress

    /// The Progress row's second line: "3/5 this week · 29%".
    static func progressLine(_ p: WatchProgress) -> String {
        var parts: [String] = []
        if p.week.sessions > 0 { parts.append("\(p.week.done)/\(p.week.sessions) this week") }
        if let pct = p.program?.pct { parts.append("\(pct)%") }
        return parts.joined(separator: " · ")
    }

    /// The Progress page, a label over its value per row:
    /// This week · 3 of 5 done · 4 due; Programme · 2 of 7 done · 29%; the
    /// methodology's measure and its sentence; Trend.
    static func progressRows(_ p: WatchProgress) -> [(label: String, value: String)] {
        var rows: [(String, String)] = [
            ("This week", "\(p.week.done) of \(p.week.sessions) done · \(p.week.due) due"),
        ]
        if let pr = p.program, pr.due > 0 {
            rows.append(("Programme", "\(pr.done) of \(pr.due) done" + (pr.pct.map { " · \($0)%" } ?? "")))
        }
        if let h = p.headline, let label = h.label {
            rows.append((label, h.text ?? "Not measured yet"))
            if let trend = h.trendText { rows.append(("Trend", trend)) }
        }
        return rows
    }

    // MARK: - The week

    /// "Week 3  Build", from the day's week number and phase; "Week" when
    /// the day says neither.
    static func weekTitle(_ day: WatchDay?) -> String {
        guard let n = day?.weekNumber else { return "Week" }
        guard let phase = day?.phase, !phase.isEmpty else { return "Week \(n)" }
        return "Week \(n)  " + phase.prefix(1).uppercased() + phase.dropFirst()
    }

    /// "Today", else the weekday and the day of the month: "Tue 20".
    static func dayName(_ d: WatchDayAhead) -> String {
        if d.offset == 0 { return "Today" }
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        parse.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parse.date(from: d.date) else { return d.date }
        let show = DateFormatter()
        show.locale = Locale(identifier: "en_US_POSIX")
        show.dateFormat = "EEE d"
        return show.string(from: date)
    }

    /// A day's row in the Week list: "Strength A +1  95 min", or "Rest day".
    static func dayLine(_ d: WatchDayAhead) -> String {
        guard !d.sessions.isEmpty else { return "Rest day" }
        return "\(d.title)  \(d.sessions.reduce(0) { $0 + $1.estimatedMinutes }) min"
    }

    /// A session's row in a day: "45 min  5 exercises".
    static func sessionLine(_ s: WatchSession) -> String {
        let n = s.exercises.count
        return "\(s.estimatedMinutes) min  \(n) exercise\(n == 1 ? "" : "s")"
    }

    /// Tomorrow, under a rest day: "Strength A  60 min", "Rest", or nil when
    /// the program ends today.
    static func tomorrowLine(_ t: WatchTomorrow?) -> String? {
        guard let t else { return nil }
        guard t.sessionCount > 0, let name = t.archetypeName else { return "Rest" }
        return "\(name)  \(t.estimatedMinutes ?? 45) min" + (t.sessionCount > 1 ? " +\(t.sessionCount - 1)" : "")
    }

    // MARK: - Sync

    /// The last sync, in words: "ok 07:41", or "failed 07:41 · No phone";
    /// nil before the first.
    static func syncLine(ok: Bool, at: Date?, reason: String?) -> String? {
        guard let at else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let hm = f.string(from: at)
        return ok ? "ok \(hm)" : "failed \(hm)" + (reason.map { " · \($0)" } ?? "")
    }
}
