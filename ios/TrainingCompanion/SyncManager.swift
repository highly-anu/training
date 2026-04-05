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

    private let logger = AppLogger.shared

    func configure(auth: AuthManager) {
        let client = APIClient(auth: auth)
        api = client
        watchSync = WatchSessionManager(api: client)
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
                logger.log("syncAll: complete")
            }
        } catch {
            lastError = error.localizedDescription
            logger.log("syncAll: ERROR — \(error.localizedDescription)")
        }

        isSyncing = false
    }
}
