import SwiftUI

/// A hold, set by set. The set is the session's (`.active(_, setIndex)`), as
/// in SetsRepsView: the view is rebuilt after every rest, and a count kept
/// in its own state went back to the first set each time and never reached
/// the Done that moves on.
struct StaticHoldView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var actualHoldSeconds = 0
    @State private var isHolding = false
    @State private var holdStartOffset: Int = 0

    private let targetHoldSec: Int
    private let totalSets: Int
    private let restSec: Int

    init(exercise: WatchExercise, exerciseIndex: Int) {
        self.exercise = exercise
        self.exerciseIndex = exerciseIndex
        self.targetHoldSec = exercise.holdSeconds ?? 30
        self.totalSets = exercise.sets ?? 3
        self.restSec = exercise.restSeconds ?? 60
    }

    var body: some View {
        if case let .active(ei, si) = sessionState.phase, ei == exerciseIndex {
            VStack(spacing: 8) {
                setDots(currentSet: si)
                timerDisplay
                actionButtons(setIndex: si)
            }
            .task(id: isHolding) {
                guard isHolding else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    actualHoldSeconds += 1
                }
            }
        }
    }

    private func setDots(currentSet: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSets, id: \.self) { i in
                Circle()
                    .fill(i < currentSet ? Color.green :
                          i == currentSet ? Color.blue : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var timerDisplay: some View {
        if isHolding {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(1.0, Double(actualHoldSeconds) / Double(targetHoldSec)))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(actualHoldSeconds)s")
                        .font(.title3.monospacedDigit().bold())
                    Text("/ \(targetHoldSec)s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, height: 70)
        } else {
            Text("Hold \(targetHoldSec)s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actionButtons(setIndex si: Int) -> some View {
        if si >= totalSets {
            Button("Done") {
                sessionState.markExerciseComplete(id: exercise.exerciseId)
                sessionState.advance(to: exerciseIndex + 1)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        } else if isHolding {
            HStack(spacing: 10) {
                Button("Fail") {
                    completeSet(si, held: false)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.caption)

                Button("Done") {
                    completeSet(si, held: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .font(.caption)
            }
        } else {
            Button("Hold") {
                holdStartOffset = sessionState.elapsedSeconds
                isHolding = true
                actualHoldSeconds = 0
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }

    private func completeSet(_ si: Int, held: Bool) {
        isHolding = false
        let log = WatchSetLog(
            setIndex: si,
            repsActual: nil,
            weightKg: nil,
            rpe: nil,
            completed: held,
            durationSeconds: actualHoldSeconds,
            startOffset: holdStartOffset,
            endOffset: sessionState.elapsedSeconds
        )
        sessionState.completeSet(log, for: exercise.exerciseId)
        if si + 1 >= totalSets {
            sessionState.markExerciseComplete(id: exercise.exerciseId)
        }
        sessionState.startRest(exerciseIndex: exerciseIndex, completedSet: si, seconds: restSec)
    }
}
