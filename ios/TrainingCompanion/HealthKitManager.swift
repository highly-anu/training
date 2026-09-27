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
    /// Bumped when a change to the import filter means the anchor is hiding
    /// workouts an earlier build refused. Without this, widening the filter
    /// looks like it did nothing: the anchor has already moved past every
    /// workout the old rule discarded, and only the user knows to press
    /// "Re-import recent workouts".
    private static let anchorResetKey = "hkWorkoutAnchorReset.v5-hr-timerange"
    /// On a first run there is no anchor, so HealthKit returns the entire
    /// workout history. Import only the recent tail of that first flood.
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

    /// What one pass over the workout store saw — not just what survived.
    ///
    /// "Nothing was imported" has three very different causes (no read
    /// permission, a filter that rejected everything, an anchor already past
    /// the workouts) and they are indistinguishable from the kept list alone.
    /// Every field here exists to tell them apart from the in-app log.
    struct WorkoutImportScan {
        var kept: [HKWorkout] = []
        var rawCount: Int = 0
        var hadAnchor: Bool = false
        var queryError: String? = nil
        /// Every bundle id in the raw batch, with how many it wrote.
        var bundleCounts: [String: Int] = [:]
        var skippedByBundle: Int = 0
        var skippedByCutoff: Int = 0
        var newAnchor: HKQueryAnchor? = nil
    }

    /// Workouts added since the last pass that we want to import.
    ///
    /// Does NOT move the anchor — the caller commits it with
    /// `commitWorkoutAnchor(_:)` once it knows the batch was handled. Advancing
    /// unconditionally is what made a filter mistake permanent: the workouts it
    /// refused were never offered again.
    func scanImportableWorkouts() async -> WorkoutImportScan {
        if !UserDefaults.standard.bool(forKey: Self.anchorResetKey) {
            resetWorkoutAnchor()
            UserDefaults.standard.set(true, forKey: Self.anchorResetKey)
            AppLogger.shared.logFromBackground(
                "workout-import: anchor reset once for the widened source filter")
        }

        var scan = WorkoutImportScan()
        scan.hadAnchor = storedAnchor != nil

        let (workouts, newAnchor, error): ([HKWorkout], HKQueryAnchor?, Error?) =
            await withCheckedContinuation { continuation in
                let query = HKAnchoredObjectQuery(
                    type: HKObjectType.workoutType(),
                    predicate: nil,
                    anchor: storedAnchor,
                    limit: HKObjectQueryNoLimit
                ) { _, samples, _, anchor, error in
                    continuation.resume(returning: ((samples as? [HKWorkout]) ?? [], anchor, error))
                }
                store.execute(query)
            }

        scan.rawCount = workouts.count
        scan.newAnchor = newAnchor
        // A denied workout read surfaces here about half the time and as silent
        // emptiness the rest, so keeping it turns a guess into a fact when we
        // are lucky and costs nothing when we are not.
        scan.queryError = error?.localizedDescription

        for workout in workouts {
            let bundle = workout.sourceRevision.source.bundleIdentifier
            scan.bundleCounts[bundle, default: 0] += 1
        }

        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.firstRunLookbackDays, to: Date())!

        scan.kept = workouts.filter { workout in
            guard HKWorkoutMapping.shouldImport(workout) else {
                scan.skippedByBundle += 1
                return false
            }
            if !scan.hadAnchor && workout.startDate < cutoff {
                scan.skippedByCutoff += 1
                return false
            }
            return true
        }

        return scan
    }

    /// Move the sync position forward, but only when doing so cannot lose a
    /// workout a later build would want.
    ///
    /// Three cases are held back:
    ///
    /// - the query errored;
    /// - the batch was discarded by the *source* filter — exactly the case a
    ///   widened filter must be able to see again;
    /// - **the batch was empty.** An empty read is ambiguous: it means "no new
    ///   workouts" or "not authorised to see them", and the two are
    ///   indistinguishable by design. Observed in the wild: on a fresh install
    ///   the authorisation sheet is still up when the first sync runs, reads
    ///   come back empty, and an anchor committed then represents "you have
    ///   seen everything" — parking permanently past 95 real workouts. There is
    ///   nothing to advance past in an empty batch, so committing one can only
    ///   ever lose data.
    ///
    /// A batch dropped only by the first-run cutoff is safe to commit: those
    /// workouts are old and we never want them, and the cutoff bounds the
    /// first-run flood on its own.
    func commitWorkoutAnchor(_ scan: WorkoutImportScan) {
        guard let anchor = scan.newAnchor, scan.queryError == nil else { return }
        guard scan.rawCount > 0 else { return }
        if scan.kept.isEmpty && scan.skippedByBundle > 0 { return }
        storedAnchor = anchor
    }

    // MARK: - Access diagnosis

    /// Read the workout store directly, ignoring the anchor and the import
    /// filter, to answer "is anything there, and who wrote it?".
    ///
    /// Unanchored on purpose: it must be runnable repeatedly without consuming
    /// the batch the importer is waiting for, and unfiltered on purpose, so a
    /// source the importer excludes is still visible here.
    func diagnoseWorkoutAccess(days: Int = 90) async -> WorkoutAccessDiagnosis {
        var result = WorkoutAccessDiagnosis()
        result.days = days
        result.healthDataAvailable = HKHealthStore.isHealthDataAvailable()
        guard result.healthDataAvailable else { return result }

        let status = try? await store.statusForAuthorizationRequest(
            toShare: [], read: [HKObjectType.workoutType(), HKSeriesType.workoutRoute()])
        result.needsAuthorizationPrompt = (status == .shouldRequest)

        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let (workouts, error): ([HKWorkout], Error?) = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date()),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                   ascending: false)]
            ) { _, samples, error in
                continuation.resume(returning: ((samples as? [HKWorkout]) ?? [], error))
            }
            store.execute(query)
        }

        result.queryError = error?.localizedDescription
        result.total = workouts.count

        let recentCutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        result.recent = workouts.filter { $0.startDate >= recentCutoff }.count

        var grouped: [String: [HKWorkout]] = [:]
        for workout in workouts {
            grouped[workout.sourceRevision.source.bundleIdentifier, default: []].append(workout)
        }
        result.sources = grouped
            .map { bundle, items in
                WorkoutSourceCount(
                    bundle: bundle,
                    count: items.count,
                    latest: items.map(\.startDate).max(),
                    disposition: Self.disposition(forBundle: bundle))
            }
            .sorted { $0.count > $1.count }

        return result
    }

    /// What `shouldImport` would decide for this source, phrased for a human.
    static func disposition(forBundle bundle: String) -> String {
        switch HKWorkoutMapping.origin(ofBundle: bundle) {
        case .garmin:     return "import"
        case .apple:      return "skip: already ours"
        case .thirdParty: return "import"
        }
    }

    /// How a workout's heart-rate series was found — reported in the import
    /// summary, because which strategy worked says which app wrote what.
    enum HRSource { case associated, timeRange, none }

    /// Per-sample heart rate recorded during a workout.
    ///
    /// Two strategies, because only the first works for workouts we did not
    /// write ourselves:
    ///
    /// 1. **Associated samples** — `predicateForObjects(from:)` matches only
    ///    samples attached to that `HKWorkout`. Apple's Fitness app and our own
    ///    watch app attach theirs.
    /// 2. **The session's time range** — Garmin Connect writes the workout and
    ///    the heart-rate samples as *unrelated* objects, so strategy 1 finds
    ///    nothing for a Garmin ride even when Health holds a full series for
    ///    exactly those minutes. That is why Garmin workouts imported with no
    ///    HR and therefore no load estimate.
    func fetchHRSamples(for workout: HKWorkout) async -> (samples: [HRSample], source: HRSource) {
        let associated = await hrSamples(matching: HKQuery.predicateForObjects(from: workout))
        if !associated.isEmpty { return (associated, .associated) }

        let inWindow = await hrSamples(matching: HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate))
        return inWindow.isEmpty ? ([], .none) : (inWindow, .timeRange)
    }

    private func hrSamples(matching predicate: NSPredicate) async -> [HRSample] {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
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

        // A time-range query can return two sources' samples for the same
        // second — a watch on the wrist while the bike computer also records.
        // Keep one reading per second so the zone maths sees a clean series.
        var seen = Set<Int>()
        var result: [HRSample] = []
        for sample in samples {
            let second = Int(sample.startDate.timeIntervalSince1970.rounded())
            guard seen.insert(second).inserted else { continue }
            result.append(HRSample(
                timestamp: WorkoutID.isoFormatter.string(from: sample.startDate),
                bpm: Int(sample.quantity.doubleValue(for: unit).rounded())))
        }
        return result
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
        let endStr = WorkoutID.isoFormatter.string(from: workout.endDate)

        let hr = await fetchHRSamples(for: workout)
        let hrSamples = hr.samples
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
        // Last resort for avg/max: the workout's own statistics. A summary-only
        // writer can populate these with no samples at all, and an average is
        // enough for the zone estimate that the load number is built on.
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrStats = workout.statistics(for: HKQuantityType(.heartRate))
        let statsAvg = hrStats?.averageQuantity()?.doubleValue(for: bpm)
        let statsMax = hrStats?.maximumQuantity()?.doubleValue(for: bpm)
        let distanceMeters = workout.statistics(
            for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())
            ?? workout.statistics(for: HKQuantityType(.distanceCycling))?
                .sumQuantity()?.doubleValue(for: .meter())
        let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        return ImportedWorkout(
            id: WorkoutID.deterministic(source: source,
                                       startTime: startStr,
                                       activityType: activityType,
                                       durationMinutes: Int(durationMin)),
            source: source,
            date: WorkoutID.dateFormatter.string(from: workout.startDate),
            startTime: startStr,
            endTime: endStr,
            durationMinutes: durationMin.rounded(),
            activityType: activityType,
            inferredModalityId: HKWorkoutMapping.modalityId(for: workout.workoutActivityType),
            heartRate: WorkoutHRData(
                avg: hrValues.isEmpty
                    ? statsAvg.map { Int($0.rounded()) }
                    : hrValues.reduce(0, +) / hrValues.count,
                max: hrValues.max() ?? statsMax.map { Int($0.rounded()) },
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

/// One writer of workouts in Apple Health, and what the importer would do with
/// what it wrote.
struct WorkoutSourceCount: Identifiable {
    let bundle: String
    let count: Int
    let latest: Date?
    let disposition: String
    var id: String { bundle }
}

/// What the workout store actually holds, reported without the import filter
/// applied — so a source the importer excludes is still visible here.
struct WorkoutAccessDiagnosis {
    var healthDataAvailable = true
    /// `true` when we have never completed a prompt covering workouts —
    /// the strongest signal available that the read was never granted,
    /// since Apple deliberately hides read denial.
    var needsAuthorizationPrompt = false
    var days = 0
    var total = 0
    var recent = 0            // last 14 days
    var sources: [WorkoutSourceCount] = []
    var queryError: String? = nil

    var summaryLine: String {
        if !healthDataAvailable { return "Health data is unavailable on this device" }
        if let queryError { return "Health query failed — \(queryError)" }
        if total == 0 {
            return needsAuthorizationPrompt
                ? "No workouts readable — access was never granted"
                : "No workouts in Apple Health in the last \(days) days"
        }
        return "\(total) workout(s) in \(days) days, \(recent) in the last 14"
    }
}
