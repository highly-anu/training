import SwiftUI

// MARK: - Step 4: Review & Generate

struct BuilderStep4ReviewView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState
    /// What the athlete typed for each starting weight, kept as typed ("62.").
    @State private var startingText: [String: String] = [:]

    private var requirements: TrackEntryRequirements? { builder.requirements(in: appState.philosophies) }
    private var requiredSkills: [String] { builder.requiredSkills(in: appState.philosophies) }

    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        List {
            if builder.isComposed {
                Section {
                    let total = max(builder.lanes.reduce(0) { $0 + $1.weight }, 1)
                    ForEach(builder.lanes) { lane in
                        let phil = appState.philosophies.first { $0.id == lane.philosophyId }
                        let track = builder.track(of: lane, in: appState.philosophies)
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(phil?.name ?? lane.philosophyId,
                                           value: "\(Int((lane.weight / total * 100).rounded())) %")
                            if let track {
                                Text(track.name + (builder.eventDate == nil
                                    ? (track.phases.first { $0.id == lane.startPhaseId }.map { " · from \($0.name)" } ?? "")
                                    : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                                TrackPhaseList(track: track)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Tracks")
                } footer: {
                    Text("One program from all of them, sharing your week by weight. The preview shows how the days were shared and what had to give.")
                }
            }
            if !builder.isComposed { Section("Methodology") {
                if let id = builder.selectedPhilosophyId,
                   let philosophy = appState.philosophies.first(where: { $0.id == id }) {
                    LabeledContent("Methodology", value: philosophy.name)
                    if let track = builder.track(in: philosophy) {
                        LabeledContent("Track", value: track.name)
                        if builder.eventDate == nil, let start = builder.startPhaseId,
                           let phase = track.phases.first(where: { $0.id == start }) {
                            LabeledContent("Starts at", value: phase.name)
                        }
                        TrackPhaseList(track: track)
                            .padding(.vertical, 4)
                    }
                }
            } }

            Section("Schedule") {
                LabeledContent("Duration", value: "\(builder.numWeeks) weeks")
                LabeledContent("Start", value: dayFmt.string(from: builder.startDate))
                if let event = builder.eventDate {
                    LabeledContent("Event", value: dayFmt.string(from: event))
                }
                LabeledContent("Days/Week", value: "\(builder.constraints.daysPerWeek)")
                LabeledContent("Session Duration", value: "\(builder.constraints.sessionTimeMinutes) min")
            }

            Section("Constraints") {
                LabeledContent("Level", value: builder.constraints.trainingLevel.capitalized)
                if !builder.constraints.equipment.isEmpty {
                    LabeledContent("Equipment", value: "\(builder.constraints.equipment.count) items")
                }
                if !builder.constraints.injuryFlags.isEmpty {
                    LabeledContent("Injuries", value: "\(builder.constraints.injuryFlags.count) flags")
                }
            }

            if let r = requirements {
                Section("Track readiness") {
                    if !r.trainingLevels.contains(builder.constraints.trainingLevel) {
                        Text("This track supports \(r.trainingLevels.joined(separator: ", ")) athletes.")
                    }
                    ForEach(requiredSkills, id: \.self) { id in
                        Toggle("Controlled technique: " + (r.exerciseNames?[id] ?? id.replacingOccurrences(of: "_", with: " ")), isOn: Binding(
                            get: { builder.constraints.masteredExercises.contains(id) },
                            set: { checked in
                                builder.constraints.masteredExercises.removeAll { $0 == id }
                                if checked { builder.constraints.masteredExercises.append(id) }
                            }))
                    }
                    ForEach(r.neededImplements, id: \.countKey) { imp in
                        Toggle("I have \(imp.number) appropriate matching \(imp.plural)", isOn: Binding(
                            get: { builder.constraints.count(for: imp.countKey) >= imp.count },
                            set: { builder.constraints.setCount($0 ? imp.count : 1, for: imp.countKey) }))
                    }
                }
                ForEach(r.options ?? []) { opt in
                    Section {
                        Picker(opt.label, selection: Binding(
                            get: { builder.constraints.contractOptions[opt.id] ?? opt.default },
                            set: { builder.constraints.contractOptions[opt.id] = $0 })) {
                            ForEach(opt.choices) { c in
                                Text(c.id == opt.default ? "\(c.label) (default)" : c.label).tag(c.id)
                            }
                        }
                        .pickerStyle(.inline)
                    } footer: {
                        let chosen = builder.constraints.contractOptions[opt.id] ?? opt.default
                        if let text = opt.choices.first(where: { $0.id == chosen })?.description { Text(text) }
                    }
                }
                if let lifts = r.startingLoads, !lifts.isEmpty {
                    Section {
                        ForEach(lifts) { lift in
                            HStack {
                                Text(lift.name)
                                Spacer()
                                TextField("kg", text: Binding(
                                    get: { startingText[lift.id]
                                        ?? builder.constraints.startingLoadsKg?[lift.id].map(LoadFormat.kilograms) ?? "" },
                                    set: { text in
                                        startingText[lift.id] = text
                                        var loads = builder.constraints.startingLoadsKg ?? [:]
                                        let kg = Double(text.replacingOccurrences(of: ",", with: "."))
                                        loads[lift.id] = (kg ?? 0) > 0 ? kg : nil
                                        builder.constraints.startingLoadsKg = loads.isEmpty ? nil : loads
                                    }))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 72)
                            }
                        }
                    } header: {
                        Text("Starting weights")
                    } footer: {
                        Text("The weight you last made on each lift, if you know it. Leave one empty and its first session works up to a weight from the empty bar.")
                    }
                }
            }

            if let error = builder.generationError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppColor.warning)
                        .font(.footnote)
                }
            }
        }
    }
}
