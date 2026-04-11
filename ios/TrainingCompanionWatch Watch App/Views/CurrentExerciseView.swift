import SwiftUI

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
                VStack(alignment: .leading, spacing: 6) {
                    // Header
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(exercise.loadDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let note = exercise.loadNote {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    // HR alert banner
                    if sessionState.isHRAlertActive {
                        Label("Check HR zone", systemImage: "heart.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    // Slot-type specific content
                    slotView
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var slotView: some View {
        switch exercise.resolvedSlotType {
        case "sets_reps":
            SetsRepsView(exercise: exercise, exerciseIndex: exerciseIndex)
        case "time_domain", "skill_practice":
            TimeDomainView(exercise: exercise, exerciseIndex: exerciseIndex)
        case "emom":
            EMOMView(exercise: exercise, exerciseIndex: exerciseIndex)
        case "amrap":
            AMRAPView(exercise: exercise, exerciseIndex: exerciseIndex)
        case "amrap_movement":
            AMRAPMovementView(exercise: exercise, exerciseIndex: exerciseIndex)
        case "for_time":
            ForTimeView(exercise: exercise, exerciseIndex: exerciseIndex)
        case "distance":
            DistanceView(exercise: exercise, exerciseIndex: exerciseIndex)
        case "static_hold":
            StaticHoldView(exercise: exercise, exerciseIndex: exerciseIndex)
        default:
            SetsRepsView(exercise: exercise, exerciseIndex: exerciseIndex)
        }
    }
}
