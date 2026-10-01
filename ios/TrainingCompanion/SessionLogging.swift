import Foundation

/// What a slot type lets the athlete log, and how a log reads back.
///
/// Mirrors `frontend/src/lib/outcomeFields.ts`: a sets × reps (or hold) slot
/// logs sets; everything else logs its currency — rounds, minutes,
/// kilometres, reps — which is what the analytics primitives read. Until the
/// phone could log, the only logger it had was the watch, and only for sets.
enum OutcomeField: String, CaseIterable {
    case rounds, minutes, km, reps

    var label: String {
        switch self {
        case .rounds: return "Rounds"
        case .minutes: return "Minutes"
        case .km: return "Kilometres"
        case .reps: return "Reps"
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

    /// The currency fields a slot type can log; empty for a sets slot.
    static func outcomeFields(for slotType: String?) -> [OutcomeField] {
        fieldsFor[slotType ?? ""] ?? []
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
                return uniform ? "\(done.count)×\(secs[0]) s hold" : "\(done.count) holds · \(secs.joined(separator: ", ")) s"
            }
            let reps = done.map { $0.repsActual.map(String.init) ?? "?" }
            let kgs = done.map { $0.weightKg.map(LoadFormat.kilograms) }
            let uniform = Set(reps).count == 1 && Set(kgs.map { $0 ?? "" }).count == 1
            if uniform {
                let kg = kgs[0].map { " @ \($0) kg" } ?? ""
                return "\(done.count) sets · \(done.count)×\(reps[0])\(kg)"
            }
            let pairs = zip(reps, kgs).map { r, kg in kg.map { "\(r)×\($0)" } ?? r }
            let unit = kgs.contains { $0 != nil } ? " kg" : ""
            return "\(done.count) sets · \(pairs.joined(separator: ", "))\(unit)"
        }
        var parts: [String] = []
        if let sec = perf.durationSec, sec > 0 { parts.append("\(Int((Double(sec) / 60).rounded())) min") }
        if let km = perf.distanceKm, km > 0 { parts.append("\(LoadFormat.kilograms(km)) km") }
        if let rounds = perf.rounds, rounds > 0 { parts.append("\(rounds) round\(rounds == 1 ? "" : "s")") }
        if let reps = perf.sets.first?.repsActual, reps > 0, outcomeFields(for: slotType).contains(.reps) {
            parts.append("\(reps) reps")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
