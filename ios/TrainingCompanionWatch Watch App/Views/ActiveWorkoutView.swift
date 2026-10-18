import SwiftUI
import WatchKit

struct ActiveWorkoutView: View {
    let session: WatchSession

    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var sessionState: WorkoutSessionState

    @Environment(\.dismiss) private var dismiss
    @State private var isStarted = false
    @State private var workoutStartDate = Date()
    @State private var showStopConfirm = false
    /// Set Next or Edit Set, open over the commands page.
    @State private var setEditor: SetEditor? = nil

    private enum SetEditor: String, Identifiable {
        case next = "Set Next", last = "Edit Set"
        var id: String { rawValue }
    }

    /// The step the commands act on, and its screen.
    private var currentStep: (index: Int, exercise: WatchExercise, screen: WatchScreen)? {
        let i = currentExerciseIndex
        guard i < session.exercises.count else { return nil }
        let ex = session.exercises[i]
        return (i, ex, session.screen(for: ex))
    }

    private var overtimeInfo: (index: Int, name: String, targetSeconds: Int)? {
        guard case let .timedWork(ei, _) = sessionState.phase,
              ei < session.exercises.count,
              let dur = session.exercises[ei].durationMinutes else { return nil }
        return (index: ei, name: session.exercises[ei].name, targetSeconds: dur * 60)
    }

    var body: some View {
        Group {
            if !isStarted {
                preWorkoutView
            } else if case .sessionComplete = sessionState.phase {
                SessionCompleteView(
                    session: session,
                    startedAt: workoutStartDate,
                    onSave: saveAndClose,
                    onDiscard: {
                        sessionState.reset()
                        dismiss()
                    }
                )
            } else if sessionState.isResting {
                RestTimerView(session: session)
            } else {
                workoutTabView
            }
        }
        .onAppear(perform: debugLaunch)
        .navigationTitle(session.archetypeName)
        .navigationBarBackButtonHidden(isStarted)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                timerStatusIndicator
            }
        }
        .sheet(isPresented: Binding(
            get: { sessionState.showOvertimePrompt },
            set: { sessionState.showOvertimePrompt = $0 }
        )) {
            if let info = overtimeInfo {
                OvertimePromptView(
                    exerciseName: info.name,
                    targetSeconds: info.targetSeconds,
                    onContinue: {
                        sessionState.showOvertimePrompt = false
                    },
                    onFinish: {
                        sessionState.showOvertimePrompt = false
                        sessionState.completeTimedWork(
                            exerciseIndex: info.index,
                            exerciseId: session.exercises[info.index].exerciseId
                        )
                        sessionState.completeSession()
                        Task { await workoutManager.endWorkout() }
                    }
                )
            }
        }
    }

    // MARK: - Pre-workout

    private var preWorkoutView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if session.isDeload {
                    Label("Deload — quality over load", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                ForEach(session.exercises, id: \.exerciseId) { ex in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: ModalityStyle.slotTypeIcon(for: ex.slotType))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(ex.name).font(.caption).lineLimit(1)
                        }
                        Text(ex.loadDescription).font(.caption2).foregroundStyle(.secondary)
                        if let note = ex.loadNote {
                            Text(note).font(.caption2).foregroundStyle(.orange)
                        }
                        if let cue = ex.coachingCue, !cue.isEmpty {
                            Text(cue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button("Begin Workout") {
                    workoutStartDate = Date()
                    isStarted = true
                    Task { await workoutManager.startWorkout(session: session,
                                                            maxHR: connectivity.maxHR) }
                }
                .buttonStyle(.borderedProminent)
                .tint(ModalityStyle.color(for: session.modalityId))
                .padding(.top, 8)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Active workout (TabView)

    private var workoutTabView: some View {
        TabView {
            currentExercisePage
            timerTabView
            SessionProgressView(session: session)
            commandsTabView
            LiveMetricsView()
        }
        .tabViewStyle(.page)
    }

    // MARK: - Timer tab

    @ViewBuilder
    private var timerTabView: some View {
        if case let .timedWork(ei, elapsed) = sessionState.phase,
           ei < session.exercises.count {
            let exercise = session.exercises[ei]
            let target = (exercise.durationMinutes ?? 0) * 60
            let overTime = elapsed >= target
            let fraction = target > 0 ? min(1.0, Double(elapsed) / Double(target)) : 0
            let nextIndex = sessionState.indexAfter(ei)
            let isLast = nextIndex >= session.exercises.count

            VStack(spacing: 12) {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(overTime ? Color.orange : ModalityStyle.color(for: session.modalityId),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(timerString(elapsed))
                            .font(.title2.monospacedDigit().bold())
                        if let zone = exercise.zoneTarget {
                            Text(zone)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
                Button(isLast ? "Done" : "Next") {
                    if isLast {
                        sessionState.completeTimedWork(exerciseIndex: ei,
                                                       exerciseId: exercise.exerciseId)
                    } else if session.exercises[nextIndex].durationMinutes != nil {
                        sessionState.autoAdvanceToNextTimedWork(
                            currentExerciseId: exercise.exerciseId,
                            nextIndex: nextIndex
                        )
                    } else {
                        sessionState.completeTimedWork(exerciseIndex: ei,
                                                       exerciseId: exercise.exerciseId)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .padding()
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No active timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func timerString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Timer status indicator (navigation bar, visible from all tabs)

    @ViewBuilder
    private var timerStatusIndicator: some View {
        if case let .timedWork(_, elapsed) = sessionState.phase {
            HStack(spacing: 3) {
                Image(systemName: sessionState.isTimerPaused ? "pause.fill" : "timer")
                    .font(.system(size: 9))
                Text(timerString(elapsed))
                    .font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(sessionState.isTimerPaused ? Color.orange : Color.green)
        }
    }

    // MARK: - Commands tab

    @ViewBuilder
    private var commandsTabView: some View {
        ScrollView {
        VStack(spacing: 10) {
            // The Garmin's hold-UP menu: Set Next and Edit Set on a set,
            // the metronome on a paced step.
            if let step = currentStep, step.screen.template == .sets {
                Button { setEditor = .next } label: {
                    Label("Set Next", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                if sessionState.setLogs[step.exercise.exerciseId]?.isEmpty == false {
                    Button { setEditor = .last } label: {
                        Label("Edit Set", systemImage: "pencil").frame(maxWidth: .infinity)
                    }
                }
            }
            if let step = currentStep, WatchSpecText.rpm(step.exercise, step.screen) != nil {
                Button { sessionState.metronomeOn.toggle() } label: {
                    Label(sessionState.metronomeOn ? "Metronome Off" : "Metronome On",
                          systemImage: sessionState.metronomeOn ? "metronome.fill" : "metronome")
                        .frame(maxWidth: .infinity)
                }
            }

            if case .timedWork = sessionState.phase {
                Button {
                    if sessionState.isTimerPaused { sessionState.resumeTimer() }
                    else { sessionState.pauseTimer() }
                } label: {
                    Label(sessionState.isTimerPaused ? "Resume" : "Pause",
                          systemImage: sessionState.isTimerPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(sessionState.isTimerPaused ? .green : .orange)
            }

            Button(role: .destructive) {
                showStopConfirm = true
            } label: {
                Label("End Session", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.8))
        }
        .padding()
        }
        .navigationTitle("Commands")
        .sheet(item: $setEditor) { editor in
            if let step = currentStep {
                let logs = sessionState.setLogs[step.exercise.exerciseId] ?? []
                let start: WorkoutSessionState.WorkingSet? = editor == .last
                    ? logs.last.map { .init(reps: $0.repsActual ?? 0, weightKg: $0.weightKg, rpe: $0.rpe) }
                    : sessionState.workingSet(step.exercise)
                SetLoggerSheetView(exercise: step.exercise, setIndex: max(0, logs.count - 1),
                                   exerciseIndex: step.index, startOffset: sessionState.elapsedSeconds,
                                   title: editor.rawValue, initial: start) { log in
                    let set = WorkoutSessionState.WorkingSet(reps: log.repsActual ?? 0, weightKg: log.weightKg, rpe: log.rpe)
                    if editor == .last { sessionState.editLastSet(step.exercise, set) }
                    else { sessionState.setNext(step.exercise, set) }
                }
            }
        }
        .confirmationDialog("End session?", isPresented: $showStopConfirm) {
            Button("Save & End") { saveAndClose() }
            Button("Discard", role: .destructive) {
                sessionState.reset()
                Task { await workoutManager.endWorkout() }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Debug launch (WatchDebugLaunch)

    /// Begins the workout, goes to a step, starts it and presses its button,
    /// as the launch switches ask — a debug build on the simulator only.
    private func debugLaunch() {
        guard !isStarted, WatchDebugLaunch.session == session.sessionId else { return }
        workoutStartDate = Date()
        isStarted = true
        Task {
            await workoutManager.startWorkout(session: session, maxHR: connectivity.maxHR)
            if let n = WatchDebugLaunch.step, n < session.exercises.count { sessionState.advance(to: n) }
            let i = currentExerciseIndex
            guard i < session.exercises.count else { return }
            let ex = session.exercises[i], screen = session.screen(for: ex)
            if WatchDebugLaunch.run { sessionState.start(i, ex, screen) }
            for _ in 0..<WatchDebugLaunch.laps {
                let outcome = WatchSpecText.lap(ex, screen, sessionState.stepState(ex, index: i, screen: screen))
                if outcome == .completeSet {
                    let reps = Int(ex.reps?.prefix { $0.isNumber } ?? "") ?? 5
                    sessionState.completeSet(WatchSetLog(setIndex: sessionState.setLogs[ex.exerciseId]?.count ?? 0,
                                                         repsActual: reps, weightKg: ex.weightKg, rpe: 7,
                                                         completed: true, durationSeconds: 40,
                                                         startOffset: nil, endOffset: nil),
                                             for: ex.exerciseId)
                    sessionState.finishSet(i, ex, screen)
                    if sessionState.isResting, case let .resting(ei, cs, _) = sessionState.phase {
                        sessionState.skipRest(exerciseIndex: ei, completedSet: cs)
                    }
                } else {
                    sessionState.perform(outcome, i, ex, screen)
                }
            }
            if WatchDebugLaunch.end {
                sessionState.completeSession()
                await workoutManager.endWorkout()
            }
        }
    }

    // MARK: - Save

    /// The one way a recorded session leaves the watch: its summary, sent
    /// once, and the session marked done — from the completion screen and
    /// from Save & End alike. The completion screen used to send the summary
    /// and then its Done sent it again, and Save & End never marked the
    /// session done. The summary is built before the reset, which clears the
    /// sets and HR it reads; ending an already ended workout is a no-op.
    private func saveAndClose() {
        connectivity.sendWorkoutSummary(workoutManager.buildSummary(for: session, startedAt: workoutStartDate))
        connectivity.markSessionComplete(session.sessionId)
        sessionState.reset()
        Task { await workoutManager.endWorkout() }
        dismiss()
    }

    // MARK: - Exercise page

    @ViewBuilder
    private var currentExercisePage: some View {
        let exerciseIndex = currentExerciseIndex
        if exerciseIndex < session.exercises.count {
            CurrentExerciseView(
                exercise: session.exercises[exerciseIndex],
                exerciseIndex: exerciseIndex,
                session: session
            )
        } else {
            finishButton
        }
    }

    private var finishButton: some View {
        Button("Finish Session") {
            sessionState.completeSession()
            Task { await workoutManager.endWorkout() }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    private var currentExerciseIndex: Int {
        switch sessionState.phase {
        case let .active(ei, _):           return ei
        case let .timedWork(ei, _):        return ei
        case let .emomInterval(ei, _, _, _): return ei
        case let .amrapRunning(ei, _):     return ei
        default:                           return 0
        }
    }
}
