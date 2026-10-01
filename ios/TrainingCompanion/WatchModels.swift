import Foundation

// Shared between iOS and watchOS targets.
// Add this file to both the TrainingCompanion and TrainingCompanionWatch targets in Xcode.

// MARK: - Server-side program (decoded from GET /api/user/program)

struct ServerProgram: Codable {
    let currentProgram: GeneratedProgram?
    let programStartDate: String?   // "YYYY-MM-DD"
    let eventDate: String?
    let sourceGoalIds: [String]
    /// Opaque revision of the copy this was read from. Echoed back on save so the
    /// server can reject a write based on a stale read (409) instead of letting
    /// this phone overwrite a program generated elsewhere since.
    let revision: String?
    /// Which archived program version the stored program currently is.
    ///
    /// Response-only, like `revision`: the server derives it on read and it is
    /// never sent back. It is what tells a match on *this* week 3 Monday from
    /// one recorded against a plan that has since been replaced — a session key
    /// is program-relative and means a different session in every plan.
    let programVersionId: String?

    init(currentProgram: GeneratedProgram?, programStartDate: String?,
         eventDate: String?, sourceGoalIds: [String], revision: String? = nil,
         programVersionId: String? = nil) {
        self.currentProgram = currentProgram
        self.programStartDate = programStartDate
        self.eventDate = eventDate
        self.sourceGoalIds = sourceGoalIds
        self.revision = revision
        self.programVersionId = programVersionId
    }
}

struct GeneratedProgram: Codable {
    let weeks: [ProgramWeek]
}

struct ProgramWeek: Codable {
    let weekNumber: Int
    let weekInPhase: Int?
    let isDeload: Bool
    let phase: String
    // Keys are day names: "Monday" … "Sunday"
    let schedule: [String: [ProgramSession]]

    enum CodingKeys: String, CodingKey {
        case weekNumber  = "week_number"
        case weekInPhase = "week_in_phase"
        case isDeload    = "is_deload"
        case phase
        case schedule
    }
}

struct ProgramSession: Codable {
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

struct ProgramArchetype: Codable {
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

struct ProgramExerciseAssignment: Codable {
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

    init(exercise: ProgramExercise?, load: ProgramLoad, slotRole: String?, slotType: String?,
         restSec: Int?, meta: Bool, injurySkip: Bool, loadNote: String?, notes: String?) {
        self.exercise = exercise
        self.load = load
        self.slotRole = slotRole
        self.slotType = slotType
        self.restSec = restSec
        self.meta = meta
        self.injurySkip = injurySkip
        self.loadNote = loadNote
        self.notes = notes
    }

    /// The server writes `meta` and `injury_skip` on every assignment, but a
    /// copy that has been through another client, or a substitute alternative,
    /// may not carry them; absent means false, not an undecodable session.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exercise   = try c.decodeIfPresent(ProgramExercise.self, forKey: .exercise)
        load       = try c.decodeIfPresent(ProgramLoad.self, forKey: .load) ?? ProgramLoad.empty
        slotRole   = try c.decodeIfPresent(String.self, forKey: .slotRole)
        slotType   = try c.decodeIfPresent(String.self, forKey: .slotType)
        restSec    = try c.decodeIfPresent(Int.self, forKey: .restSec)
        meta       = try c.decodeIfPresent(Bool.self, forKey: .meta) ?? false
        injurySkip = try c.decodeIfPresent(Bool.self, forKey: .injurySkip) ?? false
        loadNote   = try c.decodeIfPresent(String.self, forKey: .loadNote)
        notes      = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct ProgramExercise: Codable {
    let id: String
    let name: String
    let category: String?
    let notes: String?
}

/// Flexible load struct — not all fields are present for every slot_type.
struct ProgramLoad: Codable {
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

    /// A slot with no prescription yet (an unfilled or coverage-gap entry).
    static let empty = ProgramLoad(sets: nil, reps: nil, weightKg: nil, targetRpe: nil,
                                   durationMinutes: nil, zoneTarget: nil, timeMinutes: nil,
                                   targetRounds: nil, format: nil, holdSeconds: nil,
                                   distanceKm: nil, intensity: nil)

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
struct AnyCodable: Codable {
    let stringValue: String?
    let intValue: Int?

    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }

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

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let i = intValue { try c.encode(i) }
        else if let s = stringValue { try c.encode(s) }
        else { try c.encodeNil() }
    }
}

// MARK: - Generate session request (POST /api/sessions/generate)

struct GenerateSessionConstraints: Encodable {
    let sessionTimeMinutes: Int
    let fatigueState: String
    enum CodingKeys: String, CodingKey {
        case sessionTimeMinutes = "session_time_minutes"
        case fatigueState       = "fatigue_state"
    }
}

struct GenerateSessionRequest: Encodable {
    let primarySources: [String]
    let modality: String
    let phase: String
    let weekInPhase: Int
    let isDeload: Bool
    let constraints: GenerateSessionConstraints
    let archetypeId: String?
    enum CodingKeys: String, CodingKey {
        case primarySources = "primary_sources"
        case modality, phase
        case weekInPhase    = "week_in_phase"
        case isDeload       = "is_deload"
        case constraints
        case archetypeId    = "archetype_id"
    }
}

// MARK: - Save program payload (PUT /api/user/program)

// Top-level keys must be camelCase to match the web frontend's ServerProgram format.
// The server stores and returns exactly what was PUT, so mismatched case causes
// ServerProgram (which has no CodingKeys, expects camelCase) to decode as nil.
struct UserProgramSavePayload: Encodable {
    let currentProgram: GeneratedProgram?
    let programStartDate: String?
    let eventDate: String?
    let sourceGoalIds: [String]
    let sourceGoalWeights: [String: Double]
    /// Revision this edit was based on; the server rejects the write with 409 if
    /// the stored program has moved on.
    let baseRevision: String?
}

// MARK: - Watch payload (sent from iPhone to Watch via WCSession)

struct WatchSession: Codable, Identifiable, Hashable {
    var id: String { sessionId }
    let sessionId: String           // "\(weekNumber)-\(dayName)-\(sessionIndex)"
    let modalityId: String
    let archetypeName: String
    let estimatedMinutes: Int
    let isDeload: Bool
    let exercises: [WatchExercise]
}

struct WatchExercise: Codable, Hashable {
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

/// Compact HR sample — uses integer second offsets from startedAt to save ~20 bytes/sample
/// versus full ISO timestamps. Expanded back to ISO on the iPhone before sending to the API.
struct HRSamplePoint: Codable {
    let t: Int   // seconds from session startedAt
    let b: Int   // bpm
}

/// Compact GPS point with optional altitude and HR at that moment.
struct GPSTrackPoint: Codable {
    let lat: Double
    let lng: Double
    let alt: Double?
    let t: Int      // seconds from session startedAt
    let b: Int?     // bpm at this point (nil if no HR sample close in time)
}

/// Per-exercise time window with HR summary, used to correlate bio data to specific exercises.
struct ExerciseTimelineEntry: Codable {
    let exerciseId: String
    let startOffset: Int    // seconds from startedAt — when the first set of this exercise began
    let endOffset: Int      // seconds from startedAt — when the exercise was marked complete
    let avgHRDuring: Int?   // mean bpm during [startOffset, endOffset] from hrSamples
}

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
    // Rich bio / movement data (nil for indoor/strength sessions without GPS)
    let hrSamples: [HRSamplePoint]?
    let gpsTrack: [GPSTrackPoint]?
    let distanceMeters: Double?
    let elevationGainMeters: Double?
    let cadenceAvg: Double?
    let paceSecsPerKm: Double?
    let exerciseTimeline: [ExerciseTimelineEntry]?
}

struct WatchSetLog: Codable {
    let setIndex: Int
    let repsActual: Int?
    let weightKg: Double?
    let rpe: Int?
    let completed: Bool
    let durationSeconds: Int?
    let startOffset: Int?   // seconds from session startedAt when this set began
    let endOffset: Int?     // seconds from session startedAt when this set was logged
}

// MARK: - Watch sync extras (iPhone → Watch, appended to today_sessions payload)

/// Compact per-day overview for the "This Week" section on the Watch.
struct WeeklyOverviewDay: Codable {
    let dayName: String        // "Monday" … "Sunday"
    let sessionCount: Int
    let modalityIds: [String]  // in order (empty = rest day)
}

/// Derived readiness signal sent from iPhone (based on HRV + resting HR vs. 30-day baseline).
struct ReadinessInfo: Codable {
    let score: Double           // 0.0 – 1.0
    let signal: String          // "green" | "yellow" | "red"
    let restingHR: Int?
    let hrv: Int?               // ms, rounded
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
