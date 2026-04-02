import Foundation
import Combine
import WatchKit

// MARK: - State machine

enum WorkoutPhase: Codable, Equatable {
    case idle
    case active(exerciseIndex: Int, setIndex: Int)
    case timedWork(exerciseIndex: Int, secondsElapsed: Int)
    case emomInterval(exerciseIndex: Int, round: Int, isWork: Bool, remaining: Int)
    case amrapRunning(exerciseIndex: Int, round: Int, secondsRemaining: Int)
    case forTimeRunning(exerciseIndex: Int, secondsElapsed: Int)
    case resting(exerciseIndex: Int, completedSet: Int, secondsRemaining: Int)
    case sessionComplete
}

// MARK: - Per-set log

struct WatchSetLog: Codable {
    var setIndex: Int
    var repsActual: Int?
    var weightKg: Double?
    var rpe: Int?
    var completed: Bool
    var durationSeconds: Int?
}

// MARK: - WorkoutSessionState

final class WorkoutSessionState: ObservableObject {

    // Session being worked
    @Published var session: WatchSession?

    // State machine
    @Published var phase: WorkoutPhase = .idle

    // Elapsed time for the whole session (driven by a 1s timer)
    @Published var elapsedSeconds: Int = 0

    // Live HR
    @Published var currentHR: Int = 0
    @Published var currentHRZone: Int = 0
    @Published var peakHR: Int = 0
    private(set) var avgHRSamples: [Int] = []

    // Zone alert gating
    @Published var isOutOfZone: Bool = false
    var hrOutOfZoneSeconds: Int = 0
    var alertCooldownRemaining: Int = 0

    // Completion tracking
    @Published var setLogs: [String: [WatchSetLog]] = [:]   // exerciseId → sets
    @Published var completedExerciseIds: Set<String> = []
    @Published var amrapRounds: Int = 0

    // Session timing
    var startDate: Date?

    // Pending set log (filled by SetLoggerSheetView before confirming)
    var pendingSetLog: WatchSetLog?

    // Timer
    private var timer: AnyCancellable?
    private let persistKey = "workoutSessionState"

    // MARK: - Session start / stop

    func startSession(_ session: WatchSession) {
        self.session = session
        phase = .idle
        elapsedSeconds = 0
        currentHR = 0; peakHR = 0; avgHRSamples = []
        setLogs = [:]
        completedExerciseIds = []
        amrapRounds = 0
        startDate = Date()
        startElapsedTimer()
        advanceToExercise(0)
        persist()
    }

    func endSession() {
        timer?.cancel()
        phase = .sessionComplete
        persist()
    }

    // MARK: - Exercise navigation

    func advanceToExercise(_ index: Int) {
        guard let session, index < session.exercises.count else {
            phase = .sessionComplete
            return
        }
        let ex = session.exercises[index]
        switch ex.slotType {
        case "time_domain", "skill_practice":
            phase = .timedWork(exerciseIndex: index, secondsElapsed: 0)
        case "emom":
            let workSec = emomWorkSeconds(ex)
            phase = .emomInterval(exerciseIndex: index, round: 1, isWork: true, remaining: workSec)
            startEMOMCycle(exerciseIndex: index, round: 1)
        case "amrap":
            let totalSec = (ex.timeMinutes ?? 10) * 60
            phase = .amrapRunning(exerciseIndex: index, round: 0, secondsRemaining: totalSec)
            amrapRounds = 0
        case "for_time":
            phase = .forTimeRunning(exerciseIndex: index, secondsElapsed: 0)
        default:
            // sets_reps, static_hold, distance — set-based
            phase = .active(exerciseIndex: index, setIndex: 0)
        }
        persist()
    }

    func completeExercise(_ index: Int) {
        guard let session else { return }
        if let id = session.exercises[safe: index]?.exerciseId {
            completedExerciseIds.insert(id)
        }
        let next = index + 1
        if next < session.exercises.count {
            advanceToExercise(next)
        } else {
            phase = .sessionComplete
        }
        persist()
    }

    // MARK: - Set completion

    /// Called when user taps "Complete Set". Starts rest timer then logs the set.
    func completeSet(exerciseIndex: Int, setIndex: Int) {
        guard let session else { return }
        let ex = session.exercises[exerciseIndex]
        let restSec = ex.restSeconds ?? 60

        // Apply the pending log if the user filled it in
        if let log = pendingSetLog {
            var logs = setLogs[ex.exerciseId] ?? []
            logs.append(log)
            setLogs[ex.exerciseId] = logs
            pendingSetLog = nil
        } else {
            // Auto-log as completed with prescribed values
            var logs = setLogs[ex.exerciseId] ?? []
            logs.append(WatchSetLog(setIndex: setIndex, repsActual: ex.reps.flatMap { Int($0) },
                                    weightKg: ex.weightKg, rpe: ex.targetRpe, completed: true))
            setLogs[ex.exerciseId] = logs
        }

        // Determine next action
        let totalSets = ex.sets ?? 1
        let nextSet = setIndex + 1

        if restSec > 0 {
            phase = .resting(exerciseIndex: exerciseIndex, completedSet: setIndex, secondsRemaining: restSec)
            startRestCountdown(exerciseIndex: exerciseIndex, completedSet: setIndex, from: restSec, totalSets: totalSets, nextSet: nextSet)
        } else {
            // No rest — go straight to next set or next exercise
            proceedAfterSet(exerciseIndex: exerciseIndex, nextSet: nextSet, totalSets: totalSets)
        }
        persist()
    }

    func skipRest(exerciseIndex: Int, nextSet: Int, totalSets: Int) {
        timer?.cancel()
        proceedAfterSet(exerciseIndex: exerciseIndex, nextSet: nextSet, totalSets: totalSets)
    }

    func extendRest(exerciseIndex: Int, completedSet: Int, additionalSeconds: Int) {
        if case .resting(let ei, let cs, let remaining) = phase {
            phase = .resting(exerciseIndex: ei, completedSet: cs, secondsRemaining: remaining + additionalSeconds)
        }
    }

    private func proceedAfterSet(exerciseIndex: Int, nextSet: Int, totalSets: Int) {
        if nextSet < totalSets {
            phase = .active(exerciseIndex: exerciseIndex, setIndex: nextSet)
        } else {
            completeExercise(exerciseIndex)
        }
    }

    // MARK: - AMRAP / For Time

    func incrementAMRAPRound() {
        amrapRounds += 1
        if case .amrapRunning(let ei, _, let rem) = phase {
            phase = .amrapRunning(exerciseIndex: ei, round: amrapRounds, secondsRemaining: rem)
        }
    }

    // MARK: - HR updates (called by WorkoutManager)

    func updateHR(_ bpm: Int) {
        let maxHR = HRZoneCalculator.storedMaxHR()
        currentHR = bpm
        currentHRZone = HRZoneCalculator.zone(for: bpm, maxHR: maxHR)
        peakHR = max(peakHR, bpm)
        avgHRSamples.append(bpm)

        checkZoneAlert()
    }

    private func checkZoneAlert() {
        guard alertCooldownRemaining <= 0 else {
            alertCooldownRemaining -= 1
            return
        }
        let (lower, upper) = currentPrescribedZoneRange()
        guard let lower, let upper else {
            isOutOfZone = false
            hrOutOfZoneSeconds = 0
            return
        }
        let inZone = (currentHRZone >= lower && currentHRZone <= upper)
        if inZone {
            hrOutOfZoneSeconds = 0
            isOutOfZone = false
        } else {
            hrOutOfZoneSeconds += 3   // HR samples arrive ~every 3s
            if hrOutOfZoneSeconds >= 30 {
                isOutOfZone = true
                triggerZoneAlert()
                hrOutOfZoneSeconds = 0
                alertCooldownRemaining = 20   // ~60s at 3s/sample
            }
        }
    }

    private func triggerZoneAlert() {
        WKInterfaceDevice.current().play(.notification)
    }

    private func currentPrescribedZoneRange() -> (Int?, Int?) {
        guard let session else { return (nil, nil) }
        let idx: Int
        switch phase {
        case .timedWork(let i, _):    idx = i
        case .active(let i, _):       idx = i
        default:                      return (nil, nil)
        }
        guard let ex = session.exercises[safe: idx] else { return (nil, nil) }
        return (ex.prescribedZoneLower, ex.prescribedZoneUpper)
    }

    // MARK: - Timers

    private func startElapsedTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsedSeconds += 1
                self.tickPhase()
            }
    }

    private func tickPhase() {
        switch phase {
        case .timedWork(let ei, let elapsed):
            phase = .timedWork(exerciseIndex: ei, secondsElapsed: elapsed + 1)

        case .amrapRunning(let ei, let rounds, let remaining):
            if remaining <= 1 {
                WKInterfaceDevice.current().play(.success)
                completeExercise(ei)
            } else {
                phase = .amrapRunning(exerciseIndex: ei, round: rounds, secondsRemaining: remaining - 1)
            }

        case .forTimeRunning(let ei, let elapsed):
            phase = .forTimeRunning(exerciseIndex: ei, secondsElapsed: elapsed + 1)

        default:
            break
        }
    }

    private func startRestCountdown(exerciseIndex: Int, completedSet: Int, from seconds: Int, totalSets: Int, nextSet: Int) {
        // Rest countdown is driven by tickPhase via the main timer; we just update the phase each second.
        // Override tickPhase for resting:
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsedSeconds += 1
                if case .resting(let ei, let cs, let remaining) = self.phase {
                    let next = remaining - 1
                    if next <= 0 {
                        WKInterfaceDevice.current().play(.start)
                        self.proceedAfterSet(exerciseIndex: ei, nextSet: nextSet, totalSets: totalSets)
                        self.startElapsedTimer()   // restore the normal elapsed timer
                    } else {
                        // Haptic cues
                        if next == 30 { WKInterfaceDevice.current().play(.notification) }
                        if next == 10 { WKInterfaceDevice.current().play(.directionUp) }
                        if next == 5  { WKInterfaceDevice.current().play(.click) }
                        self.phase = .resting(exerciseIndex: ei, completedSet: cs, secondsRemaining: next)
                    }
                }
            }
    }

    private func startEMOMCycle(exerciseIndex: Int, round: Int) {
        guard let session else { return }
        let ex = session.exercises[exerciseIndex]
        let workSec  = emomWorkSeconds(ex)
        let restSec  = emomRestSeconds(ex)
        let totalRounds = ex.targetRounds ?? 8

        timer?.cancel()
        var workRemaining = workSec
        var restRemaining = restSec
        var currentRound  = round
        var isWork        = true

        WKInterfaceDevice.current().play(.start)

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsedSeconds += 1

                if isWork {
                    workRemaining -= 1
                    self.phase = .emomInterval(exerciseIndex: exerciseIndex, round: currentRound, isWork: true, remaining: workRemaining)
                    if workRemaining <= 0 {
                        if restSec > 0 {
                            isWork = false
                            restRemaining = restSec
                            WKInterfaceDevice.current().play(.stop)
                        } else {
                            // No rest — go straight to next round
                            currentRound += 1
                            workRemaining = workSec
                            WKInterfaceDevice.current().play(.start)
                            if currentRound > totalRounds {
                                self.completeExercise(exerciseIndex)
                            }
                        }
                    }
                } else {
                    restRemaining -= 1
                    self.phase = .emomInterval(exerciseIndex: exerciseIndex, round: currentRound, isWork: false, remaining: restRemaining)
                    if restRemaining <= 0 {
                        currentRound += 1
                        if currentRound > totalRounds {
                            self.completeExercise(exerciseIndex)
                        } else {
                            isWork = true
                            workRemaining = workSec
                            WKInterfaceDevice.current().play(.start)
                        }
                    }
                }
            }
    }

    // MARK: - EMOM format parsing

    private func emomWorkSeconds(_ ex: WatchExercise) -> Int {
        if let fmt = ex.emomFormat, let (_, w, _) = parseEMOMFormat(fmt) { return w }
        // Tabata default: 20s on
        return 20
    }

    private func emomRestSeconds(_ ex: WatchExercise) -> Int {
        if let fmt = ex.emomFormat, let (_, _, r) = parseEMOMFormat(fmt) { return r }
        // Tabata default: 10s rest
        return 10
    }

    /// Parses "8×20/10" or "Tabata 8×20/10" → (rounds, workSec, restSec)
    private func parseEMOMFormat(_ format: String) -> (Int, Int, Int)? {
        let pattern = /(\d+)\s*[×x]\s*(\d+)\s*\/\s*(\d+)/
        guard let match = try? pattern.firstMatch(in: format) else { return nil }
        guard let r = Int(match.output.1),
              let w = Int(match.output.2),
              let rest = Int(match.output.3) else { return nil }
        return (r, w, rest)
    }

    // MARK: - Computed summary

    var avgHR: Int? {
        guard !avgHRSamples.isEmpty else { return nil }
        return avgHRSamples.reduce(0, +) / avgHRSamples.count
    }

    var durationMinutes: Int {
        guard let start = startDate else { return 0 }
        return Int(Date().timeIntervalSince(start) / 60)
    }

    // MARK: - Persistence (survive mid-workout app exit)

    func persist() {
        // We persist a lightweight snapshot — enough to restore UI on re-launch.
        // WorkoutManager restores the HKWorkoutSession separately.
        let snap = WorkoutSnapshot(
            sessionId:            session?.sessionId,
            phase:                phase,
            elapsedSeconds:       elapsedSeconds,
            completedExerciseIds: Array(completedExerciseIds),
            amrapRounds:          amrapRounds,
            startDate:            startDate
        )
        UserDefaults.standard.set(try? JSONEncoder().encode(snap), forKey: persistKey)
    }

    func restoreIfNeeded() {
        guard let data   = UserDefaults.standard.data(forKey: persistKey),
              let snap   = try? JSONDecoder().decode(WorkoutSnapshot.self, from: data),
              let sessId = snap.sessionId else { return }
        // Only restore if we have a cached session matching the persisted ID
        guard let cached = loadCachedSessions()?.first(where: { $0.sessionId == sessId }) else { return }
        session               = cached
        phase                 = snap.phase
        elapsedSeconds        = snap.elapsedSeconds
        completedExerciseIds  = Set(snap.completedExerciseIds)
        amrapRounds           = snap.amrapRounds
        startDate             = snap.startDate
        // Resume the elapsed timer (WorkoutManager will re-attach to the HKWorkoutSession)
        startElapsedTimer()
    }

    private func loadCachedSessions() -> [WatchSession]? {
        guard let data = UserDefaults.standard.data(forKey: "watchTodaySessions") else { return nil }
        return try? JSONDecoder().decode([WatchSession].self, from: data)
    }
}

// MARK: - Snapshot for persistence

private struct WorkoutSnapshot: Codable {
    let sessionId: String?
    let phase: WorkoutPhase
    let elapsedSeconds: Int
    let completedExerciseIds: [String]
    let amrapRounds: Int
    let startDate: Date?
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
