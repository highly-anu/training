import SwiftUI

struct TimeDomainView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int

    @EnvironmentObject var sessionState: WorkoutSessionState

    @State private var isActive = false

    var body: some View {
        VStack(spacing: 8) {
            if isActive {
                Label("Timer running", systemImage: "timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                Button("Start Timer") {
                    isActive = true
                    sessionState.startTimedWork(exerciseIndex: exerciseIndex)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .onAppear {
            if case .timedWork(let ei, _) = sessionState.phase, ei == exerciseIndex {
                isActive = true
            }
        }
    }
}
