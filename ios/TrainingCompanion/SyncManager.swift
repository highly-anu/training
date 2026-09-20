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

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let earliest = calendar.date(byAdding: .day, value: -30, to: today)!

            var pushed = 0
            var cursor = earliest
            while cursor < today && !cancelled {
                let dateStr = dayFormatter.string(from: cursor)

                if !syncedDates.contains(dateStr) {
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

                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
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

        let workouts = await hk.importableWorkouts()
        guard !workouts.isEmpty else {
            logger.log("workout-import: nothing new")
            markWorkoutSync(imported: 0)
            return
        }

        var payload: [ImportedWorkout] = []
        for workout in workouts {
            payload.append(await hk.toImportedWorkout(workout))
        }

        do {
            // The server dedups, so re-sending one the watch relay already
            // uploaded costs a merge, not a duplicate.
            let count = try await api.saveImportedWorkouts(payload)
            logger.log("workout-import: uploaded \(count) workout(s)")
            markWorkoutSync(imported: count)
        } catch {
            // Deliberately not rethrown: a failed workout import must not fail
            // the bio sync that already succeeded. The anchor has moved on, so
            // recover with "Re-import recent workouts" in Sync settings.
            logger.log("workout-import: ERROR — \(error.localizedDescription)")
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
