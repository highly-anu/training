import SwiftUI

extension WatchExercise {
    /// Rounds, work and rest of an EMOM, read once for the view and the
    /// workout's ticker alike.
    var emomPlan: (rounds: Int, workSec: Int, restSec: Int) {
        let parsed = HRZoneCalculator.parseEMOMFormat(emomFormat)
        return (targetRounds ?? parsed.rounds, parsed.workSec, parsed.restSec)
    }
}

struct EMOMView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    private let parsedRounds: Int
    private let parsedWorkSec: Int
    private let parsedRestSec: Int

    init(exercise: WatchExercise, exerciseIndex: Int) {
        self.exercise = exercise
        self.exerciseIndex = exerciseIndex
        (parsedRounds, parsedWorkSec, parsedRestSec) = exercise.emomPlan
    }

    // The clock ticks in WorkoutManager's master ticker, not here.
    var body: some View {
        VStack(spacing: 6) {
            if case let .emomInterval(ei, round, isWork, remaining) = sessionState.phase,
               ei == exerciseIndex {
                activeView(round: round, isWork: isWork, remaining: remaining)
            } else {
                startView
            }
        }
    }

    private var startView: some View {
        VStack(spacing: 4) {
            Text("\(parsedRounds) rounds × \(parsedWorkSec)s / \(parsedRestSec)s")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Start EMOM") {
                sessionState.startEMOM(exerciseIndex: exerciseIndex, workSeconds: parsedWorkSec)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func activeView(round: Int, isWork: Bool, remaining: Int) -> some View {
        Capsule()
            .fill(isWork ? Color.green.opacity(0.3) : Color.orange.opacity(0.3))
            .frame(height: 22)
            .overlay(
                Text(isWork ? "WORK" : "REST")
                    .font(.caption2.bold())
                    .foregroundStyle(isWork ? .green : .orange)
            )

        Text("\(remaining)s")
            .font(.title.monospacedDigit().bold())

        Text("Round \(round) / \(parsedRounds)")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
