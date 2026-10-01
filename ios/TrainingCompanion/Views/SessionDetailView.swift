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
                exercisesSection
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
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

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
            if canEditProgram && rows.contains(where: { canSwap($0.assignment) }) {
                Text("Tap an exercise for cues and a demo. Swipe right to log what you did, left to swap it for an alternative that fits the same slot.")
            } else if !rows.isEmpty {
                Text("Tap an exercise for cues and a demo. Swipe right to log what you did.")
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
        canEditProgram && currentSession.archetype != nil && ea.slotRole != nil && !ea.meta
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
