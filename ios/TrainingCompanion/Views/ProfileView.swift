import SwiftUI

// MARK: - Tab definition

enum ProfileTab: Int, AppSubTab {
    // The web Profile's tabs, in its order (information-architecture.md §2),
    // except Injuries, which is part of Athlete on the phone.
    case athlete, equipment, schedule, standards

    var label: String {
        switch self {
        case .athlete:    return "Athlete"
        case .equipment:  return "Equipment"
        case .schedule:   return "Schedule"
        case .standards:  return "Standards"
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

// MARK: - Equipment Tab

private struct EquipmentTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            if !appState.constraintDifferences.isEmpty {
                Section { RegenerateOfferCard() }
            }
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

// MARK: - Injuries (in Athlete)

/// Active injury flags and custom injuries, a section of Athlete: the system
/// excludes contraindicated exercises and suggests alternatives.
private struct InjuriesSection: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddCustomInjury = false
    @State private var newCustomInjury = ""

    var body: some View {
        Section {
            if !appState.injuryFlagDefs.isEmpty {
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

            Button {
                showAddCustomInjury = true
            } label: {
                Label("Add Custom Injury", systemImage: "plus")
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
        } header: {
            let total = appState.profile.injuryFlags.count + appState.profile.customInjuryFlags.count
            HStack {
                Text("Injuries")
                Spacer()
                if total > 0 {
                    Text("\(total) active").monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Standards Tab

/// Every standard, grouped and named as the server says (the web's groups,
/// in its order), with the athlete's current result placed on the ladder by
/// the server. Tap a row to log a new result.
private struct StandardsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var logging: AppBenchmark? = nil

    private var groups: [(name: String, rows: [AppBenchmark])] {
        let byCategory = Dictionary(grouping: appState.benchmarks, by: \.category)
        return byCategory.values
            .sorted { ($0.first?.categoryOrder ?? 99, $0.first?.groupName ?? "") < ($1.first?.categoryOrder ?? 99, $1.first?.groupName ?? "") }
            .map { (name: $0.first?.groupName ?? "", rows: $0) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(appState.benchmarks.count) standards.")
                        .font(.headline)
                    Text("Log a result whenever you test one. Every result is kept with its date, so you can see where you stand now and how far you have come across programs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.profile.sex.map { "Showing the \($0) standards." }
                         ?? "Showing the male standards until you set your sex under Athlete.")
                        .font(.caption2)
                        .foregroundStyle(appState.profile.sex == nil ? Color.orange : Color.secondary)
                    if let bw = appState.standardResults?.bodyweight {
                        Text("Bodyweight \(bw.valueText) — used for the ×BW standards.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("No bodyweight logged — the ×BW standards need one (Athlete).")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.rows) { standard in
                        StandardRow(standard: standard, result: appState.standardResults?.standards[standard.id])
                            .contentShape(Rectangle())
                            .onTapGesture { logging = standard }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await AppRefresh.perform { await appState.loadStandardResults() } }
        .sheet(item: $logging) { standard in
            StandardResultSheet(standard: standard, result: appState.standardResults?.standards[standard.id])
        }
    }
}

private struct StandardRow: View {
    let standard: AppBenchmark
    let result: StandardResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(standard.name).font(.subheadline).lineLimit(2)
                Spacer(minLength: 8)
                if let current = result?.current {
                    Text(current.valueText).font(.subheadline).fontWeight(.semibold).monospacedDigit()
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            if let result {
                HStack(spacing: 6) {
                    StandardLevelBadge(level: result.current.level, domain: standard.domain)
                    Text(detail(result)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            StandardLadder(thresholds: standard.thresholdTexts, levelIndex: result?.current.levelIndex,
                           domain: standard.domain)
        }
        .padding(.vertical, 2)
    }

    private func detail(_ r: StandardResult) -> String {
        var parts: [String] = []
        if let day = StandardLevel.day(r.current.date) { parts.append(day) }
        if r.best.value != r.current.value { parts.append("best \(r.best.valueText)") }
        if let next = r.current.next, let gap = r.current.gapText { parts.append("\(gap) to \(next)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Athlete Tab

/// Who is training: the facts the generator and the analytics read before any
/// equipment — level, age (max HR), bodyweight (the ×BW standards), injuries,
/// and the heart-rate zones every HR chart and TRIMP calculation uses.
private struct AthleteTab: View {
    @EnvironmentObject var appState: AppState
    @State private var bodyweightInput: String = ""
    @State private var maxHRInput: String = ""

    private let trainingLevels = ["novice", "intermediate", "advanced", "elite"]
    private let zoneNames = ["Zone 1 ends", "Zone 2 ends", "Zone 3 ends", "Zone 4 ends"]

    private var boundaries: [Double] {
        let stored = appState.profile.hrConfig?.zoneBoundaries ?? []
        return stored.count == 4 ? stored : AnalyticsEngine.defaultZoneBoundaries
    }

    /// Override → 220 − age → 190, the same priority AnalyticsEngine uses.
    private var effectiveMaxHR: Int {
        if let o = appState.profile.hrConfig?.maxHROverride, o > 0 { return o }
        if let dob = appState.profile.dateOfBirth, let age = computeAge(dob) { return 220 - age }
        return 190
    }

    private var bodyweight: StandardResults.Bodyweight? { appState.standardResults?.bodyweight }
    @State private var bodyweightError: String? = nil

    var body: some View {
        List {
            if !appState.constraintDifferences.isEmpty {
                Section { RegenerateOfferCard() }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("About you.")
                        .font(.headline)
                    Text("Level, age and injuries shape every program; bodyweight and heart-rate zones shape how your training is measured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Training level") {
                Picker("Level", selection: Binding(
                    get: { appState.profile.trainingLevel },
                    set: { appState.profile.trainingLevel = $0; Task { await appState.saveProfile() } }
                )) {
                    ForEach(trainingLevels, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section("Body") {
                // Which standards' tables apply. Clearing the cached ladders
                // makes the Standards section re-fetch the right table, and the
                // results are re-read so their levels follow.
                Picker("Sex", selection: Binding(
                    get: { appState.profile.sex ?? "unset" },
                    set: { value in
                        appState.profile.sex = value == "unset" ? nil : value
                        appState.benchmarks = []
                        Task {
                            await appState.saveProfile()
                            await appState.loadStandardResults()
                        }
                    }
                )) {
                    Text("Not set").tag("unset")
                    Text("Female").tag("female")
                    Text("Male").tag("male")
                }
                .pickerStyle(.menu)
                DatePicker("Date of Birth", selection: dobBinding, displayedComponents: .date)
                if let dob = appState.profile.dateOfBirth, let age = computeAge(dob) {
                    LabeledContent("Age", value: "\(age)")
                }
                LabeledContent("Bodyweight", value: bodyweight.map { bw in
                    [bw.valueText, StandardLevel.day(bw.date)].compactMap { $0 }.joined(separator: " · ")
                } ?? "—")
                HStack {
                    TextField("New weight (kg)", text: $bodyweightInput)
                        .keyboardType(.decimalPad)
                    Button("Log") { logBodyweight() }
                        .disabled(bodyweightInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let bodyweightError {
                    Text(bodyweightError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Text("Max HR")
                    Spacer()
                    TextField("\(effectiveMaxHR)", text: $maxHRInput)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit { saveMaxHROverride() }
                    Text("bpm").foregroundStyle(.secondary)
                }
                if appState.profile.hrConfig?.maxHROverride != nil {
                    Button("Use the estimate from age instead") { clearMaxHROverride() }
                        .font(.footnote)
                }
                HRZoneBar(boundaries: boundaries, maxHR: effectiveMaxHR)
                    .padding(.vertical, 4)
                ForEach(0..<4, id: \.self) { i in
                    Stepper(value: Binding(
                        get: { Int((boundaries[i] * 100).rounded()) },
                        set: { setBoundary(i, percent: $0) }
                    ), in: 40...97) {
                        HStack(spacing: 8) {
                            Capsule()
                                .fill(HRZoneStyle.color(i + 1))
                                .frame(width: 4, height: 18)
                                .accessibilityHidden(true)
                            Text(zoneNames[i])
                            Spacer()
                            Text("\(Int((boundaries[i] * 100).rounded()))%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Button("Reset zones to defaults") { resetZones() }
                    .font(.footnote)
            } header: {
                Text("Heart rate zones")
            } footer: {
                Text("Max HR defaults to 220 − age. Zone edges are percentages of max HR and stay at least 3% apart — the same rule the web app enforces.")
            }

            InjuriesSection()
        }
        .listStyle(.insetGrouped)
        .onAppear {
            if let o = appState.profile.hrConfig?.maxHROverride { maxHRInput = String(o) }
        }
    }

    private var dobBinding: Binding<Date> {
        Binding(
            get: {
                if let dob = appState.profile.dateOfBirth, let d = dobDate(dob) { return d }
                return Date()
            },
            set: { d in
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                appState.profile.dateOfBirth = f.string(from: d)
                Task { await appState.saveProfile() }
            }
        )
    }

    /// Bodyweight is a series of its own, not a profile field: the ×BW
    /// standards read `bodyweight_kg` against the day of each result.
    private func logBodyweight() {
        let text = bodyweightInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        Task {
            if let problem = await appState.logResult(benchmarkId: "bodyweight_kg", text: text) {
                bodyweightError = problem
                AppHaptics.error()
            } else {
                bodyweightError = nil
                bodyweightInput = ""
                AppHaptics.success()
            }
        }
    }

    private func saveMaxHROverride() {
        guard let v = Int(maxHRInput), (100...250).contains(v) else { return }
        var cfg = appState.profile.hrConfig ?? HRConfig()
        cfg.maxHROverride = v
        appState.profile.hrConfig = cfg
        Task { await appState.saveProfile() }
    }

    private func clearMaxHROverride() {
        maxHRInput = ""
        var cfg = appState.profile.hrConfig ?? HRConfig()
        cfg.maxHROverride = nil
        appState.profile.hrConfig = cfg
        Task { await appState.saveProfile() }
    }

    /// Minimum 3% gap between neighbours, first edge ≥ 40%, last ≤ 97% — the
    /// web's HRSettingsOverview rule, so both clients accept the same values.
    private func setBoundary(_ i: Int, percent: Int) {
        var next = boundaries
        let lower = i == 0 ? 0.40 : next[i - 1] + 0.03
        let upper = i == 3 ? 0.97 : next[i + 1] - 0.03
        next[i] = min(upper, max(lower, Double(percent) / 100))
        var cfg = appState.profile.hrConfig ?? HRConfig()
        cfg.zoneBoundaries = next
        appState.profile.hrConfig = cfg
        Task { await appState.saveProfile() }
    }

    private func resetZones() {
        maxHRInput = ""
        appState.profile.hrConfig = HRConfig()
        Task { await appState.saveProfile() }
    }

    private func dobDate(_ string: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: string)
    }
    private func computeAge(_ dob: String) -> Int? {
        guard let date = dobDate(dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year
    }
}

// MARK: - Zone bar

/// The five zones as one bar in the zone colours (§3.5), each segment as wide
/// as its share of the heart rates from Z1's floor to max, its name inside and
/// its bpm range under it. Z1 has no lower edge, so it is drawn from 10 %
/// under its top.
private struct HRZoneBar: View {
    let boundaries: [Double]
    let maxHR: Int

    private var edges: [Double] {
        [max(0, boundaries[0] - 0.10)] + boundaries + [1.0]
    }

    private func bpm(_ fraction: Double) -> Int { Int((Double(maxHR) * fraction).rounded()) }

    private func range(_ zone: Int) -> String {
        switch zone {
        case 1: return "<\(bpm(edges[1]))"
        case 5: return "\(bpm(edges[4]))+"
        default: return "\(bpm(edges[zone - 1]))–\(bpm(edges[zone]))"
        }
    }

    var body: some View {
        let e = edges
        let span = e[5] - e[0]
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let usable = geo.size.width - spacing * 4
            // A floor so a 3 %-wide zone still fits its name, then scaled back
            // so the five always fill the row exactly.
            let raw = (1...5).map { max(28, usable * (e[$0] - e[$0 - 1]) / span) }
            let fit = usable / raw.reduce(0, +)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(1...5, id: \.self) { zone in
                    let width = raw[zone - 1] * fit
                    VStack(spacing: 3) {
                        Text("Z\(zone)")
                            .font(.caption2).fontWeight(.bold)
                            .foregroundStyle(.black.opacity(0.75))
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .background(HRZoneStyle.color(zone),
                                        in: RoundedRectangle(cornerRadius: 4))
                        Text(range(zone))
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(width: width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Zone \(zone), \(range(zone)) beats per minute")
                }
            }
        }
        .frame(height: 40)
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
            if !appState.constraintDifferences.isEmpty {
                Section { RegenerateOfferCard() }
            }
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

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: ProfileTab = .athlete
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            AppSubTabScreen(selection: $selectedTab) { tab in
                switch tab {
                case .athlete:    AthleteTab()
                case .equipment:  EquipmentTab()
                case .standards:  StandardsTab()
                case .schedule:   ScheduleTab()
                }
            }
            .task { applyRequestedSection() }
            .onChange(of: router.profileSection) { applyRequestedSection() }
            .navigationTitle("Profile")
            .appTabStyle()
            .toolbar {
                // Configuration lives one push away: connections, devices and
                // sync status, appearance, sign-out. The training level moved
                // into the Athlete section, where the rest of "who is
                // training" lives.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task {
                await appState.loadInjuryFlagsIfNeeded()
                await appState.loadBenchmarksIfNeeded()
                if appState.standardResults == nil { await appState.loadStandardResults() }
            }
        }
    }
}

// MARK: - Log a result

/// Logs a new result on one standard. The field reads what the athlete would
/// write — "4:58" for a time — and the server parses it; a value it cannot
/// read comes back in its own words instead of being dropped.
private struct StandardResultSheet: View {
    let standard: AppBenchmark
    let result: StandardResult?

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var problem: String? = nil
    @State private var saving = false

    private var canSave: Bool { !saving && !inputText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(standard.inputHint ?? "Result", text: $inputText)
                            .keyboardType(standard.inputHint == "m:ss" || standard.inputHint == "h:mm:ss"
                                          ? .numbersAndPunctuation : .decimalPad)
                            .onSubmit(save)
                        if let hint = standard.inputHint { Text(hint).foregroundStyle(.secondary) }
                    }
                    if let problem {
                        Text(problem).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text(standard.name)
                } footer: {
                    if let current = result?.current {
                        Text("Now \(current.valueText) (\(StandardLevel.name(current.level).lowercased()))"
                             + (result.map { $0.best.value != current.value ? ", best \($0.best.valueText)" : "" } ?? ""))
                    }
                }
                Section("Standards") {
                    StandardLadder(thresholds: standard.thresholdTexts, levelIndex: result?.current.levelIndex,
                                   domain: standard.domain)
                        .padding(.vertical, 4)
                    if let notes = standard.notes {
                        Text(notes).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log a result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        let text = inputText.trimmingCharacters(in: .whitespaces)
        Task {
            let failure = await appState.logResult(benchmarkId: standard.id, text: text)
            saving = false
            if let failure {
                problem = failure
                AppHaptics.error()
            } else {
                AppHaptics.success()
                dismiss()
            }
        }
    }
}

extension ProfileView {
    /// Move to the section the router asked for (a deep link), then clear it
    /// so a later visit keeps the user's own last choice.
    fileprivate func applyRequestedSection() {
        guard let requested = router.profileSection else { return }
        if selectedTab != requested {
            withAnimation(AppAnimation.springStandard) { selectedTab = requested }
        }
        router.clearProfileSection()
    }
}
