import Foundation

/// What the profile says now versus what the active program was built for —
/// the phone's copy of the web's `lib/programConstraintsDiff.ts`.
///
/// The program carries the constraints it was generated from (`constraints`
/// in `GeneratedProgram.extra`, kept since saves round-trip the envelope);
/// the profile moves on. Until the two were compared, the phone's only
/// regenerate replaced the whole program.
struct ConstraintDifference: Equatable, Identifiable {
    let field: String
    let label: String
    /// What the program was built for.
    let program: String
    /// What the profile says now.
    let profile: String
    var id: String { field }
}

enum ProgramConstraintsDiff {

    /// Days with at least one non-rest session; nil without a schedule.
    static func daysPerWeek(_ schedule: WeeklySchedule?) -> Int? {
        guard let schedule, !schedule.isEmpty else { return nil }
        return schedule.values.filter { d in
            [d.session1, d.session2, d.session3, d.session4].contains { $0 != .rest }
        }.count
    }

    static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    static func string(_ value: JSONValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }

    static func int(_ value: JSONValue?) -> Int? {
        switch value {
        case .int(let i)?: return i
        case .double(let d)?: return Int(d.rounded())
        default: return nil
        }
    }

    private static func setChange(from: [String], to: [String]) -> String {
        let added = Set(to).subtracting(from).count
        let removed = Set(from).subtracting(to).count
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if removed > 0 { parts.append("\(removed) removed") }
        return parts.isEmpty ? "unchanged" : parts.joined(separator: ", ")
    }

    /// `program` is the stored program's `constraints` object.
    static func differences(program: [String: JSONValue], profile: UserProfile) -> [ConstraintDifference] {
        guard !program.isEmpty else { return [] }
        var out: [ConstraintDifference] = []
        if let level = string(program["training_level"]), !profile.trainingLevel.isEmpty, level != profile.trainingLevel {
            out.append(ConstraintDifference(field: "training_level", label: "Training level",
                                            program: level, profile: profile.trainingLevel))
        }
        let equipment = strings(program["equipment"])
        if !profile.equipment.isEmpty, Set(equipment) != Set(profile.equipment) {
            out.append(ConstraintDifference(field: "equipment", label: "Equipment",
                                            program: "\(equipment.count) items",
                                            profile: setChange(from: equipment, to: profile.equipment)))
        }
        if let days = daysPerWeek(profile.weeklySchedule), days > 0,
           let planned = int(program["days_per_week"]), planned != days {
            out.append(ConstraintDifference(field: "days_per_week", label: "Days per week",
                                            program: String(planned), profile: String(days)))
        }
        let injuries = strings(program["injury_flags"])
        if Set(injuries) != Set(profile.injuryFlags) {
            out.append(ConstraintDifference(field: "injury_flags", label: "Injuries",
                                            program: "\(injuries.count) flagged",
                                            profile: setChange(from: injuries, to: profile.injuryFlags)))
        }
        return out
    }

    /// The program's constraints with the profile's current values applied,
    /// continuing the phase the regenerated week is in.
    static func merged(program: [String: JSONValue], profile: UserProfile,
                       weekInPhase: Int?, phase: String?) -> GenerateConstraints {
        var c = GenerateConstraints()
        c.trainingLevel = profile.trainingLevel.isEmpty
            ? (string(program["training_level"]) ?? c.trainingLevel) : profile.trainingLevel
        c.daysPerWeek = int(program["days_per_week"]) ?? c.daysPerWeek
        if let days = daysPerWeek(profile.weeklySchedule), days > 0 { c.daysPerWeek = days }
        c.sessionTimeMinutes = int(program["session_time_minutes"]) ?? c.sessionTimeMinutes
        let programEquipment = strings(program["equipment"])
        c.equipment = profile.equipment.isEmpty ? programEquipment : profile.equipment
        c.injuryFlags = profile.injuryFlags
        c.phase = phase ?? string(program["training_phase"])
        c.trainingPhase = c.phase
        c.periodizationWeek = weekInPhase
        return c
    }
}

/// Splicing a regenerated tail onto the weeks already behind the athlete —
/// what the web's `useRegenerateFromWeek` does on success.
enum Regeneration {
    /// Keeps `weeks[0..<start]`, appends the generated weeks, takes the
    /// generated program's goal, constraints, validation and coverage report,
    /// and drops `volume_summary` so the server recomputes it for the whole
    /// program on save.
    static func splice(current: GeneratedProgram, from start: Int, generated: GeneratedProgram) -> GeneratedProgram {
        let keep = max(0, min(start, current.weeks.count))
        var extra = current.extra
        for key in ["goal", "constraints", "validation", "coverage_report"] {
            if let value = generated.extra[key] { extra[key] = value }
        }
        extra.removeValue(forKey: "volume_summary")
        return GeneratedProgram(weeks: Array(current.weeks.prefix(keep)) + generated.weeks, extra: extra)
    }
}
