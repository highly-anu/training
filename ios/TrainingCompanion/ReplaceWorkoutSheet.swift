import SwiftUI

struct ReplaceWorkoutSheet: View {
    let api: APIClient
    let weekIndex: Int
    let dayName: String
    let sessionIndex: Int
    let session: ProgramSession

    @EnvironmentObject var programStore: ProgramStore
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
            .filter { !sameModalityOnly || $0.modality == session.modality }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q) }
            .sorted {
                let aMatch = $0.modality == session.modality ? 0 : 1
                let bMatch = $1.modality == session.modality ? 0 : 1
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
            .navigationTitle("Replace Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
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
            Section("Current Workout") {
                Text(session.archetype?.name
                     ?? session.modality.replacingOccurrences(of: "_", with: " ").capitalized)
                    .foregroundStyle(.secondary)
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
                        Label("Generate Session", systemImage: "arrow.2.circlepath")
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
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        preview = nil
                        selectedArchId = nil
                        generateError = nil
                    } label: {
                        Text("Try Again")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        programStore.replaceSession(weekIndex: weekIndex, day: dayName,
                                                    sessionIndex: sessionIndex,
                                                    session: p, api: api)
                        dismiss()
                    } label: {
                        Text("Confirm Replace")
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

    // MARK: - Network

    private func generateWithArchetype(_ arch: AppArchetype) async {
        isGenerating = true
        defer { isGenerating = false }
        let week = programStore.serverProgram?.currentProgram?.weeks[safe: weekIndex]
        let request = GenerateSessionRequest(
            primarySources: [],
            modality: arch.modality,
            phase: week?.phase ?? "base",
            weekInPhase: weekIndex + 1,
            isDeload: week?.isDeload ?? false,
            constraints: GenerateSessionConstraints(
                sessionTimeMinutes: arch.durationEstimateMinutes ?? Int(sessionMinutes),
                fatigueState: fatigueState.rawValue
            ),
            archetypeId: arch.id
        )
        do {
            preview = try await api.generateSession(request)
        } catch {
            generateError = error.localizedDescription
            selectedArchId = nil
        }
    }

    private func generateSession() async {
        isGenerating = true
        defer { isGenerating = false }
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
    }
}
