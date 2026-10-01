import Foundation

/// The one place a prescription is turned into words on the phone.
///
/// `SessionDetailView` had this as private helpers; the swap sheet needs the
/// same string for each alternative, and two copies of "3×5 @ 80 kg" drift
/// (design system §1.7). The watch keeps its own `loadDescription`, which the
/// phone pre-formats for it in `WatchSessionManager`.
enum LoadFormat {

    static let knownSlotTypes = ["sets_reps", "time_domain", "skill_practice", "emom",
                                 "amrap", "amrap_movement", "for_time", "distance", "static_hold"]

    /// Passes a known `slot_type` through; infers one from the load's fields
    /// for custom archetypes that omit it. Order matters.
    static func resolvedSlotType(_ ea: ProgramExerciseAssignment) -> String {
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
                return "\(min) min · \(rounds) rounds"
            }
            return load.format ?? "EMOM"
        case "amrap":
            return load.timeMinutes.map { "AMRAP \($0) min" } ?? "AMRAP"
        case "for_time":
            return load.targetRounds.map { "\($0) rounds for time" } ?? "For time"
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

    /// 80 → "80", 82.5 → "82.5": a whole number never shows a ".0".
    static func kilograms(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
