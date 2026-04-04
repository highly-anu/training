import Combine
import CoreLocation
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

    // GPS
    private var locationManager: CLLocationManager?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var gpsPoints: [(location: CLLocation, bpm: Int)] = []

    // Timestamped HR samples for per-exercise correlation and rich HR timeline
    private var hrTimestampedSamples: [(t: Int, b: Int)] = []

    // Session start time (used to compute integer offsets for samples)
    private var workoutStartedAt: Date?

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKSeriesType.workoutRoute(),
        ]
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
        ]
        try? await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Start workout

    func startWorkout(session: WatchSession, maxHR: Int = 190) async {
        activeSession = session
        self.maxHR = maxHR
        workoutStartedAt = Date()
        gpsPoints = []
        hrTimestampedSamples = []
        sessionState.startSession()
        startElapsedTimer()
        isWorkoutActive = true

        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = hkActivityType(for: session.modalityId)
        config.locationType = hkLocationType(for: session.modalityId)

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

            // Route builder for GPS persistence in HealthKit store
            if config.locationType == .outdoor {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
            }

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
        var completedWorkout: HKWorkout?
        if let builder = workoutBuilder {
            try? await builder.endCollection(at: Date())
            completedWorkout = try? await builder.finishWorkout()
        }
        // Commit GPS route to HealthKit store
        if let route = routeBuilder, let workout = completedWorkout {
            _ = try? await route.finishRoute(with: workout, metadata: nil)
        } else {
            routeBuilder?.discard()
        }
        locationManager?.stopUpdatingLocation()
        workoutSession = nil
        workoutBuilder = nil
        routeBuilder = nil
        isWorkoutActive = false
    }

    // MARK: - Summary

    func buildSummary(startedAt: Date) -> WatchWorkoutSummary? {
        guard let session = activeSession else { return nil }
        let iso = ISO8601DateFormatter()
        let now = Date()
        let df  = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        // Subsample HR: keep ≤ 600 points
        let hrRaw = hrTimestampedSamples
        let hrStride = max(1, hrRaw.count / 600)
        let hrSubsampled = stride(from: 0, to: hrRaw.count, by: hrStride).map { hrRaw[$0] }
        let hrPoints = hrSubsampled.isEmpty ? nil : hrSubsampled.map { HRSamplePoint(t: $0.t, b: $0.b) }

        // Subsample GPS: already distance-filtered; cap at 400 points
        let gpsRaw = gpsPoints
        let gpsStride = max(1, gpsRaw.count / 400)
        let gpsSubsampled = stride(from: 0, to: gpsRaw.count, by: gpsStride).map { gpsRaw[$0] }
        let gpsTrackPoints: [GPSTrackPoint]? = gpsSubsampled.isEmpty ? nil : gpsSubsampled.map { point in
            let tOffset = Int(point.location.timestamp.timeIntervalSince(startedAt))
            return GPSTrackPoint(
                lat: point.location.coordinate.latitude,
                lng: point.location.coordinate.longitude,
                alt: point.location.altitude > 0 ? point.location.altitude : nil,
                t: tOffset,
                b: point.bpm > 0 ? point.bpm : nil
            )
        }

        // Per-exercise timeline from set logs
        let exerciseTimeline: [ExerciseTimelineEntry]? = buildExerciseTimeline()

        // Pace: metres per second → seconds per km
        let dist = sessionState.distanceMeters
        let durationSecs = now.timeIntervalSince(startedAt)
        let paceSecsPerKm: Double? = dist > 100 ? (durationSecs / (dist / 1000.0)) : nil

        return WatchWorkoutSummary(
            sessionId:          session.sessionId,
            date:               df.string(from: startedAt),
            startedAt:          iso.string(from: startedAt),
            endedAt:            iso.string(from: now),
            durationMinutes:    max(1, Int(durationSecs / 60)),
            avgHR:              sessionState.avgHR > 0 ? sessionState.avgHR : nil,
            peakHR:             sessionState.peakHR > 0 ? sessionState.peakHR : nil,
            setLogs:            sessionState.setLogs,
            exercisesCompleted: sessionState.completedExerciseIds.count,
            source:             "apple_watch_live",
            hrSamples:          hrPoints,
            gpsTrack:           gpsTrackPoints,
            distanceMeters:     dist > 0 ? dist : nil,
            elevationGainMeters: sessionState.floorsAscended > 0 ? sessionState.floorsAscended * 3.0 : nil,
            cadenceAvg:         sessionState.currentCadence > 0 ? sessionState.currentCadence : nil,
            paceSecsPerKm:      paceSecsPerKm,
            exerciseTimeline:   exerciseTimeline
        )
    }

    private func buildExerciseTimeline() -> [ExerciseTimelineEntry]? {
        let logs = sessionState.setLogs
        guard !logs.isEmpty else { return nil }
        var entries: [ExerciseTimelineEntry] = []
        for (exerciseId, sets) in logs {
            let startOffsets = sets.compactMap { $0.startOffset }
            let endOffsets   = sets.compactMap { $0.endOffset }
            guard let start = startOffsets.min(), let end = endOffsets.max() else { continue }
            // Compute avg HR during this window from the timestamped HR samples
            let samples = hrTimestampedSamples.filter { $0.t >= start && $0.t <= end }
            let avgHR: Int? = samples.isEmpty ? nil : samples.reduce(0) { $0 + $1.b } / samples.count
            entries.append(ExerciseTimelineEntry(
                exerciseId: exerciseId,
                startOffset: start,
                endOffset: end,
                avgHRDuring: avgHR
            ))
        }
        return entries.isEmpty ? nil : entries
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

    private func hkLocationType(for modalityId: String) -> HKWorkoutSessionLocationType {
        switch modalityId {
        case "aerobic_base", "anaerobic_intervals", "durability": return .outdoor
        default: return .unknown
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
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .running else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Start GPS only for outdoor sessions
            if self.routeBuilder != nil {
                let mgr = CLLocationManager()
                mgr.delegate = self
                mgr.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                mgr.distanceFilter = 5
                mgr.startUpdatingLocation()
                self.locationManager = mgr
            }
        }
    }
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
        let startedAt = workoutStartedAt ?? Date()
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            let bpm = Int(stats.mostRecentQuantity()?.doubleValue(
                for: HKUnit.count().unitDivided(by: .minute())) ?? 0)
            guard bpm > 0 else { return }
            let tOffset = Int(Date().timeIntervalSince(startedAt))
            hrTimestampedSamples.append((t: tOffset, b: bpm))
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
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
             HKQuantityTypeIdentifier.distanceCycling.rawValue:
            let meters = stats.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            if meters > 0 { sessionState.updateDistance(meters) }
        case HKQuantityTypeIdentifier.runningSpeed.rawValue:
            let mps = stats.mostRecentQuantity()?.doubleValue(for: .meter().unitDivided(by: .second())) ?? 0
            if mps > 0 { sessionState.updateSpeed(mps) }
        default:
            break
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let currentBPM = self.sessionState.currentHR
            for location in locations {
                self.gpsPoints.append((location: location, bpm: currentBPM))
            }
            if let routeBuilder = self.routeBuilder {
                try? await routeBuilder.insertRouteData(locations)
            }
        }
    }
}
