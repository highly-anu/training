import SwiftUI

/// The heart-rate zone colours, easy to hard: Z1 blue, Z2 green, Z3 yellow,
/// Z4 orange, Z5 red (design-system §3.5). Analytics ▸ Program's intensity
/// rows, a workout's zone distribution and timeline, and Profile ▸ Athlete's
/// zone bar all read these; each used to declare its own.
enum HRZoneStyle {
    static let colors: [Color] = [.blue, .green, .yellow, .orange, .red]

    /// Zone 1…5; anything outside clamps to the nearest end.
    static func color(_ zone: Int) -> Color {
        colors[min(max(zone, 1), 5) - 1]
    }

    /// "z1"…"z5", as the server names them.
    static func color(_ key: String) -> Color {
        color(Int(key.dropFirst()) ?? 5)
    }
}

/// A workout's TRIMP as a band: low, moderate, high, very high, each with its
/// colour. The workout row's load badge, the workout detail's Training Load
/// and the "Workout complete" sheet read it; the first two each had a copy.
enum TrimpStyle {
    static func label(_ trimp: Int) -> String {
        switch trimp {
        case ..<40:    return "Low"
        case 40..<70:  return "Moderate"
        case 70..<100: return "High"
        default:       return "Very High"
        }
    }

    static func color(_ trimp: Int) -> Color {
        switch trimp {
        case ..<40:    return .secondary
        case 40..<70:  return .blue
        case 70..<100: return .orange
        default:       return .red
        }
    }
}
