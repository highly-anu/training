import SwiftUI

/// Small HR badge shown in the corner of exercise views.
struct HRBadge: View {
    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        if sessionState.currentHR > 0 {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
                Text("\(sessionState.currentHR)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(HRZoneColor(zone: sessionState.currentHRZone))
            }
        }
    }
}

/// Returns a SwiftUI Color for a given HR zone (1–5).
func HRZoneColor(zone: Int) -> Color {
    switch zone {
    case 1: return .blue
    case 2: return .green
    case 3: return .yellow
    case 4: return .orange
    case 5: return .red
    default: return .secondary
    }
}
