import SwiftUI

struct TimeDomainView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    private var isActive: Bool {
        if case let .timedWork(ei, _) = sessionState.phase { return ei == exerciseIndex }
        return false
    }

    var body: some View {
        VStack(spacing: 8) {
            if isActive {
                Label("Timer running", systemImage: "timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                Button("Start Timer") {
                    sessionState.startTimedWork(exerciseIndex: exerciseIndex)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }
}
