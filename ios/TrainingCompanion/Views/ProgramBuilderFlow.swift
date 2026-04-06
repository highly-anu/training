import SwiftUI
import Combine

// MARK: - Builder State

@MainActor
final class BuilderState: ObservableObject {
    // Step 1
    @Published var selectedGoalId: String? = nil

    // Step 2
    @Published var numWeeks: Int = 12
    @Published var eventDate: Date? = nil
    @Published var startDate: Date = Date()

    // Step 3
    @Published var constraints = GenerateConstraints()

    // Generation
    @Published var isGenerating = false
    @Published var generationError: String? = nil
    @Published var didSucceed = false

    var isStep1Valid: Bool { selectedGoalId != nil }
    var isStep3Valid: Bool { !constraints.equipment.isEmpty }
}

// MARK: - Program Builder Flow

struct ProgramBuilderFlow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var builder = BuilderState()
    @State private var step = 1

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 1: BuilderStep1GoalView(builder: builder)
                case 2: BuilderStep2ScheduleView(builder: builder)
                case 3: BuilderStep3ConstraintsView(builder: builder)
                case 4: BuilderStep4ReviewView(builder: builder, onGenerate: generateProgram)
                default: EmptyView()
                }
            }
            .navigationTitle("New Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 1 {
                        Button("Back") { step -= 1 }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if step < 4 {
                        Button("Next") { step += 1 }
                            .fontWeight(.semibold)
                            .disabled(!canAdvance)
                    }
                }
            }
        }
        .task {
            await appState.loadGoalsIfNeeded()
            await appState.loadInjuryFlagsIfNeeded()
            // Pre-fill constraints from profile
            builder.constraints.trainingLevel = appState.profile.trainingLevel
            builder.constraints.equipment = appState.profile.equipment
            builder.constraints.injuryFlags = appState.profile.injuryFlags
        }
        .onChange(of: builder.didSucceed) { _, succeeded in
            if succeeded { dismiss() }
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return builder.isStep1Valid
        case 2: return true
        case 3: return true
        default: return true
        }
    }

    private func generateProgram() async {
        guard let goalId = builder.selectedGoalId else { return }
        builder.isGenerating = true
        builder.generationError = nil

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let startStr = dayFmt.string(from: builder.startDate)
        let eventStr = builder.eventDate.map { dayFmt.string(from: $0) }

        let request = GenerateProgramRequest(
            goalId: goalId,
            constraints: builder.constraints,
            numWeeks: builder.numWeeks,
            startDate: startStr,
            eventDate: eventStr
        )

        do {
            try await appState.generateProgramViaAPI(request)
        } catch {
            builder.generationError = "Generation failed. Please try again."
        }

        // Reload program into AppState
        await appState.loadProgram()
        builder.isGenerating = false
        builder.didSucceed = appState.serverProgram != nil
    }
}

// MARK: - Step 1: Goal Selection

struct BuilderStep1GoalView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose a training goal")
                    .font(.headline)
                    .padding(.horizontal)

                if appState.goals.isEmpty {
                    ProgressView().padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(appState.goals) { goal in
                            goalCard(goal)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func goalCard(_ goal: GoalProfile) -> some View {
        let selected = builder.selectedGoalId == goal.id
        let topModality = goal.priorities.sorted { $0.value > $1.value }.first

        return Button {
            builder.selectedGoalId = selected ? nil : goal.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let mod = topModality {
                        Image(systemName: ModalityStyle.icon(for: mod.key))
                            .foregroundStyle(ModalityStyle.color(for: mod.key))
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                Text(goal.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Text(goal.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 2: Schedule

struct BuilderStep2ScheduleView: View {
    @ObservedObject var builder: BuilderState

    private let weekOptions = [4, 6, 8, 10, 12, 16, 20, 24]
    private let dayOptions = Array(2...7)

    var body: some View {
        Form {
            Section("Duration") {
                Picker("Number of Weeks", selection: $builder.numWeeks) {
                    ForEach(weekOptions, id: \.self) { w in
                        Text("\(w) weeks").tag(w)
                    }
                }

                DatePicker("Start Date", selection: $builder.startDate, displayedComponents: .date)
            }

            Section("Training Days") {
                Stepper(
                    "Days per Week: \(builder.constraints.daysPerWeek)",
                    value: Binding(
                        get: { builder.constraints.daysPerWeek },
                        set: { builder.constraints.daysPerWeek = $0 }
                    ),
                    in: 2...7
                )
                Stepper(
                    "Session Duration: \(builder.constraints.sessionTimeMinutes) min",
                    value: Binding(
                        get: { builder.constraints.sessionTimeMinutes },
                        set: { builder.constraints.sessionTimeMinutes = $0 }
                    ),
                    in: 20...180, step: 10
                )
            }

            Section("Event Target (optional)") {
                Toggle("Has Target Event", isOn: Binding(
                    get: { builder.eventDate != nil },
                    set: { if $0 { builder.eventDate = Date().addingTimeInterval(60 * 60 * 24 * 84) } else { builder.eventDate = nil } }
                ))
                if builder.eventDate != nil {
                    DatePicker("Event Date", selection: Binding(
                        get: { builder.eventDate ?? Date() },
                        set: { builder.eventDate = $0 }
                    ), displayedComponents: .date)
                }
            }
        }
    }
}

// MARK: - Step 3: Constraints

struct BuilderStep3ConstraintsView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    private let trainingLevels = ["novice", "intermediate", "advanced", "elite"]
    private let phases = ["base", "build", "peak", "taper"]

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

            Section("Equipment") {
                ForEach(EquipmentItem.all) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { builder.constraints.equipment.contains(item.id) },
                        set: { on in
                            if on { builder.constraints.equipment.append(item.id) }
                            else { builder.constraints.equipment.removeAll { $0 == item.id } }
                        }
                    ))
                }
            }

            Section("Active Injuries") {
                ForEach(appState.injuryFlagDefs) { flag in
                    Toggle(flag.name, isOn: Binding(
                        get: { builder.constraints.injuryFlags.contains(flag.id) },
                        set: { on in
                            if on { builder.constraints.injuryFlags.append(flag.id) }
                            else { builder.constraints.injuryFlags.removeAll { $0 == flag.id } }
                        }
                    ))
                }
            }

            Section("Starting Phase (optional)") {
                Picker("Phase", selection: Binding(
                    get: { builder.constraints.phase ?? "base" },
                    set: { builder.constraints.phase = $0 }
                )) {
                    ForEach(phases, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

// MARK: - Step 4: Review & Generate

struct BuilderStep4ReviewView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState
    let onGenerate: () async -> Void

    private let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()

    var body: some View {
        List {
            Section("Goal") {
                if let goalId = builder.selectedGoalId,
                   let goal = appState.goals.first(where: { $0.id == goalId }) {
                    LabeledContent("Goal", value: goal.name)
                }
            }

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
                LabeledContent("Phase", value: (builder.constraints.phase ?? "base").capitalized)
                if !builder.constraints.equipment.isEmpty {
                    LabeledContent("Equipment", value: "\(builder.constraints.equipment.count) items")
                }
                if !builder.constraints.injuryFlags.isEmpty {
                    LabeledContent("Injuries", value: "\(builder.constraints.injuryFlags.count) flags")
                }
            }

            Section {
                Button {
                    Task { await onGenerate() }
                } label: {
                    HStack {
                        Spacer()
                        if builder.isGenerating {
                            ProgressView()
                        } else {
                            Label("Generate Program", systemImage: "sparkles")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(builder.isGenerating)
            }

            if let error = builder.generationError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
        }
    }
}

// MARK: - AppState generation helper

extension AppState {
    /// Called by ProgramBuilderFlow to trigger program generation then reload.
    func generateProgramViaAPI(_ request: GenerateProgramRequest) async throws {
        guard let api else { throw APIError.unauthenticated }
        try await api.generateProgram(request)
    }
}

// MARK: - Program Settings Sheet (edit & regenerate an existing program)

@MainActor
private final class SettingsState: ObservableObject {
    @Published var selectedGoalId: String
    @Published var numWeeks: Int
    @Published var startDate: Date
    @Published var eventDate: Date?
    @Published var constraints: GenerateConstraints

    @Published var isGenerating = false
    @Published var generationError: String? = nil
    @Published var didSucceed = false

    init(program: ServerProgram, weeks: [ProgramWeek], profile: UserProfile) {
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        selectedGoalId = program.sourceGoalIds.first ?? ""
        numWeeks = weeks.count
        startDate = program.programStartDate.flatMap { dayFmt.date(from: $0) } ?? Date()
        eventDate = program.eventDate.flatMap { dayFmt.date(from: $0) }

        var c = GenerateConstraints()
        c.trainingLevel = profile.trainingLevel
        c.equipment = profile.equipment
        c.injuryFlags = profile.injuryFlags
        c.daysPerWeek = max(
            weeks.first.map { w in
                ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
                    .filter { !(w.schedule[$0] ?? []).isEmpty }.count
            } ?? 4, 2)
        c.sessionTimeMinutes = 60
        c.phase = weeks.first?.phase
        constraints = c
    }
}

struct ProgramSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var settings: SettingsState = {
        // Placeholder — real init happens in .task below via onAppear trick.
        SettingsState(program: ServerProgram(currentProgram: nil, programStartDate: nil,
                                             eventDate: nil, sourceGoalIds: []),
                      weeks: [], profile: .default)
    }()
    @State private var isInitialized = false
    @State private var showConfirm = false

    private let weekOptions = [4, 6, 8, 10, 12, 16, 20, 24]
    private let trainingLevels = ["novice", "intermediate", "advanced", "elite"]
    private let phases = ["base", "build", "peak", "taper"]

    var body: some View {
        NavigationStack {
            if !isInitialized {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    goalSection
                    scheduleSection
                    constraintsSection
                    generateSection
                    if let err = settings.generationError {
                        Section {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).font(.footnote)
                        }
                    }
                }
            }
        }
        .navigationTitle("Program Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
        }
        .task {
            await appState.loadGoalsIfNeeded()
            await appState.loadInjuryFlagsIfNeeded()
            if let prog = appState.serverProgram {
                let fresh = SettingsState(program: prog,
                                          weeks: appState.allWeeks,
                                          profile: appState.profile)
                settings.selectedGoalId = fresh.selectedGoalId
                settings.numWeeks = fresh.numWeeks
                settings.startDate = fresh.startDate
                settings.eventDate = fresh.eventDate
                settings.constraints = fresh.constraints
            }
            isInitialized = true
        }
        .onChange(of: settings.didSucceed) { _, succeeded in
            if succeeded { dismiss() }
        }
    }

    // MARK: - Sections

    private var goalSection: some View {
        Section("Goal") {
            if appState.goals.isEmpty {
                ProgressView()
            } else {
                Picker("Goal", selection: $settings.selectedGoalId) {
                    ForEach(appState.goals) { goal in
                        Text(goal.name).tag(goal.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Duration", selection: $settings.numWeeks) {
                ForEach(weekOptions, id: \.self) { Text("\($0) weeks").tag($0) }
            }
            DatePicker("Start Date", selection: $settings.startDate,
                       displayedComponents: .date)
            Toggle("Has Target Event", isOn: Binding(
                get: { settings.eventDate != nil },
                set: { if $0 { settings.eventDate = Date().addingTimeInterval(60*60*24*84) }
                      else { settings.eventDate = nil } }
            ))
            if settings.eventDate != nil {
                DatePicker("Event Date",
                           selection: Binding(get: { settings.eventDate ?? Date() },
                                              set: { settings.eventDate = $0 }),
                           displayedComponents: .date)
            }
            Stepper("Days per Week: \(settings.constraints.daysPerWeek)",
                    value: $settings.constraints.daysPerWeek, in: 2...7)
            Stepper("Session Duration: \(settings.constraints.sessionTimeMinutes) min",
                    value: $settings.constraints.sessionTimeMinutes, in: 20...180, step: 10)
        }
    }

    private var constraintsSection: some View {
        Group {
            Section("Training Level") {
                Picker("Level", selection: $settings.constraints.trainingLevel) {
                    ForEach(trainingLevels, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section("Starting Phase") {
                Picker("Phase", selection: Binding(
                    get: { settings.constraints.phase ?? "base" },
                    set: { settings.constraints.phase = $0 }
                )) {
                    ForEach(phases, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section("Equipment") {
                ForEach(EquipmentItem.all) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { settings.constraints.equipment.contains(item.id) },
                        set: { on in
                            if on { settings.constraints.equipment.append(item.id) }
                            else { settings.constraints.equipment.removeAll { $0 == item.id } }
                        }
                    ))
                }
            }

            Section("Active Injuries") {
                ForEach(appState.injuryFlagDefs) { flag in
                    Toggle(flag.name, isOn: Binding(
                        get: { settings.constraints.injuryFlags.contains(flag.id) },
                        set: { on in
                            if on { settings.constraints.injuryFlags.append(flag.id) }
                            else { settings.constraints.injuryFlags.removeAll { $0 == flag.id } }
                        }
                    ))
                }
            }
        }
    }

    private var generateSection: some View {
        Section {
            Button {
                showConfirm = true
            } label: {
                HStack {
                    Spacer()
                    if settings.isGenerating {
                        ProgressView()
                    } else {
                        Label("Regenerate Program", systemImage: "sparkles")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(settings.isGenerating || settings.selectedGoalId.isEmpty)
        } footer: {
            Text("This replaces your current program. Completed sessions are preserved.")
                .font(.caption)
        }
        .confirmationDialog("Regenerate Program?",
                             isPresented: $showConfirm,
                             titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) {
                Task { await regenerate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current program and all logged session progress will be permanently deleted and replaced with the new settings.")
        }
    }

    // MARK: - Generation

    private func regenerate() async {
        settings.isGenerating = true
        settings.generationError = nil
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let request = GenerateProgramRequest(
            goalId: settings.selectedGoalId,
            constraints: settings.constraints,
            numWeeks: settings.numWeeks,
            startDate: dayFmt.string(from: settings.startDate),
            eventDate: settings.eventDate.map { dayFmt.string(from: $0) }
        )
        do {
            try await appState.generateProgramViaAPI(request)
            await appState.loadProgram()
            settings.didSucceed = true
        } catch {
            settings.generationError = "Regeneration failed. Please try again."
        }
        settings.isGenerating = false
    }
}
