import SwiftUI

struct TimeDomainView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    @EnvironmentObject var sessionState: WorkoutSessionState
    @State private var showZoneAlert = false

    private var elapsedSeconds: Int {
        if case .timedWork(_, let e) = sessionState.phase { return e }
        return 0
    }
    private var targetSeconds: Int { (exercise.durationMinutes ?? 0) * 60 }
    private var progress: Double {
        guard targetSeconds > 0 else { return 0 }
        return min(Double(elapsedSeconds) / Double(targetSeconds), 1.0)
    }

    var body: some View {
        VStack(spacing: 8) {

            // Progress ring
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: 2) {
                    Text(formatTime(elapsedSeconds))
                        .font(.title2.monospacedDigit().bold())
                    if targetSeconds > 0 {
                        Text("/ \(formatTime(targetSeconds))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 100, height: 100)

            Text(exercise.name)
                .font(.headline)
                .lineLimit(2)

            // Zone target
            if let zone = exercise.zoneTarget {
                Text(zone)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Zone alert overlay
            if sessionState.isOutOfZone {
                zoneAlertBanner
            }

            // HR badge
            HRBadge()

            Button {
                sessionState.completeExercise(exerciseIndex)
            } label: {
                Label("Mark Complete", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
    }

    private var zoneColor: Color {
        HRZoneColor(zone: sessionState.currentHRZone)
    }

    private var zoneAlertBanner: some View {
        let upper = exercise.prescribedZoneUpper ?? 0
        let current = sessionState.currentHRZone
        let msg = current > upper
            ? "HR climbing — ease off"
            : "HR below target — pick it up"
        return Text(msg)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(6)
            .background(current > upper ? Color.red : Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}
