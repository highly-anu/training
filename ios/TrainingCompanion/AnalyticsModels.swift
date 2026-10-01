import SwiftUI

// MARK: - HR / Zone Types

struct HRZoneDistribution {
    var z1: Double
    var z2: Double
    var z3: Double
    var z4: Double
    var z5: Double
    var method: String  // "samples" | "summary_estimate"
}

struct HRZoneMinutes {
    var z1: Double
    var z2: Double
    var z3: Double
    var z4: Double
    var z5: Double
}

struct DecouplingResult {
    var pct: Double
    var label: String   // "efficient" | "moderate" | "high"
    var color: Color
}

// MARK: - PMC / Load

struct PMCEntry: Identifiable {
    var id: Date { date }
    var date: Date
    var ctl: Double
    var atl: Double
    var tsb: Double
    var trimp: Double
}

struct WeeklyLoadEntry: Identifiable {
    var id: String { week }
    var week: String        // "MMM d"
    var trimp: Double
    var sessions: Double
}

// MARK: - Server-computed load (GET /api/health/load/pmc, /weekly)

/// One day of the server's Performance Management Chart. The web reads the
/// same endpoint, so phone and web agree on fitness, fatigue and form; the
/// on-device `AnalyticsEngine.computePMC` is the offline fallback.
struct ServerPMCEntry: Decodable, Equatable {
    let date: String      // "yyyy-MM-dd"
    let ctl: Double
    let atl: Double
    let tsb: Double
    let trimp: Double

    /// Local midnight of `date`, for the chart's day axis.
    func pmcEntry(calendar: Calendar = .current) -> PMCEntry? {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return nil }
        return PMCEntry(date: d, ctl: ctl, atl: atl, tsb: tsb, trimp: trimp)
    }
}

/// One ISO week of TRIMP and session count, "2026-W35".
struct ServerWeeklyLoadEntry: Decodable, Equatable, Identifiable {
    let week: String
    let trimp: Double
    let sessions: Int

    var id: String { week }

    /// The Monday the ISO week key names, or nil for a malformed key.
    var weekStart: Date? {
        let parts = week.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]),
              parts[1].hasPrefix("W"), let number = Int(parts[1].dropFirst()) else { return nil }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = number
        comps.weekday = 2
        return cal.date(from: comps)
    }
}

// Garmin-style: Z1+Z2 = Base, Z3 = Threshold, Z4+Z5 = Anaerobic
struct TrainingLoadFocus {
    var baseMinutes: Double
    var thresholdMinutes: Double
    var anaerobicMinutes: Double

    var total: Double { baseMinutes + thresholdMinutes + anaerobicMinutes }
}

// MARK: - Period Stats

struct WorkoutPeriodStats {
    var sessions: Double
    var totalMinutes: Double
    var totalDistanceKm: Double
    var totalElevationGainM: Double
    var totalCalories: Double
    // Prior same-length period (for trend arrows)
    var prevSessions: Double
    var prevMinutes: Double
    var prevDistanceKm: Double
}

// MARK: - Chart Breakdown Types

struct ModalityShare: Identifiable {
    var id: String { modalityId }
    var modalityId: String
    var label: String
    var pct: Int
    var color: Color
}

struct ActivityTypeEntry: Identifiable {
    var id: String { name }
    var name: String
    var hours: Double
    var sessions: Double
    var color: Color
}

struct WeeklyConsistencyEntry: Identifiable {
    var id: Date { weekStart }
    var weekLabel: String
    var sessionCount: Int
    var weekStart: Date
}

// MARK: - Strava-style Best Efforts

struct BestEffort: Identifiable {
    var id: String { label }
    var label: String           // "1 km", "5 km", "10 km"
    var timeSeconds: Double
    var paceStr: String         // "4:32 /km"
    var isPersonalRecord: Bool  // fastest ever in allWorkouts
}

// MARK: - Garmin-style Training Effect

enum TrainingEffect: String, CaseIterable {
    case recovery        = "Recovery"
    case maintenance     = "Maintenance"
    case baseDevelopment = "Base Development"
    case aerobicCapacity = "Aerobic Capacity"
    case threshold       = "Threshold"
    case highlyImpacting = "Highly Impacting"

    var color: Color {
        switch self {
        case .recovery:        return .secondary
        case .maintenance:     return Color(red: 0.078, green: 0.722, blue: 0.651)   // teal
        case .baseDevelopment: return Color(red: 0.055, green: 0.647, blue: 0.914)   // sky
        case .aerobicCapacity: return Color(red: 0.063, green: 0.725, blue: 0.506)   // green
        case .threshold:       return Color(red: 0.976, green: 0.451, blue: 0.086)   // orange
        case .highlyImpacting: return Color(red: 0.937, green: 0.267, blue: 0.267)   // red
        }
    }

    var icon: String {
        switch self {
        case .recovery:        return "bed.double.fill"
        case .maintenance:     return "checkmark.circle.fill"
        case .baseDevelopment: return "waveform.path"
        case .aerobicCapacity: return "heart.circle.fill"
        case .threshold:       return "flame.fill"
        case .highlyImpacting: return "bolt.fill"
        }
    }
}

// MARK: - Period / Sort

enum AnalyticsPeriod: String, CaseIterable, Identifiable {
    case sevenDays    = "7d"
    case thirtyDays   = "30d"
    case threeMonths  = "3m"
    case oneYear      = "1y"
    case all          = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .sevenDays:   return 7
        case .thirtyDays:  return 30
        case .threeMonths: return 90
        case .oneYear:     return 365
        case .all:         return nil
        }
    }

    var label: String { rawValue }
}

enum WorkoutSortKey: String, CaseIterable, Identifiable {
    case date     = "Date"
    case duration = "Duration"
    case distance = "Distance"
    case avgHR    = "Avg HR"

    var id: String { rawValue }
}
