import SwiftUI

/// Swap one exercise for a ranked alternative that fits the same slot.
///
/// The smallest regenerable unit used to be a session, so swapping one
/// movement meant regenerating all of them. The server runs the selector's
/// own filter and score for the slot; a pick replaces the assignment in place
/// and saves through the same revision-checked path as move and replace.
struct SwapExerciseSheet: View {
    let weekIndex: Int
    let dayName: String
    let sessionIndex: Int
    /// Index into the session's full `exercises` array, not the filtered rows.
    let exerciseIndex: Int
    /// A program that is not the active one (the preview's draft): its own
    /// methodologies and constraints, and the pick goes to `onPick`.
    var draft: Draft? = nil

    struct Draft {
        let program: GeneratedProgram
        let philosophyIds: [String]
        let constraints: GenerateConstraints
        let onPick: (ProgramExerciseAssignment) -> Void
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var alternatives: [ExerciseAlternative] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var detail: ExerciseAlternative? = nil

    private var current: ProgramExerciseAssignment? {
        (draft?.program ?? appState.serverProgram?.currentProgram)?.weeks[safe: weekIndex]?
            .schedule[dayName]?[safe: sessionIndex]?.exercises[safe: exerciseIndex]
    }

    var body: some View {
        NavigationStack {
            List {
                if let current, let ex = current.exercise {
                    Section("Current") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ex.name).font(.body).fontWeight(.medium)
                            Text(LoadFormat.describe(current))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Finding alternatives…").foregroundStyle(.secondary)
                        }
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    } else if alternatives.isEmpty {
                        Text("Nothing else fits this slot under the program's methodology, your equipment and injury flags.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alternatives) { alt in
                            alternativeRow(alt)
                        }
                    }
                } header: {
                    Text("Alternatives")
                } footer: {
                    if !alternatives.isEmpty {
                        Text("Same slot, same rules as a generate. The load is worked out for this week.")
                    }
                }
            }
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $detail) { alt in
                if let ex = alt.assignment.exercise {
                    ExerciseDetailSheet(exerciseId: ex.id, name: ex.name, assignment: alt.assignment)
                        .environmentObject(appState)
                }
            }
            .task { await load() }
        }
    }

    private func alternativeRow(_ alt: ExerciseAlternative) -> some View {
        HStack(spacing: 12) {
            Button {
                pick(alt)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alt.assignment.exercise?.name ?? "Exercise")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(LoadFormat.describe(alt.assignment))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                    if !alt.reasons.isEmpty {
                        Text(alt.reasons.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                detail = alt
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(alt.assignment.exercise?.name ?? "this exercise")")
        }
        .padding(.vertical, 2)
    }

    private func pick(_ alt: ExerciseAlternative) {
        if let draft {
            draft.onPick(alt.assignment)
        } else {
            appState.replaceExercise(weekIndex: weekIndex, day: dayName, sessionIndex: sessionIndex,
                                     exerciseIndex: exerciseIndex, assignment: alt.assignment)
        }
        AppHaptics.success()
        dismiss()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let draft {
                alternatives = try await appState.substituteAlternatives(
                    in: draft.program, philosophyIds: draft.philosophyIds,
                    trainingLevel: draft.constraints.trainingLevel, equipment: draft.constraints.equipment,
                    injuryFlags: draft.constraints.injuryFlags,
                    weekIndex: weekIndex, day: dayName, sessionIndex: sessionIndex, exerciseIndex: exerciseIndex)
                return
            }
            alternatives = try await appState.substituteAlternatives(
                weekIndex: weekIndex, day: dayName,
                sessionIndex: sessionIndex, exerciseIndex: exerciseIndex)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
