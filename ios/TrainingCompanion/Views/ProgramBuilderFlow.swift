import SwiftUI
import Combine

// MARK: - Builder State

@MainActor
final class BuilderState: ObservableObject {
    // Step 1
    @Published var selectedPhilosophyId: String? = nil {
        didSet {
            guard oldValue != selectedPhilosophyId else { return }
            selectedTrackId = nil
            startPhaseId = nil
            lengthSetFor = nil
        }
    }

    // Step 2
    /// The track to run; nil is the methodology's primary track.
    @Published var selectedTrackId: String? = nil
    /// The phase to start at; nil is the track's first.
    @Published var startPhaseId: String? = nil
    @Published var numWeeks: Int = 12
    /// The track whose length `numWeeks` was last set from, so the default
    /// is applied once per track and never over the athlete's own choice.
    var lengthSetFor: String? = nil
    @Published var eventDate: Date? = nil
    @Published var startDate: Date = Date()

    // Step 3
    @Published var constraints = GenerateConstraints()

    // Generation
    @Published var isGenerating = false
    @Published var generationError: String? = nil
    @Published var didSucceed = false
    /// The generated draft, pushed as Program ▸ Preview; started from there.
    @Published var preview: PreviewDraft? = nil

    /// A blend: two or more tracks composed into one program
    /// (ProgramComposition.swift). One lane is the single-methodology path
    /// above, kept in `selectedPhilosophyId`.
    @Published var lanes: [BuilderLane] = [] {
        didSet {
            let single = lanes.count == 1 ? lanes[0].philosophyId : nil
            if selectedPhilosophyId != single { selectedPhilosophyId = single }
        }
    }
    var isComposed: Bool { lanes.count > 1 }

    var isStep1Valid: Bool { !lanes.isEmpty }
    var isStep3Valid: Bool { !constraints.equipment.isEmpty }

    /// Up to four methodologies; picking one again removes it (and any
    /// further track of it).
    func toggle(_ philosophy: PhilosophyCard) {
        if lanes.contains(where: { $0.philosophyId == philosophy.id }) {
            lanes.removeAll { $0.philosophyId == philosophy.id }
        } else if Set(lanes.map(\.philosophyId)).count < 4 {
            lanes.append(BuilderLane(philosophyId: philosophy.id))
        }
    }

    /// The track a lane runs: its pick, else the one for the athlete's level.
    func track(of lane: BuilderLane, in philosophies: [PhilosophyCard]) -> PhilosophyTrack? {
        philosophies.first { $0.id == lane.philosophyId }?.track(lane.trackId, level: constraints.trainingLevel)
    }

    /// A composition runs as long as its longest track.
    func applyLength(ofLanes philosophies: [PhilosophyCard]) {
        let key = "lanes:" + lanes.map { "\($0.philosophyId)/\(track(of: $0, in: philosophies)?.id ?? "")" }.joined(separator: ",")
        guard lengthSetFor != key else { return }
        lengthSetFor = key
        let longest = lanes.compactMap { track(of: $0, in: philosophies)?.totalWeeks }.max()
        if let longest, longest > 0 { numWeeks = longest }
    }

    /// The track the program will run: the picked one, else the one written
    /// for the athlete's level, else the primary — as the server picks it.
    func track(in philosophy: PhilosophyCard?) -> PhilosophyTrack? {
        philosophy?.track(selectedTrackId, level: constraints.trainingLevel)
    }

    /// A multi-phase track runs all its phases, so its length becomes the
    /// default duration — once per track. A single repeatable block keeps the
    /// athlete's choice.
    func applyLength(of track: PhilosophyTrack?) {
        guard let track, lengthSetFor != track.id else { return }
        lengthSetFor = track.id
        if track.phases.count > 1 { numWeeks = track.totalWeeks }
    }
}

/// One track of a blend in the builder: a methodology's track, its weight
/// (5–95, normalised when sent) and where it starts.
struct BuilderLane: Identifiable, Hashable {
    let id = UUID()
    let philosophyId: String
    var trackId: String? = nil
    var weight: Double = 50
    var startPhaseId: String? = nil
}

/// A generated program not yet started, and the request that made it —
/// what the builder and the settings sheet push as the preview.
struct PreviewDraft: Identifiable, Hashable {
    let id = UUID()
    let request: GenerateProgramRequest
    let draft: GeneratedProgram
    static func == (a: PreviewDraft, b: PreviewDraft) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
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
                case 1: BuilderStep1PhilosophyView(builder: builder)
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
            .navigationDestination(item: $builder.preview) { p in
                ProgramPreviewView(mode: .new, request: p.request, draft: p.draft,
                                   onEditSchedule: {
                                       builder.preview = nil
                                       step = 2
                                   }) { started in
                    if started { builder.didSucceed = true }
                }
            }
        }
        .task {
            await appState.loadPhilosophiesIfNeeded()
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
        guard builder.isComposed || builder.selectedPhilosophyId != nil else { return }
        builder.isGenerating = true
        builder.generationError = nil

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"
        let startStr = dayFmt.string(from: builder.startDate)
        let eventStr = builder.eventDate.map { dayFmt.string(from: $0) }

        // The track and its start phase, by id. The phase picker used to send
        // `phase` only, a key the server never read, so every phone-built
        // program started wherever the server defaulted.
        var constraints = builder.constraints
        constraints.trackId = builder.selectedTrackId
        constraints.startPhase = builder.eventDate == nil ? builder.startPhaseId : nil
        constraints.phase = nil
        constraints.trainingPhase = nil

        // A draft: nothing is saved until the preview's Start. This used to
        // post `persist: true` and throw the answer away, so a refusal kept
        // the old program with nothing said.
        // Several tracks: each its own track and start phase (none with an
        // event date, which puts every track's last phase on it).
        let total = builder.lanes.reduce(0) { $0 + $1.weight }
        let lanes: [ProgramLane]? = builder.isComposed ? builder.lanes.map {
            ProgramLane(philosophyId: $0.philosophyId, trackId: $0.trackId,
                        weight: $0.weight / (total > 0 ? total : 1),
                        startPhase: builder.eventDate == nil ? $0.startPhaseId : nil)
        } : nil
        if lanes != nil { constraints.trackId = nil; constraints.startPhase = nil }
        let request = GenerateProgramRequest(
            philosophyId: lanes == nil ? builder.selectedPhilosophyId : nil,
            lanes: lanes,
            constraints: constraints,
            numWeeks: builder.numWeeks,
            startDate: startStr,
            eventDate: eventStr,
            persist: false
        )
        defer { builder.isGenerating = false }
        guard let api = appState.api else {
            builder.generationError = "Sign in to generate a program."
            return
        }
        do {
            // A refusal is previewed too: it says what alone would let it build.
            let draft = try await api.generateProgramPreview(request)
            builder.preview = PreviewDraft(request: request, draft: draft)
        } catch {
            builder.generationError = "Generation failed. Please try again."
        }
    }
}

// MARK: - Step 1: Methodology

/// Picks the philosophy the program is generated from.
///
/// This was a "goal" grid fed by `GET /api/goals`, a route removed on
/// 2026-04-25 when programs became philosophy-driven. The grid never
/// populated, so Next stayed disabled and no program could be generated from
/// the phone. The request has sent `philosophy_id` all along; this is the
/// picker that matches it.
struct BuilderStep1PhilosophyView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState
    @State private var detail: PhilosophyCard? = nil
    @State private var loadFailed = false

    let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a methodology")
                        .font(.headline)
                    Text("The training philosophy the program is built from — or up to four, blended into one program that shares your week. Tap ⓘ to read what each believes and how it trains.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if appState.philosophies.isEmpty {
                    if loadFailed {
                        VStack(spacing: 8) {
                            Text("Couldn't load methodologies.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Retry") { Task { await load() } }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(appState.philosophies) { philosophy in
                            philosophyCard(philosophy)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .task { await load() }
        .sheet(item: $detail) { philosophy in
            PhilosophyDetailSheet(philosophy: philosophy)
        }
    }

    private func load() async {
        loadFailed = false
        await appState.loadPhilosophiesIfNeeded()
        loadFailed = appState.philosophies.isEmpty
    }

    private func philosophyCard(_ philosophy: PhilosophyCard) -> some View {
        let selected = builder.lanes.contains { $0.philosophyId == philosophy.id }
        let topModality = philosophy.bias?.first

        return Button {
            AppHaptics.light()
            builder.toggle(philosophy)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let mod = topModality {
                        Image(systemName: ModalityStyle.icon(for: mod))
                            .foregroundStyle(ModalityStyle.color(for: mod))
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.trailing, 28)   // room for the ⓘ overlay
                Text(philosophy.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Text(philosophy.summary ?? "")
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
        .overlay(alignment: .topTrailing) {
            Button {
                detail = philosophy
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(philosophy.name)")
        }
    }
}

/// What a methodology believes and how it trains — the phone's slice of the
/// web Explore philosophy detail, shown from the builder so the choice is
/// informed rather than a name on a card.
// MARK: - Step 2: Schedule

struct BuilderStep2ScheduleView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    private let dayOptions = Array(2...7)

    private var philosophy: PhilosophyCard? {
        appState.philosophies.first { $0.id == builder.selectedPhilosophyId }
    }

    /// The standard lengths plus the track's own and the current choice, so
    /// a 31-week track is selectable.
    private var weekOptions: [Int] {
        var options: Set<Int> = [4, 6, 8, 10, 12, 16, 20, 24, builder.numWeeks]
        if let track = builder.track(in: philosophy) { options.insert(track.totalWeeks) }
        for lane in builder.lanes {
            if let t = builder.track(of: lane, in: appState.philosophies) { options.insert(t.totalWeeks) }
        }
        return options.sorted()
    }

    var body: some View {
        Form {
            if builder.isComposed {
                LaneSections(builder: builder)
            } else if let tracks = philosophy?.tracks, !tracks.isEmpty {
                trackSection(tracks)
            }

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
        .onAppear {
            if builder.isComposed { builder.applyLength(ofLanes: appState.philosophies) }
            else { builder.applyLength(of: builder.track(in: philosophy)) }
        }
    }

    /// The methodology's tracks, each with its own phases. One track is shown
    /// for what it is; two or more are a choice.
    private func trackSection(_ tracks: [PhilosophyTrack]) -> some View {
        let active = builder.track(in: philosophy)
        return Section {
            ForEach(tracks) { track in
                if tracks.count > 1 {
                    Button {
                        AppHaptics.light()
                        builder.selectedTrackId = track.id
                        builder.startPhaseId = nil
                        builder.applyLength(of: track)
                    } label: {
                        TrackChoiceRow(track: track, selected: track.id == active?.id,
                                       primary: track.id == philosophy?.primaryTrack?.id)
                    }
                    .buttonStyle(.plain)
                } else {
                    TrackChoiceRow(track: track, selected: false, primary: false)
                }
            }
        } header: {
            Text(tracks.count > 1 ? "Track" : "Phases")
        } footer: {
            if tracks.count > 1 {
                Text("Each track is one way to follow this methodology, in its own phases.")
            }
        }
    }
}

/// One track of a methodology as a choice: its name, description and phases
/// (TrackPhaseList). The builder's track list and a blend's tracks.
struct TrackChoiceRow: View {
    let track: PhilosophyTrack
    let selected: Bool
    let primary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(track.name)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if primary {
                    Text("Primary")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                }
            }
            if let text = track.description, !text.isEmpty {
                Text(text)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            TrackPhaseList(track: track)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A blend's tracks (step 2): each methodology runs one of its tracks in its
/// own phases at its weight, and may add another of its tracks. The server
/// composes them into one week; the preview says how the days were shared
/// and what gave way (design-system §6.22).
struct LaneSections: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    private var total: Double { max(builder.lanes.reduce(0) { $0 + $1.weight }, 1) }

    var body: some View {
        ForEach($builder.lanes) { $lane in
            laneSection($lane)
        }
        let addable = addableTracks
        if !addable.isEmpty {
            Section {
                ForEach(addable, id: \.0.id) { philosophy, track in
                    Button {
                        AppHaptics.light()
                        builder.lanes.append(BuilderLane(philosophyId: philosophy.id, trackId: track.id))
                        builder.applyLength(ofLanes: appState.philosophies)
                    } label: {
                        Label("Add another \(philosophy.name) track", systemImage: "plus.circle")
                    }
                }
            } footer: {
                Text("Every track runs in its own phases on your week together; its weight is its share of your days.")
            }
        }
    }

    /// A methodology in the blend with a track not in it yet, and that track.
    private var addableTracks: [(PhilosophyCard, PhilosophyTrack)] {
        var seen: [String] = []
        var out: [(PhilosophyCard, PhilosophyTrack)] = []
        for lane in builder.lanes where !seen.contains(lane.philosophyId) {
            seen.append(lane.philosophyId)
            guard let phil = appState.philosophies.first(where: { $0.id == lane.philosophyId }) else { continue }
            let used = Set(builder.lanes.filter { $0.philosophyId == phil.id }
                .compactMap { builder.track(of: $0, in: appState.philosophies)?.id })
            if let next = (phil.tracks ?? []).first(where: { !used.contains($0.id) }) { out.append((phil, next)) }
        }
        return out
    }

    private func laneSection(_ lane: Binding<BuilderLane>) -> some View {
        let phil = appState.philosophies.first { $0.id == lane.wrappedValue.philosophyId }
        let active = builder.track(of: lane.wrappedValue, in: appState.philosophies)
        let siblings = builder.lanes.filter { $0.id != lane.wrappedValue.id && $0.philosophyId == lane.wrappedValue.philosophyId }
            .compactMap { builder.track(of: $0, in: appState.philosophies)?.id }
        let tracks = phil?.tracks ?? []
        return Section {
            ForEach(tracks.count > 1 ? tracks : (active.map { [$0] } ?? [])) { track in
                let taken = siblings.contains(track.id)
                Button {
                    AppHaptics.light()
                    lane.wrappedValue.trackId = track.id
                    lane.wrappedValue.startPhaseId = nil
                    builder.applyLength(ofLanes: appState.philosophies)
                } label: {
                    TrackChoiceRow(track: track, selected: tracks.count > 1 && track.id == active?.id, primary: false)
                }
                .buttonStyle(.plain)
                .disabled(tracks.count < 2 || taken)
                .opacity(taken ? 0.4 : 1)
            }
            HStack {
                Text("Weight")
                Slider(value: lane.weight, in: 5...95, step: 5)
                Text("\(Int((lane.wrappedValue.weight / total * 100).rounded())) %")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            if !siblings.isEmpty {
                Button("Remove this track", role: .destructive) {
                    builder.lanes.removeAll { $0.id == lane.wrappedValue.id }
                }
            }
        } header: {
            Text(phil?.name ?? lane.wrappedValue.philosophyId)
        }
    }
}

// MARK: - Step 3: Constraints

struct BuilderStep3ConstraintsView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState

    private let trainingLevels = ["novice", "intermediate", "advanced", "elite"]

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

// MARK: - Step 4: Review & Generate

struct BuilderStep4ReviewView: View {
    @ObservedObject var builder: BuilderState
    @EnvironmentObject var appState: AppState
    let onGenerate: () async -> Void
    /// What the athlete typed for each starting weight, kept as typed ("62.").
    @State private var startingText: [String: String] = [:]

    private var requirements: TrackEntryRequirements? {
        if builder.isComposed {
            // What any of the tracks asks before it runs.
            return .merged(builder.lanes.compactMap { builder.track(of: $0, in: appState.philosophies)?.entryRequirements },
                           level: builder.constraints.trainingLevel)
        }
        return builder.track(in: appState.philosophies.first { $0.id == builder.selectedPhilosophyId })?.entryRequirements
    }
    private var entryReady: Bool {
        guard let r = requirements else { return true }
        return r.trainingLevels.contains(builder.constraints.trainingLevel)
            && Set(requiredSkills).isSubset(of: Set(builder.constraints.masteredExercises))
            && (r.kettlebellCount < 2 || (builder.constraints.kettlebellCount ?? 0) >= 2)
    }
    private var requiredSkills: [String] {
        requirements?.masteredExercisesByLevel?[builder.constraints.trainingLevel]
            ?? requirements?.masteredExercises ?? []
    }

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
                    if r.kettlebellCount >= 2 {
                        Toggle("I have two appropriate matching kettlebells", isOn: Binding(
                            get: { (builder.constraints.kettlebellCount ?? 0) >= 2 },
                            set: { builder.constraints.kettlebellCount = $0 ? 2 : 1 }))
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

            Section {
                Button {
                    Task { await onGenerate() }
                } label: {
                    HStack {
                        Spacer()
                        if builder.isGenerating {
                            ProgressView()
                        } else {
                            Label("Preview Program", systemImage: "eye")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(builder.isGenerating || !entryReady)
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

    private let trainingLevels = ["novice", "intermediate", "advanced", "elite"]

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
                            .foregroundStyle(.orange).font(.footnote)
                    }
                }
            }
            .navigationTitle("Program Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
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
            .buttonStyle(.bordered)
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
            .buttonStyle(.borderedProminent)
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
