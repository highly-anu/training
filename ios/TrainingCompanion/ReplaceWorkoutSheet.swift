import SwiftUI

/// Replace a planned session, or (`mode: .add`) add one on the fly to today or
/// a later day — a rest day's mobility (design-system §6.43). An added session
/// may come from any package, and counts only once it is done.
struct ReplaceWorkoutSheet: View {
    enum Mode { case replace, add }

    let api: APIClient
    let weekIndex: Int
    let dayName: String
    var sessionIndex: Int = 0
    /// The session replaced; none when adding.
    var session: ProgramSession? = nil
    var mode: Mode = .replace

    /// The kinds offered when adding: what a rest day usually takes.
    static let addKinds = ["mobility", "movement_skill", "aerobic_base", "durability", "rehab"]
    @State private var kind = "mobility"
    private var adding: Bool { mode == .add }
    private var modality: String { adding ? kind : (session?.modality ?? kind) }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Tab = .browse

    // Browse tab
    @State private var archetypes: [AppArchetype] = []
    @State private var isLoadingArchetypes = false
    @State private var searchQuery = ""
    @State private var sameModalityOnly = true
    @State private var selectedArchId: String? = nil

    // Generate tab
    @State private var sessionMinutes: Double = 60
    @State private var fatigueState: FatigueState = .normal

    // Shared
    @State private var preview: ProgramSession? = nil
    @State private var isGenerating = false
    @State private var generateError: String? = nil

    enum Tab { case browse, generate }

    enum FatigueState: String, CaseIterable, Identifiable {
        case fresh, normal, accumulated, overreached
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private var filtered: [AppArchetype] {
        let q = searchQuery.lowercased()
        return archetypes
            .filter { !sameModalityOnly || $0.modality == modality }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q) }
            .sorted {
                let aMatch = $0.modality == modality ? 0 : 1
                let bMatch = $1.modality == modality ? 0 : 1
                return aMatch != bMatch ? aMatch < bMatch : $0.name < $1.name
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $selectedTab) {
                    Text("Browse").tag(Tab.browse)
                    Text("Generate").tag(Tab.generate)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()

                if selectedTab == .browse {
                    browseTab
                } else {
                    generateTab
                }

                if let preview {
                    previewCard(preview)
                } else if let error = generateError {
                    errorBanner(error)
                }
            }
            .navigationTitle(adding ? "Add a Session" : "Replace Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if adding { selectedTab = .generate }
                guard archetypes.isEmpty else { return }
                isLoadingArchetypes = true
                archetypes = (try? await api.fetchArchetypes()) ?? []
                isLoadingArchetypes = false
            }
        }
    }

    // MARK: - Browse Tab

    private var browseTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search archetypes…", text: $searchQuery)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                Toggle("Same modality only", isOn: $sameModalityOnly)
                    .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            if isLoadingArchetypes {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Text("No archetypes match")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { arch in
                    Button {
                        selectedArchId = arch.id
                        preview = nil
                        generateError = nil
                        Task { await generateWithArchetype(arch) }
                    } label: {
                        archetypeRow(arch)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
                }
                .listStyle(.plain)
            }
        }
    }

    private func archetypeRow(_ arch: AppArchetype) -> some View {
        let isSelected = selectedArchId == arch.id
        return HStack(spacing: 12) {
            Image(systemName: ModalityStyle.icon(for: arch.modality))
                .foregroundStyle(ModalityStyle.color(for: arch.modality))
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(arch.name)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .blue : .primary)
                Text(arch.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected && isGenerating {
                ProgressView().scaleEffect(0.8)
            } else {
                if let mins = arch.durationEstimateMinutes {
                    Label("\(mins)m", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(isGenerating && selectedArchId != arch.id ? 0.4 : 1)
    }

    // MARK: - Generate Tab

    private var generateTab: some View {
        Form {
            if adding {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(Self.addKinds, id: \.self) { k in
                            Label(ModalityStyle.label(for: k), systemImage: ModalityStyle.icon(for: k)).tag(k)
                        }
                    }
                    .onChange(of: kind) { _, _ in preview = nil; generateError = nil; selectedArchId = nil }
                } header: {
                    Text(dayName)
                } footer: {
                    Text("An extra: it counts once you do it, and you can remove it.")
                }
            } else if let session {
                Section("Current Workout") {
                    Text(session.archetype?.name
                         ?? session.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Settings") {
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
                    selectedArchId = nil
                    preview = nil
                    generateError = nil
                    Task { await generateSession() }
                } label: {
                    if isGenerating {
                        HStack {
                            ProgressView().scaleEffect(0.8)
                            Text("Generating…")
                        }
                    } else {
                        Label(adding ? "Find a \(ModalityStyle.label(for: kind).lowercased()) session" : "Generate Session",
                              systemImage: adding ? "plus.circle" : "arrow.2.circlepath")
                    }
                }
                .disabled(isGenerating)
            }
        }
    }

    // MARK: - Shared Preview + Error

    private func previewCard(_ p: ProgramSession) -> some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.archetype?.name
                             ?? p.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 8) {
                            Text(p.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                            if let mins = p.archetype?.durationEstimateMinutes {
                                Text("· \(mins) min").font(.caption).foregroundStyle(.secondary)
                            }
                            let count = p.exercises.filter { !$0.injurySkip }.count
                            if count > 0 {
                                Text("· \(count) exercises").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let via = Self.borrowedLabel(p) {
                            Text("via \(via)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        let current = p.archetype?.id
                        preview = nil
                        generateError = nil
                        // Adding without a pick: another session of the kind straight away.
                        if adding && selectedArchId == nil {
                            Task { await generateSession(excluding: current) }
                        }
                        selectedArchId = nil
                    } label: {
                        Text("Try Again")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if adding {
                            appState.addSession(weekIndex: weekIndex, day: dayName, session: p)
                        } else {
                            appState.replaceSession(weekIndex: weekIndex, day: dayName,
                                                    sessionIndex: sessionIndex, session: p)
                        }
                        dismiss()
                    } label: {
                        Text(adding ? "Add Session" : "Confirm Replace")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .background(.background)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
                .padding()
        }
    }

    /// "Kelly Starrett / Built to Move" for a session borrowed from another package.
    static func borrowedLabel(_ p: ProgramSession) -> String? {
        guard case .object(let o)? = p.extra["provenance"], case .bool(true)? = o["borrowed"] else { return nil }
        return o["label"]?.stringValue ?? o["package"]?.stringValue?.replacingOccurrences(of: "_", with: " ")
    }

    private func message(_ error: Error) -> String {
        if case APIError.serverErrorDetail(_, let text) = error { return text }
        return error.localizedDescription
    }

    // MARK: - Network

    private func request(modality: String, archetypeId: String?, minutes: Int,
                         excluding: String? = nil) -> GenerateSessionRequest {
        let week = appState.serverProgram?.currentProgram?.weeks[safe: weekIndex]
        var r = GenerateSessionRequest(
            primarySources: [],
            modality: modality,
            // A composed program's session runs its own track's phase.
            phase: session?.lanePhase ?? week?.phase ?? "base",
            weekInPhase: session?.laneWeekInPhase ?? weekIndex + 1,
            isDeload: session?.laneKey != nil ? (session?.isDeload ?? false) : (week?.isDeload ?? false),
            constraints: GenerateSessionConstraints(sessionTimeMinutes: minutes,
                                                    fatigueState: fatigueState.rawValue),
            archetypeId: archetypeId,
            phaseId: session?.lanePhaseId ?? week?.phaseId,
            frameworkId: session?.laneFramework ?? week?.frameworkId,
            laneKey: adding ? nil : session?.laneKey
        )
        if adding {
            r.add = true
            r.currentArchetypeId = excluding
        }
        return r
    }

    private func generateWithArchetype(_ arch: AppArchetype) async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            preview = try await api.generateSession(
                request(modality: arch.modality, archetypeId: arch.id,
                        minutes: arch.durationEstimateMinutes ?? Int(sessionMinutes)))
        } catch {
            generateError = message(error)
            selectedArchId = nil
        }
    }

    private func generateSession(excluding: String? = nil) async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            preview = try await api.generateSession(
                request(modality: modality, archetypeId: nil, minutes: Int(sessionMinutes), excluding: excluding))
        } catch {
            generateError = message(error)
        }
    }
}
