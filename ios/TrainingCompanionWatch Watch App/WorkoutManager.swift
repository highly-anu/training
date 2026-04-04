import Combine
import Foundation
import HealthKit
import WatchKit

@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    let sessionState = WorkoutSessionState()

    @Published var isWorkoutActive = false

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var activeSession: WatchSession?
    private var maxHR: Int = 190

    private var elapsedTimer: Timer?

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        try? await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Start workout

    func startWorkout(session: WatchSession, maxHR: Int = 190) async {
        activeSession = session
        self.maxHR = maxHR
        sessionState.startSession()
        startElapsedTimer()
        isWorkoutActive = true

        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = hkActivityType(for: session.modalityId)
        config.locationType = .unknown

        do {
            let hkSession = try HKWorkoutSession(healthStore: healthStore,
                                                  configuration: config)
            let builder = hkSession.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                          workoutConfiguration: config)
            hkSession.delegate = self
            builder.delegate = self
            workoutSession = hkSession
            workoutBuilder = builder

            try await builder.beginCollection(at: Date())
            hkSession.startActivity(with: Date())
        } catch {
            // Simulator or capability issue — continue without HK session
        }
    }

    // MARK: - End workout

    func endWorkout() async {
        stopElapsedTimer()
        workoutSession?.end()
        if let builder = workoutBuilder {
            try? await builder.endCollection(at: Date())
            try? await builder.finishWorkout()
        }
        workoutSession = nil
        workoutBuilder = nil
        isWorkoutActive = false
    }

    // MARK: - Summary

    func buildSummary(startedAt: Date) -> WatchWorkoutSummary? {
        guard let session = activeSession else { return nil }
        let iso = ISO8601DateFormatter()
        let now = Date()
        let df  = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return WatchWorkoutSummary(
            sessionId:          session.sessionId,
            date:               df.string(from: startedAt),
            startedAt:          iso.string(from: startedAt),
            endedAt:            iso.string(from: now),
            durationMinutes:    max(1, Int(now.timeIntervalSince(startedAt) / 60)),
            avgHR:              sessionState.avgHR > 0 ? sessionState.avgHR : nil,
            peakHR:             sessionState.peakHR > 0 ? sessionState.peakHR : nil,
            setLogs:            sessionState.setLogs,
            exercisesCompleted: sessionState.completedExerciseIds.count,
            source:             "apple_watch_live"
        )
    }

    // MARK: - Helpers

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sessionState.tickElapsed() }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func hkActivityType(for modalityId: String) -> HKWorkoutActivityType {
        switch modalityId {
        case "aerobic_base", "anaerobic_intervals": return .running
        case "durability":   return .hiking
        case "movement_skill", "mobility": return .flexibility
        case "kettlebell":   return .functionalStrengthTraining
        case "mixed_modal_conditioning": return .crossTraining
        default:             return .traditionalStrengthTraining
        }
    }

    // HR zone lookup from current session exercise
    private func zoneBounds(for exerciseIndex: Int) -> (Int?, Int?) {
        guard let session = activeSession,
              exerciseIndex < session.exercises.count else { return (nil, nil) }
        let ex = session.exercises[exerciseIndex]
        return (ex.prescribedZoneLower, ex.prescribedZoneUpper)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {}
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let qty = type as? HKQuantityType else { continue }
            let stats = workoutBuilder.statistics(for: qty)
            Task { @MainActor [weak self] in self?.process(stats, for: qty) }
        }
    }

    @MainActor
    private func process(_ stats: HKStatistics?, for type: HKQuantityType) {
        guard let stats else { return }
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            let bpm = Int(stats.mostRecentQuantity()?.doubleValue(
                for: HKUnit.count().unitDivided(by: .minute())) ?? 0)
            let (lower, upper): (Int?, Int?)
            if case let .active(ei, _) = sessionState.phase {
                (lower, upper) = zoneBounds(for: ei)
            } else {
                (lower, upper) = (nil, nil)
            }
            sessionState.updateHR(bpm, maxHR: maxHR,
                                   prescribedLower: lower, prescribedUpper: upper)
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            let cal = Int(stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            sessionState.updateCalories(cal)
        default:
            break
        }
    }
}
