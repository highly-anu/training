import SwiftUI

// MARK: - Tab definition

private enum ProfileTab: Int, CaseIterable {
    case equipment, injuries, benchmarks, schedule, sync

    var label: String {
        switch self {
        case .equipment:  return "Equipment"
        case .injuries:   return "Injuries"
        case .benchmarks: return "Benchmarks"
        case .schedule:   return "Schedule"
        case .sync:       return "Sync"
        }
    }

    var icon: String {
        switch self {
        case .equipment:  return "dumbbell"
        case .injuries:   return "bandage"
        case .benchmarks: return "trophy"
        case .schedule:   return "calendar"
        case .sync:       return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Equipment categories (mirrors web EQUIPMENT_CATEGORIES)

private struct EquipmentCategory {
    let name: String       // matches EquipmentItem.group exactly
    let modalityId: String // for accent color only
}

// Group names and order match ConstraintsForm.tsx exactly.
private let equipmentCategories: [EquipmentCategory] = [
    EquipmentCategory(name: "Strength",               modalityId: "max_strength"),
    EquipmentCategory(name: "Power & Kettlebell",     modalityId: "power"),
    EquipmentCategory(name: "Bodyweight & Gymnastics",modalityId: "relative_strength"),
    EquipmentCategory(name: "Aerobic & Conditioning", modalityId: "aerobic_base"),
    EquipmentCategory(name: "GPP & Durability",       modalityId: "durability"),
    EquipmentCategory(name: "Mobility & Prehab",      modalityId: "rehab"),
    EquipmentCategory(name: "General",                modalityId: "movement_skill"),
]

// MARK: - Shared selection card

private struct SelectionCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isSelected ? accentColor : Color.clear)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(isSelected ? accentColor.opacity(0.10) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? accentColor.opacity(0.4) : Color(.separator).opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom tab bar

private struct ProfileTabBar: View {
    @Binding var selected: ProfileTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProfileTab.allCases, id: \.rawValue) { tab in
                    let isActive = tab == selected
                    Button {
                        selected = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11))
                            Text(tab.label)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color(.separator).opacity(0.4))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Equipment Tab

private struct EquipmentTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Available equipment.")
                        .font(.headline)
                    Text("Select all equipment you have access to. This filters archetypes and exercises during program generation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(equipmentCategories, id: \.name) { category in
                let items = EquipmentItem.all.filter { $0.group == category.name }
                if !items.isEmpty {
                    Section(category.name) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(items) { item in
                                let isSelected = appState.profile.equipment.contains(item.id)
                                SelectionCard(
                                    title: item.label,
                                    subtitle: isSelected ? "Available" : "Not selected",
                                    isSelected: isSelected,
                                    accentColor: ModalityStyle.color(for: category.modalityId)
                                ) {
                                    if isSelected {
                                        appState.profile.equipment.removeAll { $0 == item.id }
                                    } else {
                                        appState.profile.equipment.append(item.id)
                                    }
                                    Task { await appState.saveProfile() }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                Text("\(appState.profile.equipment.count) items selected")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Injuries Tab

private struct InjuriesTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddCustomInjury = false
    @State private var newCustomInjury = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active injury flags.")
                        .font(.headline)
                    Text("Select any current injuries or movement limitations. The system will exclude contraindicated exercises and suggest alternatives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !appState.injuryFlagDefs.isEmpty {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(appState.injuryFlagDefs) { flag in
                            let isSelected = appState.profile.injuryFlags.contains(flag.id)
                            let patternCount = flag.excludedMovementPatterns?.count ?? 0
                            SelectionCard(
                                title: flag.name,
                                subtitle: isSelected ? "\(patternCount) patterns excluded" : "Not active",
                                isSelected: isSelected,
                                accentColor: .red
                            ) {
                                if isSelected {
                                    appState.profile.injuryFlags.removeAll { $0 == flag.id }
                                } else {
                                    appState.profile.injuryFlags.append(flag.id)
                                }
                                Task { await appState.saveProfile() }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !appState.profile.customInjuryFlags.isEmpty {
                Section("Custom") {
                    ForEach(appState.profile.customInjuryFlags) { custom in
                        HStack {
                            Text(custom.description)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
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
            }

            Section {
                Button {
                    showAddCustomInjury = true
                } label: {
                    Label("Add Custom Injury", systemImage: "plus")
                }

                let totalActive = appState.profile.injuryFlags.count + appState.profile.customInjuryFlags.count
                Text("\(totalActive) active \(totalActive == 1 ? "injury" : "injuries")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.insetGrouped)
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
}

// MARK: - Benchmarks Tab

private struct BenchmarksTab: View {
    @EnvironmentObject var appState: AppState
    @State private var editingBenchmarkId: String? = nil

    var body: some View {
        let grouped = Dictionary(grouping: appState.benchmarks, by: \.category)
        let categories = grouped.keys.sorted()

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(appState.benchmarks.count) benchmark standards.")
                        .font(.headline)
                    Text("Track your personal records against standardized benchmarks. Your PRs are saved to your profile and used to calculate training loads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(categories, id: \.self) { category in
                Section(category.replacingOccurrences(of: "_", with: " ").capitalized) {
                    ForEach(grouped[category] ?? []) { benchmark in
                        benchmarkRow(benchmark)
                    }
                }
            }

            Section("Max HR") {
                dobRows
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: Binding(
            get: { editingBenchmarkId != nil },
            set: { if !$0 { editingBenchmarkId = nil } }
        )) {
            if let id = editingBenchmarkId,
               let benchmark = appState.benchmarks.first(where: { $0.id == id }) {
                BenchmarkEditSheet(
                    benchmark: benchmark,
                    currentValue: appState.profile.performanceLogs?[id]?.last?.value,
                    onSave: { value in
                        let entry = PerformanceEntry(value: value, date: todayString())
                        if appState.profile.performanceLogs == nil { appState.profile.performanceLogs = [:] }
                        appState.profile.performanceLogs![id, default: []].append(entry)
                        Task { await appState.saveProfile() }
                        editingBenchmarkId = nil
                    }
                )
            }
        }
    }

    private func benchmarkRow(_ benchmark: AppBenchmark) -> some View {
        let entries = appState.profile.performanceLogs?[benchmark.id] ?? []
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
                    Text(String(format: "%.1f", val)).font(.headline).monospacedDigit()
                    Text(levelLabel(val, benchmark: benchmark))
                        .font(.caption2)
                        .foregroundStyle(levelColor(val, benchmark: benchmark))
                }
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editingBenchmarkId = benchmark.id }
    }

    private var dobRows: some View {
        Group {
            DatePicker(
                "Date of Birth",
                selection: Binding(
                    get: {
                        if let dob = appState.profile.dateOfBirth {
                            return dobDate(dob) ?? Date()
                        }
                        return Date()
                    },
                    set: { d in
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                        appState.profile.dateOfBirth = f.string(from: d)
                        Task { await appState.saveProfile() }
                    }
                ),
                displayedComponents: .date
            )
            if let dob = appState.profile.dateOfBirth, let age = computeAge(dob) {
                LabeledContent("Estimated Max HR", value: "\(220 - age) bpm")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dobDate(_ string: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: string)
    }
    private func computeAge(_ dob: String) -> Int? {
        guard let date = dobDate(dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year
    }
    private func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
    private func levelLabel(_ value: Double, benchmark: AppBenchmark) -> String {
        guard let s = benchmark.standards else { return "" }
        let h = benchmark.higherIsBetter
        if let e = s.elite,        h ? value >= e : value <= e { return "Elite" }
        if let a = s.advanced,     h ? value >= a : value <= a { return "Advanced" }
        if let i = s.intermediate, h ? value >= i : value <= i { return "Intermediate" }
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

// MARK: - Schedule Tab

private let scheduleDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

private let defaultWeeklySchedule: WeeklySchedule = [
    "Monday":    DaySchedule(session1: .long,  session2: .rest,     session3: .rest, session4: .rest),
    "Tuesday":   DaySchedule(session1: .short, session2: .mobility, session3: .rest, session4: .rest),
    "Wednesday": DaySchedule(session1: .long,  session2: .rest,     session3: .rest, session4: .rest),
    "Thursday":  DaySchedule(session1: .short, session2: .mobility, session3: .rest, session4: .rest),
    "Friday":    DaySchedule(session1: .long,  session2: .rest,     session3: .rest, session4: .rest),
    "Saturday":  DaySchedule(session1: .long,  session2: .rest,     session3: .rest, session4: .rest),
    "Sunday":    DaySchedule(session1: .rest,  session2: .rest,     session3: .rest, session4: .rest),
]

private func nextSessionType(_ t: SessionType) -> SessionType {
    switch t {
    case .rest:     return .short
    case .short:    return .long
    case .long:     return .mobility
    case .mobility: return .rest
    }
}

private struct SessionChip: View {
    let type: SessionType
    let action: () -> Void

    private var chipText: String {
        switch type {
        case .rest:     return "Rest"
        case .short:    return "Short"
        case .long:     return "Long"
        case .mobility: return "Mobility"
        }
    }

    private var chipColor: Color {
        switch type {
        case .rest:     return Color(.systemGray3)
        case .short:    return .yellow
        case .long:     return Color(red: 0.36, green: 0.77, blue: 0.96)
        case .mobility: return Color(red: 0.67, green: 0.44, blue: 0.96)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(chipText)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chipColor.opacity(0.15))
                .foregroundStyle(chipColor)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(chipColor.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

private struct DayRow: View {
    let day: String
    @Binding var daySchedule: DaySchedule
    let onChanged: () -> Void

    var body: some View {
        let hasAny = daySchedule.session1 != .rest || daySchedule.session2 != .rest
            || daySchedule.session3 != .rest || daySchedule.session4 != .rest

        let showS2 = daySchedule.session1 != .rest || daySchedule.session2 != .rest
        let showS3 = daySchedule.session2 != .rest || daySchedule.session3 != .rest
        let showS4 = daySchedule.session3 != .rest || daySchedule.session4 != .rest

        HStack(spacing: 10) {
            Circle()
                .fill(hasAny ? Color.accentColor : Color(.systemGray4))
                .frame(width: 7, height: 7)
            Text(day)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 86, alignment: .leading)
            HStack(spacing: 6) {
                slotView(label: "1", type: daySchedule.session1) {
                    daySchedule.session1 = nextSessionType(daySchedule.session1)
                    onChanged()
                }
                if showS2 {
                    slotView(label: "2", type: daySchedule.session2) {
                        daySchedule.session2 = nextSessionType(daySchedule.session2)
                        onChanged()
                    }
                }
                if showS3 {
                    slotView(label: "3", type: daySchedule.session3) {
                        daySchedule.session3 = nextSessionType(daySchedule.session3)
                        onChanged()
                    }
                }
                if showS4 {
                    slotView(label: "4", type: daySchedule.session4) {
                        daySchedule.session4 = nextSessionType(daySchedule.session4)
                        onChanged()
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(hasAny ? accentLeftColor : Color.clear)
                    .frame(width: 3)
                Color(.secondarySystemGroupedBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        )
    }

    private var accentLeftColor: Color {
        switch daySchedule.session1 {
        case .long:     return Color(red: 0.36, green: 0.77, blue: 0.96)
        case .short:    return .yellow
        case .mobility: return Color(red: 0.67, green: 0.44, blue: 0.96)
        case .rest:     return Color.accentColor
        }
    }

    private func slotView(label: String, type: SessionType, action: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text("\(label):")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            SessionChip(type: type, action: action)
        }
    }
}

private struct ScheduleTab: View {
    @EnvironmentObject var appState: AppState
    @State private var schedule: WeeklySchedule = defaultWeeklySchedule

    private func save() {
        appState.profile.weeklySchedule = schedule
        Task { await appState.saveProfile() }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly availability.")
                        .font(.headline)
                    Text("Configure your weekly schedule. Short = 30–45 min, Long = 60+ min, Mobility = 15–20 min. Tap each session to cycle through types.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(scheduleDays, id: \.self) { day in
                    DayRow(
                        day: day,
                        daySchedule: Binding(
                            get: { schedule[day] ?? DaySchedule(session1: .rest, session2: .rest, session3: .rest, session4: .rest) },
                            set: { schedule[day] = $0 }
                        ),
                        onChanged: save
                    )
                }
            }

            Section {
                let trainingDays = scheduleDays.filter { day in
                    guard let d = schedule[day] else { return false }
                    return d.session1 != .rest || d.session2 != .rest || d.session3 != .rest || d.session4 != .rest
                }.count
                let totalSessions = scheduleDays.reduce(0) { sum, day in
                    guard let d = schedule[day] else { return sum }
                    return sum + [d.session1, d.session2, d.session3, d.session4].filter { $0 != .rest }.count
                }
                Text("\(trainingDays) \(trainingDays == 1 ? "day" : "days") • \(totalSessions) total \(totalSessions == 1 ? "session" : "sessions")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            schedule = appState.profile.weeklySchedule ?? defaultWeeklySchedule
        }
    }
}

// MARK: - Sync Tab

private struct SyncTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            // Profile section — what is currently loaded from server
            Section("Profile") {
                LabeledContent("Training level", value: appState.profile.trainingLevel.capitalized)

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Equipment", value: "\(appState.profile.equipment.count) items")
                    if !appState.profile.equipment.isEmpty {
                        Text(appState.profile.equipment.sorted().joined(separator: ", "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Injury flags", value: "\(appState.profile.injuryFlags.count) active")
                    if !appState.profile.injuryFlags.isEmpty {
                        Text(appState.profile.injuryFlags.sorted().joined(separator: ", "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Custom injuries",  value: "\(appState.profile.customInjuryFlags.count)")
                LabeledContent("Weekly schedule",  value: appState.profile.weeklySchedule != nil ? "Set" : "Not set")
                LabeledContent("Date of birth",    value: appState.profile.dateOfBirth ?? "Not set")
                LabeledContent("Performance logs", value: "\(appState.profile.performanceLogs?.count ?? 0) benchmarks")
            }

            // Sync status + manual trigger
            Section("Sync") {
                if let date = appState.lastProfileSyncAt {
                    LabeledContent("Last synced", value: date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Not yet synced this session")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await appState.loadProfile()
                        await appState.loadPerformanceLogs()
                    }
                } label: {
                    Label(
                        appState.isLoadingProfile ? "Syncing…" : "Pull from server",
                        systemImage: "arrow.down.circle"
                    )
                }
                .disabled(appState.isLoadingProfile)
            }

            // Debug log
            if !appState.profileSyncLog.isEmpty {
                Section(header: HStack {
                    Text("Debug Log")
                    Spacer()
                    Button("Clear") { appState.profileSyncLog.removeAll() }
                        .font(.caption)
                }) {
                    ForEach(appState.profileSyncLog.reversed(), id: \.self) { msg in
                        Text(msg)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: ProfileTab = .equipment

    private let trainingLevels = ["novice", "intermediate", "advanced", "elite"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProfileTabBar(selected: $selectedTab)
                Divider()

                switch selectedTab {
                case .equipment:  EquipmentTab()
                case .injuries:   InjuriesTab()
                case .benchmarks: BenchmarksTab()
                case .schedule:   ScheduleTab()
                case .sync:       SyncTab()
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Picker("Level", selection: Binding(
                        get: { appState.profile.trainingLevel },
                        set: { appState.profile.trainingLevel = $0; Task { await appState.saveProfile() } }
                    )) {
                        ForEach(trainingLevels, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            .task {
                await appState.loadInjuryFlagsIfNeeded()
                await appState.loadBenchmarksIfNeeded()
            }
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
                        TextField("Value", text: $inputText).keyboardType(.decimalPad)
                        if let unit = benchmark.unit {
                            Text(unit).foregroundStyle(.secondary)
                        }
                    }
                }
                if let standards = benchmark.standards {
                    Section("Standards") {
                        if let e = standards.elite        { LabeledContent("Elite",        value: "\(e)") }
                        if let a = standards.advanced     { LabeledContent("Advanced",     value: "\(a)") }
                        if let i = standards.intermediate { LabeledContent("Intermediate", value: "\(i)") }
                        if let n = standards.entry        { LabeledContent("Entry",        value: "\(n)") }
                    }
                }
            }
            .navigationTitle("Log PR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let v = Double(inputText) { onSave(v) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(inputText) == nil)
                }
            }
            .onAppear { if let c = currentValue { inputText = "\(c)" } }
        }
    }
}
