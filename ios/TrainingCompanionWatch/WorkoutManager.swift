import Foundation
import HealthKit
import WatchKit
import WatchConnectivity

/// Owns the HKWorkoutSession + HKLiveWorkoutBuilder.
/// Streams live HR to WorkoutSessionState and writes the completed workout to HealthKit.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    @Published var isSessionActive: Bool = false
    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    // Weak reference to state — WorkoutManager feeds HR into it.
    weak var sessionState: WorkoutSessionState?

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
    ]
    private let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
    ]

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
        } catch {
            // Authorization errors are non-fatal — HR simply won't stream.
        }
    }

    // MARK: - Start / Pause / End

    func startWorkout(activityType: HKWorkoutActivityType = .traditionalStrengthTraining) async {
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder

            session.startActivity(with: Date())
            try await builder.beginCollection(at: Date())
            isSessionActive = true
        } catch {
            isSessionActive = false
        }
    }

    func pauseWorkout() {
        workoutSession?.pause()
    }

    func resumeWorkout() {
        workoutSession?.resume()
    }

    func endWorkout() async {
        workoutSession?.end()
        do {
            try await workoutBuilder?.endCollection(at: Date())
            _ = try await workoutBuilder?.finishWorkout()
        } catch {
            // Workout is still saved to HealthKit even if this throws in some edge cases.
        }
        isSessionActive = false

        // Send summary to iPhone
        sendWorkoutSummary()
    }

    // MARK: - Workout activity type from modality

    static func activityType(for modalityId: String) -> HKWorkoutActivityType {
        switch modalityId {
        case "max_strength", "relative_strength", "strength_endurance":
            return .traditionalStrengthTraining
        case "power":
            return .functionalStrengthTraining
        case "aerobic_base":
            return .running         // fallback; user may be running or rowing
        case "anaerobic_intervals", "mixed_modal_conditioning":
            return .highIntensityIntervalTraining
        case "mobility", "movement_skill":
            return .yoga
        case "durability":
            return .walking
        default:
            return .other
        }
    }

    // MARK: - Post-workout summary → Watch → iPhone

    private func sendWorkoutSummary() {
        guard let state = sessionState,
              let session = state.session else { return }

        let startedAt = state.startDate ?? Date()
        let endedAt   = Date()
        let iso       = ISO8601DateFormatter()
        let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

        let summary = WatchWorkoutSummary(
            sessionId:           session.sessionId,
            date:                dayFmt.string(from: startedAt),
            startedAt:           iso.string(from: startedAt),
            endedAt:             iso.string(from: endedAt),
            durationMinutes:     state.durationMinutes,
            avgHR:               state.avgHR,
            peakHR:              state.peakHR > 0 ? state.peakHR : nil,
            setLogs:             state.setLogs,
            exercisesCompleted:  state.completedExerciseIds.count,
            source:              "apple_watch_live"
        )

        guard let data    = try? JSONEncoder().encode(summary),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        WCSession.default.transferUserInfo(payload)
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            self.isSessionActive = (toState == .running)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {}
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  quantityType == HKObjectType.quantityType(forIdentifier: .heartRate) else { continue }

            let stats = workoutBuilder.statistics(for: quantityType)
            guard let bpm = stats?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) else { continue }

            Task { @MainActor in
                self.sessionState?.updateHR(Int(bpm))
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
