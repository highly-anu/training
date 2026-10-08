import Foundation
import Combine

@MainActor
final class SyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    @Published var lastError: String? = nil

    // Per-category tracking (persisted in UserDefaults)
    @Published var lastBioSyncDate: Date? = UserDefaults.standard.object(forKey: "lastBioSyncDate") as? Date
    @Published var lastBioPushedCount: Int = UserDefaults.standard.integer(forKey: "lastBioPushedCount")
    @Published var lastProgramSyncDate: Date? = UserDefaults.standard.object(forKey: "lastProgramSyncDate") as? Date
    @Published var lastWorkoutSyncDate: Date? = UserDefaults.standard.object(forKey: "lastWorkoutSyncDate") as? Date
    @Published var lastWorkoutImportedCount: Int = UserDefaults.standard.integer(forKey: "lastWorkoutImportedCount")

    private var cancelled = false
    private let hk = HealthKitManager.shared
    private let iso = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var api: APIClient?
    private var watchSync: WatchSessionManager?
    /// Needed to read the athlete's auto-import settings, which live on the
    /// server profile rather than in UserDefaults — the Garmin webhook worker
    /// reads the same object.
    private weak var appState: AppState?

    private let logger = AppLogger.shared

    /// Workouts per upload request — see the batching note in
    /// `importHealthWorkouts()`. Small because a single workout can carry a
    /// multi-thousand-point GPS route plus a per-second HR series; ten at a
    /// time lost the connection mid-import.
    private static let uploadBatchSize = 3
    /// Attempts per batch before giving up on it.
    private static let uploadAttempts = 3

    func configure(auth: AuthManager, appState: AppState? = nil) {
        let client = APIClient(auth: auth)
        api = client
        watchSync = WatchSessionManager(api: client)
        self.appState = appState
    }

    func cancel() { cancelled = true }

    func syncAll() async {
        guard let api else { logger.log("syncAll: no API client — configure() not called"); return }
        cancelled = false
        isSyncing = true
        lastError = nil
        logger.log("syncAll: started")

        do {
            let syncedDates = Set(try await api.getSyncedDates())
            logger.log("syncAll: server has \(syncedDates.count) synced bio dates")

            // Today and the last two days are re-sent every time: Garmin
            // Connect writes the watch's daily resting HR into Apple Health
            // whenever it syncs, so a day sent earlier may have gained it
            // (BioSyncPlan).
            var pushed = 0
            let days = BioSyncPlan.days(today: Date(), synced: syncedDates, calendar: Calendar.current,
                                        key: dayFormatter.string(from:))
            for cursor in days where !cancelled {
                let dateStr = dayFormatter.string(from: cursor)

                let sleep = await hk.fetchSleepData(for: cursor)
                let bio = await hk.fetchDailyBiometrics(for: cursor)

                // Cache latest biometrics for Watch readiness payload
                if let hrv = bio.hrv { UserDefaults.standard.set(hrv, forKey: "lastHRV") }
                if let hr = bio.restingHR { UserDefaults.standard.set(hr, forKey: "lastRestingHR") }

                if sleep.totalMin > 0 || bio.restingHR != nil || bio.hrv != nil
                    || bio.spo2Avg != nil || bio.respiratoryRateAvg != nil {
                    let payload = DailyBioPayload(
                        restingHR: bio.restingHR,
                        hrv: bio.hrv,
                        sleepDurationMin: sleep.totalMin > 0 ? sleep.totalMin : nil,
                        deepSleepMin: sleep.deepMin > 0 ? sleep.deepMin : nil,
                        remSleepMin: sleep.remMin > 0 ? sleep.remMin : nil,
                        lightSleepMin: sleep.lightMin > 0 ? sleep.lightMin : nil,
                        awakeMins: sleep.awakeMin > 0 ? sleep.awakeMin : nil,
                        sleepStart: sleep.sleepStart.map { iso.string(from: $0) },
                        sleepEnd: sleep.sleepEnd.map { iso.string(from: $0) },
                        spo2Avg: bio.spo2Avg,
                        respiratoryRateAvg: bio.respiratoryRateAvg
                    )
                    try await api.pushBio(date: dateStr, payload: payload)
                    pushed += 1
                    logger.log("bio: pushed \(dateStr)")
                }
            }

            if !cancelled {
                logger.log("syncAll: bio done (\(pushed) dates pushed), syncing watch program…")
                let now = Date()
                lastSyncDate = now
                UserDefaults.standard.set(now, forKey: "lastSyncDate")
                lastBioSyncDate = now
                lastBioPushedCount = pushed
                UserDefaults.standard.set(now, forKey: "lastBioSyncDate")
                UserDefaults.standard.set(pushed, forKey: "lastBioPushedCount")
                await watchSync?.syncProgram()
                lastProgramSyncDate = Date()
                UserDefaults.standard.set(lastProgramSyncDate!, forKey: "lastProgramSyncDate")
                await importHealthWorkouts()
                logger.log("syncAll: complete")
            }
        } catch {
            lastError = error.localizedDescription
            logger.log("syncAll: ERROR — \(error.localizedDescription)")
        }

        isSyncing = false
    }

    // MARK: - Workout import (Garmin via Apple Health)

    /// Pull workouts other apps wrote to Apple Health — in practice, the
    /// activities Garmin Connect syncs down from the watch.
    ///
    /// Runs inside syncAll(), so it inherits the existing ~6h BGAppRefreshTask
    /// with no new background identifier. The HKObserverQuery registered at
    /// launch makes it closer to immediate when the entitlement allows.
    func importHealthWorkouts() async {
        guard let api else { return }

        // In the foreground AppState already holds the profile. The background
        // task builds its own SyncManager with no AppState, and that is the
        // path where the gate matters most, so fall back to fetching it.
        var settings = appState?.profile.integrations
        if settings == nil {
            settings = try? await api.fetchUserProfile().integrations
        }
        guard (settings ?? .default).allows("appleHealth") else {
            logger.log("workout-import: skipped — auto-import is off")
            return
        }

        let scan = await hk.scanImportableWorkouts()
        logScan(scan)

        guard !scan.kept.isEmpty else {
            logger.log("workout-import: nothing new (anchor=\(scan.hadAnchor ? "yes" : "no"), "
                       + "raw=\(scan.rawCount))")
            hk.commitWorkoutAnchor(scan)
            markWorkoutSync(imported: 0)
            return
        }

        var payload: [ImportedWorkout] = []
        var hrCounts: [String: Int] = [:]
        for workout in scan.kept {
            let imported = await hk.toImportedWorkout(workout)
            payload.append(imported)
            let samples = imported.heartRate?.samples.count ?? 0
            let key = samples > 0 ? "series" : (imported.heartRate?.avg != nil ? "avg-only" : "none")
            hrCounts[key, default: 0] += 1
        }
        logger.log("workout-import: heart rate — "
                   + hrCounts.sorted { $0.key < $1.key }
                       .map { "\($0.key):\($0.value)" }.joined(separator: " "))

        // Uploaded in batches because the first pass after an anchor reset can
        // carry 90 days of workouts, each with its HR samples and GPS track.
        // The server dedups, so a replayed batch costs a merge — but a single
        // timed-out request would lose the whole import.
        let batches = stride(from: 0, to: payload.count, by: Self.uploadBatchSize).map {
            Array(payload[$0..<min($0 + Self.uploadBatchSize, payload.count)])
        }
        var uploaded = 0
        var failed = 0
        for (index, batch) in batches.enumerated() {
            var lastError: String? = nil
            for attempt in 1...Self.uploadAttempts {
                do {
                    let count = try await api.saveImportedWorkouts(batch)
                    uploaded += count
                    logger.log("workout-import: uploaded \(count) "
                               + "(batch \(index + 1)/\(batches.count))")
                    lastError = nil
                    break
                } catch {
                    lastError = error.localizedDescription
                    // A dropped connection on a large payload is transient;
                    // back off briefly rather than abandoning the import.
                    if attempt < Self.uploadAttempts {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
                    }
                }
            }
            if let lastError {
                // Keep going: one bad batch must not cost the other 29. The
                // anchor is withheld below, so the next pass retries the lot
                // and the server dedups what already landed.
                failed += 1
                logger.log("workout-import: batch \(index + 1) failed — \(lastError)")
            }
        }

        if failed == 0 {
            hk.commitWorkoutAnchor(scan)
        } else {
            logger.log("workout-import: \(failed) batch(es) failed — "
                       + "keeping the sync position so they are retried")
        }
        markWorkoutSync(imported: uploaded)
    }

    /// One aggregate line per sync, plus one for the sources.
    ///
    /// `AppLogger` keeps only the last 100 entries, so a line per workout would
    /// evict everything else on the very sync the user is trying to read.
    private func logScan(_ scan: HealthKitManager.WorkoutImportScan) {
        logger.log("workout-import: scan anchor=\(scan.hadAnchor ? "yes" : "no") "
                   + "raw=\(scan.rawCount) kept=\(scan.kept.count) "
                   + "skip(source)=\(scan.skippedByBundle) skip(cutoff)=\(scan.skippedByCutoff)")

        if let error = scan.queryError {
            logger.log("workout-import: query ERROR — \(error)")
        }

        if !scan.bundleCounts.isEmpty {
            let sources = scan.bundleCounts
                .sorted { $0.value > $1.value }
                .prefix(6)
                .map { "\($0.key)×\($0.value) [\(HealthKitManager.disposition(forBundle: $0.key))]" }
                .joined(separator: ", ")
            logger.log("workout-import: sources \(sources)")
        }
    }

    /// Forget the HealthKit anchor so the next pass re-examines recent history.
    func reimportRecentWorkouts() async {
        hk.resetWorkoutAnchor()
        logger.log("workout-import: anchor reset, re-importing")
        await importHealthWorkouts()
    }

    private func markWorkoutSync(imported: Int) {
        let now = Date()
        lastWorkoutSyncDate = now
        lastWorkoutImportedCount = imported
        UserDefaults.standard.set(now, forKey: "lastWorkoutSyncDate")
        UserDefaults.standard.set(imported, forKey: "lastWorkoutImportedCount")
    }
}
