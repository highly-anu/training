import SwiftUI

/// A workout the server matched to a planned session too weakly to confirm
/// on its own (Garmin webhook, Apple Health relay): where the decision gets
/// made. Today shows the first three; Log ▸ Linking is the full inbox. One
/// row for both (§1.7): what was recorded, the session it looks like, and
/// the answers in words beneath — until 1.39 they shared the text's line,
/// which wrapped the date ("2026-11-\n07") on every phone.
struct SuggestionRowView: View {
    let suggestion: MatchSuggestion
    let workout: ImportedWorkout
    let planned: ProgramSession?
    var onAccept: (() -> Void)? = nil
    let onReview: () -> Void
    let onDismiss: () -> Void

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let dayDisplay: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE d MMM"); return f
    }()

    /// "Sat 7 Nov · 45 min"
    private var recorded: String {
        let day = Self.dayParser.date(from: workout.date).map(Self.dayDisplay.string(from:)) ?? workout.date
        guard let minutes = workout.durationMinutes else { return day }
        return "\(day) · \(Int(minutes)) min"
    }

    var body: some View {
        let modalityId = workout.inferredModalityId ?? planned?.modality ?? "aerobic_base"
        let plannedName = planned.map { $0.archetype?.name ?? ModalityStyle.label(for: $0.modality) }
            ?? suggestion.sessionKey
        VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
            HStack(alignment: .top, spacing: AppMetrics.gapMedium) {
                Image(symbol: ActivityIcon.forWorkout(activityType: workout.activityType,
                                                      modalityId: workout.inferredModalityId))
                    .foregroundStyle(ModalityStyle.color(for: modalityId))
                    .font(.title3)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.recordedTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(recorded)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(plannedName, systemImage: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel("Looks like \(plannedName)")
                }
                Spacer(minLength: 0)
                Button {
                    AppHaptics.light()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")
            }
            HStack(spacing: AppMetrics.gapSmall) {
                if let onAccept {
                    Button {
                        AppHaptics.success()
                        onAccept()
                    } label: {
                        Label("Link", systemImage: "checkmark")
                    }
                    .appButton(.primary)
                    .tint(AppColor.complete)
                    .accessibilityLabel("Link to \(plannedName)")
                }
                Button("Review") {
                    AppHaptics.light()
                    onReview()
                }
                .appButton(.secondary)
            }
            .controlSize(.small)
            // Under the text, clear of the icon.
            .padding(.leading, 24 + AppMetrics.gapMedium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(compact: true, border: AppColor.warning)
    }
}
