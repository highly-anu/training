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

    @StateObject private var briefing = SessionBriefingLoader()
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
                Button { onClose() } label: { Image(systemName: "xmark").font(.headline).appTapTarget() }
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
                // Today against the earlier times it was done (§6.61); with
                // nothing to add, or unread, the steps' own "Last time" stay.
                if briefing.briefing?.saysSomething ?? (briefing.isLoading || briefing.error != nil) {
                    Section {
                        SessionBriefingView(loader: briefing, tint: tint) { await loadBriefing(force: true) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section("Steps") {
                    ForEach(Array(session.exercises.enumerated()), id: \.offset) { i, ex in
                        if !WatchSteps.isFolded(session, i) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.body.weight(.medium))
                                Text(WatchSteps.preview(ex, session.screen(for: ex))).font(.subheadline).foregroundStyle(.secondary)
                                if briefing.briefing?.saysSomething != true, let last = ex.lastTime {
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
            .appButton(.primary)
            .tint(tint)
            .padding()
        }
        .task { await loadBriefing() }
    }

    private func loadBriefing(force: Bool = false) async {
        await briefing.load(api: appState.api, sessionKey: player.target.sessionKey, date: player.target.date,
                            force: force)
    }

    private func failed(_ why: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
            Text(why).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Try again") { Task { await player.load(api: appState.api, fallback: fallback) } }
                .appButton(.primary)
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
            if engine.isPaused {
                PlayerPausedView(engine: engine, exercise: ex, tint: tint) { player.togglePause() }
            } else if case let .resting(ei, cs, left) = engine.phase {
                PlayerRestView(engine: engine, session: session, index: ei, completedSet: cs, left: left, tint: tint) {
                    player.togglePause()
                }
            } else {
                PlayerStepView(engine: engine, session: session, exercise: ex, index: index, tint: tint)
                Spacer(minLength: 0)
                PlayerControls(engine: engine, session: session, exercise: ex, index: index, tint: tint,
                               showLogger: $showLogger) { player.togglePause() }
            }
        }
        .overlay { leadIn(index, tint: tint) }
        .sheet(isPresented: $showSteps) {
            PlayerStepList(session: session, engine: engine) { i in
                player.go(to: i)
                showSteps = false
            }
            .appSheet(.flexible)
        }
        .sheet(isPresented: $showLogger) {
            PlayerSetLogger(engine: engine, session: session, exercise: ex, index: index, tint: tint)
                .appSheet(.compact)
        }
        .confirmationDialog("Leave the workout?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Finish and save") { player.finish() }
            Button("Leave, resume later") { player.leaveForLater(); onClose() }
            Button("Discard workout", role: .destructive) { player.discard(); onClose() }
        } message: {
            Text("Resume later keeps where you are; it waits above the tab bar.")
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
                Button { confirmLeave = true } label: { Image(systemName: "xmark").font(.headline).appTapTarget() }
                    .accessibilityLabel("Leave workout")
                Spacer()
                VStack(spacing: 0) {
                    Text(session.archetypeName).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(WatchSpecText.mmss(engine.elapsedSeconds))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showSteps = true } label: { Image(systemName: "list.bullet").font(.headline).appTapTarget() }
                    .accessibilityLabel("All steps")
            }
            // One segment per step: done, current, to come.
            HStack(spacing: 3) {
                ForEach(steps, id: \.self) { i in
                    Capsule()
                        .fill(engine.completedExerciseIds.contains(session.exercises[i].exerciseId) ? tint
                              : i == index ? tint.opacity(0.55) : Color.secondary.opacity(AppColor.Opacity.fillStrong))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text("Step \(place) of \(steps.count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// "3, 2, 1, go": a Start's count, or a rest's last seconds, over everything.
    /// A rest-less interval counts its minute out in place (PlayerStepView):
    /// the work is still going on under it.
    @ViewBuilder
    private func leadIn(_ index: Int, tint: Color) -> some View {
        if let left = player.engine.leadInLeft(index), !player.engine.isWorkingInterval(index) {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text("Work in").font(.title2.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                    Text("\(left)")
                        .font(AppFont.hero(160))
                        .foregroundStyle(tint)
                        .appNumeric(countsDown: true)
                }
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - A step

/// A step as both watches draw it, phone-sized: the title, the step's clock
/// large — field A, or B when only B is the clock — the other field beside
/// it, the step's gauge, the two lines and its notes. An interval's clock
/// sits in a ring that empties with the round, counts its last seconds out
/// in place and is covered for a moment by the new round's number.
struct PlayerStepView: View {
    @ObservedObject var engine: WorkoutSessionState
    let session: WatchSession
    let exercise: WatchExercise
    let index: Int
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNotes = false
    /// The round that has just begun, while its band shows.
    @State private var turn: RoundTurn?

    /// A step and its round: a change of the round alone is a turn.
    private struct RoundKey: Equatable { let step: Int; let round: Int; let running: Bool }
    private struct RoundTurn: Equatable { let round: Int; let name: String? }

    var body: some View {
        let screen = session.screen(for: exercise)
        let st = engine.stepState(exercise, index: index, screen: screen)
        let lines = WatchSpecText.lines(exercise, screen, st, lapWord: "the button")
        let fields = WatchSpecText.playerFields(screen)
        let lead = WatchSpecText.field(fields.lead, exercise, screen, st)
        let second = WatchSpecText.field(fields.second, exercise, screen, st)
        let running = engine.isWorkingInterval(index) || engine.isRestingInterval(index)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(WatchSpecText.title(exercise, screen, st))
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if screen.template == .interval, let lead {
                    intervalClock(lead, st)
                } else if let lead {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(lead.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(lead.value)
                            .font(AppFont.hero(96))
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .appNumeric(countsDown: fields.lead != .elapsed && WatchSpecText.isClock(fields.lead))
                    }
                }
                if let second {
                    HStack(alignment: .firstTextBaseline) {
                        Text(second.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(second.value)
                            .font(AppFont.hero(44))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .appNumeric()
                    }
                    .accessibilityElement(children: .combine)
                }
                gauge(screen, st)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lines.0)
                        .font(.title3)
                        .foregroundStyle(screen.lines == .standardTarget && exercise.standard != nil ? AppColor.caution : .primary)
                    if let second = lines.1 {
                        Text(second).font(.body).foregroundStyle(.secondary)
                    }
                }
                notes
            }
            .padding()
        }
        .overlay { turnBand }
        .clipped()
        .animation(AppAnimation.springStandard, value: turn)
        .onChange(of: RoundKey(step: index, round: st.intervalRound, running: running)) { old, new in
            // The same step, still running, one round on: the minute turned.
            guard old.step == new.step, old.running, new.running, new.round > old.round else { return }
            let name = exercise.alternateName == nil ? nil : WatchSpecText.roundName(exercise, screen, st)
            let shown = RoundTurn(round: new.round, name: name)
            turn = shown
            Task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                if turn == shown { turn = nil }
            }
        }
    }

    /// An interval's clock in its ring: the round's time left, the ring
    /// emptying with it and full again at the turn. In the last seconds
    /// before the next round's work the ring thickens and the number beats.
    private func intervalClock(_ lead: WatchSpecText.Field, _ st: WatchStepState) -> some View {
        let total = st.intervalWorking ? st.intervalWorkSec : st.intervalRestSec
        // Shown whatever the cue settings say: the count is on the page.
        let closing = engine.isWorkingInterval(index) && st.intervalRestSec == 0
            && st.intervalRound < st.intervalTotal && st.intervalLeftSec <= WatchVocab.leadInSeconds
        return PlayerCountdownRing(left: st.intervalLeftSec, total: total,
                                   tint: st.intervalWorking ? tint : .secondary, closing: closing) {
            VStack(spacing: 0) {
                Text(lead.label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(lead.value)
                    .font(AppFont.hero(96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(closing ? tint : .primary)
                    .appNumeric(countsDown: true)
                    .appPulse(value: closing ? st.intervalLeftSec : 0)
                Text(st.intervalWorking ? "Work" : "Rest")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(st.intervalWorking ? tint : .secondary)
                    .opacity(engine.isWorkingInterval(index) || engine.isRestingInterval(index) ? 1 : 0)
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(st.intervalWorking ? "Work" : "Rest"), \(lead.label.lowercased()) \(lead.value)")
    }

    /// The new round, said across the step as its minute begins.
    @ViewBuilder
    private var turnBand: some View {
        if let turn {
            ZStack {
                tint
                VStack(spacing: 4) {
                    Text("ROUND").font(.title2.weight(.semibold)).opacity(0.85)
                    Text("\(turn.round)").font(AppFont.hero(160)).minimumScaleFactor(0.4).lineLimit(1)
                    if let name = turn.name {
                        Text(name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.white)
                .padding()
            }
            .transition(reduceMotion ? .opacity
                        : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Sets as dots, an interval's rounds as pips, a timed step's time as a
    /// bar: where the step stands at a glance.
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(st.setsDone) of \(total) sets done")
            }
        case .interval:
            // One pip a round: those behind, the one running, those to come.
            // Past thirty they would be hairlines: the rounds as one bar.
            if st.intervalTotal > 30 {
                ProgressView(value: Double(max(0, st.intervalRound - 1)), total: Double(max(1, st.intervalTotal)))
                    .tint(tint)
            } else if st.intervalTotal > 1 {
                HStack(spacing: 3) {
                    ForEach(1...st.intervalTotal, id: \.self) { round in
                        Capsule()
                            .fill(round < st.intervalRound ? tint
                                  : round == st.intervalRound ? tint.opacity(0.55)
                                  : Color.secondary.opacity(AppColor.Opacity.fillStrong))
                            .frame(height: 8)
                    }
                }
                .accessibilityHidden(true)
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
    /// Pause the whole workout.
    var onPause: () -> Void = {}

    var body: some View {
        let screen = session.screen(for: exercise)
        let st = engine.stepState(exercise, index: index, screen: screen)
        let running = engine.isRunning(index, exercise, screen)
        let outcome = WatchSpecText.lap(exercise, screen, st)
        // The buttons float over the step in glass (§6.47): the one primary
        // in the step's colour, the small ones beside each other beneath it.
        AppFloatingControls(spacing: AppMetrics.gapMedium) {
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
            HStack(spacing: AppMetrics.gapSmall) {
                if running, screen.template == .distance, !WatchSpecText.isShortDistance(exercise, screen) {
                    small("−0.1 km") { addKm(-0.1, st) }
                    small("+0.1 km") { addKm(0.1, st) }
                }
                // Every clock of the workout, on any step.
                small("Pause", systemImage: "pause.fill") { onPause() }
                small("Skip", systemImage: "forward.end.fill") { engine.finishStep(index, exercise, screen) }
            }
            .controlSize(.large)
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
        .appButton(.primary)
        .tint(tint)
    }

    private func small(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            // Pause becomes play in place.
            .appSymbolReplace(value: systemImage)
        }
        .appButton(.secondary)
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

// MARK: - Paused

/// The workout held: every clock stands where it was, and the one thing to
/// do is carry on. Leaving and the step list stay in the header.
struct PlayerPausedView: View {
    @ObservedObject var engine: WorkoutSessionState
    let exercise: WatchExercise
    let tint: Color
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "pause.circle.fill")
                .font(AppFont.hero(96))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Paused").font(.largeTitle.bold())
            VStack(spacing: 4) {
                Text(exercise.name).font(.title3.weight(.semibold))
                Text("\(WatchSpecText.mmss(engine.elapsedSeconds)) so far · the clocks wait")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Button {
                AppHaptics.medium()
                onResume()
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .font(.title2.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .appButton(.primary)
            .tint(tint)
            .padding()
        }
        .padding(.horizontal)
    }
}

// MARK: - A countdown's ring

/// The player's countdown ring: what is left of a rest or of an interval's
/// round as the arc, the clock inside. `closing` thickens it for the last
/// seconds before work.
struct PlayerCountdownRing<Content: View>: View {
    let left: Int
    let total: Int
    let tint: Color
    var closing = false
    @ViewBuilder let content: Content

    var body: some View {
        let width: CGFloat = closing ? 26 : 18
        ZStack {
            Circle().stroke(Color.secondary.opacity(AppColor.Opacity.fill), lineWidth: width)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, left)) / CGFloat(max(1, total, left)))
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AppAnimation.tick, value: left)
            content
        }
        .frame(width: 260, height: 260)
        .animation(AppAnimation.springSnappy, value: closing)
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
    /// Pause the whole workout.
    var onPause: () -> Void = {}

    var body: some View {
        let ex = session.exercises[index]
        let next = WatchSteps.nextStep(session, index: index, setsDone: completedSet + 1, resting: true)
        let total = max(engine.restTotalSec, left, 1)
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Text("Rest").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
            PlayerCountdownRing(left: left, total: total, tint: tint) {
                Text(WatchSpecText.mmss(left))
                    .font(AppFont.hero(72))
                    .appNumeric(countsDown: true)
            }
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
                Button { onPause() } label: {
                    Image(systemName: "pause.fill").frame(minWidth: 52, minHeight: 52)
                }
                .appButton(.secondary)
                .accessibilityLabel("Pause workout")
                Button {
                    engine.extendRest(exerciseIndex: index, completedSet: completedSet, current: left)
                } label: {
                    Text("+30 s").frame(maxWidth: .infinity, minHeight: 52)
                }
                .appButton(.secondary)
                Button {
                    AppHaptics.medium()
                    engine.skipRest(exerciseIndex: index, completedSet: completedSet)
                } label: {
                    Text("Skip rest").frame(maxWidth: .infinity, minHeight: 52)
                }
                .appButton(.primary)
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
                                    .foregroundStyle(engine.completedExerciseIds.contains(ex.exerciseId) ? AppColor.complete
                                                     : engine.phase.exerciseIndex == i ? .accentColor : .secondary)
                                    .accessibilityLabel(engine.completedExerciseIds.contains(ex.exerciseId) ? "Done"
                                                        : engine.phase.exerciseIndex == i ? "Current step" : "To do")
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
