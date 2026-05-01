import SwiftUI

struct ReplaceWorkoutSheet: View {
    let api: APIClient
    let weekIndex: Int
    let dayName: String
    let sessionIndex: Int
    let session: ProgramSession

    @EnvironmentObject var programStore: ProgramStore
    @Environment(\.dismiss) private var dismiss

    @State private var sessionMinutes: Double = 60
    @State private var fatigueState: FatigueState = .normal
    @State private var preview: ProgramSession? = nil
    @State private var isGenerating = false
    @State private var generateError: String? = nil

    enum FatigueState: String, CaseIterable, Identifiable {
        case fresh, normal, accumulated, overreached
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Workout") {
                    Text(session.archetype?.name
                         ?? session.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                        .foregroundStyle(.secondary)
                }

                Section("Replacement Settings") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Session Length")
                            Spacer()
                            Text("\(Int(sessionMinutes)) min")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $sessionMinutes, in: 30...120, step: 15)
                    }

                    Picker("Fatigue State", selection: $fatigueState) {
                        ForEach(FatigueState.allCases) { state in
                            Text(state.label).tag(state)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await generatePreview() }
                    } label: {
                        if isGenerating {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Generating…")
                            }
                        } else {
                            Label("Preview Replacement", systemImage: "arrow.2.circlepath")
                        }
                    }
                    .disabled(isGenerating)

                    if let error = generateError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if let preview {
                    Section("Preview") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(preview.archetype?.name
                                 ?? preview.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.body.weight(.medium))
                            HStack(spacing: 8) {
                                Text(preview.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let mins = preview.archetype?.durationEstimateMinutes {
                                    Text("·")
                                        .foregroundStyle(.tertiary)
                                    Text("\(mins) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text("\(preview.exercises.filter { !$0.injurySkip }.count) exercises")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)

                        Button {
                            programStore.replaceSession(
                                weekIndex: weekIndex,
                                day: dayName,
                                sessionIndex: sessionIndex,
                                session: preview,
                                api: api
                            )
                            dismiss()
                        } label: {
                            Label("Confirm Replacement", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Replace Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func generatePreview() async {
        isGenerating = true
        generateError = nil
        preview = nil

        let week = programStore.serverProgram?.currentProgram?.weeks[safe: weekIndex]
        let request = GenerateSessionRequest(
            primarySources: [],
            modality: session.modality,
            phase: week?.phase ?? "base",
            weekInPhase: weekIndex + 1,
            isDeload: week?.isDeload ?? false,
            constraints: GenerateSessionConstraints(
                sessionTimeMinutes: Int(sessionMinutes),
                fatigueState: fatigueState.rawValue
            ),
            archetypeId: nil
        )

        do {
            preview = try await api.generateSession(request)
        } catch {
            generateError = error.localizedDescription
        }
        isGenerating = false
    }
}
