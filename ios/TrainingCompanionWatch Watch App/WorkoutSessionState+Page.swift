import Foundation
import WatchKit

extension WatchExercise {
    /// Rounds, work and rest of an interval step, read once for the page and
    /// the workout's ticker alike.
    var emomPlan: (rounds: Int, workSec: Int, restSec: Int) {
        let parsed = HRZoneCalculator.parseEMOMFormat(emomFormat)
        return (targetRounds ?? parsed.rounds, workSec ?? parsed.workSec, intervalRestSec ?? parsed.restSec)
    }
}

/// The data page's side of the engine: the state a step's screen reads
/// (`WatchStepState`, the Garmin's WorkoutController in plain values) and
/// what the primary button — the Garmin's LAP — does to it.
extension WorkoutSessionState {

    // MARK: - Starting a step

    /// Sets and holds run from the moment they are current; every other step
    /// waits for its Start.
    func isRunning(_ index: Int, _ ex: WatchExercise, _ screen: WatchScreen) -> Bool {
        switch screen.template {
        case .sets, .hold:
            return true
        case .timed, .roundTimer:
            if case let .timedWork(ei, _) = phase { return ei == index }
            return false
        case .interval:
            if case let .emomInterval(ei, _, _, _) = phase { return ei == index }
            return false
        case .rounds:
            if case let .amrapRunning(ei, _) = phase { return ei == index }
            return clockStarts[index] != nil
        case .forTime, .distance:
            return clockStarts[index] != nil
        }
    }

    func start(_ index: Int, _ ex: WatchExercise, _ screen: WatchScreen) {
        switch screen.template {
        case .sets, .hold:
            return
        case .timed, .roundTimer:
            startTimedWork(exerciseIndex: index)
        case .interval:
            startEMOM(exerciseIndex: index, workSeconds: ex.emomPlan.workSec)
        case .rounds:
            // A capped AMRAP counts down; an uncapped one (a ladder) counts up.
            if let cap = ex.timeMinutes, cap > 0 { startAMRAP(exerciseIndex: index, minutes: cap) }
            else { startClock(index) }
        case .forTime, .distance:
            startClock(index)
        }
    }

    private func startClock(_ index: Int) {
        clockStarts[index] = Date()
        WKInterfaceDevice.current().play(.start)
    }

    /// The time on a running step.
    func clockElapsed(_ index: Int, _ ex: WatchExercise, now: Date = Date()) -> Int {
        if case let .timedWork(ei, secs) = phase, ei == index { return secs }
        if case let .amrapRunning(ei, left) = phase, ei == index { return max(0, (ex.timeMinutes ?? 0) * 60 - left) }
        if let t = clockStarts[index] { return max(0, Int(now.timeIntervalSince(t))) }
        return 0
    }

    // MARK: - The page's state

    func stepState(_ ex: WatchExercise, index: Int, screen: WatchScreen, now: Date = Date()) -> WatchStepState {
        var s = WatchStepState()
        let logs = setLogs[ex.exerciseId] ?? []
        // The working set: Set Next's or Edit Set's, else what the logger
        // last took, else the prescription.
        let working = workingSet(ex)
        s.reps = working.reps
        s.weightKg = working.weightKg
        s.rpe = Double(working.rpe ?? 0)
        s.setsDone = logs.count
        if case let .resting(ei, _, _) = phase, ei == index { s.resting = true }
        s.sideIsLeft = sideIsLeft
        s.rounds = outcomes[ex.exerciseId]?.rounds ?? 0
        s.repsDone = logs.compactMap(\.repsActual).reduce(0, +)
        if case let .amrapRunning(ei, left) = phase, ei == index { s.capLeftSec = left }
        else { s.capLeftSec = (ex.timeMinutes ?? 0) * 60 }
        s.elapsedSec = clockElapsed(index, ex, now: now)
        s.distanceKm = outcomes[ex.exerciseId]?.distanceKm ?? distanceMeters / 1000
        if let started = holdStartedAt {
            s.holdRunning = true
            s.holdLeftSec = max(0, (ex.holdSeconds ?? 30) - Int(now.timeIntervalSince(started)))
        }
        let plan = ex.emomPlan
        s.intervalTotal = plan.rounds
        s.intervalWorkSec = plan.workSec
        s.intervalRestSec = plan.restSec
        if case let .emomInterval(ei, round, isWork, left) = phase, ei == index {
            s.intervalWorking = isWork
            s.intervalRound = round
            s.intervalLeftSec = left
            // A rest that ends on heart rate shows its time so far and the HR
            // to reach, not a countdown.
            s.gateRest = !isWork && ex.restUntilHr != nil
            if !isWork { s.restPhaseElapsedSec = max(0, plan.restSec - left) }
        } else {
            s.intervalLeftSec = plan.workSec
        }
        s.heartRate = currentHR > 0 ? currentHR : nil
        if let session {
            let next = WatchSteps.nextStep(session, index: index, setsDone: s.setsDone, resting: s.resting)
            s.nextTitle = next.title
            s.nextValue = next.value
            s.components = WatchSteps.components(of: session, at: index)
                .map { .init(name: $0.name, repsPerRound: $0.repsPerRound) }
        }
        return s
    }

    // MARK: - Set Next and Edit Set

    /// The set the next log starts from: Set Next's or Edit Set's values,
    /// else the last logged set's, else the prescription's.
    func workingSet(_ ex: WatchExercise) -> WorkingSet {
        if let w = workingSets[ex.exerciseId] { return w }
        if let last = setLogs[ex.exerciseId]?.last {
            return WorkingSet(reps: last.repsActual ?? 0, weightKg: last.weightKg, rpe: last.rpe ?? ex.targetRpe)
        }
        return WorkingSet(reps: Int(ex.reps?.prefix { $0.isNumber } ?? "") ?? 0,
                          weightKg: ex.weightKg, rpe: ex.targetRpe)
    }

    /// Set Next: the coming sets' reps, weight and RPE.
    func setNext(_ ex: WatchExercise, _ set: WorkingSet) {
        workingSets[ex.exerciseId] = set
    }

    /// Edit Set: corrects the last logged set and carries the values forward
    /// to the sets after it, as the Garmin's Strength does.
    func editLastSet(_ ex: WatchExercise, _ set: WorkingSet) {
        guard var logs = setLogs[ex.exerciseId], let last = logs.popLast() else { return }
        logs.append(WatchSetLog(setIndex: last.setIndex, repsActual: set.reps, weightKg: set.weightKg, rpe: set.rpe,
                                completed: last.completed, durationSeconds: last.durationSeconds,
                                startOffset: last.startOffset, endOffset: last.endOffset))
        setLogs[ex.exerciseId] = logs
        workingSets[ex.exerciseId] = set
    }

    // MARK: - The primary button

    /// Carries out what the page's button does. A set is logged through the
    /// set logger first (`completeSet`, then `finishSet`).
    func perform(_ outcome: WatchLapOutcome, _ index: Int, _ ex: WatchExercise, _ screen: WatchScreen) {
        switch outcome {
        case .completeSet:
            return
        case .startHold:
            holdStartedAt = Date()
            WKInterfaceDevice.current().play(.start)
        case .stopHold:
            stopHold(index, ex, screen)
        case .logRound:
            recordOutcome(ex.exerciseId, rounds: (outcomes[ex.exerciseId]?.rounds ?? 0) + 1)
            WKInterfaceDevice.current().play(.click)
        case .logRoundAndNext:
            recordOutcome(ex.exerciseId, rounds: (outcomes[ex.exerciseId]?.rounds ?? 0) + 1)
            finishStep(index, ex, screen)
        case .next:
            finishStep(index, ex, screen)
        case .nextSide:
            sideIsLeft.toggle()
            WKInterfaceDevice.current().play(.directionUp)
        }
    }

    /// The hold went up as one set of its seconds; then the rest.
    private func stopHold(_ index: Int, _ ex: WatchExercise, _ screen: WatchScreen) {
        guard let started = holdStartedAt else { return }
        let now = Date()
        let held = max(0, Int(now.timeIntervalSince(started)))
        let end = elapsedSeconds
        holdStartedAt = nil
        completeSet(WatchSetLog(setIndex: setLogs[ex.exerciseId]?.count ?? 0, repsActual: nil, weightKg: ex.weightKg,
                                rpe: nil, completed: true, durationSeconds: held,
                                startOffset: max(0, end - held), endOffset: end),
                    for: ex.exerciseId)
        finishSet(index, ex, screen)
    }

    /// After a set: the other side next on a side-tracked step, then the
    /// rest — which, after the last set, leads on to the next step, as the
    /// Garmin's does.
    func finishSet(_ index: Int, _ ex: WatchExercise, _ screen: WatchScreen) {
        if WatchSpecText.sideTracked(ex, screen) { sideIsLeft.toggle() }
        let done = setLogs[ex.exerciseId]?.count ?? 0
        let last = done >= WatchSpecText.setCount(ex, screen)
        if last { markExerciseComplete(id: ex.exerciseId) }
        let rest = WatchSteps.restSec(ex, screen)
        if last && (rest == 0 || indexAfter(index) >= (session?.exercises.count ?? 0)) {
            advance(to: indexAfter(index))
            return
        }
        restAdvances = last
        startRest(exerciseIndex: index, completedSet: done - 1, seconds: rest)
    }

    /// Ends the step with what it produced — a clock for a for-time step or
    /// a distance, the km covered — and moves on.
    func finishStep(_ index: Int, _ ex: WatchExercise, _ screen: WatchScreen) {
        let secs = clockElapsed(index, ex)
        switch screen.template {
        case .forTime:
            recordOutcome(ex.exerciseId, durationSec: secs)
        case .distance:
            let km = outcomes[ex.exerciseId]?.distanceKm ?? (distanceMeters > 0 ? distanceMeters / 1000 : nil)
            recordOutcome(ex.exerciseId, durationSec: secs, distanceKm: km)
        case .rounds where ex.timeMinutes == nil:
            recordOutcome(ex.exerciseId, durationSec: secs)
        default:
            break
        }
        holdStartedAt = nil
        if case let .timedWork(ei, _) = phase, ei == index {
            completeTimedWork(exerciseIndex: index, exerciseId: ex.exerciseId)
            return
        }
        markExerciseComplete(id: ex.exerciseId)
        advance(to: indexAfter(index))
        WKInterfaceDevice.current().play(.success)
    }
}
