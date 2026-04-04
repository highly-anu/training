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
