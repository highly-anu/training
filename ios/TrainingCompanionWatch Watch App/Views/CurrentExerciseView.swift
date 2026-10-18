import SwiftUI

/// Page 1 of the workout: the step's data page (its package's screen) and
/// its buttons. The views it used to pick by slot type are gone; the
/// template in the spec runs the step, as on the Garmin.
struct CurrentExerciseView: View {
    let exercise: WatchExercise
    let exerciseIndex: Int
    let session: WatchSession

    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        VStack(spacing: 0) {
            // Modality colour bar
            Rectangle()
                .fill(ModalityStyle.color(for: session.modalityId))
                .frame(height: 3)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    DataPageView(exercise: exercise, index: exerciseIndex, session: session)

                    if sessionState.isHRAlertActive {
                        Label("Check HR zone", systemImage: "heart.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    StepControlsView(exercise: exercise, index: exerciseIndex, session: session)
                        .frame(maxWidth: .infinity)

                    if let note = exercise.loadNote {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }
}
