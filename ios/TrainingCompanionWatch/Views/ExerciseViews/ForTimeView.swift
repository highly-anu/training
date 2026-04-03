import SwiftUI

struct ForTimeView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    @EnvironmentObject var sessionState: WorkoutSessionState

    private var elapsed: Int {
        if case .forTimeRunning(_, let e) = sessionState.phase { return e }
        return 0
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("FOR TIME")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(formatTime(elapsed))
                .font(.system(size: 44, weight: .bold, design: .monospaced))

            Text(exercise.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let rounds = exercise.targetRounds, let reps = exercise.reps {
                Text("\(rounds) rounds × \(reps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HRBadge()

            Button {
                sessionState.completeExercise(exerciseIndex)
            } label: {
                Label("Done", systemImage: "flag.checkered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
    }
}

private func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}
