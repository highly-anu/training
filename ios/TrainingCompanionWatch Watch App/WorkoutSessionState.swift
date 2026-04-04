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
    }

    @Published var phase: Phase = .idle

    // Timer control
    @Published var isTimerPaused: Bool = false

    // HR
    @Published var currentHR: Int = 0
    @Published var peakHR: Int = 0
    @Published var hrOutOfZoneSeconds: Int = 0
    @Published var isHRAlertActive: Bool = false

    // Session data
    @Published var completedExerciseIds: Set<String> = []
    @Published var setLogs: [String: [WatchSetLog]] = [:]
    @Published var elapsedSeconds: Int = 0
    @Published var calories: Int = 0

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

    func startSession() {
        reset()
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
        elapsedSeconds = 0; calories = 0
        hrOutOfZoneCounter = 0; hrAlertCooldown = 0
    }

    // MARK: - Sets / reps

    func completeSet(_ log: WatchSetLog, for exerciseId: String) {
        var logs = setLogs[exerciseId] ?? []
        logs.append(log)
        setLogs[exerciseId] = logs
        WKInterfaceDevice.current().play(.success)
    }

    func startRest(exerciseIndex: Int, completedSet: Int, seconds: Int) {
        guard seconds > 0 else {
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
            phase = .active(exerciseIndex: ei, setIndex: cs + 1)
            WKInterfaceDevice.current().play(.start)
        } else {
            phase = .resting(exerciseIndex: ei, completedSet: cs, secondsRemaining: remaining - 1)
        }
    }

    func skipRest(exerciseIndex: Int, completedSet: Int) {
        phase = .active(exerciseIndex: exerciseIndex, setIndex: completedSet + 1)
        WKInterfaceDevice.current().play(.start)
    }

    func extendRest(exerciseIndex: Int, completedSet: Int, current remaining: Int) {
        phase = .resting(exerciseIndex: exerciseIndex, completedSet: completedSet,
                         secondsRemaining: remaining + 30)
    }

    func markExerciseComplete(id: String) {
        completedExerciseIds.insert(id)
    }

    // MARK: - Timed work

    func startTimedWork(exerciseIndex: Int) {
        phase = .timedWork(exerciseIndex: exerciseIndex, secondsElapsed: 0)
        WKInterfaceDevice.current().play(.start)
    }

    func tickTimedWork() {
        guard case let .timedWork(ei, elapsed) = phase else { return }
        phase = .timedWork(exerciseIndex: ei, secondsElapsed: elapsed + 1)
    }

    func completeTimedWork(exerciseIndex: Int, exerciseId: String) {
        markExerciseComplete(id: exerciseId)
        phase = .active(exerciseIndex: exerciseIndex + 1, setIndex: 0)
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
                  exerciseIndex: Int, exerciseId: String) {
        guard case let .emomInterval(ei, round, isWork, remaining) = phase else { return }
        if remaining <= 1 {
            if isWork {
                if restSec > 0 {
                    phase = .emomInterval(exerciseIndex: ei, round: round,
                                         isWork: false, remaining: restSec)
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
        }
    }

    private func advanceEMOMRound(ei: Int, round: Int, workSec: Int,
                                   totalRounds: Int, exerciseId: String) {
        let next = round + 1
        if next > totalRounds {
            markExerciseComplete(id: exerciseId)
            phase = .active(exerciseIndex: ei + 1, setIndex: 0)
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
            phase = .active(exerciseIndex: ei + 1, setIndex: 0)
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
    func tickElapsed() { elapsedSeconds += 1 }
}
