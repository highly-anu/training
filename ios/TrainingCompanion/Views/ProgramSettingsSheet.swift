import SwiftUI
import Combine

// MARK: - Program Settings Sheet (edit & regenerate an existing program)

@MainActor
private final class SettingsState: ObservableObject {
    @Published var selectedPhilosophyId: String {
        didSet {
            guard oldValue != selectedPhilosophyId else { return }
            selectedTrackId = nil
            startPhaseId = nil
        }
    }
    /// The program's own track and first phase, so a regenerate keeps them
    /// unless the athlete picks others; nil is the primary track / first phase.
    @Published var selectedTrackId: String?
    @Published var startPhaseId: String?
    @Published var numWeeks: Int
    @Published var startDate: Date
    @Published var eventDate: Date?
    @Published var constraints: GenerateConstraints
    /// A program of several tracks regenerates as all of them, each from the
    /// first week's own phase; empty for one track. A blend used to collapse
    /// to its first source here.
    let lanes: [ProgramLane]
    let laneNames: [String: String]

    @Published var isGenerating = false
    @Published var generationError: String? = nil
    @Published var didSucceed = false

    init(program: ServerProgram, weeks: [ProgramWeek], profile: UserProfile) {
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        // sourceGoalIds holds philosophy ids — the name predates the removal
        // of the goals layer.
        selectedPhilosophyId = program.sourceGoalIds.first ?? ""
        let composed = program.currentProgram?.compositionLanes ?? []
        if composed.count > 1 {
            lanes = program.currentProgram?.regenerateLanes(from: 0) ?? []
            laneNames = Dictionary(uniqueKeysWithValues: composed.map { ($0.key, $0.name) })
        } else if program.sourceGoalIds.filter({ $0 != "_blended" }).count > 1 {
            // A blend stored before compositions: each methodology on the
            // track written for the athlete's level.
            lanes = program.sourceGoalIds.filter { $0 != "_blended" }.map {
                ProgramLane(philosophyId: $0, trackId: nil, weight: program.sourceGoalWeights[$0] ?? 1)
            }
            laneNames = [:]
        } else {
            lanes = []
            laneNames = [:]
        }
        selectedTrackId = weeks.first?.trackId
        startPhaseId = weeks.first?.phaseId
        numWeeks = weeks.count
        startDate = program.programStartDate.flatMap { dayFmt.date(from: $0) } ?? Date()
        eventDate = program.eventDate.flatMap { dayFmt.date(from: $0) }

        var c = GenerateConstraints()
        if case .object(let saved)? = program.currentProgram?.extra["constraints"] {
            if case .array(let ids)? = saved["mastered_exercises"] {
                c.masteredExercises = ids.compactMap(\.stringValue)
            }
            if case .int(let count)? = saved["kettlebell_count"] { c.kettlebellCount = count }
            // The track's options the program was built with (Wildman's swing minutes).
            if case .object(let options)? = saved["contract_options"] {
                for (key, value) in options { if let s = value.stringValue { c.contractOptions[key] = s } }
            }
            // Any other implement the track asked for (`dumbbell_count`).
            for (key, value) in saved where key.hasSuffix("_count") && key != "kettlebell_count" {
                if case .int(let count) = value { c.implementCounts[key] = count }
            }
        }
        c.trainingLevel = profile.trainingLevel
        c.equipment = profile.equipment
        c.injuryFlags = profile.injuryFlags
        c.daysPerWeek = max(
            weeks.first.map { w in
                ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
                    .filter { !(w.schedule[$0] ?? []).isEmpty }.count
            } ?? 4, 2)
        c.sessionTimeMinutes = 60
        // Weeks generated before phases had ids: start at the first phase of
        // the first week's kind, as before.
        if weeks.first?.phaseId == nil { c.trainingPhase = weeks.first?.phase }
        constraints = c
    }
}

struct ProgramSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var settings: SettingsState
    @State private var isRegeneratingTail = false
    /// The rebuilt program, previewed before it replaces this one.
    @State private var preview: PreviewDraft? = nil
    /// The rest of this program rebuilt from this week, previewed before it
    /// is applied: (start week index, the sessions it changes, the draft).
    @State private var tailPreview: TailPreview? = nil

    struct TailPreview: Identifiable, Hashable {
        let draft: PreviewDraft
        let start: Int
        let changed: Set<String>
        var id: PreviewDraft.ID { draft.id }
    }

    /// Seeded from the live program once, at construction. This replaces a
    /// placeholder state object built from an empty program and field-copied
    /// in `.task`, which showed a spinner before the form every time.
    init(program: ServerProgram, weeks: [ProgramWeek], profile: UserProfile) {
        _settings = StateObject(wrappedValue: SettingsState(program: program, weeks: weeks, profile: profile))
    }

    private let trainingLevels = ClientVocab.trainingLevels

    private var philosophy: PhilosophyCard? {
        appState.philosophies.first { $0.id == settings.selectedPhilosophyId }
    }

    private var track: PhilosophyTrack? { philosophy?.track(settings.selectedTrackId) }

    private var weekOptions: [Int] {
        var options: Set<Int> = [4, 6, 8, 10, 12, 16, 20, 24, settings.numWeeks]
        if let track { options.insert(track.totalWeeks) }
        return options.sorted()
    }

    var body: some View {
        NavigationStack {
            // The title and Cancel button belong to the stack's content, not to
            // the NavigationStack itself — attached outside they never rendered,
            // and swipe-down was the only way out of this sheet.
            Form {
                methodologySection
                scheduleSection
                constraintsSection
                generateSection
                if let err = settings.generationError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppColor.warning).font(.footnote)
                    }
                }
            }
            .navigationTitle("Program Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .navigationDestination(item: $preview) { p in
                ProgramPreviewView(mode: .new, request: p.request, draft: p.draft,
                                   onEditSchedule: { preview = nil }) { started in
                    if started { settings.didSucceed = true }
                }
            }
            .navigationDestination(item: $tailPreview) { p in
                ProgramPreviewView(mode: .regenerate(start: p.start, changed: p.changed),
                                   request: p.draft.request, draft: p.draft.draft) { applied in
                    if applied { settings.didSucceed = true }
                }
            }
        }
        .task {
            await appState.loadPhilosophiesIfNeeded()
            await appState.loadInjuryFlagsIfNeeded()
        }
        .onChange(of: settings.didSucceed) { _, succeeded in
            if succeeded { dismiss() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var methodologySection: some View {
        if !settings.lanes.isEmpty {
            Section {
                let total = max(settings.lanes.reduce(0) { $0 + $1.weight }, 0.0001)
                ForEach(settings.lanes, id: \.self) { lane in
                    let phil = appState.philosophies.first { $0.id == lane.philosophyId }
                    let track = phil?.track(lane.trackId, level: settings.constraints.trainingLevel)
                    LabeledContent(lane.key.flatMap { settings.laneNames[$0] } ?? phil?.name ?? lane.philosophyId,
                                   value: "\(Int((lane.weight / total * 100).rounded())) %")
                    if let track { TrackPhaseList(track: track).padding(.vertical, 2) }
                }
            } header: {
                Text("Tracks")
            } footer: {
                Text("A new preview keeps these tracks and their weights. To change them, build a new program.")
            }
        } else {
            singleMethodologySection
        }
    }

    private var singleMethodologySection: some View {
        Section("Methodology") {
            if appState.philosophies.isEmpty {
                ProgressView()
            } else {
                Picker("Methodology", selection: $settings.selectedPhilosophyId) {
                    ForEach(appState.philosophies) { philosophy in
                        Text(philosophy.name).tag(philosophy.id)
                    }
                }
                .pickerStyle(.menu)
                if let tracks = philosophy?.tracks, tracks.count > 1 {
                    Picker("Track", selection: Binding(
                        get: { track?.id ?? "" },
                        set: { settings.selectedTrackId = $0; settings.startPhaseId = nil }
                    )) {
                        ForEach(tracks) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                }
                if let track {
                    TrackPhaseList(track: track)
                        .padding(.vertical, 4)
                }
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

            if let phases = track?.phases, phases.count > 1 {
                Section {
                    StartPhasePicker(phases: phases, selection: Binding(
                        get: { phases.contains(where: { $0.id == settings.startPhaseId }) ? settings.startPhaseId : nil },
                        set: { settings.startPhaseId = $0 }
                    ))
                    .disabled(settings.eventDate != nil)
                } header: {
                    Text("Starting Phase")
                } footer: {
                    if settings.eventDate != nil {
                        Text("Set from the event date: the phases are counted back from it.")
                    }
                }
            }

            EquipmentToggleSection(selection: $settings.constraints.equipment)
            InjuryToggleSection(selection: $settings.constraints.injuryFlags)
        }
    }

    private var generateSection: some View {
        Section {
            // The non-destructive option: keeps the weeks already behind the
            // athlete, rebuilds the rest with the profile's current settings
            // (level, equipment, injuries, schedule).
            Button {
                Task { await regenerateFromThisWeek() }
            } label: {
                HStack {
                    Spacer()
                    if isRegeneratingTail {
                        ProgressView()
                    } else {
                        Label("Preview from this week", systemImage: "arrow.uturn.forward")
                    }
                    Spacer()
                }
            }
            .appButton(.secondary)
            .disabled(settings.isGenerating || isRegeneratingTail)
            Button {
                Task { await regenerate() }
            } label: {
                HStack {
                    Spacer()
                    if settings.isGenerating {
                        ProgressView()
                    } else {
                        Label("Preview a new program", systemImage: "eye")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .appButton(.primary)
            .disabled(settings.isGenerating || settings.selectedPhilosophyId.isEmpty)
        } footer: {
            // Both preview first and ask before they change anything; the
            // current plan is kept in Program ▸ History with everything logged
            // against it.
            Text("Preview from this week keeps the weeks and days behind you and rebuilds the rest. Preview a new program builds a new one with these settings. Both show it first; nothing changes until you apply or start it.")
                .font(.caption)
        }
    }

    // MARK: - Generation

    /// Rebuilds the rest from this week and shows it; the preview's Apply saves.
    private func regenerateFromThisWeek() async {
        isRegeneratingTail = true
        settings.generationError = nil
        do {
            let p = try await appState.previewRegenerateFromCurrentWeek()
            tailPreview = TailPreview(draft: PreviewDraft(request: p.request, draft: p.draft),
                                      start: p.start, changed: p.changed)
        } catch {
            settings.generationError = error.localizedDescription
        }
        isRegeneratingTail = false
    }

    private func regenerate() async {
        settings.isGenerating = true
        settings.generationError = nil
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        var constraints = settings.constraints
        constraints.trackId = track?.id ?? settings.selectedTrackId
        // A start phase from another methodology's track would be an error on
        // the server; only send one this track has.
        let start = settings.startPhaseId.flatMap { id in
            (track?.phases.contains(where: { $0.id == id }) ?? false) ? id : nil
        }
        constraints.startPhase = settings.eventDate == nil ? start : nil
        if start != nil || settings.eventDate != nil { constraints.trainingPhase = nil }
        let composed = !settings.lanes.isEmpty
        if composed { constraints.trackId = nil; constraints.startPhase = nil; constraints.trainingPhase = nil }
        let request = GenerateProgramRequest(
            philosophyId: composed ? nil : settings.selectedPhilosophyId,
            lanes: composed ? settings.lanes.map { lane in
                var l = lane
                if settings.eventDate != nil { l.startPhase = nil; l.periodizationWeek = nil }
                return l
            } : nil,
            constraints: constraints,
            numWeeks: settings.numWeeks,
            startDate: dayFmt.string(from: settings.startDate),
            eventDate: settings.eventDate.map { dayFmt.string(from: $0) },
            persist: false
        )
        defer { settings.isGenerating = false }
        guard let api = appState.api else { return }
        do {
            preview = PreviewDraft(request: request, draft: try await api.generateProgramPreview(request))
        } catch {
            settings.generationError = "Regeneration failed. Please try again."
        }
    }
}
