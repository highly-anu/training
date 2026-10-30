import SwiftUI

/// The session a search found (or a picked one), in full, before anything is
/// saved (design-system §6.43): its kind, name, minutes and source, every
/// exercise with its prescription, then Add / Replace — and Search Again for
/// another of the kind. Pushed inside `ReplaceWorkoutSheet`.
struct SessionPreviewView: View {
    let session: ProgramSession
    /// "Add Session" or "Replace Workout".
    let confirmTitle: String
    /// What it is when added ("An extra: it counts once you do it…"); nil when replacing.
    var note: String? = nil
    /// Another session of the kind; nil when the session was picked by hand.
    var onSearchAgain: (() -> Void)? = nil
    var isSearching: Bool = false
    /// Search Again's refusal, shown here rather than behind this screen.
    var error: String? = nil
    let onConfirm: () -> Void

    private var exercises: [ProgramExerciseAssignment] {
        session.exercises.filter { !$0.meta && !$0.injurySkip }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(ModalityStyle.label(for: session.modality),
                          systemImage: ModalityStyle.icon(for: session.modality))
                        .font(.caption)
                        .foregroundStyle(ModalityStyle.color(for: session.modality))
                    Text(session.archetype?.name ?? ModalityStyle.label(for: session.modality))
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 12) {
                        if let mins = session.archetype?.durationEstimateMinutes {
                            Label("\(mins) min", systemImage: "clock")
                        }
                        if !exercises.isEmpty {
                            Label("\(exercises.count) exercises", systemImage: "list.bullet")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let via = ReplaceWorkoutSheet.borrowedLabel(session) {
                        Text("via \(via)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                if let note { Text(note) }
            }

            Section("Exercises") {
                if exercises.isEmpty {
                    Text("Coach-led — no exercises listed").foregroundStyle(.secondary)
                }
                ForEach(Array(exercises.enumerated()), id: \.offset) { _, ea in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ea.exercise?.name ?? (ea.slotRole ?? "").replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.body.weight(.medium))
                        Text(LoadFormat.describe(ea))
                            .font(.subheadline).monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let note = ea.loadNote, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary).italic()
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onConfirm) {
                    Text(confirmTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSearching)
                if let onSearchAgain {
                    Button(action: onSearchAgain) {
                        HStack(spacing: 6) {
                            if isSearching { ProgressView().controlSize(.small) }
                            Text(isSearching ? "Searching…" : "Search Again")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSearching)
                }
            }
            .padding()
            .background(.bar)
        }
    }
}
