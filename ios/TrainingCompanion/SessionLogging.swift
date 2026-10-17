import Foundation

/// What a slot type lets the athlete log, and how a log reads back.
///
/// Mirrors `frontend/src/lib/outcomeFields.ts`: a sets × reps (or hold) slot
/// logs sets; everything else logs its currency — rounds, minutes,
/// kilometres, reps — which is what the analytics primitives read. Until the
/// phone could log, the only logger it had was the watch, and only for sets.
enum OutcomeField: String, CaseIterable {
    case rounds, minutes, time, km, reps, seconds

    var label: String {
        switch self {
        case .rounds: return "Rounds"
        case .minutes: return "Minutes"
        case .time: return "Time"
        case .km: return "Kilometres"
        case .reps: return "Reps"
        case .seconds: return "Hold (seconds)"
        }
    }
}

enum SessionLogging {

    private static let fieldsFor: [String: [OutcomeField]] = [
        "time_domain":     [.minutes, .km],
        "skill_practice":  [.minutes],
        "for_time":        [.minutes],
        "distance":        [.km, .minutes],
        "amrap":           [.rounds, .reps],
        "emom":            [.rounds],
        "rounds_for_time": [.minutes, .rounds],
        "amrap_movement":  [.reps],
    ]

    /// The field a standard's result kind is logged in (src/standard_tests.RESULTS).
    private static let resultField: [String: OutcomeField] = [
        "duration": .time, "rounds": .rounds, "reps": .reps, "hold": .seconds, "distance": .km,
    ]

    /// The currency fields a slot can log; empty for a sets slot. Two rules on
    /// the exercise, as `lib/outcomeFields.ts` has them — change both: a
    /// kettlebell in a timed slot logs reps beside minutes (Wildman's cadence
    /// is reps per minute), and an isometric in a skill-practice slot logs the
    /// hold in seconds (Ido's handstand and L-sit holds). A for-time slot logs
    /// a clock, and a test's scored slot asks first for the number its
    /// standard needs (`standardResult`): reps for push-ups in three minutes.
    static func outcomeFields(for slotType: String?, category: String? = nil,
                              patterns: [String] = [], standardResult: String? = nil) -> [OutcomeField] {
        var base: [OutcomeField]
        if slotType == "time_domain", category == "kettlebell" { base = [.minutes, .reps] }
        else if slotType == "skill_practice", patterns.contains("isometric") { base = [.minutes, .seconds] }
        else { base = fieldsFor[slotType ?? ""] ?? [] }
        if slotType == "for_time" || slotType == "rounds_for_time" { base = base.map { $0 == .minutes ? .time : $0 } }
        guard let want = standardResult.flatMap({ resultField[$0] }) else { return base }
        if want == .time { base = base.map { $0 == .minutes ? .time : $0 } }
        return [want] + base.filter { $0 != want && ($0 != .km || want == .km) }
    }

    /// A clock as typed — "7:32", "1:02:30", or plain minutes ("7.5") — in
    /// seconds; nil when it is not one (`lib/outcomeFields.parseClock`).
    static func parseClock(_ raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.contains(":") {
            let parts = t.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
            guard parts.count <= 3, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
            let n = parts.map { $0! }
            guard !n.dropFirst().contains(where: { $0 >= 60 }) else { return nil }
            let sec = n.reduce(0) { $0 * 60 + $1 }
            return sec > 0 ? Int(sec.rounded()) : nil
        }
        guard let min = Double(t.replacingOccurrences(of: ",", with: ".")), min > 0 else { return nil }
        return Int((min * 60).rounded())
    }

    /// Seconds as a clock: 452 → "7:32", 3750 → "1:02:30".
    static func formatClock(_ sec: Int) -> String {
        let h = sec / 3600, m = (sec % 3600) / 60, s = sec % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The exercise's `movement_patterns`, kept in its extras.
    static func patterns(of exercise: ProgramExercise?) -> [String] {
        guard case .array(let values)? = exercise?.extra["movement_patterns"] else { return [] }
        return values.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    /// Sets × reps and static holds log per set; the rest log an outcome.
    static func logsSets(_ slotType: String) -> Bool {
        outcomeFields(for: slotType).isEmpty
    }

    /// "3 sets · 5×80 kg", "3 sets · 5×80, 5×82.5, 4×82.5 kg", "3×30 s hold",
    /// "32 min · 8.4 km", "7 rounds · 48 reps"; nil when nothing was logged.
    static func summary(_ perf: ExercisePerformanceLog, slotType: String) -> String? {
        if logsSets(slotType) {
            let done = perf.sets.filter(\.completed)
            guard !done.isEmpty else { return nil }
            if slotType == "static_hold" {
                let secs = done.map { "\($0.durationSeconds ?? 0)" }
                let uniform = Set(secs).count == 1
                return uniform ? "\(done.count)×\(secs[0]) s hold"
                    : "\(done.count) hold\(done.count == 1 ? "" : "s") · \(secs.joined(separator: ", ")) s"
            }
            let reps = done.map { $0.repsActual.map(String.init) ?? "?" }
            let kgs = done.map { $0.weightKg.map(LoadFormat.kilograms) }
            let uniform = Set(reps).count == 1 && Set(kgs.map { $0 ?? "" }).count == 1
            let count = "\(done.count) set\(done.count == 1 ? "" : "s")"
            if uniform {
                let kg = kgs[0].map { " @ \($0) kg" } ?? ""
                return "\(count) · \(done.count)×\(reps[0])\(kg)"
            }
            let pairs = zip(reps, kgs).map { r, kg in kg.map { "\(r)×\($0)" } ?? r }
            let unit = kgs.contains { $0 != nil } ? " kg" : ""
            return "\(count) · \(pairs.joined(separator: ", "))\(unit)"
        }
        var parts: [String] = []
        let clock = slotType == "for_time" || slotType == "rounds_for_time"
        if let sec = perf.durationSec, sec > 0 {
            parts.append(clock ? formatClock(sec) : "\(Int((Double(sec) / 60).rounded())) min")
        }
        if let km = perf.distanceKm, km > 0 { parts.append("\(LoadFormat.kilograms(km)) km") }
        if let rounds = perf.rounds, rounds > 0 { parts.append("\(rounds) round\(rounds == 1 ? "" : "s")") }
        if let reps = perf.sets.first?.repsActual, reps > 0 { parts.append("\(reps) reps") }
        if let hold = perf.sets.first?.durationSeconds, hold > 0 { parts.append("\(hold) s hold") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
