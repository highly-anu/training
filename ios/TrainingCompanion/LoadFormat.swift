import Foundation

/// The one place a prescription is turned into words on the phone.
///
/// `SessionDetailView` had this as private helpers; the swap sheet needs the
/// same string for each alternative, and two copies of "3×5 @ 80 kg" drift
/// (design system §1.7). The watch keeps its own `loadDescription`, which the
/// phone pre-formats for it in `WatchSessionManager`.
enum LoadFormat {

    nonisolated static let knownSlotTypes = ["sets_reps", "time_domain", "skill_practice", "emom",
                                 "amrap", "amrap_movement", "for_time", "distance", "static_hold"]

    /// Passes a known `slot_type` through; infers one from the load's fields
    /// for custom archetypes that omit it. Order matters.
    nonisolated static func resolvedSlotType(_ ea: ProgramExerciseAssignment) -> String {
        if let st = ea.slotType, knownSlotTypes.contains(st) { return st }
        let load = ea.load
        if load.distanceKm      != nil { return "distance" }
        if load.holdSeconds     != nil { return "static_hold" }
        if load.format          != nil { return "emom" }
        if load.durationMinutes != nil { return "time_domain" }
        if load.timeMinutes != nil && load.targetRounds != nil { return "amrap" }
        if load.targetRounds    != nil { return "for_time" }
        return "sets_reps"
    }

    static func slotTypeLabel(_ slotType: String) -> String {
        switch slotType {
        case "sets_reps":      return "Sets × Reps"
        case "time_domain":    return "Duration"
        case "emom":           return "EMOM"
        case "amrap":          return "AMRAP"
        case "for_time":       return "For Time"
        case "amrap_movement": return "Each Round"
        case "distance":       return "Distance"
        case "static_hold":    return "Static Hold"
        case "skill_practice": return "Skill"
        default:               return slotType
        }
    }

    /// "3×5 @ 80 kg", "45 min · Z2", "AMRAP 12 min", "3×30s hold".
    static func describe(_ ea: ProgramExerciseAssignment) -> String {
        let load = ea.load
        switch resolvedSlotType(ea) {
        case "sets_reps":
            let sets = load.sets.map { "\($0)" } ?? "?"
            let reps = load.reps?.displayString ?? "?"
            if let kg = load.weightKg { return "\(sets)×\(reps) @ \(kilograms(kg)) kg" }
            if let rpe = load.targetRpe { return "\(sets)×\(reps) @ RPE \(rpe)" }
            return "\(sets)×\(reps)"
        case "time_domain", "skill_practice":
            if let min = load.durationMinutes {
                return "\(min) min\(load.zoneTarget.map { " · \($0)" } ?? "")"
            }
            return "Duration TBD"
        case "emom":
            if let min = load.timeMinutes, let rounds = load.targetRounds {
                let reps: String
                if case .int(let count)? = load.extra["reps_per_round"] {
                    reps = " · \(count) reps/round"
                } else { reps = "" }
                let bell = load.weightKg.map { " · \(kilograms($0)) kg" } ?? ""
                return "\(min) min · \(rounds) rounds\(reps)\(bell)"
            }
            return load.format ?? "EMOM"
        case "amrap":
            let amrap = load.timeMinutes.map { "AMRAP \($0) min" } ?? "AMRAP"
            return ([amrap] + [roundCount(load)].compactMap { $0 }).joined(separator: " · ")
        case "for_time":
            // A scheme says its rounds (21-15-9 is three); a count is each round's.
            if let scheme = repScheme(load) { return "\(scheme) reps for time\(atWeight(load))" }
            guard let rounds = load.targetRounds else { return "For time" }
            let each = roundCount(load).map { " × \($0)" } ?? ""
            return "\(rounds) round\(rounds == 1 ? "" : "s")\(each) for time"
        case "amrap_movement":
            // A movement of an AMRAP's or a for-time piece's round.
            return (roundCount(load) ?? "") + atWeight(load)
        case "distance":
            return load.distanceKm.map { "\(kilograms($0)) km" } ?? "Distance"
        case "static_hold":
            let sets = load.sets.map { "\($0)×" } ?? ""
            let secs = load.holdSeconds.map { "\($0)s" } ?? "?"
            return "\(sets)\(secs) hold"
        default:
            return ""
        }
    }

    /// Reps round by round as the sources write them: [21, 15, 9] → "21-15-9".
    nonisolated static func repScheme(_ load: ProgramLoad) -> String? {
        guard case .array(let items)? = load.extra["rep_scheme"] else { return nil }
        let counts = items.compactMap { item -> Int? in
            if case .int(let n) = item { return n }
            return nil
        }
        return counts.isEmpty ? nil : counts.map(String.init).joined(separator: "-")
    }

    /// One round's own count: "21-15-9 reps", "5 reps", or a run's "0.4 km";
    /// nil when the source gives none (Nicole's max pull-ups).
    nonisolated static func roundCount(_ load: ProgramLoad) -> String? {
        if let scheme = repScheme(load) { return "\(scheme) reps" }
        if case .int(let n)? = load.extra["reps_per_round"] { return "\(n) reps" }
        if let km = load.distanceKm {
            return (km.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(km)) : String(km)) + " km"
        }
        if case .int(let m)? = load.extra["distance_m"] { return "\(m) m" }
        return nil
    }

    /// " @ 22.5 kg" where a round's movement carries a fixed weight (a scaled
    /// Rx load, src/level_scaling.py); "" otherwise.
    nonisolated static func atWeight(_ load: ProgramLoad) -> String {
        load.weightKg.map { " @ \(kilograms($0)) kg" } ?? ""
    }

    /// "Scaled for Novice · Rx 21-15-9 reps · 30 kg": a prescription done at
    /// the athlete's share of what is written (src/level_scaling.py), read from
    /// the load's `rx` (the written values) and `level_scaled`; nil when it is
    /// done as written. The web's lib/levelScaling.ts says the same.
    nonisolated static func scaledText(_ ea: ProgramExerciseAssignment) -> String? {
        guard case .object(let rx)? = ea.load.extra["rx"],
              case .object(let how)? = ea.load.extra["level_scaled"],
              case .string(let level)? = how["level"] else { return nil }
        func number(_ key: String) -> Double? {
            switch rx[key] {
            case .int(let n)?: return Double(n)
            case .double(let d)?: return d
            default: return nil
            }
        }
        var parts: [String] = []
        if case .array(let items)? = rx["rep_scheme"] {
            let counts = items.compactMap { item -> Int? in if case .int(let n) = item { return n }; return nil }
            if !counts.isEmpty { parts.append(counts.map(String.init).joined(separator: "-") + " reps") }
        }
        if let n = number("reps_per_round") { parts.append("\(Int(n)) reps") }
        if let sets = number("sets") { parts.append("\(Int(sets)) sets") }
        if let reps = number("reps") { parts.append("\(Int(reps)) reps") }
        if let min = number("time_minutes") ?? number("duration_minutes") { parts.append("\(Int(min)) min") }
        if let secs = number("hold_seconds") ?? number("work_sec") { parts.append("\(Int(secs)) s") }
        if let km = number("distance_km") { parts.append("\(kilograms(km)) km") }
        if let m = number("distance_m") { parts.append("\(Int(m)) m") }
        if let kg = number("weight_kg") { parts.append("\(kilograms(kg)) kg") }
        let label = level.prefix(1).uppercased() + level.dropFirst()
        return (["Scaled for \(label)"] + (parts.isEmpty ? [] : ["Rx " + parts.joined(separator: " · ")]))
            .joined(separator: " · ")
    }

    /// "In place of Pull-Up (Overhand)": the written movement a scale stands
    /// for (the server's `scaled_from_name`); nil for the written movement.
    nonisolated static func scaledFromText(_ ea: ProgramExerciseAssignment) -> String? {
        guard case .string(let id)? = ea.extra["scaled_from"] else { return nil }
        if case .string(let name)? = ea.extra["scaled_from_name"] { return "In place of \(name)" }
        return "In place of \(id)"
    }

    /// 80 → "80", 82.5 → "82.5": a whole number never shows a ".0".
    nonisolated static func kilograms(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
