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
    var id = UUID()
    var date: Date
    var ctl: Double
    var atl: Double
    var tsb: Double
    var trimp: Double
}

struct WeeklyLoadEntry: Identifiable {
    var id = UUID()
    var week: String        // "MMM d"
    var trimp: Double
    var sessions: Double
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
    var id = UUID()
    var modalityId: String
    var label: String
    var pct: Int
    var color: Color
}

struct ActivityTypeEntry: Identifiable {
    var id = UUID()
    var name: String
    var hours: Double
    var sessions: Double
    var color: Color
}

struct WeeklyConsistencyEntry: Identifiable {
    var id = UUID()
    var weekLabel: String
    var sessionCount: Int
    var weekStart: Date
}

// MARK: - Strava-style Best Efforts

struct BestEffort: Identifiable {
    var id = UUID()
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
