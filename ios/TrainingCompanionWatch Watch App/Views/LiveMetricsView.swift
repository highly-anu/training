import SwiftUI

struct LiveMetricsView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        VStack(spacing: 6) {
            // HR ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: hrFraction)
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(zoneColor)
                    Text("\(sessionState.currentHR)")
                        .font(.title2.bold().monospacedDigit())
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            HStack(spacing: 16) {
                metricItem(value: elapsedString, label: "Time")
                metricItem(value: "\(sessionState.calories)", label: "kcal")
            }

            if sessionState.currentHR > 0 {
                Text("Zone \(HRZoneCalculator.zone(for: sessionState.currentHR, maxHR: connectivity.maxHR))")
                    .font(.caption2)
                    .foregroundStyle(zoneColor)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func metricItem(value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.caption.monospacedDigit().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var hrFraction: Double {
        guard connectivity.maxHR > 0, sessionState.currentHR > 0 else { return 0 }
        return min(1.0, Double(sessionState.currentHR) / Double(connectivity.maxHR))
    }

    private var zoneColor: Color {
        guard sessionState.currentHR > 0 else { return .secondary }
        switch HRZoneCalculator.zone(for: sessionState.currentHR, maxHR: connectivity.maxHR) {
        case 1:  return .gray
        case 2:  return .blue
        case 3:  return .green
        case 4:  return .orange
        default: return .red
        }
    }

    private var elapsedString: String {
        let h = sessionState.elapsedSeconds / 3600
        let m = (sessionState.elapsedSeconds % 3600) / 60
        let s = sessionState.elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
