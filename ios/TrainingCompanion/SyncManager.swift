import Foundation

@MainActor
final class SyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    @Published var lastError: String? = nil

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

    func configure(auth: AuthManager) {
        let client = APIClient(auth: auth)
        api = client
        watchSync = WatchSessionManager(api: client)
    }

    func cancel() { cancelled = true }

    func syncAll() async {
        guard let api else { return }
        cancelled = false
        isSyncing = true
        lastError = nil

        do {
            let syncedDates = Set(try await api.getSyncedDates())

            // Sync from last sync date (or 30 days ago) up to yesterday
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let earliest = lastSyncDate.map { calendar.startOfDay(for: $0) }
                ?? calendar.date(byAdding: .day, value: -30, to: today)!

            var cursor = earliest
            while cursor < today && !cancelled {
                let dateStr = dayFormatter.string(from: cursor)

                if !syncedDates.contains(dateStr) {
                    let sleep = await hk.fetchSleepData(for: cursor)
                    let bio = await hk.fetchDailyBiometrics(for: cursor)

                    // Only push if we actually have data for this day
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
                    }
                }

                cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            }

            if !cancelled {
                lastSyncDate = today
                UserDefaults.standard.set(today, forKey: "lastSyncDate")
                await watchSync?.syncProgram()
            }
        } catch {
            lastError = error.localizedDescription
        }

        isSyncing = false
    }
}
