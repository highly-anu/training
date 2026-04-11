import SwiftUI

struct SetsRepsView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var showLogger = false

    var body: some View {
        guard case let .active(ei, si) = sessionState.phase, ei == exerciseIndex else {
            return AnyView(EmptyView())
        }
        let totalSets = exercise.sets ?? 1
        let restSec   = exercise.restSeconds ?? 120

        return AnyView(
            VStack(spacing: 8) {
                // Set dots
                setDots(currentSet: si, totalSets: totalSets)

                // RPE feedback for previous set
                rpeFeedback(setIndex: si)

                Button(si < totalSets ? "Complete Set \(si + 1)" : "Done") {
                    if si < totalSets {
                        showLogger = true
                    } else {
                        sessionState.markExerciseComplete(id: exercise.exerciseId)
                        sessionState.phase = .active(exerciseIndex: exerciseIndex + 1, setIndex: 0)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .sheet(isPresented: $showLogger) {
                SetLoggerSheetView(
                    exercise: exercise,
                    setIndex: si,
                    exerciseIndex: exerciseIndex,
                    startOffset: sessionState.currentSetStartOffset ?? sessionState.elapsedSeconds
                ) { log in
                    sessionState.completeSet(log, for: exercise.exerciseId)
                    let nextSet = si + 1
                    if nextSet < totalSets {
                        sessionState.startRest(exerciseIndex: exerciseIndex,
                                               completedSet: si, seconds: restSec)
                    } else {
                        sessionState.markExerciseComplete(id: exercise.exerciseId)
                        sessionState.startRest(exerciseIndex: exerciseIndex,
                                               completedSet: si, seconds: restSec)
                    }
                }
            }
        )
    }

    @ViewBuilder
    private func setDots(currentSet: Int, totalSets: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSets, id: \.self) { i in
                Circle()
                    .fill(i < currentSet ? Color.green :
                          i == currentSet ? Color.blue : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
            }
        }
    }

    @ViewBuilder
    private func rpeFeedback(setIndex: Int) -> some View {
        let logs = sessionState.setLogs[exercise.exerciseId] ?? []
        if let last = logs.last, let rpe = last.rpe, let prescribed = exercise.targetRpe {
            if rpe >= prescribed + 2 {
                Text("Felt hard — consider lighter load")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if rpe <= prescribed - 2 {
                Text("Felt easy — ready to progress")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }
}
