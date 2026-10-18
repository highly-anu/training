import Combine
import Foundation
import WatchKit

@MainActor
final class WorkoutSessionState: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case active(exerciseIndex: Int, setIndex: Int)
        case timedWork(exerciseIndex: Int, secondsElapsed: Int)
        case emomInterval(exerciseIndex: Int, round: Int, isWork: Bool, remaining: Int)
        case amrapRunning(exerciseIndex: Int, secondsRemaining: Int)
        case resting(exerciseIndex: Int, completedSet: Int, secondsRemaining: Int)
        case sessionComplete

        /// The exercise the phase is on; nil before the first and after the last.
        var exerciseIndex: Int? {
            switch self {
            case let .active(ei, _), let .timedWork(ei, _), let .emomInterval(ei, _, _, _),
                 let .amrapRunning(ei, _), let .resting(ei, _, _):
                return ei
            case .idle, .sessionComplete:
                return nil
            }
        }
    }

    @Published var phase: Phase = .idle {
        didSet { noteStep(phase.exerciseIndex) }
    }

    /// Exercise index → when it became current and when the athlete moved
    /// on, by the wall clock the heart-rate samples are stamped with. The
    /// session log sends it as `exerciseTimeline`, which the server cuts the
    /// heart rate by: only an exercise that prescribes zones counts in them
    /// (src/analytics/hr_plan.py). Sets alone timed only set-logged steps, so
    /// a warm-up or a timed piece had no window.
    private(set) var stepWindows: [Int: (start: Date, end: Date?)] = [:]
    private var currentStep: Int? = nil

    private func noteStep(_ index: Int?, at now: Date = Date()) {
        guard index != currentStep else { return }
        if let cur = currentStep, let w = stepWindows[cur] { stepWindows[cur] = (w.start, now) }
        if let index {
            // Back to a step already done: it runs on from its first start.
            let start = stepWindows[index]?.start ?? now
            stepWindows[index] = (start, nil)
        }
        currentStep = index
    }

    // Timer control
    @Published var isTimerPaused: Bool = false

    // Shown when a long timed exercise hits its prescribed duration —
    // user can dismiss to keep going or tap Finish to end the session.
    @Published var showOvertimePrompt: Bool = false

    // HR
    @Published var currentHR: Int = 0
    @Published var peakHR: Int = 0
    @Published var hrOutOfZoneSeconds: Int = 0
    @Published var isHRAlertActive: Bool = false

    // Movement metrics (populated for outdoor/distance sessions)
    @Published var distanceMeters: Double = 0
    @Published var currentCadence: Double = 0
    @Published var currentSpeedMps: Double = 0
    @Published var floorsAscended: Double = 0

    // Session data
    @Published var completedExerciseIds: Set<String> = []
    @Published var setLogs: [String: [WatchSetLog]] = [:]
    /// exerciseId → what a step produced that is not a set: a for-time
    /// clock, an AMRAP's rounds, a distance. The views kept these in their
    /// own state and dropped them when the step ended.
    @Published var outcomes: [String: WatchOutcome] = [:]
    /// The Results answer for a test session: "save" or "dismiss"; nil = left
    /// for the phone and the web to decide.
    @Published var resultDecision: String? = nil
    @Published var elapsedSeconds: Int = 0
    @Published var calories: Int = 0

    /// Set when transitioning into `.active` phase — marks the start of the next set
    /// so it can be stamped onto WatchSetLog.startOffset.
    private(set) var currentSetStartOffset: Int? = nil

    /// The session being run: what the page reads its steps, specs and
    /// "Next:" line from (WatchSteps), and how the engine moves on past the
    /// movements folded into an AMRAP.
    private(set) var session: WatchSession? = nil

    /// The side being worked on a side-tracked step (the side_tracked
    /// behaviour or a unilateral movement): it switches after each set.
    @Published var sideIsLeft = true
    /// A hold that is running, and since when.
    @Published var holdStartedAt: Date? = nil
    /// When a clocked step (for time, a distance) was started with its
    /// Start; the timed, interval and AMRAP steps run on their phases.
    @Published var clockStarts: [Int: Date] = [:]
    /// The rest running now follows a step's last set: when it ends, the
    /// next step comes up (the Garmin's advanceAfterRest).
    var restAdvances = false
    /// The coming sets' reps, weight and RPE, as Set Next or Edit Set left
    /// them (exercise id → set); the next log starts from them.
    @Published var workingSets: [String: WorkingSet] = [:]
    /// The metronome on a paced step; the commands page switches it.
    @Published var metronomeOn = true
    /// An interval rest that ends on heart rate: seconds under its target so far.
    var restGate = WatchCues.RestGate()

    struct WorkingSet: Equatable {
        var reps: Int
        var weightKg: Double?
        var rpe: Int?
    }

    private(set) var avgHRSamples: [Int] = []
    private var hrOutOfZoneCounter = 0
    private var hrAlertCooldown = 0

    var avgHR: Int {
        avgHRSamples.isEmpty ? 0 : avgHRSamples.reduce(0, +) / avgHRSamples.count
    }

    var isResting: Bool {
        if case .resting = phase { return true }
        return false
    }

    // MARK: - Session lifecycle

    func startSession(_ session: WatchSession) {
        reset()
        self.session = session
        currentSetStartOffset = 0
        phase = .active(exerciseIndex: 0, setIndex: 0)
        WKInterfaceDevice.current().play(.start)
    }

    func completeSession() {
        phase = .sessionComplete
        WKInterfaceDevice.current().play(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            WKInterfaceDevice.current().play(.success)
        }
    }

    func pauseTimer()  { isTimerPaused = true;  WKInterfaceDevice.current().play(.stop) }
    func resumeTimer() { isTimerPaused = false; WKInterfaceDevice.current().play(.start) }

    func reset() {
        phase = .idle
        isTimerPaused = false
        currentHR = 0; peakHR = 0
        avgHRSamples = []
        hrOutOfZoneSeconds = 0; isHRAlertActive = false
        completedExerciseIds = []; setLogs = [:]
        outcomes = [:]; resultDecision = nil
        elapsedSeconds = 0; calories = 0
        hrOutOfZoneCounter = 0; hrAlertCooldown = 0
        distanceMeters = 0; currentCadence = 0; currentSpeedMps = 0; floorsAscended = 0
        currentSetStartOffset = nil
        showOvertimePrompt = false
        stepWindows = [:]; currentStep = nil
        sideIsLeft = true; holdStartedAt = nil; clockStarts = [:]; restAdvances = false
        workingSets = [:]; metronomeOn = true
    }

    /// The step after `index`, past the movements folded into an AMRAP.
    func indexAfter(_ index: Int) -> Int {
        session.map { WatchSteps.indexAfter($0, index) } ?? index + 1
    }

    // MARK: - Sets / reps

    func completeSet(_ log: WatchSetLog, for exerciseId: String) {
        var logs = setLogs[exerciseId] ?? []
        logs.append(log)
        setLogs[exerciseId] = logs
        currentSetStartOffset = nil
        WKInterfaceDevice.current().play(.success)
    }

    func startRest(exerciseIndex: Int, completedSet: Int, seconds: Int) {
        guard seconds > 0 else {
            currentSetStartOffset = elapsedSeconds
            phase = .active(exerciseIndex: exerciseIndex, setIndex: completedSet + 1)
            return
        }
        phase = .resting(exerciseIndex: exerciseIndex, completedSet: completedSet,
                         secondsRemaining: seconds)
    }

    /// Call once per second from a timer while resting.
    func tickRest() {
        guard case let .resting(ei, cs, remaining) = phase else { return }
        switch remaining {
        case 31: WKInterfaceDevice.current().play(.notification)
        case 11: WKInterfaceDevice.current().play(.directionUp)
        default: break
        }
        if remaining <= 1 {
            endRest(exerciseIndex: ei, completedSet: cs)
        } else {
            phase = .resting(exerciseIndex: ei, completedSet: cs, secondsRemaining: remaining - 1)
        }
    }

    func skipRest(exerciseIndex: Int, completedSet: Int) {
        endRest(exerciseIndex: exerciseIndex, completedSet: completedSet)
    }

    /// The next set — or, after a step's last set, the next step.
    private func endRest(exerciseIndex: Int, completedSet: Int) {
        if restAdvances {
            restAdvances = false
            advance(to: indexAfter(exerciseIndex))
        } else {
            currentSetStartOffset = elapsedSeconds
            phase = .active(exerciseIndex: exerciseIndex, setIndex: completedSet + 1)
        }
        WKInterfaceDevice.current().play(.start)
    }

    func extendRest(exerciseIndex: Int, completedSet: Int, current remaining: Int) {
        phase = .resting(exerciseIndex: exerciseIndex, completedSet: completedSet,
                         secondsRemaining: remaining + 30)
    }

    /// Keep what a step produced (only the values given are changed).
    func recordOutcome(_ exerciseId: String, rounds: Int? = nil, durationSec: Int? = nil,
                       distanceKm: Double? = nil) {
        var o = outcomes[exerciseId] ?? WatchOutcome()
        if let rounds { o.rounds = rounds }
        if let durationSec { o.durationSec = durationSec }
        if let distanceKm { o.distanceKm = distanceKm }
        outcomes[exerciseId] = o
    }

    /// A test step's result entered or corrected on the Results screen: a
    /// count goes in as the step's one set (where the server and the
    /// analytics read reps and holds), a clock or rounds as its outcome.
    func setResult(_ ex: WatchExercise, value: Double) {
        switch ex.standard?.result {
        case "duration": recordOutcome(ex.exerciseId, durationSec: Int(value.rounded()))
        case "rounds":   recordOutcome(ex.exerciseId, rounds: Int(value.rounded()))
        case "distance": recordOutcome(ex.exerciseId, distanceKm: value)
        case "hold":
            setLogs[ex.exerciseId] = [WatchSetLog(setIndex: 0, repsActual: nil, weightKg: ex.weightKg, rpe: nil,
                                                  completed: true, durationSeconds: Int(value.rounded()),
                                                  startOffset: nil, endOffset: nil)]
        default:
            setLogs[ex.exerciseId] = [WatchSetLog(setIndex: 0, repsActual: Int(value.rounded()), weightKg: ex.weightKg,
                                                  rpe: nil, completed: true, durationSeconds: nil,
                                                  startOffset: nil, endOffset: nil)]
        }
    }

    func markExerciseComplete(id: String) {
        completedExerciseIds.insert(id)
    }

    /// Move on to an exercise's first set and start its set clock now. The
    /// views used to set the phase directly, so the next exercise's first set
    /// also counted the time spent on the previous screen (its
    /// `durationSeconds` is start → logger open).
    func advance(to exerciseIndex: Int) {
        currentSetStartOffset = elapsedSeconds
        sideIsLeft = true
        holdStartedAt = nil
        phase = .active(exerciseIndex: exerciseIndex, setIndex: 0)
    }

    // MARK: - Timed work

    func startTimedWork(exerciseIndex: Int) {
        phase = .timedWork(exerciseIndex: exerciseIndex, secondsElapsed: 0)
        WKInterfaceDevice.current().play(.start)
    }

    func tickTimedWork(exercise: WatchExercise? = nil) {
        guard case let .timedWork(ei, elapsed) = phase else { return }
        phase = .timedWork(exerciseIndex: ei, secondsElapsed: elapsed + 1)
        if let ex = exercise, WatchCues.switchDue(ex, workSecond: elapsed + 1) { switchHands() }
    }

    func completeTimedWork(exerciseIndex: Int, exerciseId: String) {
        markExerciseComplete(id: exerciseId)
        advance(to: indexAfter(exerciseIndex))
        WKInterfaceDevice.current().play(.success)
    }

    /// Called by the master ticker when the next exercise is also timed — skips the
    /// intermediate .active state so the next timer starts immediately.
    func autoAdvanceToNextTimedWork(currentExerciseId: String, nextIndex: Int) {
        markExerciseComplete(id: currentExerciseId)
        isTimerPaused = false
        phase = .timedWork(exerciseIndex: nextIndex, secondsElapsed: 0)
        WKInterfaceDevice.current().play(.start)
    }

    // MARK: - EMOM

    func startEMOM(exerciseIndex: Int, workSeconds: Int) {
        phase = .emomInterval(exerciseIndex: exerciseIndex, round: 1,
                              isWork: true, remaining: workSeconds)
        WKInterfaceDevice.current().play(.start)
    }

    func tickEMOM(workSec: Int, restSec: Int, totalRounds: Int,
                  exerciseIndex: Int, exerciseId: String, exercise: WatchExercise? = nil) {
        guard case let .emomInterval(ei, round, isWork, remaining) = phase else { return }
        // A rest that ends on heart rate is over once HR has stayed under its
        // target for five seconds; its time is then only the cap.
        if !isWork, let target = exercise?.restUntilHr,
           restGate.tick(heartRate: currentHR, target: target) {
            advanceEMOMRound(ei: ei, round: round, workSec: workSec,
                             totalRounds: totalRounds, exerciseId: exerciseId)
            return
        }
        if remaining <= 1 {
            if isWork {
                if restSec > 0 {
                    phase = .emomInterval(exerciseIndex: ei, round: round,
                                         isWork: false, remaining: restSec)
                    restGate = WatchCues.RestGate()
                    WKInterfaceDevice.current().play(.stop)
                } else {
                    advanceEMOMRound(ei: ei, round: round, workSec: workSec,
                                     totalRounds: totalRounds, exerciseId: exerciseId)
                }
            } else {
                advanceEMOMRound(ei: ei, round: round, workSec: workSec,
                                 totalRounds: totalRounds, exerciseId: exerciseId)
            }
        } else {
            phase = .emomInterval(exerciseIndex: ei, round: round,
                                  isWork: isWork, remaining: remaining - 1)
            if isWork, let ex = exercise, WatchCues.switchDue(ex, workSecond: workSec - remaining + 1) {
                switchHands()
            }
        }
    }

    /// The hand switch of a one-arm block (`switchAtSec`): the other side,
    /// with the turn haptic for that hand.
    func switchHands() {
        sideIsLeft.toggle()
        WKInterfaceDevice.current().play(sideIsLeft ? .navigationLeftTurn : .navigationRightTurn)
    }

    private func advanceEMOMRound(ei: Int, round: Int, workSec: Int,
                                   totalRounds: Int, exerciseId: String) {
        let next = round + 1
        if next > totalRounds {
            markExerciseComplete(id: exerciseId)
            advance(to: indexAfter(ei))
            WKInterfaceDevice.current().play(.success)
        } else {
            phase = .emomInterval(exerciseIndex: ei, round: next,
                                  isWork: true, remaining: workSec)
            WKInterfaceDevice.current().play(.start)
        }
    }

    // MARK: - AMRAP

    func startAMRAP(exerciseIndex: Int, minutes: Int) {
        phase = .amrapRunning(exerciseIndex: exerciseIndex,
                              secondsRemaining: minutes * 60)
        WKInterfaceDevice.current().play(.start)
    }

    func tickAMRAP(exerciseIndex: Int, exerciseId: String) {
        guard case let .amrapRunning(ei, remaining) = phase else { return }
        if remaining == 31 { WKInterfaceDevice.current().play(.notification) }
        if remaining <= 1 {
            markExerciseComplete(id: exerciseId)
            advance(to: indexAfter(ei))
            WKInterfaceDevice.current().play(.success)
        } else {
            phase = .amrapRunning(exerciseIndex: ei, secondsRemaining: remaining - 1)
        }
    }

    // MARK: - HR tracking

    func updateHR(_ bpm: Int, maxHR: Int, prescribedLower: Int?, prescribedUpper: Int?) {
        guard bpm > 0 else { return }
        currentHR = bpm
        if bpm > peakHR { peakHR = bpm }
        avgHRSamples.append(bpm)

        if let lower = prescribedLower, let upper = prescribedUpper, maxHR > 0 {
            let zone = HRZoneCalculator.zone(for: bpm, maxHR: maxHR)
            if zone >= lower && zone <= upper {
                hrOutOfZoneCounter = 0
            } else {
                hrOutOfZoneCounter += 1
                hrOutOfZoneSeconds += 1
            }
            if hrOutOfZoneCounter >= 30 && hrAlertCooldown == 0 {
                isHRAlertActive = true
                for _ in 0..<3 { WKInterfaceDevice.current().play(.notification) }
                hrAlertCooldown = 60
                hrOutOfZoneCounter = 0
            }
        }
        if hrAlertCooldown > 0 {
            hrAlertCooldown -= 1
            if hrAlertCooldown == 0 { isHRAlertActive = false }
        }
    }

    func updateCalories(_ cal: Int) { calories = cal }
    func updateDistance(_ meters: Double) { distanceMeters = meters }
    func updateCadence(_ spm: Double) { currentCadence = spm }
    func updateSpeed(_ mps: Double) { currentSpeedMps = mps }
    func updateFloors(_ floors: Double) { floorsAscended = floors }
    func tickElapsed() { elapsedSeconds += 1 }
}
