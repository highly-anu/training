import SwiftUI

struct StaticHoldView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    @EnvironmentObject var sessionState: WorkoutSessionState
    @State private var holdElapsed: Int = 0
    @State private var isHolding = false
    @State private var holdTimer: Timer?

    private var targetHoldSec: Int { exercise.holdSeconds ?? 30 }
    private var currentSet: Int {
        if case .active(_, let s) = sessionState.phase { return s }
        return 0
    }
    private var totalSets: Int { exercise.sets ?? 3 }
    private var progress: Double { Double(holdElapsed) / Double(targetHoldSec) }

    var body: some View {
        VStack(spacing: 8) {
            Text(exercise.name)
                .font(.headline)

            // Hold ring
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(progress, 1.0))
                    .stroke(isHolding ? Color.green : Color.secondary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
                Text(isHolding ? "\(targetHoldSec - holdElapsed)s" : "Ready")
                    .font(.title3.monospacedDigit().bold())
            }
            .frame(width: 90, height: 90)

            Text("Set \(currentSet + 1) of \(totalSets)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Begin / Fail
                if !isHolding {
                    Button {
                        startHold()
                    } label: {
                        Label("Begin", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button {
                        failHold()
                    } label: {
                        Text("Fail")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .onDisappear { holdTimer?.invalidate() }
    }

    private func startHold() {
        holdElapsed = 0
        isHolding = true
        holdTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            holdElapsed += 1
            if holdElapsed >= targetHoldSec {
                holdTimer?.invalidate()
                isHolding = false
                WKInterfaceDevice.current().play(.success)
                sessionState.completeSet(exerciseIndex: exerciseIndex, setIndex: currentSet)
            }
        }
    }

    private func failHold() {
        holdTimer?.invalidate()
        isHolding = false
        // Log the actual hold time achieved
        var log = WatchSetLog(setIndex: currentSet, repsActual: nil, weightKg: nil, rpe: nil, completed: false, durationSeconds: holdElapsed)
        sessionState.pendingSetLog = log
        sessionState.completeSet(exerciseIndex: exerciseIndex, setIndex: currentSet)
    }
}
