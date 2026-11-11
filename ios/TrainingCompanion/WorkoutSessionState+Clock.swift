import Foundation

/// The engine's clock, shared by the watch and the phone: one second of the
/// workout (`tick`), the seconds a locked phone missed (`catchUp`), what is
/// coming (`forecast`, for the phone's notifications and Live Activity), and
/// the engine saved and restored (`snapshot`), so a workout outlives its app.
/// What a session produced for the upload (`exerciseTimeline`,
/// `standardDecisions`) is here too, so both devices send the same.
extension WorkoutSessionState {

    // MARK: - The clock

    /// One second of the workout: the rest, the timed step, the interval,
    /// the AMRAP's cap and a hold each count down on it. The watch's
    /// WorkoutManager ticked these itself; a running clock lives here now.
    func tick() {
        tickElapsed()
        defer { lastTickAt = now }
        guard let session else { return }
        switch phase {
        case .resting:
            tickRest()

        case let .timedWork(ei, elapsed):
            guard !isTimerPaused, ei < session.exercises.count else { return }
            let ex = session.exercises[ei]
            tickTimedWork(exercise: ex)
            guard let minutes = ex.durationMinutes, elapsed + 1 == minutes * 60,
                  lastAutoAdvancedIndex != ei else { return }
            lastAutoAdvancedIndex = ei
            timedStepEnded(ei, in: session)

        case let .emomInterval(ei, _, _, _):
            guard ei < session.exercises.count else { return }
            let ex = session.exercises[ei]
            let plan = ex.emomPlan
            tickEMOM(workSec: plan.workSec, restSec: plan.restSec, totalRounds: plan.rounds,
                     exerciseIndex: ei, exerciseId: ex.exerciseId, exercise: ex)

        case let .amrapRunning(ei, _):
            guard ei < session.exercises.count else { return }
            tickAMRAP(exerciseIndex: ei, exerciseId: session.exercises[ei].exerciseId)

        case let .active(ei, _):
            // A hold ends itself at its seconds (it used to run on at 0).
            guard let started = holdStartedAt, ei < session.exercises.count else { return }
            let ex = session.exercises[ei]
            let screen = session.screen(for: ex)
            if screen.template == .hold, Int(now.timeIntervalSince(started)) >= (ex.holdSeconds ?? 30) {
                perform(.stopHold, ei, ex, screen)
            }

        default:
            break
        }
    }

    /// A timed step at its time: the next timed step starts at once, any
    /// other step comes up, and the last asks whether to keep going. Two taps
    /// first, a beat apart; replayed (muted), it rolls on at once.
    private func timedStepEnded(_ ei: Int, in session: WatchSession) {
        let roll = { [weak self] in
            guard let self else { return }
            let next = self.indexAfter(ei)
            if next < session.exercises.count {
                if session.exercises[next].durationMinutes != nil {
                    self.autoAdvanceToNextTimedWork(currentExerciseId: session.exercises[ei].exerciseId, nextIndex: next)
                } else {
                    self.completeTimedWork(exerciseIndex: ei, exerciseId: session.exercises[ei].exerciseId)
                }
            } else {
                self.showOvertimePrompt = true
            }
        }
        guard !muted else { roll(); return }
        play(.notification)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.play(.notification)
            try? await Task.sleep(nanoseconds: 800_000_000)
            roll()
        }
    }

    /// The seconds since the last tick, each ticked in turn: a phone that was
    /// locked or in the background catches its workout up when it comes
    /// back. Only the last second sounds. At most four hours are replayed.
    func catchUp(to target: Date) {
        guard let last = lastTickAt else { lastTickAt = target; return }
        let missed = min(Int(target.timeIntervalSince(last)), 4 * 3600)
        guard missed > 0 else { return }
        let wasMuted = muted
        for second in 1...missed {
            simulatedNow = last.addingTimeInterval(TimeInterval(second))
            muted = wasMuted || second < missed
            tick()
            if phase == .sessionComplete { break }
        }
        muted = wasMuted
        simulatedNow = nil
        lastTickAt = target
    }

    /// Whether a clock is running that will move the workout on by itself: a
    /// rest, a timed step, an interval, a capped AMRAP, a hold. A set waits
    /// for the athlete.
    var clockDrivesNext: Bool {
        switch phase {
        case .resting, .emomInterval, .amrapRunning: return true
        case .timedWork: return !isTimerPaused
        case .active: return holdStartedAt != nil
        case .idle, .sessionComplete: return false
        }
    }

    // MARK: - What comes next

    struct ForecastEvent: Equatable {
        let at: Date
        /// What the athlete is told then: "Rest over · Goblet squat — set 3 of 5".
        let text: String
        /// The step it leads to, nil at the session's end.
        let stepIndex: Int?
    }

    /// The coming moments the clock moves the workout on by itself — a rest
    /// over, an interval's work and rest, a timed step's end, the AMRAP's cap
    /// — found by ticking a silent copy forward until it waits for the
    /// athlete. The phone schedules its notifications and its Live
    /// Activity's countdown from them.
    func forecast(limit: Int = 48, horizonSec: Int = 3 * 3600) -> [ForecastEvent] {
        guard let session, clockDrivesNext else { return [] }
        let copy = WorkoutSessionState()
        copy.restore(snapshot(), session: session)
        copy.muted = true
        var t = now
        copy.simulatedNow = t
        copy.lastTickAt = t
        var key = copy.phaseKey
        var events: [ForecastEvent] = []
        for _ in 0..<horizonSec {
            t = t.addingTimeInterval(1)
            copy.simulatedNow = t
            copy.tick()
            let next = copy.phaseKey
            if next != key {
                events.append(ForecastEvent(at: t, text: copy.cueText, stepIndex: copy.phase.exerciseIndex))
                key = next
                if events.count >= limit || copy.phase == .sessionComplete { break }
            }
            if !copy.clockDrivesNext { break }
        }
        return events
    }

    /// The phase without its counters: a change in it is a moment to tell.
    var phaseKey: String {
        switch phase {
        case .idle: return "idle"
        case let .active(ei, set): return "active:\(ei):\(set):\(holdStartedAt == nil ? 0 : 1)"
        case let .timedWork(ei, _): return showOvertimePrompt ? "overtime:\(ei)" : "timed:\(ei)"
        case let .emomInterval(ei, round, isWork, _): return "interval:\(ei):\(round):\(isWork)"
        case let .amrapRunning(ei, _): return "amrap:\(ei)"
        case let .resting(ei, set, _): return "rest:\(ei):\(set)"
        case .sessionComplete: return "complete"
        }
    }

    /// What the athlete is told about the phase now: the step and its set,
    /// round or rest.
    var cueText: String {
        guard let session else { return "" }
        func name(_ i: Int) -> String { i < session.exercises.count ? session.exercises[i].name : "" }
        switch phase {
        case .idle:
            return session.archetypeName
        case let .active(ei, set):
            guard ei < session.exercises.count else { return "" }
            let ex = session.exercises[ei]
            let sets = WatchSpecText.setCount(ex, session.screen(for: ex))
            return sets > 1 ? "\(ex.name) — set \(min(set + 1, sets)) of \(sets)" : ex.name
        case let .timedWork(ei, _):
            return showOvertimePrompt ? "Time — \(name(ei))" : name(ei)
        case let .emomInterval(ei, round, isWork, _):
            guard ei < session.exercises.count else { return "" }
            let total = session.exercises[ei].emomPlan.rounds
            return isWork ? "Round \(round) of \(total) · \(name(ei))" : "Rest · round \(round) of \(total)"
        case let .amrapRunning(ei, _):
            return name(ei)
        case let .resting(ei, _, _):
            let next = restAdvances ? indexAfter(ei) : ei
            return next < session.exercises.count ? "Rest · up next \(name(next))" : "Rest"
        case .sessionComplete:
            return "Workout complete"
        }
    }

    /// When the phase now ends by the clock (a rest, an interval's phase, a
    /// timed step, the cap), else nil: the Live Activity's countdown.
    var phaseEndsAt: Date? {
        forecast(limit: 1).first?.at
    }

    // MARK: - Saved and restored

    struct Snapshot: Codable {
        struct Window: Codable {
            let start: Date
            let end: Date?
        }
        var phase: Phase
        var elapsedSeconds: Int
        var setLogs: [String: [WatchSetLog]]
        var outcomes: [String: WatchOutcome]
        var completedExerciseIds: Set<String>
        var resultDecision: String?
        var stepWindows: [Int: Window]
        var currentStep: Int?
        var currentSetStartOffset: Int?
        var sideIsLeft: Bool
        var holdStartedAt: Date?
        var clockStarts: [Int: Date]
        var restAdvances: Bool
        var restTotalSec: Int = 0
        var workingSets: [String: WorkingSet]
        var metronomeOn: Bool
        var restGateBelow: Int
        var isTimerPaused: Bool
        var showOvertimePrompt: Bool
        var lastAutoAdvancedIndex: Int
        var lastTickAt: Date?
    }

    func snapshot() -> Snapshot {
        Snapshot(phase: phase, elapsedSeconds: elapsedSeconds, setLogs: setLogs, outcomes: outcomes,
                 completedExerciseIds: completedExerciseIds, resultDecision: resultDecision,
                 stepWindows: stepWindows.mapValues { Snapshot.Window(start: $0.start, end: $0.end) },
                 currentStep: currentStep, currentSetStartOffset: currentSetStartOffset,
                 sideIsLeft: sideIsLeft, holdStartedAt: holdStartedAt, clockStarts: clockStarts,
                 restAdvances: restAdvances, restTotalSec: restTotalSec, workingSets: workingSets, metronomeOn: metronomeOn,
                 restGateBelow: restGate.below, isTimerPaused: isTimerPaused,
                 showOvertimePrompt: showOvertimePrompt, lastAutoAdvancedIndex: lastAutoAdvancedIndex,
                 lastTickAt: lastTickAt)
    }

    /// The engine as a snapshot left it, on its session. Nothing sounds.
    func restore(_ s: Snapshot, session: WatchSession) {
        reset()
        self.session = session
        phase = s.phase
        // Assigned after the phase, whose didSet opens a window of its own.
        stepWindows = s.stepWindows.mapValues { ($0.start, $0.end) }
        currentStep = s.currentStep
        elapsedSeconds = s.elapsedSeconds
        setLogs = s.setLogs
        outcomes = s.outcomes
        completedExerciseIds = s.completedExerciseIds
        resultDecision = s.resultDecision
        currentSetStartOffset = s.currentSetStartOffset
        sideIsLeft = s.sideIsLeft
        holdStartedAt = s.holdStartedAt
        clockStarts = s.clockStarts
        restAdvances = s.restAdvances
        restTotalSec = s.restTotalSec
        workingSets = s.workingSets
        metronomeOn = s.metronomeOn
        restGate = WatchCues.RestGate(below: s.restGateBelow)
        isTimerPaused = s.isTimerPaused
        showOvertimePrompt = s.showOvertimePrompt
        lastAutoAdvancedIndex = s.lastAutoAdvancedIndex
        lastTickAt = s.lastTickAt
    }

    // MARK: - What the session produced

    /// Each step's window — from when it became current to when the athlete
    /// moved on — else, for a step with none, the span of its sets' offsets.
    /// Each entry carries its offsets from `startedAt` and its wall-clock
    /// times: a recording the device made itself lines up by the offsets, a
    /// band's that started at another moment only by the times
    /// (src/analytics/hr_plan.py reads `startAt` / `endAt` first).
    func exerciseTimeline(startedAt: Date, hrSamples: [(t: Int, b: Int)] = []) -> [ExerciseTimelineEntry]? {
        let iso = ISO8601DateFormatter()
        func avg(_ start: Int, _ end: Int) -> Int? {
            let samples = hrSamples.filter { $0.t >= start && $0.t <= end }
            return samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.b } / samples.count
        }
        func entry(_ id: String, _ start: Int, _ end: Int) -> ExerciseTimelineEntry {
            ExerciseTimelineEntry(exerciseId: id, startOffset: start, endOffset: end, avgHRDuring: avg(start, end),
                                  startAt: iso.string(from: startedAt.addingTimeInterval(TimeInterval(start))),
                                  endAt: iso.string(from: startedAt.addingTimeInterval(TimeInterval(end))))
        }
        var entries: [ExerciseTimelineEntry] = []
        var timed = Set<String>()
        if let session {
            for (index, window) in stepWindows.sorted(by: { $0.key < $1.key }) where index < session.exercises.count {
                let id = session.exercises[index].exerciseId
                let start = max(0, Int(window.start.timeIntervalSince(startedAt)))
                let end = Int((window.end ?? now).timeIntervalSince(startedAt))
                guard end > start, !timed.contains(id) else { continue }
                timed.insert(id)
                entries.append(entry(id, start, end))
            }
        }
        for (exerciseId, sets) in setLogs.sorted(by: { $0.key < $1.key }) where !timed.contains(exerciseId) {
            guard let start = sets.compactMap(\.startOffset).min(),
                  let end = sets.compactMap(\.endOffset).max() else { continue }
            entries.append(entry(exerciseId, start, end))
        }
        return entries.isEmpty ? nil : entries
    }

    /// The Results answer, for each test step that produced a value.
    func standardDecisions(_ session: WatchSession) -> [String: String]? {
        guard let decision = resultDecision else { return nil }
        var out: [String: String] = [:]
        for ex in session.exercises {
            guard let st = ex.standard,
                  WatchResults.value(ex, sets: setLogs[ex.exerciseId] ?? [], outcome: outcomes[ex.exerciseId]) != nil
            else { continue }
            out[st.id] = decision
        }
        return out.isEmpty ? nil : out
    }
}
