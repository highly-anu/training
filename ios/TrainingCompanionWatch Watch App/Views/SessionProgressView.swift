import SwiftUI

struct SessionProgressView: View {
    let session: WatchSession

    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(session.exercises.enumerated()), id: \.offset) { idx, ex in
                    HStack(spacing: 8) {
                        Image(systemName: sessionState.completedExerciseIds.contains(ex.exerciseId)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(sessionState.completedExerciseIds.contains(ex.exerciseId)
                                             ? .green : .secondary)
                            .font(.caption)

                        Image(systemName: ModalityStyle.slotTypeIcon(for: ex.resolvedSlotType))
                            .foregroundStyle(.secondary)
                            .font(.caption2)

                        Text(ex.name)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(isCurrentExercise(idx) ? .primary : .secondary)
                    }
                    .padding(.vertical, 2)
                }

            }
            .padding(.horizontal)
        }
        .navigationTitle("Progress")
    }

    private func isCurrentExercise(_ idx: Int) -> Bool {
        switch sessionState.phase {
        case let .active(ei, _):              return ei == idx
        case let .timedWork(ei, _):           return ei == idx
        case let .emomInterval(ei, _, _, _):  return ei == idx
        case let .amrapRunning(ei, _):        return ei == idx
        case let .resting(ei, _, _):          return ei == idx
        default:                              return false
        }
    }
}
