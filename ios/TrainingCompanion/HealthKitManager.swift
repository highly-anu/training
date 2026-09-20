import CoreLocation
import Foundation
import HealthKit

struct SleepData {
    var totalMin: Int = 0
    var deepMin: Int = 0
    var remMin: Int = 0
    var lightMin: Int = 0
    var awakeMin: Int = 0
    var sleepStart: Date? = nil
    var sleepEnd: Date? = nil
}

struct DailyBiometrics {
    var restingHR: Double? = nil
    var hrv: Double? = nil          // RMSSD ms
    var spo2Avg: Double? = nil      // %
    var respiratoryRateAvg: Double? = nil  // breaths/min
}

final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
        HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
        HKObjectType.quantityType(forIdentifier: .vo2Max)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKSeriesType.workoutRoute(),
        HKObjectType.workoutType(),
    ]

    func requestPermissions() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Sleep

    func fetchSleepData(for date: Date) async -> SleepData {
        let calendar = Calendar.current
        // Sleep for "date" = previous evening 6pm → this morning noon
        let sleepWindowStart = calendar.date(
            bySettingHour: 18, minute: 0, second: 0,
            of: calendar.date(byAdding: .day, value: -1, to: date)!
        )!
        let sleepWindowEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!

        let predicate = HKQuery.predicateForSamples(
            withStart: sleepWindowStart, end: sleepWindowEnd
        )
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate, ascending: true
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                var data = SleepData()
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: data)
                    return
                }

                // Only use Apple Watch samples (source bundle contains "com.apple.health" or "com.apple.watch")
                let watchSamples = samples.filter {
                    $0.sourceRevision.source.bundleIdentifier.contains("com.apple")
                }
                let relevant = watchSamples.isEmpty ? samples : watchSamples

                data.sleepStart = relevant.first?.startDate
                data.sleepEnd = relevant.last?.endDate

                for sample in relevant {
                    let minutes = Int(sample.endDate.timeIntervalSince(sample.startDate) / 60)
                    switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    case .asleepDeep:   data.deepMin  += minutes
                    case .asleepREM:    data.remMin   += minutes
                    case .asleepCore:   data.lightMin += minutes
                    case .awake:        data.awakeMin += minutes
                    case .inBed:        break // don't count inBed separately
                    default:            data.lightMin += minutes // legacy .asleep → light
                    }
                }
                data.totalMin = data.deepMin + data.remMin + data.lightMin

                continuation.resume(returning: data)
            }
            store.execute(query)
        }
    }

    // MARK: - Biometrics

    func fetchDailyBiometrics(for date: Date) async -> DailyBiometrics {
        async let restingHR = fetchLatestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), date: date)
        async let hrv = fetchLatestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), date: date)
        async let spo2 = fetchAverageQuantity(.oxygenSaturation, unit: .percent(), date: date)
        async let respRate = fetchAverageQuantity(.respiratoryRate, unit: .count().unitDivided(by: .minute()), date: date)

        let (rhr, hrvVal, spo2Val, respVal) = await (restingHR, hrv, spo2, respRate)

        return DailyBiometrics(
            restingHR: rhr,
            hrv: hrvVal,                          // already ms — queried with .secondUnit(with: .milli)
            spo2Avg: spo2Val.map { $0 * 100 },    // SDK returns 0–1; convert to %
            respiratoryRateAvg: respVal
        )
    }

    private func fetchLatestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, date: Date) async -> Double? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.quantityType(forIdentifier: identifier)!,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - VO2max

    func fetchVO2max() async -> Double? {
        let type = HKObjectType.quantityType(forIdentifier: .vo2Max)!
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: HKUnit(from: "ml/kg/min"))
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Step count

    func fetchStepCount(for date: Date) async -> Double? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let type = HKObjectType.quantityType(forIdentifier: .stepCount)!
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Workout route (GPS)

    /// Fetches the GPS route for a completed HKWorkout. Returns an empty array for indoor
    /// sessions or when the route has not yet synced from the Watch.
    func fetchWorkoutRoute(for workout: HKWorkout) async -> [CLLocation] {
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKSeriesType.workoutRoute(),
                predicate: routePredicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, _, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        guard let route = routes.first else { return [] }

        var locations: [CLLocation] = []
        return await withCheckedContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, routeLocations, done, _ in
                if let routeLocations { locations.append(contentsOf: routeLocations) }
                if done { continuation.resume(returning: locations) }
            }
            store.execute(query)
        }
    }

    /// Finds the HKWorkout closest to the given start time (within ±60 seconds).
    func findHKWorkout(near startDate: Date) async -> HKWorkout? {
        let window = 60.0
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate.addingTimeInterval(-window),
            end: startDate.addingTimeInterval(window)
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate, limit: 1, sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(query)
        }
    }

    // MARK: - Workout import (Garmin via Apple Health)
    //
    // Garmin Connect writes the activities it syncs from the watch into Apple
    // Health. Reading them here is what makes automatic import work without a
    // Garmin Developer Program approval — and on a phone that already has both
    // apps, it is the shortest path the data can take.

    private static let anchorKey = "hkWorkoutAnchor"
    /// On a first run there is no anchor, so HealthKit returns the entire
    /// workout history. Import only the recent tail of that first flood; the
    /// anchor is still saved, so it happens exactly once.
    private static let firstRunLookbackDays = 90

    private var storedAnchor: HKQueryAnchor? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.anchorKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        set {
            guard let anchor = newValue,
                  let data = try? NSKeyedArchiver.archivedData(
                      withRootObject: anchor, requiringSecureCoding: true)
            else { return }
            UserDefaults.standard.set(data, forKey: Self.anchorKey)
        }
    }

    /// Forget the sync position, so the next pass re-examines recent history.
    /// Dedup on the server makes a replay harmless.
    func resetWorkoutAnchor() {
        UserDefaults.standard.removeObject(forKey: Self.anchorKey)
    }

    /// Workouts added since the last pass that we want to import.
    func importableWorkouts() async -> [HKWorkout] {
        let hadAnchor = storedAnchor != nil

        let (workouts, newAnchor): ([HKWorkout], HKQueryAnchor?) = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: nil,
                anchor: storedAnchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, anchor, _ in
                continuation.resume(returning: ((samples as? [HKWorkout]) ?? [], anchor))
            }
            store.execute(query)
        }

        // Save the anchor even when we discard most of this batch, so the
        // first-run flood is bounded to a single pass.
        if let newAnchor { storedAnchor = newAnchor }

        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.firstRunLookbackDays, to: Date())!

        return workouts.filter { workout in
            guard HKWorkoutMapping.shouldImport(workout) else {
                AppLogger.shared.logFromBackground(
                    "workout-import: skipping \(workout.sourceRevision.source.bundleIdentifier)")
                return false
            }
            if !hadAnchor && workout.startDate < cutoff { return false }
            return true
        }
    }

    /// Per-sample heart rate recorded during a workout.
    func fetchHRSamples(for workout: HKWorkout) async -> [HRSample] {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }

        return samples.map {
            HRSample(timestamp: WorkoutID.isoFormatter.string(from: $0.startDate),
                     bpm: Int($0.quantity.doubleValue(for: unit).rounded()))
        }
    }

    /// Convert an HKWorkout into the shape the backend stores.
    ///
    /// A note on ids: these will NOT match the ids the web app's Apple Health
    /// XML importer produces for the same workout. That path hashes the raw
    /// `HKWorkoutActivityTypeRunning` spelling with a differently formatted
    /// start time, and mimicking it here would be brittle for no gain — the
    /// server's cross-source dedup collapses the two anyway. Don't "fix" this.
    func toImportedWorkout(_ workout: HKWorkout) async -> ImportedWorkout {
        let source = HKWorkoutMapping.sourceTag(for: workout)
        let activityType = HKWorkoutMapping.displayName(for: workout.workoutActivityType)
        let durationMin = workout.duration / 60.0
        let startStr = WorkoutID.isoFormatter.string(from: workout.startDate)

        let hrSamples = await fetchHRSamples(for: workout)
        let locations = await fetchWorkoutRoute(for: workout)

        let gpsTrack: [GPSPoint]? = locations.isEmpty ? nil : locations.map { loc in
            GPSPoint(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                altitude: loc.altitude,
                timestamp: WorkoutID.isoFormatter.string(from: loc.timestamp),
                bpm: nil,
                speed: loc.speed >= 0 ? loc.speed : nil
            )
        }

        let hrValues = hrSamples.map(\.bpm)
        let distanceMeters = workout.statistics(
            for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter)
            ?? workout.statistics(for: HKQuantityType(.distanceCycling))?
                .sumQuantity()?.doubleValue(for: .meter)
        let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie)

        return ImportedWorkout(
            id: WorkoutID.deterministic(source: source,
                                       startTime: startStr,
                                       activityType: activityType,
                                       durationMinutes: Int(durationMin)),
            source: source,
            date: WorkoutID.dateFormatter.string(from: workout.startDate),
            startTime: startStr,
            durationMinutes: durationMin.rounded(),
            activityType: activityType,
            inferredModalityId: HKWorkoutMapping.modalityId(for: workout.workoutActivityType),
            heartRate: WorkoutHRData(
                avg: hrValues.isEmpty ? nil : hrValues.reduce(0, +) / hrValues.count,
                max: hrValues.max(),
                samples: hrSamples
            ),
            calories: calories,
            distance: distanceMeters.map {
                WorkoutDistance(value: (($0 / 1000) * 1000).rounded() / 1000, unit: "km")
            },
            gpsTrack: gpsTrack,
            // Left to the server, which recomputes gain/loss from the track's
            // altitudes whenever loss is zero (see POST /api/health/workouts).
            elevation: nil
        )
    }

    // MARK: - Background delivery

    /// Ask HealthKit to wake the app when a workout is written.
    ///
    /// Needs the `com.apple.developer.healthkit.background-delivery`
    /// entitlement; without it this throws and the app falls back to the
    /// existing ~6h BGAppRefreshTask, which is why the caller only logs.
    func enableWorkoutBackgroundDelivery() async throws {
        try await store.enableBackgroundDelivery(
            for: HKObjectType.workoutType(), frequency: .immediate)
    }

    /// Observer queries must be re-registered on every launch, and the
    /// completion handler MUST be called or iOS throttles delivery.
    func startWorkoutObserver(onChange: @escaping () async -> Void) {
        let query = HKObserverQuery(
            sampleType: HKObjectType.workoutType(), predicate: nil
        ) { _, completionHandler, error in
            if let error {
                AppLogger.shared.logFromBackground(
                    "workout-import: observer error \(error.localizedDescription)")
                completionHandler()
                return
            }
            Task {
                await onChange()
                completionHandler()
            }
        }
        store.execute(query)
    }

    private func fetchAverageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, date: Date) async -> Double? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKObjectType.quantityType(forIdentifier: identifier)!,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                let value = statistics?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
