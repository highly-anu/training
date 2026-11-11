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

// MARK: - Equipment categories (Profile's sections, the same data as the web's)

private struct EquipmentCategory {
    let name: String       // matches EquipmentItem.group exactly
    let color: Color       // the colour of the training the section serves
}

/// Profile's sections, in order, from data/commons/constraints/equipment.yaml
/// (ClientVocab.equipmentSections).
private let equipmentCategories: [EquipmentCategory] = ClientVocab.equipmentSections.map {
    EquipmentCategory(name: $0.name, color: ClientVocab.color($0.hex))
}

// MARK: - Shared selection card

/// One thing the athlete has or has not (a piece of equipment, an injury):
/// the app's card (§6.15), ringed and washed in its colour with a tick when
/// selected. Until 1.39 it drew its own surface at the control radius and
/// said "selected" by colour alone.
private struct SelectionCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppMetrics.gapSmall) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .appCard(compact: true, border: isSelected ? accentColor : nil, tint: isSelected ? accentColor : nil)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Custom tab bar

// MARK: - Equipment Tab

private struct EquipmentTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            if appState.showsRegenerateOffer {
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
                                    accentColor: category.color
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
                            accentColor: AppColor.destructive
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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.warning)
                        .font(.caption)
                    Text(custom.description)
                    Spacer()
                    // Visible; the swipe removes it too (§6.51).
                    Button {
                        AppHaptics.light()
                        appState.profile.customInjuryFlags.removeAll { $0.id == custom.id }
                        Task { await appState.saveProfile() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppColor.destructive)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(custom.description)")
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
/// the server. Tap a row for its history, to log, correct or delete a result.
private struct StandardsTab: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var router: AppRouter
    @State private var open: AppBenchmark? = nil
    @State private var bodyweightOpen = false
    @State private var showAll = false

    /// The current program's own standards (declared or tested), in the server's order.
    private var programRows: [AppBenchmark] {
        let byId = Dictionary(uniqueKeysWithValues: appState.benchmarks.map { ($0.id, $0) })
        return (appState.standardResults?.programStandards ?? []).compactMap { byId[$0] }
    }
    /// Every other standard with a result, from this program or earlier ones.
    private var resultRows: [AppBenchmark] {
        let own = Set(programRows.map(\.id))
        return appState.benchmarks.filter { appState.standardResults?.standards[$0.id] != nil && !own.contains($0.id) }
    }
    /// The rest, by group: the reference ladders.
    private var groups: [(name: String, rows: [AppBenchmark])] {
        let placed = Set((programRows + resultRows).map(\.id))
        let byCategory = Dictionary(grouping: appState.benchmarks.filter { !placed.contains($0.id) }, by: \.category)
        return byCategory.values
            .sorted { ($0.first?.categoryOrder ?? 99, $0.first?.groupName ?? "") < ($1.first?.categoryOrder ?? 99, $1.first?.groupName ?? "") }
            .map { (name: $0.first?.groupName ?? "", rows: $0) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.benchmarks.isEmpty
                         ? (appState.isLoadingBenchmarks ? "Loading the standards…" : "The standards could not be loaded.")
                         : "\(appState.benchmarks.count) standards.")
                        .font(.headline)
                    Text("Log a result whenever you test one. Every result is kept with its date, so you can see where you stand now and how far you have come across programs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.profile.sex.map { "Showing the \($0) standards." }
                         ?? "Showing the male standards until you set your sex under Athlete.")
                        .font(.caption2)
                        .foregroundStyle(appState.profile.sex == nil ? AppColor.warning : Color.secondary)
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

            if !appState.standardSuggestions.isEmpty {
                Section {
                    ForEach(appState.standardSuggestions) { StandardSuggestionRow(suggestion: $0) }
                } header: {
                    Text("To confirm")
                } footer: {
                    Text("Results your sessions and imported runs suggest. They count once you save them.")
                }
            }
            if !programRows.isEmpty {
                Section {
                    ForEach(programRows) { row($0) }
                } header: {
                    Text("This program")
                } footer: {
                    Text("What your current program is measured by: declared by its methodology, or tested in it.")
                }
            }
            if !resultRows.isEmpty {
                Section {
                    ForEach(resultRows) { row($0) }
                } header: {
                    Text("Your results")
                } footer: {
                    Text("Every other standard you have a result on, from this program or earlier ones.")
                }
            }
            // With nothing of the program's and no result, the reference is the page.
            let allOpen = showAll || (programRows.isEmpty && resultRows.isEmpty)
            if !(programRows.isEmpty && resultRows.isEmpty) {
                Section {
                    Button(allOpen ? "Hide the other standards" : "Show all \(groups.reduce(0) { $0 + $1.rows.count }) other standards") {
                        withAnimation(AppAnimation.layoutChange) { showAll.toggle() }
                    }
                }
            }
            if allOpen {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.rows) { row($0) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await AppRefresh.perform {
                await appState.loadStandardResults()
                await appState.loadStandardSuggestions()
            }
        }
        .sheet(item: $open) { standard in
            StandardDetailSheet(subject: .standard(standard))
        }
        .sheet(isPresented: $bodyweightOpen) { StandardDetailSheet(subject: .bodyweight) }
        .task { applyPendingStandard() }
        .onChange(of: router.pendingStandardId) { applyPendingStandard() }
        .onChange(of: appState.benchmarks.count) { applyPendingStandard() }
    }
}

extension StandardsTab {
    fileprivate func row(_ standard: AppBenchmark) -> some View {
        StandardRow(standard: standard, result: appState.standardResults?.standards[standard.id])
            .contentShape(Rectangle())
            .onTapGesture { open = standard }
            .appTapRow()
    }

    /// Open the sheet a deep link asked for, once the standards are loaded.
    fileprivate func applyPendingStandard() {
        guard let id = router.pendingStandardId else { return }
        if id == "bodyweight_kg" {
            bodyweightOpen = true
        } else if let standard = appState.benchmarks.first(where: { $0.id == id }) {
            open = standard
        } else {
            return
        }
        router.clearPendingStandard()
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

    private let trainingLevels = ClientVocab.trainingLevels
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
    @State private var showBodyweightHistory = false

    var body: some View {
        List {
            if appState.showsRegenerateOffer {
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
                    Text(bodyweightError).font(.caption).foregroundStyle(AppColor.destructive)
                }
                if bodyweight != nil {
                    Button("Bodyweight history") { showBodyweightHistory = true }
                        .font(.footnote)
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
        .sheet(isPresented: $showBodyweightHistory) { StandardDetailSheet(subject: .bodyweight) }
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
        // As tall as a zone's name over its range at the athlete's type size
        // (a fixed 40 pt clipped the ranges at the larger ones until 1.39).
        VStack(spacing: 3) {
            Text("Z1").font(.caption2).fontWeight(.bold).frame(minHeight: 20)
            Text("000").font(.caption2)
        }
        .hidden()
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity)
        .overlay { GeometryReader { geo in
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
        } }
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

private let sessionTypeChoices: [SessionType] = [.rest, .short, .long, .mobility]

private func sessionTypeText(_ type: SessionType) -> String {
    switch type {
    case .rest:     return "Rest"
    case .short:    return "Short"
    case .long:     return "Long"
    case .mobility: return "Mobility"
    }
}

/// One session slot of a day: a menu of the four types, the current one
/// ticked (§6.51). Until 1.38 a tap cycled to the next type, so reaching
/// Rest from Short took three taps and nothing said what came next.
private struct SessionChip: View {
    let label: String
    let type: SessionType
    let onPick: (SessionType) -> Void

    private var chipColor: Color {
        switch type {
        case .rest:     return AppColor.Schedule.rest
        case .short:    return AppColor.Schedule.short
        case .long:     return AppColor.Schedule.long
        case .mobility: return AppColor.Schedule.mobility
        }
    }

    var body: some View {
        Menu {
            Picker(label, selection: Binding(get: { type }, set: { picked in
                AppHaptics.selection()
                onPick(picked)
            })) {
                ForEach(sessionTypeChoices, id: \.self) { choice in
                    Text(sessionTypeText(choice)).tag(choice)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(sessionTypeText(type))
                    .font(AppFont.microStrong)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.micro)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(chipColor.opacity(AppColor.Opacity.fill))
            .foregroundStyle(chipColor)
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.radiusChip))
            .overlay(RoundedRectangle(cornerRadius: AppMetrics.radiusChip).stroke(chipColor.opacity(0.4)))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(sessionTypeText(type))
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
                .accessibilityHidden(true)
            Text(day)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(minWidth: 86, alignment: .leading)
            HStack(spacing: 6) {
                SessionChip(label: "\(day), session 1", type: daySchedule.session1) {
                    daySchedule.session1 = $0
                    onChanged()
                }
                if showS2 {
                    SessionChip(label: "\(day), session 2", type: daySchedule.session2) {
                        daySchedule.session2 = $0
                        onChanged()
                    }
                }
                if showS3 {
                    SessionChip(label: "\(day), session 3", type: daySchedule.session3) {
                        daySchedule.session3 = $0
                        onChanged()
                    }
                }
                if showS4 {
                    SessionChip(label: "\(day), session 4", type: daySchedule.session4) {
                        daySchedule.session4 = $0
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
        case .long:     return AppColor.Schedule.long
        case .short:    return AppColor.Schedule.short
        case .mobility: return AppColor.Schedule.mobility
        case .rest:     return Color.accentColor
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
            if appState.showsRegenerateOffer {
                Section { RegenerateOfferCard() }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekly availability.")
                        .font(.headline)
                    Text("Configure your weekly schedule. Short = 30–45 min, Long = 60+ min, Mobility = 15–20 min. Tap a session to choose its type; a day's next session appears once the one before it is set.")
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
                Group {
                    switch tab {
                    case .athlete:    AthleteTab()
                    case .equipment:  EquipmentTab()
                    case .standards:  StandardsTab()
                    case .schedule:   ScheduleTab()
                    }
                }
                // What is shown is then this device's copy (§6.3). An inset,
                // not a stack: the bar collapses its title by the section's
                // own scroll view.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let error = appState.profileError {
                        AppErrorBanner(message: "Your profile could not be read: \(error)") {
                            await appState.loadProfile()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, AppMetrics.gapSmall)
                    }
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
