import SwiftUI

struct DistanceView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var distanceCovered: Double = 0.0
    @State private var elapsedSeconds = 0
    @State private var isRunning = false

    private let targetKm: Double

    init(exercise: WatchExercise, exerciseIndex: Int) {
        self.exercise = exercise
        self.exerciseIndex = exerciseIndex
        self.targetKm = exercise.distanceKm ?? 1.0
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%.2f / %.1f km", distanceCovered, targetKm))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(timeString(elapsedSeconds))
                .font(.title3.monospacedDigit().bold())

            if isRunning {
                // Manual distance entry (GPS not available in watchOS simulator)
                HStack(spacing: 8) {
                    Button("-0.1") {
                        distanceCovered = max(0, distanceCovered - 0.1)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button("+0.1") {
                        distanceCovered += 0.1
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                Button("Done") {
                    isRunning = false
                    sessionState.markExerciseComplete(id: exercise.exerciseId)
                    sessionState.phase = .active(exerciseIndex: exerciseIndex + 1, setIndex: 0)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Button("Start") {
                    isRunning = true
                    elapsedSeconds = 0
                    distanceCovered = 0
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
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
