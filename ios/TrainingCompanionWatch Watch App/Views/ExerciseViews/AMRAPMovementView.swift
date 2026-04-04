import SwiftUI

/// Individual movement within an AMRAP — self-paced, rep counter, no rest timer.
struct AMRAPMovementView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var repsTapped = 0

    var body: some View {
        VStack(spacing: 10) {
            Text(exercise.reps.map { "\($0) reps" } ?? "Reps")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(repsTapped)")
                .font(.title.bold())

            Button("+") {
                repsTapped += 1
            }
            .font(.largeTitle.bold())
            .buttonStyle(.plain)
            .foregroundStyle(.green)

            Button("Done") {
                sessionState.markExerciseComplete(id: exercise.exerciseId)
                sessionState.phase = .active(exerciseIndex: exerciseIndex + 1, setIndex: 0)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
