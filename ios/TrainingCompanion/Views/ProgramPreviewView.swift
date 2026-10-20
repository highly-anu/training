import SwiftUI

/// Program ▸ Preview: a generated program before it is anyone's
/// (design-system §6.39; the web's `pages/ProgramPreview.tsx`).
///
/// The builder's last step and the Program settings sheet's full regenerate
/// land here with a draft (`.new`); the profile's regenerate offer with the
/// rest of the active program rebuilt for the new settings (`.regenerate`).
/// The athlete sees the plan, what their constraints held back and what
/// would restore it, adjusts and swaps on the draft, and only Start / Apply
/// saves it. The builder used to post `persist: true` and throw the answer
/// away — a refusal silently kept the old program.
struct ProgramPreviewView: View {
    enum Mode: Equatable {
        case new
        /// The tail from week index `start`; `changed` marks the sessions the
        /// change moves ("weekIndex|day|sessionIndex").
        case regenerate(start: Int, changed: Set<String>)
    }

    @EnvironmentObject var appState: AppState
    let mode: Mode
    /// Called once the draft is saved (true) or the athlete leaves it (false).
    let onFinished: (Bool) -> Void
    /// Days and minutes are the schedule's: the builder's step 2, or the
    /// profile's Schedule. Nil hides the action.
    var onEditSchedule: (() -> Void)? = nil

    @State private var request: GenerateProgramRequest
    @State private var draft: GeneratedProgram
    @State private var changed: Set<String>
    @State private var edits = 0
    /// Bumped on each re-preview, so Held back asks again.
    @State private var generation = 0
    @State private var tab: PreviewTab = .plan
    @State private var impact: ImpactState = .loading
    @State private var isWorking = false
    @State private var error: String? = nil
    @State private var target: SessionTarget? = nil
    @State private var adjusting = false
    @State private var confirming = false
    @State private var addToProfile = true

    init(mode: Mode, request: GenerateProgramRequest, draft: GeneratedProgram,
         onEditSchedule: (() -> Void)? = nil, onFinished: @escaping (Bool) -> Void) {
        self.mode = mode
        self.onFinished = onFinished
        self.onEditSchedule = onEditSchedule
        _request = State(initialValue: request)
        _draft = State(initialValue: draft)
        if case .regenerate(_, let changed) = mode {
            _changed = State(initialValue: changed)
        } else {
            _changed = State(initialValue: [])
        }
        #if DEBUG
        // `TC_PREVIEW_TAB=heldback` opens on Held back (ProgramPreviewDebugLaunch).
        if ProcessInfo.processInfo.environment["TC_PREVIEW_TAB"] == "heldback" {
            _tab = State(initialValue: .heldBack)
        }
        #endif
    }

    private enum PreviewTab: Int, AppSubTab {
        case plan, heldBack
        var label: String { self == .plan ? "Plan" : "Held back" }
    }

    enum ImpactState {
        case loading
        case loaded(ConstraintImpact)
        case failed(String)
    }

    struct SessionTarget: Identifiable {
        let weekIndex: Int
        let day: String
        let sessionIndex: Int
        var id: String { "\(weekIndex)|\(day)|\(sessionIndex)" }
    }

    private var names: HeldBack.Names {
        HeldBack.Names(exercise: { appState.exerciseCatalog[$0]?.name },
                       flag: { id in appState.injuryFlagDefs.first { $0.id == id }?.name })
    }

    private var title: String {
        let ids = request.sourceIds
        let names = appState.philosophies.filter { ids.contains($0.id) }.map(\.name)
        return names.isEmpty ? (ids.first.map(HeldBack.label) ?? "Program") : names.joined(separator: " + ")
    }

    private var startWeek: Int {
        if case .regenerate(let start, _) = mode { return start + 1 }
        return 1
    }

    /// Equipment the draft is built for that the profile lacks: offered back.
    private var extraEquipment: [String] {
        guard mode == .new else { return [] }
        return ProgramConstraintsDiff.realEquipment(request.constraints.equipment)
            .filter { !appState.profile.equipment.contains($0) }
    }

    var body: some View {
        List {
            headerSection
            if draft.isInfeasible {
                refusedSections
            } else {
                switch tab {
                case .plan: planSections
                case .heldBack: heldBackSections
                }
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !draft.isInfeasible {
                AppSubTabPicker(selection: $tab).background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { commitBar }
        .navigationTitle(mode == .new ? "Preview" : "Preview changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Adjust") { adjusting = true }.disabled(isWorking)
            }
        }
        .task(id: generation) { await loadImpact() }
        .task { await appState.loadExercisesIfNeeded(); await appState.loadInjuryFlagsIfNeeded() }
        .sheet(item: $target) { t in
            PreviewSessionSheet(program: draft, target: t, request: request, names: names) { edited in
                draft = edited
                edits += 1
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $adjusting) {
            PreviewAdjustSheet(constraints: request.constraints, edits: edits,
                               onEditSchedule: onEditSchedule.map { action in { adjusting = false; action() } }) { c in
                adjusting = false
                Task { await repreview(c) }
            }
            .environmentObject(appState)
        }
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(confirmAction) { Task { await commit() } }
            Button("Keep previewing", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                if !draft.isInfeasible {
                    let counts = HeldBack.counts(draft)
                    Text("\(draft.weeks.count) weeks"
                         + (counts.sessions > 0 ? " · \(counts.sessions) session\(counts.sessions == 1 ? "" : "s") with something held back" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                    PhaseProgressBar(weeks: draft.weeks, currentIndex: nil)
                }
                if case .regenerate = mode, !changed.isEmpty, !draft.isInfeasible {
                    Text("Your new settings change \(changed.count) session\(changed.count == 1 ? "" : "s"), marked below. Weeks before week \(startWeek), and the days already behind you this week, stay as they are.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isWorking {
                    HStack(spacing: 8) { ProgressView(); Text("Previewing again…").font(.caption) }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var planSections: some View {
        ForEach(Array(draft.weeks.enumerated()), id: \.offset) { wi, week in
            Section {
                ForEach(Regeneration.dayOrder, id: \.self) { day in
                    ForEach(Array((week.schedule[day] ?? []).enumerated()), id: \.offset) { si, session in
                        sessionRow(session, day: day, target: SessionTarget(weekIndex: wi, day: day, sessionIndex: si))
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Week \(week.weekNumber)")
                    Text(week.phaseLabel).foregroundStyle(PhaseStyle.color(for: week.phase))
                    if week.isDeload { Text("Deload") }
                }
            } footer: {
                if !week.testsSkippedReasons.isEmpty {
                    Text("Test skipped: " + week.testsSkippedReasons.map(HeldBack.label).joined(separator: ", "))
                }
            }
        }
    }

    private func sessionRow(_ session: ProgramSession, day: String, target: SessionTarget) -> some View {
        let held = HeldBack.heldBackSlots(session)
        let notes = HeldBack.sessionNotes(session)
        let isChanged = changed.contains(target.id)
        return Button {
            AppHaptics.light()
            self.target = target
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(day.prefix(3)).font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                Image(systemName: ModalityStyle.icon(for: session.modality))
                    .foregroundStyle(ModalityStyle.color(for: session.modality))
                    .font(.caption)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.archetype?.name ?? ModalityStyle.label(for: session.modality))
                            .font(.subheadline).foregroundStyle(.primary)
                        if session.testInfo != nil { TestBadge() }
                    }
                    if held > 0 {
                        // Symbol and words, never colour alone (§1.6).
                        Label("\(held) held back", systemImage: "circle.slash")
                            .labelStyle(.inline)
                            .font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(notes, id: \.self) { n in
                        Text(n).font(.caption).foregroundStyle(.orange)
                    }
                    if isChanged {
                        Label("Changes", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.inline)
                            .font(.caption).fontWeight(.medium).foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isChanged ? Color.accentColor.opacity(0.08) : nil)
    }

    @ViewBuilder
    private var heldBackSections: some View {
        let counts = HeldBack.counts(draft)
        Section("In this program") {
            Text(counts.slots == 0 && counts.sessions == 0
                 ? "No slot is left empty and no session runs in place of another."
                 : "\(counts.slots) exercise slot\(counts.slots == 1 ? "" : "s") left empty across \(counts.sessions) session\(counts.sessions == 1 ? "" : "s"); open a session in Plan for why.")
                .font(.subheadline)
        }
        let schedule = HeldBack.scheduleFindings(draft)
        if !schedule.isEmpty {
            Section {
                ForEach(schedule, id: \.self) { Text($0).font(.caption) }
                if let onEditSchedule {
                    Button("Change schedule", action: onEditSchedule)
                }
            } header: {
                Text("Schedule")
            }
        }
        switch impact {
        case .loading:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking what your constraints change — this builds the program several ways (about 10 s).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Section { Text("Could not compare against the unconstrained program: \(message)").font(.caption) }
        case .loaded(let result):
            impactSections(result)
        }
    }

    @ViewBuilder
    private func impactSections(_ result: ConstraintImpact) -> some View {
        if !result.referenceGenerates {
            Section { Text(result.detail ?? "Nothing to compare the program with.").font(.caption) }
        } else if result.direct.isEmpty {
            Section {
                Text("Your constraints change nothing: this is the program the methodology writes with nothing in the way.")
                    .font(.subheadline)
            }
        } else {
            Section {
                ForEach(result.restore.prefix(6)) { r in
                    Button {
                        Task { await addEquipment([r.id]) }
                    } label: {
                        Label("Add \(HeldBack.label(r.id)) · restores \(r.changes)", systemImage: "plus.circle")
                    }
                    .disabled(isWorking)
                }
                if result.lifted.contains("injury"), let text = result.lifts["injury"] {
                    Button("Preview \(text)") { Task { await repreviewPatch { $0.injuryFlags = [] } } }
                        .disabled(isWorking)
                }
                if result.lifted.contains("level"), let level = result.reference?.trainingLevel {
                    Button("Preview at \(level)") { Task { await repreviewPatch { $0.trainingLevel = level } } }
                        .disabled(isWorking)
                }
            } header: {
                Text("What would restore it")
            } footer: {
                Text("\(result.direct.count)\(result.sessionsTotal.map { " of \($0)" } ?? "") session\(result.direct.count == 1 && result.sessionsTotal == nil ? "" : "s") change against the same program with nothing in the way. Each action previews again; your profile changes only if you start the program and keep the switch on.")
            }
            ForEach(["equipment", "injury", "level", "proficiency", "combined"], id: \.self) { cause in
                let group = result.direct.filter { $0.primaryCause == cause }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { change in
                            let line = change.line
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.title).font(.caption).fontWeight(.medium)
                                ForEach(line.detail, id: \.self) {
                                    Text($0).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("\(Self.causeLabel(cause)) · \(group.count)")
                    }
                }
            }
            if !result.knockOn.isEmpty {
                Section {
                    Text("\(result.knockOn.count) more change\(result.knockOn.count == 1 ? "" : "s") follow from these: the rotation moved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func causeLabel(_ cause: String) -> String {
        switch cause {
        case "equipment": return "Equipment"
        case "injury": return "Injuries"
        case "level": return "Level"
        case "proficiency": return "Proficiency"
        case "schedule": return "Schedule"
        default: return "More than one constraint"
        }
    }

    @ViewBuilder
    private var refusedSections: some View {
        let v = draft.validation
        Section("Can't build as asked") {
            ForEach(v?.errors ?? []) { Text($0.message).font(.subheadline) }
            if v?.errors.isEmpty ?? true {
                Text("The methodology cannot build this program with these settings.").font(.subheadline)
            }
        }
        switch impact {
        case .loading:
            Section { HStack(spacing: 10) { ProgressView(); Text("Finding what would let it build…").font(.caption) } }
        case .failed:
            EmptyView()
        case .loaded(let result) where !result.unblockedBy.isEmpty:
            Section("What would let it build") {
                ForEach(result.unblockedBy, id: \.self) { u in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Self.causeLabel(u.cause)): \(u.text)").font(.subheadline)
                        unblockAction(u.cause, result: result)
                    }
                    .padding(.vertical, 2)
                }
            }
        case .loaded:
            EmptyView()
        }
        Section {
            Button("Adjust") { adjusting = true }
        }
    }

    @ViewBuilder
    private func unblockAction(_ cause: String, result: ConstraintImpact) -> some View {
        switch cause {
        case "equipment":
            let missing = ProgramConstraintsDiff.realEquipment(result.reference?.equipment ?? [])
                .filter { !request.constraints.equipment.contains($0) }
            if !missing.isEmpty {
                Button("Add \(missing.map(HeldBack.label).joined(separator: ", ")) and preview") {
                    Task { await addEquipment(missing) }
                }
                .buttonStyle(.bordered).disabled(isWorking)
            }
        case "injury":
            Button("Preview without the injury flags") { Task { await repreviewPatch { $0.injuryFlags = [] } } }
                .buttonStyle(.bordered).disabled(isWorking)
        case "level":
            if let level = result.reference?.trainingLevel {
                Button("Preview at \(level)") { Task { await repreviewPatch { $0.trainingLevel = level } } }
                    .buttonStyle(.bordered).disabled(isWorking)
            }
        case "schedule":
            if let onEditSchedule {
                Button("Change schedule", action: onEditSchedule).buttonStyle(.bordered)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Commit

    private var commitBar: some View {
        VStack(spacing: 8) {
            if !extraEquipment.isEmpty && !draft.isInfeasible {
                Toggle("Also add \(extraEquipment.map(HeldBack.label).joined(separator: ", ")) to my profile",
                       isOn: $addToProfile)
                    .font(.footnote)
            }
            Button {
                confirming = true
            } label: {
                Text(mode == .new ? "Start this program" : "Apply from week \(startWeek)")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(draft.isInfeasible || isWorking)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var hasActive: Bool { appState.serverProgram?.currentProgram != nil }

    private var confirmTitle: String {
        switch mode {
        case .new: return hasActive ? "Replace your current program?" : "Start this program?"
        case .regenerate: return "Apply the changes from week \(startWeek)?"
        }
    }
    private var confirmAction: String {
        switch mode {
        case .new: return hasActive ? "Replace" : "Start"
        case .regenerate: return "Apply"
        }
    }
    private var confirmMessage: String {
        switch mode {
        case .new:
            return hasActive
                ? "\(title) becomes your program. The one you are on now stays in Program ▸ History with its logs and linked workouts."
                : "\(title) becomes your program."
        case .regenerate:
            return "The rest of your program is rebuilt for your new settings. The weeks and days already behind you keep their sessions, logs and linked workouts."
        }
    }

    private func commit() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            switch mode {
            case .new:
                try await appState.startProgram(draft, request: request)
                if addToProfile && !extraEquipment.isEmpty {
                    appState.profile.equipment += extraEquipment
                    await appState.saveProfile()
                }
            case .regenerate(let start, _):
                try appState.applyRegeneratedTail(draft, from: start)
            }
            AppHaptics.success()
            onFinished(true)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Re-preview

    private func loadImpact() async {
        impact = .loading
        do {
            impact = .loaded(try await appState.programImpact(request))
        } catch is CancellationError {
        } catch {
            impact = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func addEquipment(_ ids: [String]) async {
        await repreviewPatch { c in
            for id in ids where !c.equipment.contains(id) { c.equipment.append(id) }
        }
    }

    private func repreviewPatch(_ patch: (inout GenerateConstraints) -> Void) async {
        var c = request.constraints
        patch(&c)
        await repreview(c)
    }

    /// The same request with other constraints, previewed again; swaps on
    /// the draft are dropped with it, and the change marks no longer apply.
    private func repreview(_ constraints: GenerateConstraints) async {
        guard let api = appState.api else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        let next = request.with(constraints: constraints)
        do {
            let d = try await api.generateProgramPreview(next)
            request = next
            draft = d
            edits = 0
            changed = []
            generation += 1
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - One session of the draft

private struct PreviewSessionSheet: View {
    let program: GeneratedProgram
    let target: ProgramPreviewView.SessionTarget
    let request: GenerateProgramRequest
    let names: HeldBack.Names
    let onEdit: (GeneratedProgram) -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var swapIndex: SwapIndex? = nil

    private struct SwapIndex: Identifiable { let value: Int; var id: Int { value } }

    var body: some View {
        let week = program.weeks[safe: target.weekIndex]
        let session = week?.schedule[target.day]?[safe: target.sessionIndex]
        NavigationStack {
            List {
                if let session {
                    let notes = HeldBack.sessionNotes(session)
                    if !notes.isEmpty {
                        Section { ForEach(notes, id: \.self) { Text($0).font(.subheadline) } }
                    }
                    Section {
                        ForEach(Array(session.exercises.enumerated()), id: \.offset) { i, ea in
                            if !(ea.meta || ea.skipsExercise) { exerciseRow(ea, index: i, swappable: session.archetype != nil) }
                        }
                    } footer: {
                        Text("Changes here edit this preview only; nothing is saved until you start the program.")
                    }
                }
            }
            .navigationTitle(session?.archetype?.name ?? session.map { ModalityStyle.label(for: $0.modality) } ?? "Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $swapIndex) { s in
                SwapExerciseSheet(weekIndex: target.weekIndex, dayName: target.day,
                                  sessionIndex: target.sessionIndex, exerciseIndex: s.value,
                                  draft: .init(program: program, philosophyIds: request.sourceIds,
                                               constraints: request.constraints) { assignment in
                                      onEdit(ProgramEdits.replacingExercise(
                                          in: program, weekIndex: target.weekIndex, day: target.day,
                                          sessionIndex: target.sessionIndex, exerciseIndex: s.value,
                                          with: assignment))
                                  })
                .environmentObject(appState)
            }
        }
    }

    private func exerciseRow(_ ea: ProgramExerciseAssignment, index: Int, swappable: Bool) -> some View {
        let empty = HeldBack.emptySlotText(ea, names: names)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ea.exercise?.name ?? HeldBack.label(ea.slotRole ?? "slot"))
                    .font(.body).fontWeight(ea.exercise == nil ? .regular : .medium)
                    .foregroundStyle(ea.exercise == nil ? .secondary : .primary)
                if ea.exercise != nil {
                    Text(LoadFormat.describe(ea)).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                }
                if let was = ea.substitutedForExercise {
                    let flag = ea.substitutedByFlag.map { " (\(names.flag($0) ?? HeldBack.label($0)))" } ?? ""
                    Text("In place of \(names.exercise(was) ?? HeldBack.label(was))\(flag)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let empty {
                    Label(empty, systemImage: "circle.slash")
                        .labelStyle(.inline)
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            if ea.exercise != nil && swappable {
                Button {
                    swapIndex = SwapIndex(value: index)
                } label: {
                    Label("Swap", systemImage: "arrow.left.arrow.right").labelStyle(.inline).font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Adjust

private struct PreviewAdjustSheet: View {
    @State var constraints: GenerateConstraints
    let edits: Int
    let onEditSchedule: (() -> Void)?
    let onApply: (GenerateConstraints) -> Void
    @Environment(\.dismiss) private var dismiss

    init(constraints: GenerateConstraints, edits: Int, onEditSchedule: (() -> Void)?,
         onApply: @escaping (GenerateConstraints) -> Void) {
        _constraints = State(initialValue: constraints)
        self.edits = edits
        self.onEditSchedule = onEditSchedule
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Level", selection: $constraints.trainingLevel) {
                        ForEach(["novice", "intermediate", "advanced", "elite"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Training Level")
                } footer: {
                    Text("Change what the program is built for and preview it again. Your profile stays as it is.")
                }
                EquipmentToggleSection(selection: $constraints.equipment)
                InjuryToggleSection(selection: $constraints.injuryFlags)
                if let onEditSchedule {
                    Section {
                        Button("Change the schedule", action: onEditSchedule)
                    } footer: {
                        Text("Days and session length come from the schedule.")
                    }
                }
                if edits > 0 {
                    Section {
                        Label("Previewing again replaces your \(edits) swap\(edits == 1 ? "" : "s") on this draft.",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update preview") { onApply(constraints) }.fontWeight(.semibold)
                }
            }
        }
    }
}

#if DEBUG
/// `SIMCTL_CHILD_TC_PREVIEW=<philosophy id>` (and `TC_PREVIEW_WEEKS`, default
/// 8) opens Program ▸ Preview on launch with a draft built from the profile's
/// level, equipment, injuries and schedule — the builder's last step without
/// the taps the simulator cannot script (`ROUTE='trainingcompanion://program'`).
enum ProgramPreviewDebugLaunch {
    @MainActor
    static func draft(appState: AppState,
                      environment: [String: String] = ProcessInfo.processInfo.environment) async -> PreviewDraft? {
        guard let id = environment["TC_PREVIEW"], !id.isEmpty, let api = appState.api else { return nil }
        await appState.loadProfile()   // the launch may not have read it yet
        let p = appState.profile
        var c = GenerateConstraints()
        c.trainingLevel = p.trainingLevel
        c.equipment = p.equipment
        c.injuryFlags = p.injuryFlags
        c.daysPerWeek = ProgramConstraintsDiff.daysPerWeek(p.weeklySchedule) ?? 3
        c.sessionTimeMinutes = 75
        let request = GenerateProgramRequest(philosophyId: id, constraints: c,
                                             numWeeks: Int(environment["TC_PREVIEW_WEEKS"] ?? "") ?? 8,
                                             startDate: nil, eventDate: nil)
        guard let draft = try? await api.generateProgramPreview(request) else { return nil }
        return PreviewDraft(request: request, draft: draft)
    }
}
#endif
