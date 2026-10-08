import Foundation

/// Which days the Apple Health relay (`SyncManager.syncAll`) sends to
/// `PUT /health/bio/{date}` — pure, so `BioSyncPlanTests` pins it.
///
/// Garmin Connect writes the watch's exact daily resting HR into Apple Health
/// (docs/roadmap.md, item 2: 46, 45, 49 for 6–8 Oct, identical to the watch),
/// and readiness scores it from `daily_bio`. Two rules kept it from arriving:
/// the relay stopped before today, so today's value only landed tomorrow, and
/// it never sent a day the server already had, so a day sent before Garmin
/// Connect had synced kept no resting HR for good. Now the last
/// `refreshDays` days — today included — are sent on every sync whatever the
/// server holds, and older days only when the server has none.
enum BioSyncPlan {

    /// Today and the two days before it.
    static let refreshDays = 3
    /// How far back a day the server lacks is still filled in.
    static let lookbackDays = 30

    /// Oldest first, so the newest values are the last ones cached.
    /// `synced` holds the "yyyy-MM-dd" keys the server already has from the
    /// relay (`GET /health/bio/synced-dates`); `key` formats a day the same way.
    static func days(today: Date, synced: Set<String>, calendar: Calendar,
                     key: (Date) -> String) -> [Date] {
        let start = calendar.startOfDay(for: today)
        return (0...lookbackDays).reversed().compactMap { back -> Date? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            return back < refreshDays || !synced.contains(key(day)) ? day : nil
        }
    }
}
