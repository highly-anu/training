import Combine
import CoreLocation
import Foundation
import HealthKit
import WatchConnectivity

// MARK: - Default rest seconds by modality (fallback when slot rest_sec is nil)

private let modalityRestDefaults: [String: Int] = [
    "max_strength":             240,
    "relative_strength":        180,
    "strength_endurance":       90,
    "power":                    240,
    "aerobic_base":             0,
    "anaerobic_intervals":      120,
    "mixed_modal_conditioning": 60,
    "mobility":                 30,
    "movement_skill":           30,
    "durability":               0,
    "combat_sport":             0,
    "rehab":                    30,
]

// MARK: - WatchSessionManager

/// Fetches the current training program from the API, computes today's sessions,
/// encodes them for the Watch, and relays post-workout summaries back to the API.
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    private let api: APIClient
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // UserDefaults keys

    init(api: APIClient) {
        self.api = api
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Program sync

    /// Fetches today's program from the API and sends sessions to the Watch.
    func syncProgram() async {
        let todayStr = dayFormatter.string(from: Date())
        do {
            guard let server = try await api.fetchProgram() else {
                sendNoProgramMessage()
                return
            }
            guard let program = server.currentProgram,
                  let startDateStr = server.programStartDate,
                  let startDate = dayFormatter.date(from: startDateStr) else {
                sendNoProgramMessage()
                return
            }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let start = calendar.startOfDay(for: startDate)
            let daysSince = calendar.dateComponents([.day], from: start, to: today).day ?? 0
            let weekIndex = daysSince / 7
            let dayName = weekdayName(for: Date())

            guard weekIndex < program.weeks.count else {
                sendMessage(["type": "program_expired"])
                return
            }

            let week = program.weeks[weekIndex]
            let sessions = week.schedule[dayName] ?? []
            let watchSessions = sessions.enumerated().map { (i, s) in
                encodeSession(s, weekNumber: week.weekNumber, dayName: dayName, index: i, modality: s.modality)
            }

            let profile = buildProfilePayload()
            let payload: [String: Any] = [
                "type":        "today_sessions",
                "date":        todayStr,
                "weekNumber":  week.weekNumber,
                "dayName":     dayName,
                "sessions":    encodedJSON(watchSessions),
                "profile":     profile,
            ]

            WCSession.default.transferUserInfo(payload)
        } catch {
            // Silent failure — Watch will use cached sessions
        }
    }

    // MARK: - Encoding

    private func encodeSession(
        _ s: ProgramSession,
        weekNumber: Int,
        dayName: String,
        index: Int,
        modality: String
    ) -> WatchSession {
        let exercises = s.exercises
            .filter { !$0.injurySkip && $0.exercise != nil }
            .map { encodeExercise($0, modality: modality) }

        return WatchSession(
            sessionId:        "\(weekNumber)-\(dayName)-\(index)",
            modalityId:       modality,
            archetypeName:    s.archetype?.name ?? modality,
            estimatedMinutes: s.archetype?.durationEstimateMinutes ?? 45,
            isDeload:         s.isDeload,
            exercises:        exercises
        )
    }

    private func encodeExercise(_ ea: ProgramExerciseAssignment, modality: String) -> WatchExercise {
        let ex = ea.exercise!
        let load = ea.load
        let slotType = inferSlotType(from: ea.load, explicit: ea.slotType)

        let cue = ea.notes ?? ex.notes

        // Parse zone bounds from zoneTarget string (e.g. "Zone 1–2 (conversational pace)")
        let (zoneLower, zoneUpper) = parseZoneRange(load.zoneTarget)

        // Rest seconds: slot value or modality default
        let restSec = ea.restSec ?? modalityRestDefaults[modality]

        return WatchExercise(
            exerciseId:         ex.id,
            name:               ex.name,
            slotType:           slotType,
            slotRole:           ea.slotRole ?? "",
            isMeta:             ea.meta,
            loadDescription:    formatLoad(ea),
            loadNote:           ea.loadNote,
            coachingCue:        cue,
            sets:               load.sets,
            reps:               load.reps?.displayString,
            weightKg:           load.weightKg,
            targetRpe:          load.targetRpe,
            durationMinutes:    load.durationMinutes,
            zoneTarget:         load.zoneTarget,
            timeMinutes:        load.timeMinutes,
            targetRounds:       load.targetRounds,
            emomFormat:         load.format,
            holdSeconds:        load.holdSeconds,
            distanceKm:         load.distanceKm,
            restSeconds:        restSec,
            prescribedZoneLower: zoneLower,
            prescribedZoneUpper: zoneUpper
        )
    }

    /// Infers slot type from load fields when the explicit slot_type is nil (legacy stored programs).
    private func inferSlotType(from load: ProgramLoad, explicit: String?) -> String {
        if let e = explicit, !e.isEmpty { return e }
        if load.distanceKm    != nil { return "distance" }
        if load.holdSeconds   != nil { return "static_hold" }
        if load.format        != nil { return "emom" }
        if load.durationMinutes != nil { return "time_domain" }
        if load.timeMinutes != nil && load.targetRounds != nil { return "amrap" }
        if load.targetRounds  != nil { return "for_time" }
        return "sets_reps"
    }

    private func formatLoad(_ ea: ProgramExerciseAssignment) -> String {
        let load = ea.load
        switch inferSlotType(from: ea.load, explicit: ea.slotType) {
        case "sets_reps":
            let sets = load.sets.map { "\($0)" } ?? "?"
            let reps = load.reps?.displayString ?? "?"
            if let kg = load.weightKg {
                return "\(sets)×\(reps) @ \(kg) kg"
            } else if let rpe = load.targetRpe {
                return "\(sets)×\(reps) @ RPE \(rpe)"
            } else {
                return "\(sets)×\(reps)"
            }
        case "time_domain", "skill_practice":
            if let min = load.durationMinutes {
                return "\(min) min\(load.zoneTarget.map { " — \($0)" } ?? "")"
            }
            return "Duration TBD"
        case "emom":
            if let min = load.timeMinutes, let rounds = load.targetRounds {
                return "\(min) min / \(rounds) rounds"
            }
            return load.format ?? "EMOM"
        case "amrap":
            if let min = load.timeMinutes {
                return "AMRAP \(min) min"
            }
            return "AMRAP"
        case "for_time":
            if let rounds = load.targetRounds {
                return "\(rounds) rounds for time"
            }
            return "For time"
        case "distance":
            if let km = load.distanceKm {
                return "\(km) km"
            }
            return "Distance"
        case "static_hold":
            let sets = load.sets.map { "\($0)×" } ?? ""
            let secs = load.holdSeconds.map { "\($0)s" } ?? "?"
            return "\(sets)\(secs) hold"
        default:
            return ""
        }
    }

    /// Parses "Zone 1–2 (conversational pace)" → (lower: 1, upper: 2).
    /// Returns (nil, nil) if not parseable.
    private func parseZoneRange(_ zoneTarget: String?) -> (Int?, Int?) {
        guard let s = zoneTarget else { return (nil, nil) }
        let pattern = /[Zz]one\s*(\d)(?:\s*[-–]\s*(\d))?/
        guard let m = try? pattern.firstMatch(in: s),
              let lower = Int(m.output.1) else { return (nil, nil) }
        let upper = m.output.2.flatMap { Int($0) } ?? lower
        return (lower, upper)
    }

    private func weekdayName(for date: Date) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let index = Calendar.current.component(.weekday, from: date) - 1
        return names[index]
    }

    private func buildProfilePayload() -> [String: Any] {
        var p: [String: Any] = [:]
        // dateOfBirth from profileStore is persisted in UserDefaults by the web app
        // (and may be set by the user in the iOS app's settings in the future).
        // For now we pass what we have.
        if let dob = UserDefaults.standard.string(forKey: "dateOfBirth") {
            p["dateOfBirth"] = dob
            let age = Calendar.current.dateComponents([.year], from: {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                return f.date(from: dob) ?? Date()
            }(), to: Date()).year ?? 30
            p["maxHR"] = 220 - age
        }
        return p
    }

    private func sendNoProgramMessage() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.transferUserInfo(["type": "no_program"])
    }

    private func sendMessage(_ payload: [String: Any]) {
        WCSession.default.transferUserInfo(payload)
    }

    private func encodedJSON<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let obj  = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return obj
    }
}

// MARK: - WCSessionDelegate (receive workout summaries from Watch)

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let type = userInfo["type"] as? String ?? "(no type)"
        AppLogger.shared.logFromBackground("WCSession: received userInfo type=\(type)")
        guard type == "workout_complete" else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: userInfo),
              let summary = try? JSONDecoder().decode(WatchWorkoutSummary.self, from: data) else {
            AppLogger.shared.logFromBackground("WCSession: failed to decode WatchWorkoutSummary")
            return
        }
        Task { await handleWorkoutComplete(summary) }
    }

    /// Large workout payloads arrive via transferFile when > 50 KB.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["type"] as? String == "workout_complete_file" else { return }
        guard let data = try? Data(contentsOf: file.fileURL),
              let summary = try? JSONDecoder().decode(WatchWorkoutSummary.self, from: data) else {
            AppLogger.shared.logFromBackground("WCSession: failed to decode large workout file")
            return
        }
        Task { await handleWorkoutComplete(summary) }
    }

    private func handleWorkoutComplete(_ summary: WatchWorkoutSummary) async {
        let sessionKey = summary.sessionId
        AppLogger.shared.logFromBackground("WCSession: decoded summary — session=\(sessionKey) duration=\(summary.durationMinutes)min exercises=\(summary.exercisesCompleted)")

        // 1. Save session log (exercises, set data, HR aggregates)
        var log: [String: Any] = [
            "sessionKey":    sessionKey,
            "completedAt":   summary.endedAt,
            "source":        summary.source,
            "exercises":     encodedJSON(summary.setLogs.mapValues { ["sets": $0] }),
            "notes":         "",
        ]
        if let avgHR = summary.avgHR { log["avgHR"] = avgHR }
        if let peakHR = summary.peakHR { log["peakHR"] = peakHR }
        if let timeline = summary.exerciseTimeline { log["exerciseTimeline"] = encodedJSON(timeline) }

        AppLogger.shared.log("API: saving workout log for \(sessionKey)…")
        do {
            try await api.saveWorkoutLog(sessionKey: sessionKey, log: log)
            AppLogger.shared.log("API: saved workout log for \(sessionKey) ✓")
        } catch {
            AppLogger.shared.log("API: saveWorkoutLog FAILED — \(error.localizedDescription)")
        }

        // 2. Build and save ImportedWorkout (enables HRTimeline + GPSMap on the frontend)
        let iso = ISO8601DateFormatter()
        guard let startDate = iso.date(from: summary.startedAt) else { return }

        let workoutId = "watch_live_\(sessionKey)_\(summary.startedAt)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? UUID().uuidString

        let hrSamples = summary.hrSamples?.map { point -> [String: Any] in
            let ts = iso.string(from: startDate.addingTimeInterval(Double(point.t)))
            return ["timestamp": ts, "bpm": point.b]
        }
        let gpsTrack = summary.gpsTrack?.map { point -> [String: Any] in
            let ts = iso.string(from: startDate.addingTimeInterval(Double(point.t)))
            var p: [String: Any] = ["lat": point.lat, "lng": point.lng, "timestamp": ts]
            if let alt = point.alt { p["altitude"] = alt }
            if let bpm = point.b  { p["bpm"] = bpm }
            return p
        }

        var workout: [String: Any] = [
            "id":              workoutId,
            "source":          summary.source,
            "date":            summary.date,
            "startTime":       summary.startedAt,
            "endTime":         summary.endedAt,
            "durationMinutes": summary.durationMinutes,
            "activityType":    summary.source,
            "rawData":         [:] as [String: Any],
            "heartRate":       [
                "avg": summary.avgHR as Any,
                "max": summary.peakHR as Any,
                "samples": hrSamples as Any,
            ] as [String: Any],
        ]
        if let gps = gpsTrack { workout["gpsTrack"] = gps }
        if let dist = summary.distanceMeters { workout["distance"] = ["value": dist / 1000.0, "unit": "km"] }
        if let gain = summary.elevationGainMeters { workout["elevation"] = ["gain": Int(gain), "loss": 0] }
        if let cal = log["calories"] { workout["calories"] = cal }

        do {
            try await api.saveWatchWorkouts([workout])
            AppLogger.shared.log("API: saved watch workout \(workoutId) ✓")
        } catch {
            AppLogger.shared.log("API: saveWatchWorkout FAILED — \(error.localizedDescription)")
            return
        }

        // 3. Link workout to session via workout_matches
        let now = iso.string(from: Date())
        let matchPayload: [String: Any] = [
            "importedWorkoutId": workoutId,
            "sessionKey":        sessionKey,
            "matchConfidence":   "auto",
            "matchedAt":         now,
        ]
        do {
            try await api.saveWorkoutMatch(matchPayload)
            AppLogger.shared.log("API: saved workout match \(workoutId) → \(sessionKey) ✓")
        } catch {
            AppLogger.shared.log("API: saveWorkoutMatch FAILED — \(error.localizedDescription)")
        }

        // 4. Async GPS enrichment: try to fetch the full HKWorkoutRoute after a short delay
        //    (HealthKit sync from Watch → iPhone takes ~5–30 s)
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 s
            await enrichWorkoutWithHKRoute(
                workoutId: workoutId,
                startDate: startDate,
                existingGPSCount: gpsTrack?.count ?? 0
            )
        }
    }

    private func enrichWorkoutWithHKRoute(workoutId: String, startDate: Date, existingGPSCount: Int) async {
        guard let hkWorkout = await HealthKitManager.shared.findHKWorkout(near: startDate) else {
            // Retry once at 60 s
            try? await Task.sleep(nanoseconds: 50_000_000_000)
            guard let hkWorkout = await HealthKitManager.shared.findHKWorkout(near: startDate) else { return }
            await uploadRoute(from: hkWorkout, workoutId: workoutId, existingGPSCount: existingGPSCount, startDate: startDate)
            return
        }
        await uploadRoute(from: hkWorkout, workoutId: workoutId, existingGPSCount: existingGPSCount, startDate: startDate)
    }

    private func uploadRoute(from hkWorkout: HKWorkout, workoutId: String, existingGPSCount: Int, startDate: Date) async {
        let locations = await HealthKitManager.shared.fetchWorkoutRoute(for: hkWorkout)
        guard locations.count > existingGPSCount else { return }
        let iso = ISO8601DateFormatter()
        let gpsTrack: [[String: Any]] = locations.map { loc in
            var p: [String: Any] = [
                "lat": loc.coordinate.latitude,
                "lng": loc.coordinate.longitude,
                "timestamp": iso.string(from: loc.timestamp),
            ]
            if loc.altitude > 0 { p["altitude"] = loc.altitude }
            return p
        }
        let enriched: [String: Any] = [
            "id":              workoutId,
            "source":          "apple_watch_live",
            "date":            iso.string(from: startDate).prefix(10).description,
            "startTime":       iso.string(from: hkWorkout.startDate),
            "endTime":         iso.string(from: hkWorkout.endDate),
            "durationMinutes": Int(hkWorkout.duration / 60),
            "activityType":    "apple_watch_live",
            "gpsTrack":        gpsTrack,
            "rawData":         [:] as [String: Any],
            "heartRate":       [:] as [String: Any],
        ]
        do {
            try await api.saveWatchWorkouts([enriched])
            AppLogger.shared.log("API: enriched workout \(workoutId) with \(locations.count) GPS points ✓")
        } catch {
            AppLogger.shared.log("API: GPS enrichment FAILED — \(error.localizedDescription)")
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String, type == "request_sync" else { return }
        Task { await syncProgram() }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let type = message["type"] as? String, type == "request_sync" else {
            replyHandler([:])
            return
        }
        Task {
            await syncProgram()
            replyHandler(["status": "ok"])
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

