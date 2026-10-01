import Foundation

// The two program edits that used to need a whole-session regenerate or had
// no mutation at all: swapping one exercise for an alternative that fits the
// same slot (POST /api/exercises/substitute), and applying one of the
// progression review's suggested adjustments to the stored weeks
// (POST /api/programs/adjust). Both go through the server so the phone and
// the web apply the same rules.

// MARK: - Exercise substitution

/// What the selector needs to rank alternatives for one slot — the same
/// package, equipment, injury and level rules a generate applies.
struct SubstituteRequest: Encodable {
    struct Constraints: Encodable {
        let trainingLevel: String
        let equipment: [String]
        let injuryFlags: [String]
        let sessionTimeMinutes: Int

        enum CodingKeys: String, CodingKey {
            case trainingLevel      = "training_level"
            case equipment
            case injuryFlags        = "injury_flags"
            case sessionTimeMinutes = "session_time_minutes"
        }
    }

    let archetypeId: String
    let slotRole: String
    let exerciseId: String
    let modality: String
    let constraints: Constraints
    let philosophyIds: [String]
    let phase: String
    let weekInPhase: Int
    let isDeload: Bool
    /// Exercise ids already in the session; the server never offers these.
    let exclude: [String]
    var limit: Int = 8

    enum CodingKeys: String, CodingKey {
        case archetypeId   = "archetype_id"
        case slotRole      = "slot_role"
        case exerciseId    = "exercise_id"
        case modality, constraints
        case philosophyIds = "philosophy_ids"
        case phase
        case weekInPhase   = "week_in_phase"
        case isDeload      = "is_deload"
        case exclude, limit
    }
}

/// One ranked alternative: a complete assignment, with its load worked out for
/// the week, so a pick replaces the entry in place.
struct ExerciseAlternative: Decodable, Identifiable {
    let assignment: ProgramExerciseAssignment
    let score: Double
    let reasons: [String]

    var id: String { assignment.exercise?.id ?? "slot-\(score)" }
}

struct SubstituteResponse: Decodable {
    let alternatives: [ExerciseAlternative]
    /// Set on 422, when nothing fits the slot under the program's rules.
    let detail: String?
}

// MARK: - Applying a progression adjustment

struct AdjustRequest: Encodable {
    struct Adjustment: Encodable {
        let type: String
        let target: String
        let magnitude: String?
    }

    let adjustment: Adjustment
    /// Array index of the first week to change; nil lets the server use the
    /// calendar week the athlete is in.
    let fromWeekIndex: Int?
    /// The revision this phone read; the server answers 409 if the stored
    /// program has moved on, like PUT /api/user/program.
    let baseRevision: String?

    enum CodingKeys: String, CodingKey {
        case adjustment
        case fromWeekIndex = "from_week_index"
        case baseRevision
    }
}

/// What the server changed. `weeks` are array indices, not week numbers.
struct AppliedAdjustment: Decodable, Equatable {
    let type: String
    let fromWeekIndex: Int
    let weeks: [Int]
    let exercises: Int

    enum CodingKeys: String, CodingKey {
        case type
        case fromWeekIndex = "from_week_index"
        case weeks, exercises
    }

    /// "Applied to 4 exercises in weeks 3, 4." — `weekNumber` maps an array
    /// index to the number the program shows for it, because a regenerated
    /// block can be numbered from its absolute program week.
    func summary(weekNumber: (Int) -> Int?) -> String {
        guard exercises > 0 else {
            return "Nothing in the remaining weeks matched this adjustment."
        }
        let numbers = weeks.map { weekNumber($0) ?? ($0 + 1) }.map(String.init)
        let noun = exercises == 1 ? "exercise" : "exercises"
        let weekNoun = numbers.count == 1 ? "week" : "weeks"
        return "Applied to \(exercises) \(noun) in \(weekNoun) \(numbers.joined(separator: ", "))."
    }
}

struct AdjustResult: Decodable {
    let saved: Bool
    let revision: String?
    let programVersionId: String?
    let applied: AppliedAdjustment
    /// The saved envelope, so the client replaces its copy without a second
    /// round trip. Tolerated as absent: a shape this phone cannot decode means
    /// a reload, not a failure.
    let program: ServerProgram?

    enum CodingKeys: String, CodingKey {
        case saved, revision, programVersionId, applied, program
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        saved            = try c.decodeIfPresent(Bool.self, forKey: .saved) ?? false
        revision         = try c.decodeIfPresent(String.self, forKey: .revision)
        programVersionId = try c.decodeIfPresent(String.self, forKey: .programVersionId)
        applied          = try c.decode(AppliedAdjustment.self, forKey: .applied)
        program          = try? c.decodeIfPresent(ServerProgram.self, forKey: .program)
    }
}

// MARK: - How an adjustment reads on screen

extension ProgressionAdjustment {
    /// The types the server applies to the stored weeks. `rebuild_habit` is
    /// about the athlete's consistency, not the plan, and stays advice.
    static let appliableTypes: Set<String> = [
        "hold_load", "reduce_volume_10pct", "early_deload", "increase_increment",
    ]

    var isAppliable: Bool { Self.appliableTypes.contains(type) }

    var label: String {
        switch type {
        case "hold_load":           return "Hold the load"
        case "reduce_volume_10pct": return "Reduce volume 10%"
        case "early_deload":        return "Deload this week"
        case "increase_increment":  return "Raise the increment"
        case "rebuild_habit":       return "Rebuild the habit"
        default:                    return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The tracker names targets as "all", "schedule", or a list of exercise
    /// names; only the last is worth showing next to the label.
    var targetLabel: String? {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !["all", "schedule"].contains(t.lowercased()) else { return nil }
        return t
    }
}
