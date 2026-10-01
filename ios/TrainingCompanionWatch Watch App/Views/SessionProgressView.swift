import SwiftUI

struct SessionProgressView: View {
    let session: WatchSession

    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Index + exercise id: the same movement can appear twice in a session.
                let keyed = session.exercises.enumerated().map { (id: "\($0.offset)-\($0.element.exerciseId)", idx: $0.offset, ex: $0.element) }
                ForEach(keyed, id: \.id) { item in
                    let idx = item.idx
                    let ex = item.ex
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
                .animation(.spring(response: 0.5, dampingFraction: 0.88), value: keyed.map(\.id))

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
