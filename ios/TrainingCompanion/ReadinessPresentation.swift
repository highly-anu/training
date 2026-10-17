import SwiftUI

/// Colour and label helpers for the two readiness shapes: the Apple Watch's
/// payload (`ReadinessInfo`) and the API-computed score (`ReadinessResult`).
/// Lived in the dead LogView until it was removed.

// MARK: - ReadinessInfo (the Apple Watch's copy of the server score)

extension ReadinessInfo {
    static let storageKey = "lastServerReadiness"

    /// The server's score in the shape the watch decodes. The phone used to
    /// send its own HRV rule (≥ 50 ms green) here and show it on Recovery,
    /// beside — and often against — the score Today showed.
    init(server result: ReadinessResult, restingHR: Int?, hrv: Int?) {
        self.init(score: min(1, max(0, Double(result.score) / 100)),
                  signal: result.status, restingHR: restingHR, hrv: hrv)
    }

    /// Keep the last server score for `WatchSessionManager`, which has no
    /// `AppState` and may run from a background sync.
    static func storeForWatch(_ result: ReadinessResult) {
        let payload: [String: Any] = ["score": result.score, "status": result.status,
                                      "date": ISO8601DateFormatter().string(from: Date())]
        UserDefaults.standard.set(payload, forKey: storageKey)
    }

    /// The last server score with the latest raw readings, or nil when the
    /// phone has none from today — a stale score is worse than none.
    static func fromStoredServerScore(defaults: UserDefaults = .standard, now: Date = Date()) -> ReadinessInfo? {
        guard let stored = defaults.dictionary(forKey: storageKey),
              let score = stored["score"] as? Int,
              let status = stored["status"] as? String,
              let dateStr = stored["date"] as? String,
              let date = ISO8601DateFormatter().date(from: dateStr),
              Calendar.current.isDate(date, inSameDayAs: now) else { return nil }
        let hrv = (defaults.object(forKey: "lastHRV") as? Double).map { Int($0) }
        let rhr = (defaults.object(forKey: "lastRestingHR") as? Double).map { Int($0) }
        return ReadinessInfo(score: min(1, max(0, Double(score) / 100)),
                             signal: status, restingHR: rhr, hrv: hrv)
    }

    var signalColor: Color {
        switch signal {
        case "green":  return .green
        case "yellow": return .yellow
        default:       return .red
        }
    }
    var signalIcon: String {
        switch signal {
        case "green":  return "bolt.heart.fill"
        case "yellow": return "exclamationmark.heart.fill"
        default:       return "heart.slash.fill"
        }
    }
}

// MARK: - ReadinessResult display helpers (API-computed score)

extension ReadinessResult {
    var statusColor: Color {
        switch status {
        case "green":  return .green
        case "yellow": return .yellow
        default:       return .red
        }
    }
    var statusIcon: String {
        switch status {
        case "green":  return "bolt.heart.fill"
        case "yellow": return "exclamationmark.heart.fill"
        default:       return "heart.slash.fill"
        }
    }
    var statusLabel: String {
        switch status {
        case "green":  return "Ready"
        case "yellow": return "Moderate"
        default:       return "Low"
        }
    }

    /// One line naming where resting HR, HRV and sleep came from — the same
    /// words as the web's `lib/readiness.readinessSourceNote`. Resting HR
    /// comes from one series only, so the line says which one won; a score
    /// that moved because its source changed should not look like the
    /// athlete changed. Nil for an older server or an empty score.
    var sourceNote: String? {
        guard let sources else { return nil }
        let label = ["daily_bio": "Apple Health and check-ins",
                     "garmin_ciq": "your Garmin watch's heart-rate low",
                     "garmin_watch": "your Garmin watch"]
        var order: [String] = []
        var bySource: [String: [String]] = [:]
        for (name, source) in [("resting HR", sources.rhr), ("HRV", sources.hrv), ("sleep", sources.sleep),
                               ("Body Battery and recovery time", sources.recovery)] {
            guard let source, label[source] != nil else { continue }
            if bySource[source] == nil { order.append(source) }
            bySource[source, default: []].append(name)
        }
        guard !order.isEmpty else { return nil }
        func list(_ xs: [String]) -> String {
            xs.count > 1 ? xs.dropLast().joined(separator: ", ") + " and " + xs.last! : xs[0]
        }
        let text = order.map { "\(list(bySource[$0]!)) from \(label[$0]!)" }.joined(separator: "; ")
        return String(text.prefix(1)).uppercased() + String(text.dropFirst()) + "."
    }
}

/// The server's actionable flags (not `insufficient_data`) as short chips —
/// an icon and a few words each. Analytics ▸ Recovery only: Today's card
/// carries the score and the readings, not the reasons (design-system §6.21).
struct ReadinessFlagChips: View {
    let flags: [String]

    static func chip(_ key: String) -> (icon: String, label: String) {
        switch key {
        case "elevated_rhr_3d":          return ("heart.fill", "RHR up 3d")
        case "suppressed_hrv_3d":        return ("waveform.path.ecg", "HRV down 3d")
        case "high_accumulated_fatigue": return ("battery.25", "High fatigue")
        case "insufficient_sleep":       return ("moon.zzz", "< 5h sleep")
        case "poor_sleep_3d":            return ("moon.zzz", "Poor sleep 3n")
        case "overreached":              return ("chart.line.downtrend.xyaxis", "Overreached")
        case "recovery_pending":         return ("hourglass", "Recovery capped")
        default:                         return ("exclamationmark.triangle", key.replacingOccurrences(of: "_", with: " "))
        }
    }

    var body: some View {
        let shown = flags.filter { $0 != "insufficient_data" }
        if !shown.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shown, id: \.self) { key in
                        let chip = Self.chip(key)
                        TintCapsule(text: chip.label, symbol: chip.icon, color: .orange)
                    }
                }
            }
        }
    }
}

extension WellnessReading {
    /// "8 Oct, 07:20 · HR low 47 · 7-day resting HR 47 · Body Battery 75 ·
    /// recovery 82 h" — the web's `lib/wellness.wellnessSummary`, word for word.
    func summary(locale: Locale = Locale(identifier: "en_GB"),
                 timeZone: TimeZone = .current) -> String {
        var at = date
        let out = DateFormatter()
        out.locale = locale
        out.timeZone = timeZone
        if let readAt, let instant = ISO8601DateFormatter().date(from: readAt) {
            out.dateFormat = "d MMM, HH:mm"
            at = out.string(from: instant)
        } else {
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = timeZone
            day.dateFormat = "yyyy-MM-dd"
            if let d = day.date(from: date) {
                out.dateFormat = "d MMM"
                at = out.string(from: d)
            }
        }
        var parts = [at]
        if let hrMin { parts.append("HR low\u{00A0}\(hrMin)") }
        if let restingHR7dAvg { parts.append("7-day resting HR\u{00A0}\(restingHR7dAvg)") }
        if let bodyBatteryMax { parts.append("Body Battery\u{00A0}\(bodyBatteryMax)") }
        if let recoveryTimeH { parts.append("recovery\u{00A0}\(recoveryTimeH)\u{00A0}h") }
        return parts.joined(separator: " · ")
    }
}
