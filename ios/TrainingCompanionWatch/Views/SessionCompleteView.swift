import SwiftUI

struct SessionCompleteView: View {
    @EnvironmentObject var sessionState: WorkoutSessionState
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var isSaving = false
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: saved ? "checkmark.seal.fill" : "trophy.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(saved ? .green : .yellow)

                Text(saved ? "Saved!" : "Session Complete")
                    .font(.headline)

                Divider()

                // Stats
                statRow(label: "Duration", value: "\(sessionState.durationMinutes) min")
                if let avg = sessionState.avgHR {
                    statRow(label: "Avg HR", value: "\(avg) bpm")
                }
                if sessionState.peakHR > 0 {
                    statRow(label: "Peak HR", value: "\(sessionState.peakHR) bpm")
                }
                statRow(label: "Exercises", value: "\(sessionState.completedExerciseIds.count)")

                if !saved {
                    Button {
                        isSaving = true
                        Task {
                            await workoutManager.endWorkout()
                            isSaving = false
                            saved = true
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Save Workout", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}
