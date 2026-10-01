import Foundation

/// The watch upload's server payloads.
///
/// `WatchSessionManager` used to write a finished watch workout and its match
/// straight into Supabase, the way the phone's FIT import did until it went
/// through the server. The row never met `workout_dedupe`, so the same session
/// arriving again from Apple Health or the Garmin webhook became a second
/// workout; the match skipped `session_uid` resolution; the elevation loss
/// stayed 0; and the session-log upsert still targeted the pre-006 primary
/// key. Everything here is pure so a test can pin the keys
/// `POST /api/health/workouts` and `POST /api/health/matches` read — the
/// camelCase `ImportedWorkout` shape, never the snake_case columns.
enum WatchUpload {

    /// `watch_live_<session>_<startedAt>`, percent-encoded — the id this path
    /// has always minted; `workout_matches.imported_workout_id` references it.
    static func workoutId(sessionKey: String, startedAt: String) -> String {
        "watch_live_\(sessionKey)_\(startedAt)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? UUID().uuidString
    }

    /// The watch stamps ISO 8601 with or without fractional seconds.
    static func parseStart(_ startedAt: String) -> Date? {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: startedAt) ?? fractional.date(from: startedAt)
    }

    /// The `ImportedWorkout` dictionary `POST /api/health/workouts` stores.
    ///
    /// Elevation loss is sent as 0 on purpose: that is the server's cue to
    /// recompute gain and loss from the track's altitudes, which the watch
    /// never does itself.
    static func workoutPayload(summary: WatchWorkoutSummary, workoutId: String, startDate: Date,
                               sessionName: String?, modality: String?) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let hrSamples: [[String: Any]] = (summary.hrSamples ?? []).map { point in
            ["timestamp": iso.string(from: startDate.addingTimeInterval(Double(point.t))), "bpm": point.b]
        }
        let gpsTrack: [[String: Any]]? = summary.gpsTrack?.map { point in
            var p: [String: Any] = [
                "lat": point.lat, "lng": point.lng,
                "timestamp": iso.string(from: startDate.addingTimeInterval(Double(point.t))),
            ]
            if let alt = point.alt { p["altitude"] = alt }
            if let bpm = point.b { p["bpm"] = bpm }
            return p
        }

        var heartRate: [String: Any] = ["samples": hrSamples]
        if let avg = summary.avgHR { heartRate["avg"] = avg }
        if let peak = summary.peakHR { heartRate["max"] = peak }

        var workout: [String: Any] = [
            "id":              workoutId,
            "source":          summary.source,
            "date":            summary.date,
            "startTime":       summary.startedAt,
            "endTime":         summary.endedAt,
            "durationMinutes": summary.durationMinutes,
            "activityType":    sessionName ?? summary.source,
            "rawData":         [:] as [String: Any],
            "heartRate":       heartRate,
        ]
        if let modality { workout["inferredModalityId"] = modality }
        if let gpsTrack, !gpsTrack.isEmpty { workout["gpsTrack"] = gpsTrack }
        if let meters = summary.distanceMeters { workout["distance"] = ["value": meters / 1000.0, "unit": "km"] }
        if let gain = summary.elevationGainMeters { workout["elevation"] = ["gain": Int(gain), "loss": 0] }
        return workout
    }

    /// The same workout again with the full HealthKit route.
    ///
    /// The server's upsert replaces every column, so the stub this path used
    /// to send (no heart rate, the source as the activity name) wiped the
    /// samples and the session name the first upload carried. Elevation is
    /// dropped so the server recomputes it from the new track.
    static func enriched(_ original: [String: Any], gpsTrack: [[String: Any]]) -> [String: Any] {
        var workout = original
        workout["gpsTrack"] = gpsTrack
        workout.removeValue(forKey: "elevation")
        return workout
    }

    /// `POST /api/health/matches` body: a manual match, which the server also
    /// treats as the answer to any suggestion it held for this workout.
    static func matchPayload(workoutId: String, sessionKey: String, matchedAt: Date = Date()) -> [String: Any] {
        [
            "importedWorkoutId": workoutId,
            "sessionKey":        sessionKey,
            "matchConfidence":   "manual",
            "matchedAt":         ISO8601DateFormatter().string(from: matchedAt),
        ]
    }

    /// The id the match should point at once the server has stored the upload:
    /// the upload's own id if it is listed, else — when dedup folded it into
    /// another source's richer copy and hid it — the listed row that starts
    /// within five minutes of it on the same day, the dedup rule's own window.
    /// With no listing at all (the request failed) the upload's id stands:
    /// the match route creates a stub row rather than fail.
    static func canonicalId(for workoutId: String, date: String, startedAt: String,
                            in listed: [ImportedWorkout]) -> String {
        if listed.isEmpty || listed.contains(where: { $0.id == workoutId }) { return workoutId }
        guard let start = parseStart(startedAt) else { return workoutId }
        let folded = listed.first { candidate in
            guard candidate.date == date, let other = candidate.startTime.flatMap(parseStart) else { return false }
            return abs(other.timeIntervalSince(start)) <= 5 * 60
        }
        return folded?.id ?? workoutId
    }
}
