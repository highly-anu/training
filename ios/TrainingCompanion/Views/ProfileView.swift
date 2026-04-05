import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState

    @State private var selectedTab = 0
    @State private var showAddCustomInjury = false
    @State private var newCustomInjury = ""
    @State private var selectedPhilosophy: PhilosophyCard? = nil
    @State private var editingBenchmarkId: String? = nil
    @State private var benchmarkInput: String = ""

    private let trainingLevels = ["novice", "intermediate", "advanced", "elite"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Setup").tag(0)
                    Text("Benchmarks").tag(1)
                    Text("Methods").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()

                switch selectedTab {
                case 0: setupTab
                case 1: benchmarksTab
                default: philosophiesTab
                }
            }
            .navigationTitle("Profile")
            .sheet(item: $selectedPhilosophy) { phil in
                PhilosophyDetailSheet(philosophy: phil)
            }
            .task {
                await appState.loadInjuryFlagsIfNeeded()
                await appState.loadBenchmarksIfNeeded()
                await appState.loadPhilosophiesIfNeeded()
            }
        }
    }

    // MARK: - Setup Tab

    private var setupTab: some View {
        Form {
            // Training Level
            Section("Training Level") {
                Picker("Level", selection: Binding(
                    get: { appState.profile.trainingLevel },
                    set: { appState.profile.trainingLevel = $0; Task { await appState.saveProfile() } }
                )) {
                    ForEach(trainingLevels, id: \.self) { level in
                        Text(level.capitalized).tag(level)
                    }
                }
                .pickerStyle(.menu)
            }

            // Equipment
            Section("Equipment") {
                ForEach(EquipmentItem.all) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { appState.profile.equipment.contains(item.id) },
                        set: { on in
                            if on { if !appState.profile.equipment.contains(item.id) { appState.profile.equipment.append(item.id) } }
                            else { appState.profile.equipment.removeAll { $0 == item.id } }
                            Task { await appState.saveProfile() }
                        }
                    ))
                }
            }

            // Injury Flags
            Section {
                ForEach(appState.injuryFlagDefs) { flag in
                    Toggle(flag.name, isOn: Binding(
                        get: { appState.profile.injuryFlags.contains(flag.id) },
                        set: { on in
                            if on { if !appState.profile.injuryFlags.contains(flag.id) { appState.profile.injuryFlags.append(flag.id) } }
                            else { appState.profile.injuryFlags.removeAll { $0 == flag.id } }
                            Task { await appState.saveProfile() }
                        }
                    ))
                    .toggleStyle(.switch)
                }
                if !appState.profile.customInjuryFlags.isEmpty {
                    ForEach(appState.profile.customInjuryFlags) { custom in
                        HStack {
                            Text(custom.description)
                            Spacer()
                            Image(systemName: "checkmark").foregroundStyle(.orange)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                appState.profile.customInjuryFlags.removeAll { $0.id == custom.id }
                                Task { await appState.saveProfile() }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                Button {
                    showAddCustomInjury = true
                } label: {
                    Label("Add Custom Injury", systemImage: "plus")
                }
            } header: {
                Text("Active Injuries")
            }

            // Date of Birth
            Section("Max HR Calculation") {
                if let dob = appState.profile.dateOfBirth, let date = dobDate(dob) {
                    DatePicker("Date of Birth", selection: Binding(
                        get: { date },
                        set: { d in
                            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                            appState.profile.dateOfBirth = f.string(from: d)
                            Task { await appState.saveProfile() }
                        }
                    ), displayedComponents: .date)
                } else {
                    DatePicker("Date of Birth", selection: Binding(
                        get: { Date() },
                        set: { d in
                            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                            appState.profile.dateOfBirth = f.string(from: d)
                            Task { await appState.saveProfile() }
                        }
                    ), displayedComponents: .date)
                }
                if let dob = appState.profile.dateOfBirth, let age = computeAge(dob) {
                    LabeledContent("Estimated Max HR", value: "\(220 - age) bpm")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Add Injury", isPresented: $showAddCustomInjury) {
            TextField("Describe the injury", text: $newCustomInjury)
            Button("Add") {
                let flag = CustomInjuryFlag(id: UUID().uuidString, description: newCustomInjury)
                appState.profile.customInjuryFlags.append(flag)
                Task { await appState.saveProfile() }
                newCustomInjury = ""
            }
            Button("Cancel", role: .cancel) { newCustomInjury = "" }
        }
    }

    // MARK: - Benchmarks Tab

    private var benchmarksTab: some View {
        let grouped = Dictionary(grouping: appState.benchmarks, by: \.category)
        let categories = grouped.keys.sorted()

        return List {
            ForEach(categories, id: \.self) { category in
                Section(category.replacingOccurrences(of: "_", with: " ").capitalized) {
                    ForEach(grouped[category] ?? []) { benchmark in
                        benchmarkRow(benchmark)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: Binding(
            get: { editingBenchmarkId != nil },
            set: { if !$0 { editingBenchmarkId = nil; benchmarkInput = "" } }
        )) {
            if let id = editingBenchmarkId,
               let benchmark = appState.benchmarks.first(where: { $0.id == id }) {
                BenchmarkEditSheet(
                    benchmark: benchmark,
                    currentValue: appState.profile.performanceLogs[id]?.last?.value,
                    onSave: { value in
                        let entry = PerformanceEntry(value: value, date: todayString())
                        appState.profile.performanceLogs[id, default: []].append(entry)
                        Task { await appState.saveProfile() }
                        editingBenchmarkId = nil
                    }
                )
            }
        }
    }

    private func benchmarkRow(_ benchmark: AppBenchmark) -> some View {
        let entries = appState.profile.performanceLogs[benchmark.id] ?? []
        let current = entries.last?.value

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(benchmark.name).font(.body)
                if let unit = benchmark.unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let val = current {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", val))
                        .font(.headline)
                        .monospacedDigit()
                    Text(levelLabel(val, benchmark: benchmark))
                        .font(.caption2)
                        .foregroundStyle(levelColor(val, benchmark: benchmark))
                }
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingBenchmarkId = benchmark.id
        }
    }

    // MARK: - Philosophies Tab

    private var philosophiesTab: some View {
        List {
            if appState.philosophies.isEmpty {
                ProgressView().padding()
            } else {
                ForEach(appState.philosophies) { phil in
                    philosophyRow(phil)
                        .onTapGesture { selectedPhilosophy = phil }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func philosophyRow(_ phil: PhilosophyCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phil.name).font(.body).fontWeight(.medium)
            if let desc = phil.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let bias = phil.bias, !bias.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bias, id: \.self) { b in
                            Text(ModalityStyle.label(for: b))
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(ModalityStyle.color(for: b).opacity(0.15))
                                .foregroundStyle(ModalityStyle.color(for: b))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func dobDate(_ string: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)
    }

    private func computeAge(_ dob: String) -> Int? {
        guard let date = dobDate(dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year
    }

    private func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private func levelLabel(_ value: Double, benchmark: AppBenchmark) -> String {
        guard let standards = benchmark.standards else { return "" }
        let higher = benchmark.higherIsBetter
        if let elite = standards.elite, higher ? value >= elite : value <= elite { return "Elite" }
        if let advanced = standards.advanced, higher ? value >= advanced : value <= advanced { return "Advanced" }
        if let intermediate = standards.intermediate, higher ? value >= intermediate : value <= intermediate { return "Intermediate" }
        return "Entry"
    }

    private func levelColor(_ value: Double, benchmark: AppBenchmark) -> Color {
        switch levelLabel(value, benchmark: benchmark) {
        case "Elite":        return .purple
        case "Advanced":     return .blue
        case "Intermediate": return .green
        default:             return .secondary
        }
    }
}

// MARK: - Benchmark Edit Sheet

private struct BenchmarkEditSheet: View {
    let benchmark: AppBenchmark
    let currentValue: Double?
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inputText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(benchmark.name) {
                    HStack {
                        TextField("Value", text: $inputText)
                            .keyboardType(.decimalPad)
                        if let unit = benchmark.unit {
                            Text(unit).foregroundStyle(.secondary)
                        }
                    }
                }
                if let standards = benchmark.standards {
                    Section("Standards") {
                        if let elite = standards.elite { LabeledContent("Elite", value: "\(elite)") }
                        if let adv = standards.advanced { LabeledContent("Advanced", value: "\(adv)") }
                        if let int = standards.intermediate { LabeledContent("Intermediate", value: "\(int)") }
                        if let entry = standards.entry { LabeledContent("Entry", value: "\(entry)") }
                    }
                }
            }
            .navigationTitle("Log PR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let v = Double(inputText) { onSave(v) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(inputText) == nil)
                }
            }
            .onAppear {
                if let current = currentValue { inputText = "\(current)" }
            }
        }
    }
}

// MARK: - Philosophy Detail Sheet

private struct PhilosophyDetailSheet: View {
    let philosophy: PhilosophyCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let desc = philosophy.description {
                        Text(desc).font(.body)
                    }
                }
                if let principles = philosophy.corePrinciples, !principles.isEmpty {
                    Section("Core Principles") {
                        ForEach(principles, id: \.self) { p in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 5)
                                Text(p.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                if let bias = philosophy.bias, !bias.isEmpty {
                    Section("Modality Bias") {
                        ForEach(bias, id: \.self) { b in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(ModalityStyle.color(for: b))
                                    .frame(width: 10, height: 10)
                                Text(ModalityStyle.label(for: b))
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                if let intensity = philosophy.intensityModel {
                    Section("Intensity Model") {
                        Text(intensity.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
                if let progression = philosophy.progressionStyle {
                    Section("Progression Style") {
                        Text(progression.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
            }
            .navigationTitle(philosophy.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
