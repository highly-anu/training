import SwiftUI

struct AMRAPView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    private let totalMinutes: Int

    /// Read from the session's outcome rather than kept in the view, which
    /// lost the count whenever the page was rebuilt.
    private var roundsCompleted: Int { sessionState.outcomes[exercise.exerciseId]?.rounds ?? 0 }

    init(exercise: WatchExercise, exerciseIndex: Int) {
        self.exercise = exercise
        self.exerciseIndex = exerciseIndex
        self.totalMinutes = exercise.timeMinutes ?? 10
    }

    // The clock ticks in WorkoutManager's master ticker, not here.
    var body: some View {
        VStack(spacing: 8) {
            if case let .amrapRunning(ei, remaining) = sessionState.phase, ei == exerciseIndex {
                activeView(remaining: remaining)
            } else {
                Button("Start AMRAP \(totalMinutes)m") {
                    sessionState.startAMRAP(exerciseIndex: exerciseIndex,
                                            minutes: totalMinutes)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
        }
    }

    @ViewBuilder
    private func activeView(remaining: Int) -> some View {
        Text(timeString(remaining))
            .font(.title2.monospacedDigit().bold())

        Text("AMRAP")
            .font(.caption2)
            .foregroundStyle(.secondary)

        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(roundsCompleted)")
                    .font(.title3.bold())
                Text("Rounds")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("+") {
                sessionState.recordOutcome(exercise.exerciseId, rounds: roundsCompleted + 1)
            }
            .font(.title3.bold())
            .buttonStyle(.plain)
            .foregroundStyle(.green)
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
