import Foundation

// Shared between iOS and watchOS targets.
// Add this file to both the TrainingCompanion and TrainingCompanionWatch targets in Xcode.

// MARK: - Server-side program (decoded from GET /api/user/program)

struct ServerProgram: Decodable {
    let currentProgram: GeneratedProgram?
    let programStartDate: String?   // "YYYY-MM-DD"
    let eventDate: String?
    let sourceGoalIds: [String]
}

struct GeneratedProgram: Decodable {
    let weeks: [ProgramWeek]
}

struct ProgramWeek: Decodable {
    let weekNumber: Int
    let isDeload: Bool
    let phase: String
    // Keys are day names: "Monday" … "Sunday"
    let schedule: [String: [ProgramSession]]

    enum CodingKeys: String, CodingKey {
        case weekNumber = "week_number"
        case isDeload   = "is_deload"
        case phase
        case schedule
    }
}

struct ProgramSession: Decodable {
    let modality: String
    let archetype: ProgramArchetype?
    let isDeload: Bool
    let exercises: [ProgramExerciseAssignment]

    enum CodingKeys: String, CodingKey {
        case modality
        case archetype
        case isDeload  = "is_deload"
        case exercises
    }
}

struct ProgramArchetype: Decodable {
    let id: String
    let name: String
    let durationEstimateMinutes: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case durationEstimateMinutes = "duration_estimate_minutes"
        case notes
    }
}

struct ProgramExerciseAssignment: Decodable {
    let exercise: ProgramExercise?
    let load: ProgramLoad
    let slotRole: String?
    let slotType: String?
    let restSec: Int?
    let meta: Bool
    let injurySkip: Bool
    let loadNote: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case exercise
        case load
        case slotRole   = "slot_role"
        case slotType   = "slot_type"
        case restSec    = "rest_sec"
        case meta
        case injurySkip = "injury_skip"
        case loadNote   = "load_note"
        case notes
    }
}

struct ProgramExercise: Decodable {
    let id: String
    let name: String
    let category: String?
    let notes: String?
}

/// Flexible load struct — not all fields are present for every slot_type.
struct ProgramLoad: Decodable {
    let sets: Int?
    let reps: AnyCodable?           // Int or String ("8-10")
    let weightKg: Double?
    let targetRpe: Int?
    let durationMinutes: Int?
    let zoneTarget: String?
    let timeMinutes: Int?
    let targetRounds: Int?
    let format: String?
    let holdSeconds: Int?
    let distanceKm: Double?
    let intensity: String?

    enum CodingKeys: String, CodingKey {
        case sets
        case reps
        case weightKg        = "weight_kg"
        case targetRpe       = "target_rpe"
        case durationMinutes = "duration_minutes"
        case zoneTarget      = "zone_target"
        case timeMinutes     = "time_minutes"
        case targetRounds    = "target_rounds"
        case format
        case holdSeconds     = "hold_seconds"
        case distanceKm      = "distance_km"
        case intensity
    }
}

/// Lets us decode reps as either an Int or a String without throwing.
struct AnyCodable: Decodable {
    let stringValue: String?
    let intValue: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            intValue = i; stringValue = "\(i)"
        } else if let s = try? c.decode(String.self) {
            stringValue = s; intValue = Int(s)
        } else {
            intValue = nil; stringValue = nil
        }
    }

    var displayString: String { stringValue ?? "" }
}

// MARK: - Watch payload (sent from iPhone to Watch via WCSession)

struct WatchSession: Codable {
    let sessionId: String           // "\(weekNumber)-\(dayName)-\(sessionIndex)"
    let modalityId: String
    let archetypeName: String
    let estimatedMinutes: Int
    let isDeload: Bool
    let exercises: [WatchExercise]
}

struct WatchExercise: Codable {
    // Identity
    let exerciseId: String
    let name: String
    let slotType: String            // "sets_reps" | "time_domain" | "emom" | "amrap" | "for_time" | "distance" | "skill_practice" | "static_hold"
    let slotRole: String
    let isMeta: Bool

    // Display
    let loadDescription: String     // pre-formatted, e.g. "5×5 @ 100 kg"
    let loadNote: String?           // "+2.5 kg from last session"
    let coachingCue: String?        // slot notes preferred; falls back to exercise notes

    // Structured fields for screen/timer logic
    let sets: Int?
    let reps: String?               // "5" or "8-10"
    let weightKg: Double?
    let targetRpe: Int?
    let durationMinutes: Int?
    let zoneTarget: String?
    let timeMinutes: Int?
    let targetRounds: Int?
    let emomFormat: String?         // raw format string, e.g. "Tabata 8×20/10"
    let holdSeconds: Int?
    let distanceKm: Double?
    let restSeconds: Int?           // from slot rest_sec (or modality default)

    // Parsed zone bounds (1-indexed, matching frontend Z1-Z5 labels)
    let prescribedZoneLower: Int?
    let prescribedZoneUpper: Int?
}

// MARK: - Post-workout summary (Watch → iPhone → API)

struct WatchWorkoutSummary: Codable {
    let sessionId: String
    let date: String                // "YYYY-MM-DD"
    let startedAt: String           // ISO 8601
    let endedAt: String
    let durationMinutes: Int
    let avgHR: Int?
    let peakHR: Int?
    let setLogs: [String: [WatchSetLog]]    // exerciseId → sets
    let exercisesCompleted: Int
    let source: String              // always "apple_watch_live"
}

struct WatchSetLog: Codable {
    let setIndex: Int
    let repsActual: Int?
    let weightKg: Double?
    let rpe: Int?
    let completed: Bool
    let durationSeconds: Int?
}

// MARK: - Slot-type resolution

extension WatchExercise {
    /// Canonical screen-selection key. Passes through known slot_type values;
    /// falls back to field-based inference for custom archetypes that omit slot_type.
    var resolvedSlotType: String {
        let known = ["sets_reps", "time_domain", "skill_practice", "emom",
                     "amrap", "amrap_movement", "for_time", "distance", "static_hold"]
        if known.contains(slotType) { return slotType }
        // Field-based inference — order matters
        if distanceKm    != nil { return "distance" }
        if holdSeconds   != nil { return "static_hold" }
        if emomFormat    != nil { return "emom" }
        if durationMinutes != nil { return "time_domain" }
        if timeMinutes != nil && targetRounds != nil { return "amrap" }
        if targetRounds  != nil { return "for_time" }
        return "sets_reps"
    }
}
