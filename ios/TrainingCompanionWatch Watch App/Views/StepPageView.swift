import SwiftUI

/// A step drawn the way the Garmin draws it — the title line, two fields (a
/// label over a number), the rule, the two lines — filled by the package's
/// screen spec (WatchSpecText), so both watches show one step alike
/// (docs/watch.md). It replaced eight views picked by slot type.
struct DataPageView: View {
    let exercise: WatchExercise
    let index: Int
    let session: WatchSession

    @EnvironmentObject var sessionState: WorkoutSessionState

    var body: some View {
        let screen = session.screen(for: exercise)
        let st = sessionState.stepState(exercise, index: index, screen: screen)
        let lines = WatchSpecText.lines(exercise, screen, st, lapWord: "the button")
        VStack(alignment: .leading, spacing: 4) {
            Text(WatchSpecText.title(exercise, screen, st))
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            HStack(alignment: .top, spacing: 8) {
                field(WatchSpecText.fieldA(exercise, screen, st))
                if let b = WatchSpecText.fieldB(exercise, screen, st) {
                    Spacer(minLength: 4)
                    field(b, trailing: true)
                }
            }
            Divider()
            // A test's line carries the watch's one test accent (design-system §9.4).
            Text(lines.0)
                .font(.footnote)
                .foregroundStyle(screen.lines == .standardTarget && exercise.standard != nil ? .yellow : .primary)
                .lineLimit(2)
            if let second = lines.1 {
                Text(second)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func field(_ f: WatchSpecText.Field?, trailing: Bool = false) -> some View {
        if let f {
            VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
                Text(f.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(f.value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}

/// What a step's buttons do: Start until it runs, then one primary button —
/// the spec's LAP, worked out by WatchSpecText.lap — and Skip beside it.
struct StepControlsView: View {
    let exercise: WatchExercise
    let index: Int
    let session: WatchSession

    @EnvironmentObject var sessionState: WorkoutSessionState
    @State private var showLogger = false

    private var screen: WatchScreen { session.screen(for: exercise) }

    var body: some View {
        let screen = self.screen
        let running = sessionState.isRunning(index, exercise, screen)
        let st = sessionState.stepState(exercise, index: index, screen: screen)
        let outcome = WatchSpecText.lap(exercise, screen, st)
        let tint = ModalityStyle.color(for: session.modalityId)
        VStack(spacing: 6) {
            if let left = sessionState.leadInLeft(index), let word = WatchCues.leadInWord(secondsLeft: left) {
                // The lead-in: Countdown Start's, or a rest's last seconds.
                Text(word)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText(countsDown: true))
            }
            if !running {
                if sessionState.countIn?.index != index {
                    Button("Start") { sessionState.start(index, exercise, screen) }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                }
            } else {
                Button(label(outcome, st)) {
                    if outcome == .completeSet { showLogger = true }
                    else { sessionState.perform(outcome, index, exercise, screen) }
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)

                if screen.template == .distance && !WatchSpecText.isShortDistance(exercise, screen) {
                    // Entered by hand where there is no GPS (the simulator, a treadmill).
                    HStack(spacing: 12) {
                        Button("−0.1") { addKm(-0.1, st) }
                        Button("+0.1 km") { addKm(0.1, st) }
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                if outcome != .next {
                    Button("Skip") { sessionState.finishStep(index, exercise, screen) }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showLogger) {
            SetLoggerSheetView(
                exercise: exercise,
                setIndex: st.setsDone,
                exerciseIndex: index,
                startOffset: sessionState.currentSetStartOffset ?? sessionState.elapsedSeconds,
                initial: sessionState.workingSet(exercise)
            ) { log in
                sessionState.completeSet(log, for: exercise.exerciseId)
                // What was done is where the next set starts.
                sessionState.setNext(exercise, .init(reps: log.repsActual ?? 0, weightKg: log.weightKg, rpe: log.rpe))
                sessionState.finishSet(index, exercise, screen)
            }
        }
    }

    private func addKm(_ delta: Double, _ st: WatchStepState) {
        sessionState.recordOutcome(exercise.exerciseId, distanceKm: max(0, st.distanceKm + delta))
    }

    /// The button says what it will do.
    private func label(_ outcome: WatchLapOutcome, _ st: WatchStepState) -> String {
        let laps = screen.template == .distance
        switch outcome {
        case .completeSet:     return "Complete Set \(min(st.setsDone + 1, WatchSpecText.setCount(exercise, screen)))"
        case .startHold:       return "Start Hold"
        case .stopHold:        return "End Hold"
        case .logRound:        return laps ? "+ Lap" : "+ Round"
        case .logRoundAndNext: return laps ? "Last Lap" : "Last Round"
        case .nextSide:        return "Switch Side"
        case .next:
            switch screen.template {
            case .forTime: return "Finish"
            case .distance: return "Done"
            default: return "Next"
            }
        }
    }
}
