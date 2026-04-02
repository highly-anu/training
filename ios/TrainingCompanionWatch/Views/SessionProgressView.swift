import SwiftUI

/// S3-B: Scrollable list of all exercises in the session with completion state.
struct SessionProgressView: View {
    @EnvironmentObject var sessionState: WorkoutSessionState

    private var currentIndex: Int {
        switch sessionState.phase {
        case .active(let i, _), .timedWork(let i, _),
             .emomInterval(let i, _, _, _), .amrapRunning(let i, _, _),
             .forTimeRunning(let i, _), .resting(let i, _, _):
            return i
        default:
            return -1
        }
    }

    var body: some View {
        List {
            ForEach(Array((sessionState.session?.exercises ?? []).enumerated()), id: \.element.exerciseId) { i, ex in
                HStack(spacing: 8) {
                    // Status icon
                    Group {
                        if sessionState.completedExerciseIds.contains(ex.exerciseId) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        } else if i == currentIndex {
                            Image(systemName: "play.circle.fill").foregroundStyle(.blue)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.caption)
                            .fontWeight(i == currentIndex ? .bold : .regular)
                        Text(ex.loadDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(i == currentIndex ? Color.blue.opacity(0.1) : Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}
