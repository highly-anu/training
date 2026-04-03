import SwiftUI

struct EMOMView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    @EnvironmentObject var sessionState: WorkoutSessionState

    private var emomState: (round: Int, isWork: Bool, remaining: Int) {
        if case .emomInterval(_, let r, let w, let rem) = sessionState.phase {
            return (r, w, rem)
        }
        return (1, true, 0)
    }

    private var totalRounds: Int { exercise.targetRounds ?? 8 }

    var body: some View {
        VStack(spacing: 8) {
            // WORK / REST pill
            Text(emomState.isWork ? "WORK" : "REST")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(emomState.isWork ? Color.green : Color.red.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(Capsule())

            // Large countdown
            Text(formatTime(emomState.remaining))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(emomState.isWork ? .primary : .secondary)

            // Round counter
            Text("Round \(emomState.round) of \(totalRounds)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(exercise.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Rep target if prescribed
            if let reps = exercise.reps {
                Text("\(reps) reps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HRBadge()
        }
        .padding()
    }
}

private func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return m > 0 ? String(format: "%d:%02d", m, s) : String(format: "0:%02d", s)
}
