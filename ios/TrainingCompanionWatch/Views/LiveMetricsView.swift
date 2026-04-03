import SwiftUI

/// S3-C: Always-live HR + session stats panel.
struct LiveMetricsView: View {
    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        VStack(spacing: 10) {
            // HR ring
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: hrFraction)
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: sessionState.currentHR)

                VStack(spacing: 0) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                    Text("\(sessionState.currentHR)")
                        .font(.title2.monospacedDigit().bold())
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, height: 90)

            // Zone name
            if sessionState.currentHR > 0 {
                Text(HRZoneCalculator.zoneName(sessionState.currentHRZone))
                    .font(.caption2)
                    .foregroundStyle(zoneColor)
            }

            Divider()

            // Stats row
            HStack(spacing: 16) {
                statItem(label: "Elapsed", value: formatTime(sessionState.elapsedSeconds))
                if sessionState.peakHR > 0 {
                    statItem(label: "Peak HR", value: "\(sessionState.peakHR)")
                }
            }
        }
        .padding()
    }

    private var hrFraction: Double {
        let maxHR = Double(HRZoneCalculator.storedMaxHR())
        guard maxHR > 0 else { return 0 }
        return min(Double(sessionState.currentHR) / maxHR, 1.0)
    }

    private var zoneColor: Color {
        HRZoneColor(zone: sessionState.currentHRZone)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.monospacedDigit().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private func formatTime(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
