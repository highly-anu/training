import CryptoKit
import Foundation

/// The deterministic workout id, in one place.
///
/// Must stay byte-identical to `deterministic_id` in `src/workout_ids.py` — the
/// server dedups re-imports on this value, and `workout_matches` rows reference
/// the ids it produces. Changing the formula orphans every stored match.
///
/// The id is deliberately source-tagged: the same ride imported as `fit_file`
/// and as `garmin` yields two different ids. Collapsing those is the server's
/// cross-source dedup layer's job, not this function's.
enum WorkoutID {

    /// UTC, second precision, with an explicit offset — the spelling the server
    /// hashes. `2026-03-28T08:00:00+00:00`.
    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxxxx"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func deterministic(source: String,
                             startTime: String,
                             activityType: String,
                             durationMinutes: Int) -> String {
        let raw = "\(source)|\(startTime)|\(activityType)|\(durationMinutes)"
        let hash = SHA256.hash(data: Data(raw.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        return "\(source)-\(String(hex.prefix(24)))"
    }
}
