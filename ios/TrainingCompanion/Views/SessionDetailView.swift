import SwiftUI

struct SessionDetailView: View {
    let session: ProgramSession
    let sessionKey: String
    var weekIndex: Int? = nil
    var dayName: String? = nil
    var sessionIndex: Int? = nil

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var notes: String = ""
    /// 1–5, the scale the server stores and WorkoutDetailView renders; the
    /// slider used to run 1–10 and the server folded it, so "7" showed as "4/5".
    @State private var fatigueRating: Double = 3
    @State private var showFatigue = false
    @State private var isSaving = false
    @State private var showMove = false
    @State private var showReplace = false
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var exerciseSheet: ExerciseRowItem? = nil
    @State private var swapTarget: SwapTarget? = nil
    @State private var logTarget: ExerciseRowItem? = nil

    /// A row's identity is its position plus the exercise: the same movement
    /// can appear twice in a session, and a swap must animate only its row.
    private struct ExerciseRowItem: Identifiable {
        /// Position in the session's full `exercises` array — what a swap edits.
        let index: Int
        let assignment: ProgramExerciseAssignment
        var id: String { "\(index)-\(assignment.exercise?.id ?? "slot")" }
    }

    private struct SwapTarget: Identifiable {
        let exerciseIndex: Int
        var id: Int { exerciseIndex }
    }

    @State private var linkedTrimp: Int? = nil
    @State private var confirmRpe: Int = 7
    @State private var isConfirming = false
    @State private var confirmFailed = false
    @State private var changingVerdict = false
    @State private var liftAnswers: [String: LiftConfirmation.Answer] = [:]

    private var isDone: Bool { appState.isSessionComplete(sessionKey) }

    /// Live session read from the store (updated after replace/move).
    /// Falls back to the prop value when index params are unavailable.
    private var currentSession: ProgramSession {
        guard let wi = weekIndex, let dn = dayName, let si = sessionIndex,
              let live = appState.serverProgram?.currentProgram?.weeks[safe: wi]?.schedule[dn]?[safe: si]
        else { return session }
        return live
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if let workout = linkedWorkout { linkedWorkoutSection(workout) }
                exercisesSection
                if !progressingExercises.isEmpty && (isDone || linkedWorkout != nil) {
                    if loadLifts.isEmpty { progressSection } else { liftProgressSection }
                }
                if canEditProgram { actionsSection }
                if isDone { notesSection }
            }
            .navigationTitle(currentSession.archetype?.name ?? ModalityStyle.label(for: currentSession.modality))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                completionButton
                    .padding()
                    .background(.background)
            }
            .sheet(isPresented: $showMove) {
                if let wi = weekIndex, let dn = dayName, let si = sessionIndex,
                   let week = appState.serverProgram?.currentProgram?.weeks[safe: wi] {
                    MoveWorkoutSheet(weekIndex: wi, fromDay: dn,
                                    sessionIndex: si, weekSchedule: week.schedule)
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showReplace) {
                if let wi = weekIndex, let dn = dayName, let si = sessionIndex,
                   let api = appState.api {
                    ReplaceWorkoutSheet(api: api, weekIndex: wi, dayName: dn,
                                       sessionIndex: si, session: currentSession)
                        .environmentObject(appState)
                }
            }
            // The exercise reference (§6.14): what the movement is and how to
            // do it, without leaving the session.
            .sheet(item: $exerciseSheet) { item in
                if let ex = item.assignment.exercise {
                    ExerciseDetailSheet(exerciseId: ex.id, name: ex.name, assignment: item.assignment)
                        .environmentObject(appState)
                }
            }
            .sheet(item: $swapTarget) { target in
                if let wi = weekIndex, let dn = dayName, let si = sessionIndex {
                    SwapExerciseSheet(weekIndex: wi, dayName: dn, sessionIndex: si,
                                      exerciseIndex: target.exerciseIndex)
                        .environmentObject(appState)
                }
            }
            // What was done (§6.16): sets for a sets × reps slot, the slot's
            // currency for the rest — the inputs the web's loggers offer.
            .sheet(item: $logTarget) { item in
                ExerciseLogSheet(sessionKey: sessionKey, assignment: item.assignment)
                    .environmentObject(appState)
            }
            .task {
                // A test names its standards: their names and the athlete's
                // results come from the catalog and the results.
                if currentSession.testInfo != nil || currentSession.exercises.contains(where: { $0.standardId != nil }) {
                    await appState.loadBenchmarksIfNeeded()
                    if appState.standardResults == nil { await appState.loadStandardResults() }
                    await appState.loadStandardSuggestions()
                }
                if let log = appState.sessionLogs[sessionKey] {
                    notes = log.notes ?? ""
                    if let f = log.fatigueRating {
                        fatigueRating = Double(min(max(f, 1), 5))
                        showFatigue = true
                    }
                }
            }
        }
    }

    // MARK: - Program Actions

    private var canEditProgram: Bool {
        weekIndex != nil && dayName != nil && sessionIndex != nil && appState.api != nil
    }

    private var actionsSection: some View {
        Section("Workout") {
            Button { showMove = true } label: {
                Label("Move to Another Day", systemImage: "arrow.left.arrow.right")
            }
            Button { showReplace = true } label: {
                Label("Replace Workout", systemImage: "arrow.2.circlepath")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: ModalityStyle.icon(for: currentSession.modality))
                    .foregroundStyle(ModalityStyle.color(for: currentSession.modality))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ModalityStyle.label(for: currentSession.modality))
                        .font(.caption)
                        .foregroundStyle(ModalityStyle.color(for: currentSession.modality))
                    if let arch = currentSession.archetype {
                        Text(arch.name)
                            .font(.headline)
                        HStack(spacing: 8) {
                            if let mins = arch.durationEstimateMinutes {
                                Label("\(mins) min", systemImage: "clock")
                            }
                            if currentSession.isDeload {
                                Label("Deload", systemImage: "arrow.down.circle")
                                    .foregroundStyle(.orange)
                            }
                            if currentSession.testInfo != nil { TestBadge() }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            // A test of the phase's standards: what each result is measured
            // against, before the session starts.
            if let test = currentSession.testInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(test.insteadOf.map { "A test, in place of \($0). Log each result on its exercise; it comes back here to save." }
                         ?? "A test of this phase's standards. Log each result on its exercise; it comes back here to save.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(test.standards, id: \.self) { id in
                        StandardTargetRow(standardId: id)
                        SessionSuggestion(standardId: id, sessionKey: sessionKey)
                    }
                }
                .padding(.vertical, 2)
            }

            if let log = appState.sessionLogs[sessionKey], let completedAt = log.completedAt {
                Label("Completed · \(shortDateTime(completedAt))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
                if let avgHR = log.avgHR {
                    Label("Avg HR: \(avgHR) bpm", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Recorded Workout

    private var linkedWorkout: ImportedWorkout? { appState.linkedWorkout(forSessionKey: sessionKey) }

    /// What was recorded for this session — the same row Log ▸ Activity
    /// shows, pushing the full workout. Without the session chip: the row
    /// already sits on its session.
    private func linkedWorkoutSection(_ workout: ImportedWorkout) -> some View {
        Section("Recorded Workout") {
            NavigationLink {
                WorkoutDetailView(workout: workout)
                    .environmentObject(appState)
            } label: {
                WorkoutRow(workout: workout, trimp: linkedTrimp,
                           showsSession: false, showsChevron: false)
            }
        }
        .task(id: workout.id) {
            let hrConfig = appState.profile.hrConfig
            let dob = appState.profile.dateOfBirth
            linkedTrimp = await Task.detached(priority: .background) {
                AnalyticsEngine.computeWorkoutTRIMP(workout: workout, hrConfig: hrConfig, dateOfBirth: dob)
            }.value
        }
    }

    // MARK: - Exercises

    private var exercisesSection: some View {
        let rows = currentSession.exercises.enumerated()
            .filter { !$0.element.injurySkip && $0.element.exercise != nil }
            .map { ExerciseRowItem(index: $0.offset, assignment: $0.element) }
        return Section {
            if rows.isEmpty {
                Text("No exercises").foregroundStyle(.secondary)
            } else {
                ForEach(rows) { item in
                    Button {
                        AppHaptics.selection()
                        exerciseSheet = item
                    } label: {
                        exerciseRow(item.assignment)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            logTarget = item
                        } label: {
                            Label(logLabel(item.assignment), systemImage: "square.and.pencil")
                        }
                        Button {
                            exerciseSheet = item
                        } label: {
                            Label("About this exercise", systemImage: "info.circle")
                        }
                        if canSwap(item.assignment) {
                            Button {
                                swapTarget = SwapTarget(exerciseIndex: item.index)
                            } label: {
                                Label("Swap for an alternative", systemImage: "arrow.left.arrow.right")
                            }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            logTarget = item
                        } label: {
                            Label("Log", systemImage: "square.and.pencil")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canSwap(item.assignment) {
                            Button {
                                swapTarget = SwapTarget(exerciseIndex: item.index)
                            } label: {
                                Label("Swap", systemImage: "arrow.left.arrow.right")
                            }
                            .tint(.blue)
                        }
                    }
                }
                .animation(AppAnimation.layoutChange, value: rows.map(\.id))
            }
        } header: {
            Text("Exercises")
        } footer: {
            if !rows.isEmpty {
                // Gesture hints as symbols: tap for cues, swipe right to log,
                // left to swap.
                HStack(spacing: 14) {
                    Label("Cues", systemImage: "hand.tap")
                    Label("Log", systemImage: "arrow.right")
                    if canEditProgram && rows.contains(where: { canSwap($0.assignment) }) {
                        Label("Swap", systemImage: "arrow.left")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(canEditProgram && rows.contains(where: { canSwap($0.assignment) })
                    ? "Tap an exercise for cues. Swipe right to log it, left to swap it."
                    : "Tap an exercise for cues. Swipe right to log it.")
            }
        }
    }

    private func logLabel(_ ea: ProgramExerciseAssignment) -> String {
        SessionLogging.logsSets(LoadFormat.resolvedSlotType(ea)) ? "Log sets" : "Log result"
    }

    /// "Logged: 3 sets · 5×80 kg" under the prescription, once there is one.
    private func loggedSummary(_ ea: ProgramExerciseAssignment) -> String? {
        guard let id = ea.exercise?.id,
              let perf = appState.sessionLogs[sessionKey]?.exercises[id] else { return nil }
        return SessionLogging.summary(perf, slotType: LoadFormat.resolvedSlotType(ea))
    }

    /// A swap needs the slot the exercise fills; a meta entry or a slot the
    /// server did not name has nothing to rank alternatives for.
    private func canSwap(_ ea: ProgramExerciseAssignment) -> Bool {
        canEditProgram && currentSession.archetype != nil && ea.slotRole != nil && !ea.meta && ea.load.extra["module_id"] == nil
    }

    private func exerciseRow(_ ea: ProgramExerciseAssignment) -> some View {
        let ex = ea.exercise!
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ex.name)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                if let slotType = ea.slotType {
                    Text(LoadFormat.slotTypeLabel(slotType))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(LoadFormat.describe(ea))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if case .bool(true)? = ea.load.extra["conditional"] {
                Text("Forecast: advance only after clean completion at the prescribed effort.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let sid = ea.standardId {
                Label(appState.benchmarks.first { $0.id == sid }?.name ?? sid, systemImage: "trophy")
                    .font(.caption).foregroundStyle(Color.accentColor)
            }
            if let logged = loggedSummary(ea) {
                Label(logged, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            if let note = ea.notes ?? ex.notes {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Progress (training contracts)

    /// The exercises a training-contract session's progress rides on
    /// (`advances_module`): what "done as written" confirms.
    private var progressingExercises: [String] {
        currentSession.exercises.compactMap { ea in
            guard case .bool(true)? = ea.load.extra["advances_module"], let id = ea.exercise?.id else { return nil }
            return id
        }
    }

    /// What the log says about it: clean or not, and the RPE; nil until answered.
    private var moduleVerdict: (clean: Bool, rpe: Int?)? {
        guard let first = progressingExercises.first,
              let perf = appState.sessionLogs[sessionKey]?.exercises[first],
              let clean = perf.clean else { return nil }
        return (clean, perf.rpe)
    }

    private var progressSection: some View {
        Section {
            if let verdict = moduleVerdict, !changingVerdict {
                HStack {
                    Label(verdict.clean ? "Clean, as written\(verdict.rpe.map { " · RPE \($0)" } ?? "")"
                                        : "Not clean — the cycle holds here",
                          systemImage: verdict.clean ? "checkmark.seal.fill" : "minus.circle")
                        .foregroundStyle(verdict.clean ? Color.green : Color.secondary)
                    Spacer()
                    Button("Change") { changingVerdict = true }
                        .font(.caption)
                }
            } else {
                Text("Done as written? A clean session at RPE 7 or below moves each module on when the program is next rebuilt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("RPE \(confirmRpe)", value: $confirmRpe, in: 1...10)
                HStack {
                    Button { confirm(clean: true) } label: {
                        Label("Clean, as written", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not clean") { confirm(clean: false) }
                        .buttonStyle(.bordered)
                }
                .disabled(isConfirming)
            }
            if confirmFailed {
                Text("Not saved — try again when online.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Progress")
        }
    }

    private func confirm(clean: Bool) {
        isConfirming = true
        confirmFailed = false
        Task {
            let ok = await appState.confirmSession(sessionKey: sessionKey, clean: clean, rpe: confirmRpe)
            confirmFailed = !ok
            if ok { changingVerdict = false; AppHaptics.success() }
            isConfirming = false
        }
    }

    // MARK: - Progress (loaded lifts: Starting Strength)

    /// Lifts that move on what was made (`load_per_exposure`).
    private var loadLifts: [LiftConfirmation.Lift] { LiftConfirmation.lifts(of: currentSession) }

    /// Each lift made or missed, at its prescribed weight or the one worked up
    /// to. A made lift goes up next time; a miss repeats it, two reset it.
    private var liftProgressSection: some View {
        Section {
            if let verdict = LiftConfirmation.verdict(loadLifts, log: appState.sessionLogs[sessionKey]),
               !changingVerdict {
                ForEach(loadLifts) { lift in
                    let made = verdict[lift.id] ?? true
                    let kg = appState.sessionLogs[sessionKey]?.exercises[lift.id]?.weightKg
                    HStack {
                        Label(lift.name, systemImage: made ? "checkmark.seal.fill" : "minus.circle")
                            .foregroundStyle(made ? Color.green : Color.secondary)
                        Spacer()
                        Text([kg.map { "\(LoadFormat.kilograms($0)) kg" }, made ? nil : "missed, repeats"]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Change") { changingVerdict = true }
                    .font(.caption)
            } else {
                Text("Made every rep? A made lift goes up next time; a miss repeats its weight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(loadLifts) { lift in
                    let answer = Binding(
                        get: { liftAnswers[lift.id] ?? LiftConfirmation.Answer() },
                        set: { liftAnswers[lift.id] = $0 })
                    HStack {
                        Text(lift.name)
                        Spacer()
                        if let kg = lift.weightKg {
                            Text("\(LoadFormat.kilograms(kg)) kg")
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("kg", text: answer.kg)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64)
                                .accessibilityLabel("\(lift.name) kg")
                        }
                        Picker(lift.name, selection: answer.made) {
                            Text("Made").tag(true)
                            Text("Missed").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                        .labelsHidden()
                    }
                }
                HStack {
                    Button { confirmLifts(allMade: true) } label: {
                        Label("All made", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(LiftConfirmation.unweighed(loadLifts, answers: liftAnswers, allMade: true))
                    Button("Save") { confirmLifts(allMade: false) }
                        .buttonStyle(.bordered)
                        .disabled(LiftConfirmation.unweighed(loadLifts, answers: liftAnswers, allMade: false))
                }
                .disabled(isConfirming)
                if LiftConfirmation.unweighed(loadLifts, answers: liftAnswers, allMade: false) {
                    Text("Enter the weight you worked up to on each lift you made.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if confirmFailed {
                Text("Not saved — try again when online.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Progress")
        }
    }

    private func confirmLifts(allMade: Bool) {
        isConfirming = true
        confirmFailed = false
        let body = LiftConfirmation.payload(loadLifts, answers: liftAnswers, allMade: allMade)
        Task {
            let ok = await appState.confirmSession(sessionKey: sessionKey, clean: body.clean, rpe: nil,
                                                   lifts: body.lifts)
            confirmFailed = !ok
            if ok { changingVerdict = false; AppHaptics.success() }
            isConfirming = false
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section("Session Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .onChange(of: notes) { _, _ in
                    debouncedSaveNotes()
                }

            Toggle("Log Fatigue", isOn: $showFatigue)

            if showFatigue {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fatigue: \(Int(fatigueRating))/5")
                        Spacer()
                    }
                    .font(.caption)
                    Slider(value: $fatigueRating, in: 1...5, step: 1)
                        .onChange(of: fatigueRating) { _, _ in debouncedSaveNotes() }
                }
            }
        }
    }

    // MARK: - Completion Button

    private var completionButton: some View {
        Button {
            Task {
                isSaving = true
                if isDone {
                    await appState.undoSessionComplete(sessionKey: sessionKey)
                } else {
                    await appState.markSessionComplete(sessionKey: sessionKey)
                    AppHaptics.success()
                }
                isSaving = false
            }
        } label: {
            HStack {
                if isSaving {
                    ProgressView().scaleEffect(0.9)
                } else {
                    Image(systemName: isDone ? "xmark.circle" : "checkmark.circle.fill")
                }
                Text(isDone ? "Mark Incomplete" : "Mark Session Complete")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(isDone ? .secondary : .green)
        .disabled(isSaving)
    }

    // MARK: - Helpers

    private func shortDateTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateStyle = .short; out.timeStyle = .short
        return out.string(from: date)
    }

    /// One PUT per pause in typing, not one per keystroke: each change cancels
    /// the pending save and waits 600 ms before sending the latest values.
    private func debouncedSaveNotes() {
        saveTask?.cancel()
        let notesSnapshot = notes
        let fatigue = showFatigue ? Int(fatigueRating) : nil
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            try? await appState.api?.saveSessionNotes(
                sessionKey: sessionKey,
                notes: notesSnapshot,
                fatigueRating: fatigue
            )
        }
    }
}
