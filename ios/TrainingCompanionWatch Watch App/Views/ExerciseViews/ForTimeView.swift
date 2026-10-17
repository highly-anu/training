import SwiftUI

struct ForTimeView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var elapsedSeconds = 0
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 8) {
            if let rounds = exercise.targetRounds {
                Text("\(rounds) rounds")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(timeString(elapsedSeconds))
                .font(.title2.monospacedDigit().bold())

            if isRunning {
                Button("Finish") {
                    isRunning = false
                    // The clock is the result (a 2 km row, Fran): kept for the upload.
                    sessionState.recordOutcome(exercise.exerciseId, durationSec: elapsedSeconds)
                    sessionState.markExerciseComplete(id: exercise.exerciseId)
                    sessionState.advance(to: exerciseIndex + 1)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Button("Start") {
                    isRunning = true
                    elapsedSeconds = 0
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .task(id: isRunning) {
            guard isRunning else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsedSeconds += 1
            }
        }
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}
