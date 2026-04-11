import SwiftUI

struct SessionOverviewView: View {
    let session: WatchSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if session.isDeload {
                    Label("Deload week — quality over load", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.bottom, 4)
                }

                ForEach(session.exercises, id: \.exerciseId) { ex in
                    exerciseRow(ex)
                }

                NavigationLink(destination: ActiveWorkoutView(session: session)) {
                    Label("Begin Workout", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(ModalityStyle.color(for: session.modalityId))
                .padding(.top, 8)
            }
            .padding(.horizontal)
        }
        .navigationTitle(session.archetypeName)
    }

    @ViewBuilder
    private func exerciseRow(_ ex: WatchExercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: ModalityStyle.slotTypeIcon(for: ex.resolvedSlotType))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(ex.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(ex.loadDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let note = ex.loadNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
