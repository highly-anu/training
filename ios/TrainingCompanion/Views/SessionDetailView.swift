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
    /// "After the session" open: by itself once the session is begun or done.
    @State private var afterOpen = false
    @State private var saveTask: Task<Void, Never>? = nil
    @State private var exerciseSheet: ExerciseRowItem? = nil
    @State private var swapTarget: SwapTarget? = nil
    @State private var logTarget: LogTarget? = nil

    /// A row's identity is its position plus the exercise: the same movement
    /// can appear twice in a session, and a swap must animate only its row.
    private struct ExerciseRowItem: Identifiable {
        /// Position in the session's full `exercises` array — what a swap edits.
        let index: Int
        let assignment: ProgramExerciseAssignment
        var id: String { "\(index)-\(assignment.exercise?.id ?? "slot")" }
    }

    /// The session's log form, opened at one exercise or at the top.
    private struct LogTarget: Identifiable {
        var exerciseId: String? = nil
        var id: String { exerciseId ?? "session" }
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
    /// The workout player, full screen (design-system §6.44).
    @State private var player: WorkoutPlayerModel.Target? = nil
    /// The player grows out of Start workout.
    @Namespace private var zoom

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
                // A log saved here that the server does not have yet (§6.16).
                if appState.sessionLogNotice(sessionKey: sessionKey) != nil {
                    Section {
                        SessionLogNoticeBanner(sessionKey: sessionKey)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                headerSection
                if let workout = linkedWorkout { linkedWorkoutSection(workout) }
                exercisesSection
                afterSection
            }
            .onChange(of: hasBegun) { _, begun in
                if begun { withAnimation(AppAnimation.layoutChange) { afterOpen = true } }
            }
            .onAppear { afterOpen = hasBegun }
            .navigationTitle(currentSession.archetype?.name ?? ModalityStyle.label(for: currentSession.modality))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .appActionBar {
                if !isDone { startButton }
                completionButton
            }
            .fullScreenCover(item: $player) { target in
                WorkoutPlayerView(player: .resumingIfKept(target), fallback: currentSession) {
                    player = nil
                }
                .appZoom(from: "player", in: zoom)
                .environmentObject(appState)
            }
            .onAppear {
                // Debug builds: TC_PLAYER opens this session's player (WorkoutPlayerDebug).
                if player == nil, WorkoutPlayerDebug.take(sessionKey) { openPlayer() }
                // …and TC_LOG its log form (SessionLogDebug).
                if SessionLogDebug.take(sessionKey) { logTarget = LogTarget() }
            }
            // The exercise reference (§6.14): what the movement is and how to
            // do it, without leaving the session — pushed, as the swap is
            // (§6.48); both were sheets on this sheet until 1.37.
            .appPush(item: $exerciseSheet) { item in
                if let ex = item.assignment.exercise {
                    ExerciseDetailSheet(exerciseId: ex.id, name: ex.name, assignment: item.assignment,
                                        pushed: true)
                }
            }
            .appPush(item: $swapTarget) { target in
                if let wi = weekIndex, let dn = dayName, let si = sessionIndex {
                    SwapExerciseSheet(weekIndex: wi, dayName: dn, sessionIndex: si,
                                      exerciseIndex: target.exerciseIndex, pushed: true)
                }
            }
            // What was done (§6.16): every exercise on one form, saved once —
            // sets for a sets × reps slot, the slot's currency for the rest.
            .appPush(item: $logTarget) { target in
                SessionLogForm(sessionKey: sessionKey, session: currentSession, openAt: target.exerciseId)
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
    //
    // Move, Replace and Remove are the long-press actions on Today's cards and
    // Program ▸ Calendar's rows (SessionActions, design-system §6.43); this
    // screen keeps the exercise swap, which edits one slot.

    private var canEditProgram: Bool {
        weekIndex != nil && dayName != nil && sessionIndex != nil && appState.api != nil
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(symbol: SessionIcon.symbol(icon: currentSession.icon, modality: currentSession.modality))
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
                                    .foregroundStyle(AppColor.warning)
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
                    Text(test.insteadOf.map { "A test, in place of \($0). Log each result with the session; it comes back here to save." }
                         ?? "A test of this phase's standards. Log each result with the session; it comes back here to save.")
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
                    .foregroundStyle(AppColor.complete)
                    .font(.footnote)
                if let avgHR = log.avgHR {
                    Label("Avg HR: \(avgHR) bpm", systemImage: "heart.fill")
                        .foregroundStyle(AppColor.destructive)
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
                    // Three visible controls (§6.51): the circle opens the log at it, the row
                    // opens the exercise, "…" holds the rest. The swipes and
                    // the long press are the same actions, faster.
                    HStack(alignment: .top, spacing: AppMetrics.gapSmall) {
                        logControl(item)
                        Button {
                            AppHaptics.selection()
                            exerciseSheet = item
                        } label: {
                            exerciseRow(item.assignment)
                        }
                        .buttonStyle(.plain)
                        Menu {
                            exerciseActions(item)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(item.assignment.exercise?.name ?? "Exercise") actions")
                    }
                    .contextMenu { exerciseActions(item) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            logTarget = LogTarget(exerciseId: item.assignment.exercise?.id)
                        } label: {
                            Label("Log", systemImage: "square.and.pencil")
                        }
                        .tint(AppColor.complete)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canSwap(item.assignment) {
                            Button {
                                swapTarget = SwapTarget(exerciseIndex: item.index)
                            } label: {
                                Label("Swap", systemImage: "arrow.left.arrow.right")
                            }
                            .tint(AppColor.info)
                        }
                    }
                }
                .animation(AppAnimation.layoutChange, value: rows.map(\.id))
                // The whole session on one form, one save.
                Button {
                    AppHaptics.selection()
                    logTarget = LogTarget()
                } label: {
                    Label("Log session", systemImage: "square.and.pencil")
                }
            }
        } header: {
            Text("Exercises")
        }
    }

    /// The row's leading circle: empty until the exercise is logged, then a
    /// tick; either way it opens the logger.
    private func logControl(_ item: ExerciseRowItem) -> some View {
        let logged = loggedSummary(item.assignment) != nil
        return Button {
            AppHaptics.light()
            logTarget = LogTarget(exerciseId: item.assignment.exercise?.id)
        } label: {
            Image(systemName: logged ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .appSymbolReplace(value: logged)
                .foregroundStyle(logged ? AnyShapeStyle(AppColor.complete) : AnyShapeStyle(.tertiary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(logLabel(item.assignment)): \(item.assignment.exercise?.name ?? "exercise")")
        .accessibilityValue(logged ? "Logged" : "Not logged")
    }

    @ViewBuilder
    private func exerciseActions(_ item: ExerciseRowItem) -> some View {
        Button {
            logTarget = LogTarget(exerciseId: item.assignment.exercise?.id)
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
                Text(logged)
                    .font(.caption)
                    .foregroundStyle(AppColor.complete)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var progressRows: some View {
        Group {
            if let verdict = moduleVerdict, !changingVerdict {
                HStack {
                    Label(verdict.clean ? "Clean, as written\(verdict.rpe.map { " · RPE \($0)" } ?? "")"
                                        : "Not clean — the cycle holds here",
                          systemImage: verdict.clean ? "checkmark.seal.fill" : "minus.circle")
                        .foregroundStyle(verdict.clean ? AppColor.complete : Color.secondary)
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
                    .appButton(.primary)
                    Button("Not clean") { confirm(clean: false) }
                        .appButton(.secondary)
                }
                .disabled(isConfirming)
            }
            if confirmFailed {
                Text("Not saved — try again when online.")
                    .font(.caption)
                    .foregroundStyle(AppColor.destructive)
            }
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
    private var liftProgressRows: some View {
        Group {
            if let verdict = LiftConfirmation.verdict(loadLifts, log: appState.sessionLogs[sessionKey]),
               !changingVerdict {
                ForEach(loadLifts) { lift in
                    let made = verdict[lift.id] ?? true
                    let kg = appState.sessionLogs[sessionKey]?.exercises[lift.id]?.weightKg
                    HStack {
                        Label(lift.name, systemImage: made ? "checkmark.seal.fill" : "minus.circle")
                            .foregroundStyle(made ? AppColor.complete : Color.secondary)
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
                    .appButton(.primary)
                    .disabled(LiftConfirmation.unweighed(loadLifts, answers: liftAnswers, allMade: true))
                    Button("Save") { confirmLifts(allMade: false) }
                        .appButton(.secondary)
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
                    .foregroundStyle(AppColor.destructive)
            }
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

    // MARK: - After the session

    /// Begun: something is logged for it, a workout is linked, or it is done.
    private var hasBegun: Bool {
        isDone || linkedWorkout != nil || appState.sessionLogs[sessionKey] != nil
    }

    private var asksProgress: Bool {
        !progressingExercises.isEmpty && (isDone || linkedWorkout != nil)
    }

    /// What is answered once the work is done — done as written, the notes,
    /// the fatigue — in one section under the exercises, closed until the
    /// session is begun (design-system §6.54). Until 1.39 Progress and Session
    /// Notes were two sections that appeared from nowhere on completion, and
    /// a note could not be written beforehand.
    private var afterSection: some View {
        Section {
            DisclosureGroup(isExpanded: $afterOpen) {
                if asksProgress {
                    if loadLifts.isEmpty { progressRows } else { liftProgressRows }
                }
                notesRows
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("After the session")
                        .font(.subheadline).fontWeight(.semibold)
                    Text(asksProgress ? "Done as written, notes, fatigue" : "Notes, fatigue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var notesRows: some View {
        Group {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...8)
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

    // MARK: - Start workout

    /// The session run step by step (WorkoutPlayerView), on its own day.
    private var startButton: some View {
        Button { openPlayer() } label: {
            Label("Start workout", systemImage: "play.fill")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .appButton(.primary)
        .tint(ModalityStyle.color(for: currentSession.modality))
        .disabled(playerTarget == nil)
        .matchedTransitionSource(id: "player", in: zoom)
    }

    private var playerTarget: WorkoutPlayerModel.Target? {
        guard let weekIndex, let dayName,
              let date = appState.sessionDate(weekIndex: weekIndex, dayName: dayName) else { return nil }
        return .init(sessionKey: sessionKey, date: date,
                     title: currentSession.archetype?.name ?? ModalityStyle.label(for: currentSession.modality))
    }

    private func openPlayer() {
        AppHaptics.medium()
        player = playerTarget
    }

    // MARK: - Completion Button

    /// Answers at once: the completion is written on the phone and sent in
    /// the background (`AppState.saveSessionLog`).
    private var completionButton: some View {
        Button {
            if isDone {
                appState.undoSessionComplete(sessionKey: sessionKey)
            } else {
                appState.markSessionComplete(sessionKey: sessionKey)
                AppHaptics.success()
            }
        } label: {
            HStack {
                Image(systemName: isDone ? "xmark.circle" : "checkmark.circle.fill")
                    .appSymbolReplace(value: isDone)
                Text(isDone ? "Mark Incomplete" : "Mark Session Complete")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .appButton(isDone ? .secondary : .complete)
    }

    // MARK: - Helpers

    private func shortDateTime(_ iso: String) -> String {
        // The server's own "2026-09-28 18:00:00+02:00" as well as the phone's ISO 8601.
        guard let date = LogSessions.parseServerDate(iso) else { return iso }
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
