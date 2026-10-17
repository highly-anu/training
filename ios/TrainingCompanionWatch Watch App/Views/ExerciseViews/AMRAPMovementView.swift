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
                // The count goes in as the step's one set, where the server
                // reads reps; it used to be dropped here.
                if repsTapped > 0 {
                    let start = sessionState.currentSetStartOffset
                    sessionState.completeSet(
                        WatchSetLog(setIndex: 0, repsActual: repsTapped, weightKg: exercise.weightKg, rpe: nil,
                                    completed: true,
                                    durationSeconds: start.map { sessionState.elapsedSeconds - $0 },
                                    startOffset: start, endOffset: sessionState.elapsedSeconds),
                        for: exercise.exerciseId)
                }
                sessionState.markExerciseComplete(id: exercise.exerciseId)
                sessionState.advance(to: exerciseIndex + 1)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
