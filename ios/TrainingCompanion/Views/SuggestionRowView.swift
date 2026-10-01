import SwiftUI

/// A workout the server matched to a planned session too weakly to confirm
/// on its own (Garmin webhook, Apple Health relay): where the decision gets
/// made. Today shows the first three with Review and Dismiss; Log ▸
/// Suggestions is the full inbox and adds Accept. One row for both (§1.7).
struct SuggestionRowView: View {
    let suggestion: MatchSuggestion
    let workout: ImportedWorkout
    let planned: ProgramSession?
    var onAccept: (() -> Void)? = nil
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let modalityId = workout.inferredModalityId ?? planned?.modality ?? "aerobic_base"
        HStack(spacing: 12) {
            Image(systemName: ActivityIcon.forWorkout(activityType: workout.activityType,
                                                      modalityId: workout.inferredModalityId))
                .foregroundStyle(ModalityStyle.color(for: modalityId))
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.recordedTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(workout.date)
                    if let minutes = workout.durationMinutes {
                        Text("· \(Int(minutes)) min")
                    }
                    Text("→")
                    Text(planned.map { $0.archetype?.name ?? ModalityStyle.label(for: $0.modality) }
                         ?? suggestion.sessionKey)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let onAccept {
                Button {
                    AppHaptics.success()
                    onAccept()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
                .accessibilityLabel("Accept suggestion")
            }
            Button("Review") {
                AppHaptics.light()
                onReview()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                AppHaptics.light()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}
