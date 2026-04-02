import SwiftUI

struct SessionOverviewView: View {
    let session: WatchSession
    @EnvironmentObject var sessionState: WorkoutSessionState
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var navigateToWorkout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.archetypeName)
                        .font(.headline)
                    HStack {
                        Label("\(session.estimatedMinutes) min", systemImage: "clock")
                        if session.isDeload {
                            Text("• Deload")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                // Deload note
                if session.isDeload {
                    Text("Deload week — focus on movement quality, not load.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .background(.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                // Exercise list
                ForEach(Array(session.exercises.enumerated()), id: \.element.exerciseId) { i, ex in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(ex.loadDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Begin button
                Button {
                    let activityType = WorkoutManager.activityType(for: session.modalityId)
                    sessionState.startSession(session)
                    Task { await workoutManager.startWorkout(activityType: activityType) }
                    navigateToWorkout = true
                } label: {
                    Label("Begin Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToWorkout) {
            ActiveWorkoutView()
        }
    }
}
