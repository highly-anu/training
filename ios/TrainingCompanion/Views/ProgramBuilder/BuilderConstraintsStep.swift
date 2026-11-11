import SwiftUI

// MARK: - Step 3: Constraints

struct BuilderStep3ConstraintsView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    private let trainingLevels = ClientVocab.trainingLevels

    /// The chosen track's own phases — the only places a program can start.
    private var trackPhases: [PhilosophyPhase] {
        builder.track(in: appState.philosophies.first { $0.id == builder.selectedPhilosophyId })?.phases ?? []
    }

    var body: some View {
        Form {
            Section("Training Level") {
                Picker("Level", selection: Binding(
                    get: { builder.constraints.trainingLevel },
                    set: { builder.constraints.trainingLevel = $0 }
                )) {
                    ForEach(trainingLevels, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
            }

            EquipmentToggleSection(selection: $builder.constraints.equipment)
            InjuryToggleSection(selection: $builder.constraints.injuryFlags)

            if builder.isComposed {
                // Each track starts at a phase of its own.
                ForEach($builder.lanes) { $lane in
                    let phases = builder.track(of: lane, in: appState.philosophies)?.phases ?? []
                    if phases.count > 1 {
                        Section {
                            StartPhasePicker(phases: phases, selection: $lane.startPhaseId)
                                .disabled(builder.eventDate != nil)
                        } header: {
                            Text("Starting Phase · " + (builder.track(of: lane, in: appState.philosophies)?.name ?? ""))
                        }
                    }
                }
            } else if trackPhases.count > 1 {
                Section {
                    StartPhasePicker(phases: trackPhases, selection: $builder.startPhaseId)
                        .disabled(builder.eventDate != nil)
                } header: {
                    Text("Starting Phase")
                } footer: {
                    Text(builder.eventDate != nil
                         ? "Set from the event date: the phases are counted back from it."
                         : "Where you are in this track. Most programs start at the first phase.")
                }
            }
        }
    }
}

/// Picks a start phase from a track's own phases; nil is the first phase.
/// Shared by the builder and the Program settings sheet.
struct StartPhasePicker: View {
    let phases: [PhilosophyPhase]
    @Binding var selection: String?

    var body: some View {
        Picker("Start at", selection: Binding(
            get: { selection ?? phases.first?.id ?? "" },
            set: { selection = ($0 == phases.first?.id) ? nil : $0 }
        )) {
            ForEach(phases) { phase in
                Text(phase.name).tag(phase.id)
            }
        }
        .pickerStyle(.menu)
    }
}
