import SwiftUI

struct AMRAPView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    @EnvironmentObject var sessionState: WorkoutSessionState

    private var secondsRemaining: Int {
        if case .amrapRunning(_, _, let r) = sessionState.phase { return r }
        return (exercise.timeMinutes ?? 10) * 60
    }
    private var rounds: Int {
        sessionState.amrapRounds
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("AMRAP")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            // Countdown
            Text(formatTime(secondsRemaining))
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(secondsRemaining < 60 ? .red : .primary)

            Text(exercise.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Round counter + increment
            HStack(spacing: 16) {
                Text("\(rounds)")
                    .font(.title.bold())
                Text("rounds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    sessionState.incrementAMRAPRound()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }

            HRBadge()
        }
        .padding()
    }
}

private func formatTime(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return String(format: "%d:%02d", m, s)
}
