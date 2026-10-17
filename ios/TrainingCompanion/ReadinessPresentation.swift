import SwiftUI

/// Colour and label helpers for the API-computed readiness (`ReadinessResult`).
/// Lived in the dead LogView until it was removed. The Apple Watch reads the
/// server's readiness from its day (`WatchDay.readiness`); the phone no
/// longer keeps a copy for it.

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
                        Label(chip.label, systemImage: chip.icon)
                            .font(.caption2).fontWeight(.medium)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

/// The readiness source footnote in Analytics ▸ Recovery (design-system
/// §6.21). Renders nothing when the server did not say. Today shows none.
struct ReadinessSourceNote: View {
    let result: ReadinessResult

    var body: some View {
        if let note = result.sourceNote {
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
