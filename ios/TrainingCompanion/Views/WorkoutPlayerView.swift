import SwiftUI

/// The workout player (design-system §6.44): one session, full screen, step
/// by step, on the engine the Apple Watch runs. Each step is drawn from the
/// screen the server writes for both watches (WatchSpecText) — its title,
/// two fields, its gauge and two lines — at a size read from across a gym;
/// a rest is a ring counting down with what is next; a lead-in counts
/// "3, 2, 1" over everything. Every number comes from the engine.
struct WorkoutPlayerView: View {
    @StateObject var player: WorkoutPlayerModel
    /// The stored program's session: the fallback when the server's day
    /// cannot be read.
    let fallback: ProgramSession?
    var onClose: () -> Void = {}

    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSteps = false
    @State private var showLogger = false
    @State private var confirmLeave = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            switch player.loadState {
            case .loading:
                ProgressView("Loading the workout…")
            case .failed(let why):
                failed(why)
            case .ready:
                if let session = player.session {
                    if player.finished {
                        WorkoutPlayerCompleteView(player: player, session: session, onClose: onClose)
                    } else if player.startedAt == nil {
                        overview(session)
                    } else {
                        running(session)
                    }
                }
            }
        }
        .task {
            if player.session == nil {
                await player.load(api: appState.api, fallback: fallback)
                WorkoutPlayerDebug.apply(player, appState: appState)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: player.cameToForeground()
            case .background: player.wentToBackground()
            default: break
            }
        }
    }

    // MARK: - Before the start

    /// The session laid out: every step and its prescription, and Start.
    private func overview(_ session: WatchSession) -> some View {
        let tint = ModalityStyle.color(for: session.modalityId)
        return VStack(spacing: 0) {
            HStack {
                Button { onClose() } label: { Image(systemName: "xmark").font(.headline) }
                    .accessibilityLabel("Close")
                Spacer()
            }
            .padding()
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.archetypeName).font(.largeTitle.bold())
                        Text("\(session.exercises.filter { !$0.isMeta }.count) steps · about \(session.estimatedMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Steps") {
                    ForEach(Array(session.exercises.enumerated()), id: \.offset) { i, ex in
                        if !WatchSteps.isFolded(session, i) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.body.weight(.medium))
                                Text(WatchSteps.preview(ex, session.screen(for: ex))).font(.subheadline).foregroundStyle(.secondary)
                                if let last = ex.lastTime {
                                    Text("Last time \(last)").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            Button {
                AppHaptics.success()
                WorkoutLockScreen.shared.prepare()
                player.begin()
            } label: {
                Label("Start workout", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .padding()
        }
    }

    private func failed(_ why: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
            Text(why).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Try again") { Task { await player.load(api: appState.api, fallback: fallback) } }
                .buttonStyle(.borderedProminent)
            Button("Close") { onClose() }
        }
        .padding(32)
    }

    // MARK: - Running

    private func running(_ session: WatchSession) -> some View {
        let engine = player.engine
        let index = min(engine.phase.exerciseIndex ?? 0, max(0, session.exercises.count - 1))
        let ex = session.exercises[index]
        let tint = ModalityStyle.color(for: session.modalityId)
        return VStack(spacing: 0) {
            header(session, index: index, tint: tint)
            if case let .resting(ei, cs, left) = engine.phase {
                PlayerRestView(engine: engine, session: session, index: ei, completedSet: cs, left: left, tint: tint)
            } else {
                PlayerStepView(engine: engine, session: session, exercise: ex, index: index, tint: tint)
                Spacer(minLength: 0)
                PlayerControls(engine: engine, session: session, exercise: ex, index: index, tint: tint,
                               showLogger: $showLogger)
            }
        }
        .overlay { leadIn(index, tint: tint) }
        .sheet(isPresented: $showSteps) {
            PlayerStepList(session: session, engine: engine) { i in
                player.go(to: i)
                showSteps = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLogger) {
            PlayerSetLogger(engine: engine, session: session, exercise: ex, index: index, tint: tint)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Leave the workout?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Finish and save") { player.finish() }
            Button("Leave, resume later") { player.leaveForLater(); onClose() }
            Button("Discard workout", role: .destructive) { player.discard(); onClose() }
        } message: {
            Text("Resume later keeps where you are; Today offers it again.")
        }
        .alert("Time's up", isPresented: Binding(get: { engine.showOvertimePrompt },
                                                 set: { engine.showOvertimePrompt = $0 })) {
            Button("Keep going", role: .cancel) {}
            Button("Finish") { player.finish() }
        } message: {
            Text("\(ex.name) has run its time. Keep going, or finish the workout.")
        }
    }

    private func header(_ session: WatchSession, index: Int, tint: Color) -> some View {
        let engine = player.engine
        let steps = session.exercises.indices.filter { !WatchSteps.isFolded(session, $0) }
        let place = (steps.firstIndex(of: index) ?? 0) + 1
        return VStack(spacing: 8) {
            HStack {
                Button { confirmLeave = true } label: { Image(systemName: "xmark").font(.headline) }
                    .accessibilityLabel("Leave workout")
                Spacer()
                VStack(spacing: 0) {
                    Text(session.archetypeName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(WatchSpecText.mmss(engine.elapsedSeconds))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showSteps = true } label: { Image(systemName: "list.bullet").font(.headline) }
                    .accessibilityLabel("All steps")
            }
            // One segment per step: done, current, to come.
            HStack(spacing: 3) {
                ForEach(steps, id: \.self) { i in
                    Capsule()
                        .fill(engine.completedExerciseIds.contains(session.exercises[i].exerciseId) ? tint
                              : i == index ? tint.opacity(0.55) : Color.secondary.opacity(0.2))
                        .frame(height: 4)
                }
            }
            Text("Step \(place) of \(steps.count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// "3, 2, 1, go": a Start's count, or a rest's last seconds, over everything.
    @ViewBuilder
    private func leadIn(_ index: Int, tint: Color) -> some View {
        if let left = player.engine.leadInLeft(index) {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text("Work in").font(.title2.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                    Text("\(left)")
                        .font(.system(size: 160, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - A step

/// A step as both watches draw it, phone-sized: the title, field A large,
/// field B beside it, the step's gauge, the two lines and its notes.
struct PlayerStepView: View {
    @ObservedObject var engine: WorkoutSessionState
    let session: WatchSession
    let exercise: WatchExercise
    let index: Int
    let tint: Color

    @State private var showNotes = false

    var body: some View {
        let screen = session.screen(for: exercise)
        let st = engine.stepState(exercise, index: index, screen: screen)
        let lines = WatchSpecText.lines(exercise, screen, st, lapWord: "the button")
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(WatchSpecText.title(exercise, screen, st))
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let a = WatchSpecText.fieldA(exercise, screen, st) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(a.value)
                            .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .contentTransition(.numericText())
                    }
                }
                if let b = WatchSpecText.fieldB(exercise, screen, st) {
                    HStack {
                        Text(b.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(b.value).font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                    }
                }
                gauge(screen, st)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lines.0)
                        .font(.title3)
                        .foregroundStyle(screen.lines == .standardTarget && exercise.standard != nil ? .yellow : .primary)
                    if let second = lines.1 {
                        Text(second).font(.body).foregroundStyle(.secondary)
                    }
                }
                notes
            }
            .padding()
        }
    }

    /// Sets as dots, an interval's rounds as a bar with its phase, a timed
    /// step's time as a bar: where the step stands at a glance.
    @ViewBuilder
    private func gauge(_ screen: WatchScreen, _ st: WatchStepState) -> some View {
        switch screen.template {
        case .sets, .hold:
            let total = WatchSpecText.setCount(exercise, screen)
            if total > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(i < st.setsDone ? tint : Color.secondary.opacity(0.25))
                            .frame(width: 14, height: 14)
                    }
                }
                .accessibilityLabel("\(st.setsDone) of \(total) sets done")
            }
        case .interval:
            VStack(alignment: .leading, spacing: 4) {
                // The whole step's time: the rounds behind, then this one's
                // work and rest as far as they have run.
                let round = st.intervalWorkSec + st.intervalRestSec
                let inRound = st.intervalWorking ? st.intervalWorkSec - st.intervalLeftSec
                                                 : st.intervalWorkSec + st.intervalRestSec - st.intervalLeftSec
                ProgressView(value: Double(max(0, (st.intervalRound - 1) * round + max(0, inRound))),
                             total: Double(max(1, st.intervalTotal * round)))
                    .tint(tint)
                Text(st.intervalWorking ? "Work" : "Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(st.intervalWorking ? tint : .secondary)
            }
        case .timed, .roundTimer:
            if let minutes = exercise.durationMinutes, minutes > 0 {
                ProgressView(value: Double(min(st.elapsedSec, minutes * 60)), total: Double(minutes * 60))
                    .tint(tint)
            }
        case .rounds:
            if exercise.timeMinutes != nil {
                ProgressView(value: Double(max(0, (exercise.timeMinutes ?? 0) * 60 - st.capLeftSec)),
                             total: Double(max(1, (exercise.timeMinutes ?? 0) * 60)))
                    .tint(tint)
            }
        default:
            EmptyView()
        }
    }

    /// The coach's cue, the load's note and the step's focus, opened on a tap.
    @ViewBuilder
    private var notes: some View {
        let parts = [exercise.loadNote, exercise.coachingCue, exercise.focus].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty {
            DisclosureGroup(isExpanded: $showNotes) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(parts, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Label("Notes", systemImage: "text.alignleft").font(.subheadline.weight(.medium))
            }
            .tint(.primary)
        }
    }
}

// MARK: - The buttons

/// Start until the step runs, then the one primary button — the spec's LAP
/// (WatchSpecText.lap), as both watches have it — with Skip, Pause on a
/// timed step and the distance's ±0.1 km beside it.
struct PlayerControls: View {
    @ObservedObject var engine: WorkoutSessionState
    let session: WatchSession
    let exercise: WatchExercise
    let index: Int
    let tint: Color
    @Binding var showLogger: Bool

    var body: some View {
        let screen = session.screen(for: exercise)
        let st = engine.stepState(exercise, index: index, screen: screen)
        let running = engine.isRunning(index, exercise, screen)
        let outcome = WatchSpecText.lap(exercise, screen, st)
        VStack(spacing: 12) {
            if !running {
                if engine.countIn?.index != index {
                    primary("Start", systemImage: "play.fill") { engine.start(index, exercise, screen) }
                }
            } else {
                primary(PlayerControls.label(outcome, st, exercise, screen), systemImage: nil) {
                    if outcome == .completeSet { showLogger = true }
                    else { engine.perform(outcome, index, exercise, screen) }
                }
            }
            HStack(spacing: 24) {
                if running, screen.template == .distance, !WatchSpecText.isShortDistance(exercise, screen) {
                    Button("−0.1 km") { addKm(-0.1, st) }
                    Button("+0.1 km") { addKm(0.1, st) }
                }
                if running, case .timedWork = engine.phase {
                    Button(engine.isTimerPaused ? "Resume" : "Pause") {
                        engine.isTimerPaused ? engine.resumeTimer() : engine.pauseTimer()
                    }
                }
                Button("Skip") { engine.finishStep(index, exercise, screen) }
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func primary(_ title: String, systemImage: String?, action: @escaping () -> Void) -> some View {
        Button {
            AppHaptics.medium()
            action()
        } label: {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private func addKm(_ delta: Double, _ st: WatchStepState) {
        engine.recordOutcome(exercise.exerciseId, distanceKm: max(0, st.distanceKm + delta))
    }

    /// The button says what it will do (the watch's own words).
    static func label(_ outcome: WatchLapOutcome, _ st: WatchStepState, _ exercise: WatchExercise,
                      _ screen: WatchScreen) -> String {
        let laps = screen.template == .distance
        switch outcome {
        case .completeSet:     return "Complete set \(min(st.setsDone + 1, WatchSpecText.setCount(exercise, screen)))"
        case .startHold:       return "Start hold"
        case .stopHold:        return "End hold"
        case .logRound:        return laps ? "+ Lap" : "+ Round"
        case .logRoundAndNext: return laps ? "Last lap" : "Last round"
        case .nextSide:        return "Switch side"
        case .next:
            switch screen.template {
            case .forTime: return "Finish"
            case .distance: return "Done"
            default: return "Next"
            }
        }
    }
}

// MARK: - A rest

/// A rest: a ring counting down from the rest's length, what comes next,
/// +30 s and Skip.
struct PlayerRestView: View {
    @ObservedObject var engine: WorkoutSessionState
    let session: WatchSession
    let index: Int
    let completedSet: Int
    let left: Int
    let tint: Color

    var body: some View {
        let ex = session.exercises[index]
        let next = WatchSteps.nextStep(session, index: index, setsDone: completedSet + 1, resting: true)
        let total = max(engine.restTotalSec, left, 1)
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Text("Rest").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: CGFloat(left) / CGFloat(total))
                    .stroke(tint, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                Text(WatchSpecText.mmss(left))
                    .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 260, height: 260)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rest, \(left) seconds left")
            VStack(spacing: 4) {
                Text("Up next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(next.title).font(.title3.weight(.semibold))
                if let value = next.value { Text(value).foregroundStyle(.secondary) }
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                Button {
                    engine.extendRest(exerciseIndex: index, completedSet: completedSet, current: left)
                } label: {
                    Text("+30 s").frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                Button {
                    AppHaptics.medium()
                    engine.skipRest(exerciseIndex: index, completedSet: completedSet)
                } label: {
                    Text("Skip rest").frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
            .font(.headline)
            .padding()
            .accessibilityHint("\(ex.name)")
        }
    }
}

// MARK: - Logging a set

/// A set's reps, weight and RPE, from what the last set or Set Next left
/// (the watch's crown pickers, as steppers).
struct PlayerSetLogger: View {
    @ObservedObject var engine: WorkoutSessionState
    let session: WatchSession
    let exercise: WatchExercise
    let index: Int
    let tint: Color

    @Environment(\.dismiss) private var dismiss
    @State private var reps = 0
    @State private var kg: Double = 0
    @State private var rpe = 0

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $reps, in: 0...200) {
                    LabeledContent("Reps", value: "\(reps)")
                }
                if exercise.weightKg != nil || kg > 0 {
                    Stepper(value: $kg, in: 0...500, step: 2.5) {
                        LabeledContent("Weight", value: "\(LoadFormat.kilograms(kg)) kg")
                    }
                }
                Picker("RPE", selection: $rpe) {
                    Text("—").tag(0)
                    ForEach(5...10, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log set") { log() }.fontWeight(.semibold)
                }
            }
        }
        .tint(tint)
        .onAppear {
            let w = engine.workingSet(exercise)
            reps = w.reps
            kg = w.weightKg ?? 0
            rpe = w.rpe ?? 0
        }
    }

    private func log() {
        let screen = session.screen(for: exercise)
        let start = engine.currentSetStartOffset ?? engine.elapsedSeconds
        let set = WatchSetLog(setIndex: engine.setLogs[exercise.exerciseId]?.count ?? 0, repsActual: reps,
                              weightKg: kg > 0 ? kg : nil, rpe: rpe > 0 ? rpe : nil, completed: true,
                              durationSeconds: max(0, engine.elapsedSeconds - start),
                              startOffset: start, endOffset: engine.elapsedSeconds)
        engine.completeSet(set, for: exercise.exerciseId)
        // What was done is where the next set starts.
        engine.setNext(exercise, .init(reps: reps, weightKg: kg > 0 ? kg : nil, rpe: rpe > 0 ? rpe : nil))
        engine.finishSet(index, exercise, screen)
        dismiss()
    }
}

// MARK: - Every step

/// The whole session, each step done or to come; a tap goes to it.
struct PlayerStepList: View {
    let session: WatchSession
    @ObservedObject var engine: WorkoutSessionState
    let onPick: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(session.exercises.enumerated()), id: \.offset) { i, ex in
                    if !WatchSteps.isFolded(session, i) {
                        Button { onPick(i) } label: {
                            HStack {
                                Image(systemName: engine.completedExerciseIds.contains(ex.exerciseId) ? "checkmark.circle.fill"
                                      : engine.phase.exerciseIndex == i ? "play.circle.fill" : "circle")
                                    .foregroundStyle(engine.completedExerciseIds.contains(ex.exerciseId) ? .green
                                                     : engine.phase.exerciseIndex == i ? .accentColor : .secondary)
                                VStack(alignment: .leading) {
                                    Text(ex.name).foregroundStyle(.primary)
                                    Text(WatchSteps.preview(ex, session.screen(for: ex))).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Steps")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
