import SwiftUI
import WatchKit

struct TimeDomainView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var isActive = false
    @State private var elapsedSeconds = 0
    @State private var didNotifyCompletion = false

    private let targetSeconds: Int

    init(exercise: WatchExercise, exerciseIndex: Int) {
        self.exercise = exercise
        self.exerciseIndex = exerciseIndex
        self.targetSeconds = (exercise.durationMinutes ?? 20) * 60
    }

    var body: some View {
        VStack(spacing: 8) {
            if isActive {
                activeView
            } else {
                Button("Start Timer") {
                    isActive = true
                    elapsedSeconds = 0
                    sessionState.startTimedWork(exerciseIndex: exerciseIndex)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .onAppear {
            // Restore if already running (e.g. tab switch)
            if case .timedWork(let ei, let elapsed) = sessionState.phase, ei == exerciseIndex {
                isActive = true
                elapsedSeconds = elapsed
            }
        }
        .task(id: isActive) {
            guard isActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsedSeconds += 1
                sessionState.tickTimedWork()
                if elapsedSeconds == targetSeconds && !didNotifyCompletion {
                    didNotifyCompletion = true
                    WKInterfaceDevice.current().play(.notification)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }
    }

    @ViewBuilder
    private var activeView: some View {
        Label("Timer running", systemImage: "timer")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}
