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
