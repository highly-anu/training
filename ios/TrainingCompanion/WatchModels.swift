import Foundation

// Shared between iOS and watchOS targets.
// Add this file to both the TrainingCompanion and TrainingCompanionWatch targets in Xcode.

// MARK: - Server-side program (decoded from GET /api/user/program)

struct ServerProgram: Codable {
    let currentProgram: GeneratedProgram?
    let programStartDate: String?   // "YYYY-MM-DD"
    let eventDate: String?
    let sourceGoalIds: [String]
    /// A blend's weights. This app used to send `[:]` on every save, which
    /// wiped them for the web.
    let sourceGoalWeights: [String: Double]
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
    /// Envelope keys this app does not model, carried back on save untouched.
    var extra: [String: JSONValue] = [:]

    init(currentProgram: GeneratedProgram?, programStartDate: String?,
         eventDate: String?, sourceGoalIds: [String], sourceGoalWeights: [String: Double] = [:],
         revision: String? = nil, programVersionId: String? = nil, extra: [String: JSONValue] = [:]) {
        self.currentProgram = currentProgram
        self.programStartDate = programStartDate
        self.eventDate = eventDate
        self.sourceGoalIds = sourceGoalIds
        self.sourceGoalWeights = sourceGoalWeights
        self.revision = revision
        self.programVersionId = programVersionId
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case currentProgram, programStartDate, eventDate, sourceGoalIds, sourceGoalWeights, revision, programVersionId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentProgram = try c.decodeIfPresent(GeneratedProgram.self, forKey: .currentProgram)
        programStartDate = try c.decodeIfPresent(String.self, forKey: .programStartDate)
        eventDate = try c.decodeIfPresent(String.self, forKey: .eventDate)
        sourceGoalIds = try c.decodeIfPresent([String].self, forKey: .sourceGoalIds) ?? []
        sourceGoalWeights = (try? c.decodeIfPresent([String: Double].self, forKey: .sourceGoalWeights)) ?? [:]
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
        programVersionId = try c.decodeIfPresent(String.self, forKey: .programVersionId)
        extra = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(currentProgram, forKey: .currentProgram)
        try c.encodeIfPresent(programStartDate, forKey: .programStartDate)
        try c.encodeIfPresent(eventDate, forKey: .eventDate)
        try c.encode(sourceGoalIds, forKey: .sourceGoalIds)
        try c.encode(sourceGoalWeights, forKey: .sourceGoalWeights)
        try c.encodeIfPresent(revision, forKey: .revision)
        try c.encodeIfPresent(programVersionId, forKey: .programVersionId)
        try JSONValue.encode(extra, to: encoder)
    }
}

/// The stored program. This app models the weeks; everything else the
/// generator wrote beside them — `goal`, `constraints`, `validation`,
/// `coverage_report`, `volume_summary` — rides in `extra` and is sent back on
/// save. Until it did, every save from the phone (a move, a swap, marking a
/// session complete) stripped them, along with each exercise's `slot` and
/// every key below that this model does not name.
struct GeneratedProgram: Codable {
    let weeks: [ProgramWeek]
    var extra: [String: JSONValue] = [:]

    init(weeks: [ProgramWeek], extra: [String: JSONValue] = [:]) {
        self.weeks = weeks
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case weeks }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weeks = try c.decode([ProgramWeek].self, forKey: .weeks)
        extra = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weeks, forKey: .weeks)
        try JSONValue.encode(extra, to: encoder)
    }
}

struct ProgramWeek: Codable {
    let weekNumber: Int
    let weekInPhase: Int?
    let isDeload: Bool
    let phase: String
    // Keys are day names: "Monday" … "Sunday"
    let schedule: [String: [ProgramSession]]
    var extra: [String: JSONValue] = [:]

    init(weekNumber: Int, weekInPhase: Int?, isDeload: Bool, phase: String,
         schedule: [String: [ProgramSession]], extra: [String: JSONValue] = [:]) {
        self.weekNumber = weekNumber
        self.weekInPhase = weekInPhase
        self.isDeload = isDeload
        self.phase = phase
        self.schedule = schedule
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case weekNumber  = "week_number"
        case weekInPhase = "week_in_phase"
        case isDeload    = "is_deload"
        case phase
        case schedule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekNumber = try c.decode(Int.self, forKey: .weekNumber)
        weekInPhase = try c.decodeIfPresent(Int.self, forKey: .weekInPhase)
        isDeload = try c.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
        phase = try c.decodeIfPresent(String.self, forKey: .phase) ?? "base"
        schedule = try c.decodeIfPresent([String: [ProgramSession]].self, forKey: .schedule) ?? [:]
        extra = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekNumber, forKey: .weekNumber)
        try c.encodeIfPresent(weekInPhase, forKey: .weekInPhase)
        try c.encode(isDeload, forKey: .isDeload)
        try c.encode(phase, forKey: .phase)
        try c.encode(schedule, forKey: .schedule)
        try JSONValue.encode(extra, to: encoder)
    }
}

struct ProgramSession: Codable {
    let modality: String
    let archetype: ProgramArchetype?
    let isDeload: Bool
    let exercises: [ProgramExerciseAssignment]
    /// `provenance`, `unfilled_slots`, `coverage_gap`… — kept, not modelled.
    var extra: [String: JSONValue] = [:]

    init(modality: String, archetype: ProgramArchetype?, isDeload: Bool,
         exercises: [ProgramExerciseAssignment], extra: [String: JSONValue] = [:]) {
        self.modality = modality
        self.archetype = archetype
        self.isDeload = isDeload
        self.exercises = exercises
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case modality
        case archetype
        case isDeload  = "is_deload"
        case exercises
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modality = try c.decode(String.self, forKey: .modality)
        archetype = try c.decodeIfPresent(ProgramArchetype.self, forKey: .archetype)
        isDeload = try c.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
        exercises = try c.decodeIfPresent([ProgramExerciseAssignment].self, forKey: .exercises) ?? []
        extra = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modality, forKey: .modality)
        try c.encodeIfPresent(archetype, forKey: .archetype)
        try c.encode(isDeload, forKey: .isDeload)
        try c.encode(exercises, forKey: .exercises)
        try JSONValue.encode(extra, to: encoder)
    }
}

struct ProgramArchetype: Codable {
    let id: String
    let name: String
    let durationEstimateMinutes: Int?
    let notes: String?
    /// The archetype's slots, modality, category… — the swap endpoint reads
    /// them on the server, so they must survive a save.
    var extra: [String: JSONValue] = [:]

    init(id: String, name: String, durationEstimateMinutes: Int?, notes: String?, extra: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.durationEstimateMinutes = durationEstimateMinutes
        self.notes = notes
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case name
        case durationEstimateMinutes = "duration_estimate_minutes"
        case notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        durationEstimateMinutes = try c.decodeIfPresent(Int.self, forKey: .durationEstimateMinutes)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        extra = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(durationEstimateMinutes, forKey: .durationEstimateMinutes)
        try c.encodeIfPresent(notes, forKey: .notes)
        try JSONValue.encode(extra, to: encoder)
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
    /// `slot`, `slot_index`, `coverage_gap`… — kept, not modelled.
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
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
         restSec: Int?, meta: Bool, injurySkip: Bool, loadNote: String?, notes: String?,
         extra: [String: JSONValue] = [:]) {
        self.exercise = exercise
        self.load = load
        self.slotRole = slotRole
        self.slotType = slotType
        self.restSec = restSec
        self.meta = meta
        self.injurySkip = injurySkip
        self.loadNote = loadNote
        self.notes = notes
        self.extra = extra
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
        extra      = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(exercise, forKey: .exercise)
        try c.encode(load, forKey: .load)
        try c.encodeIfPresent(slotRole, forKey: .slotRole)
        try c.encodeIfPresent(slotType, forKey: .slotType)
        try c.encodeIfPresent(restSec, forKey: .restSec)
        try c.encode(meta, forKey: .meta)
        try c.encode(injurySkip, forKey: .injurySkip)
        try c.encodeIfPresent(loadNote, forKey: .loadNote)
        try c.encodeIfPresent(notes, forKey: .notes)
        try JSONValue.encode(extra, to: encoder)
    }
}

struct ProgramExercise: Codable {
    let id: String
    let name: String
    let category: String?
    let notes: String?
    /// `movement_patterns`, `equipment`, `requires`, `unlocks`, `package`… —
    /// the web and the swap endpoint read them.
    var extra: [String: JSONValue] = [:]

    init(id: String, name: String, category: String?, notes: String?, extra: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.category = category
        self.notes = notes
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case id, name, category, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        category = try c.decodeIfPresent(String.self, forKey: .category)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        extra = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(notes, forKey: .notes)
        try JSONValue.encode(extra, to: encoder)
    }
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
    /// Prescription keys this app does not display (`focus`, `rpm_target`…).
    var extra: [String: JSONValue] = [:]

    init(sets: Int?, reps: AnyCodable?, weightKg: Double?, targetRpe: Int?, durationMinutes: Int?,
         zoneTarget: String?, timeMinutes: Int?, targetRounds: Int?, format: String?, holdSeconds: Int?,
         distanceKm: Double?, intensity: String?, extra: [String: JSONValue] = [:]) {
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        self.targetRpe = targetRpe
        self.durationMinutes = durationMinutes
        self.zoneTarget = zoneTarget
        self.timeMinutes = timeMinutes
        self.targetRounds = targetRounds
        self.format = format
        self.holdSeconds = holdSeconds
        self.distanceKm = distanceKm
        self.intensity = intensity
        self.extra = extra
    }

    /// A slot with no prescription yet (an unfilled or coverage-gap entry).
    static let empty = ProgramLoad(sets: nil, reps: nil, weightKg: nil, targetRpe: nil,
                                   durationMinutes: nil, zoneTarget: nil, timeMinutes: nil,
                                   targetRounds: nil, format: nil, holdSeconds: nil,
                                   distanceKm: nil, intensity: nil)

    enum CodingKeys: String, CodingKey, CaseIterable {
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sets = try c.decodeIfPresent(Int.self, forKey: .sets)
        reps = try c.decodeIfPresent(AnyCodable.self, forKey: .reps)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        targetRpe = try c.decodeIfPresent(Int.self, forKey: .targetRpe)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        zoneTarget = try c.decodeIfPresent(String.self, forKey: .zoneTarget)
        timeMinutes = try c.decodeIfPresent(Int.self, forKey: .timeMinutes)
        targetRounds = try c.decodeIfPresent(Int.self, forKey: .targetRounds)
        format = try c.decodeIfPresent(String.self, forKey: .format)
        holdSeconds = try c.decodeIfPresent(Int.self, forKey: .holdSeconds)
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        intensity = try c.decodeIfPresent(String.self, forKey: .intensity)
        extra = try JSONValue.extras(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sets, forKey: .sets)
        try c.encodeIfPresent(reps, forKey: .reps)
        try c.encodeIfPresent(weightKg, forKey: .weightKg)
        try c.encodeIfPresent(targetRpe, forKey: .targetRpe)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(zoneTarget, forKey: .zoneTarget)
        try c.encodeIfPresent(timeMinutes, forKey: .timeMinutes)
        try c.encodeIfPresent(targetRounds, forKey: .targetRounds)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encodeIfPresent(holdSeconds, forKey: .holdSeconds)
        try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try c.encodeIfPresent(intensity, forKey: .intensity)
        try JSONValue.encode(extra, to: encoder)
    }
}

// MARK: - Opaque JSON (what this app does not model but must not drop)

struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init(_ string: String) { stringValue = string; intValue = nil }
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

/// A JSON value kept as it came. Integers stay integers — `AnyCodable`
/// re-encodes a decoded number through Double, which is why the server's
/// version skeleton hash leaves loads out — so a round trip through this type
/// is byte-for-byte for the keys it carries.
enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Every key of the object being decoded that the model does not name.
    static func extras(from decoder: Decoder, excluding known: [String]) throws -> [String: JSONValue] {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        var out: [String: JSONValue] = [:]
        for key in c.allKeys where !known.contains(key.stringValue) {
            out[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
        }
        return out
    }

    /// Writes the kept keys beside the modelled ones; both containers share
    /// the same object.
    static func encode(_ extras: [String: JSONValue], to encoder: Encoder) throws {
        guard !extras.isEmpty else { return }
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in extras {
            try c.encode(value, forKey: AnyCodingKey(key))
        }
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
    /// Envelope keys read from the server and sent back unchanged.
    var extra: [String: JSONValue] = [:]

    init(currentProgram: GeneratedProgram?, programStartDate: String?, eventDate: String?,
         sourceGoalIds: [String], sourceGoalWeights: [String: Double], baseRevision: String?,
         extra: [String: JSONValue] = [:]) {
        self.currentProgram = currentProgram
        self.programStartDate = programStartDate
        self.eventDate = eventDate
        self.sourceGoalIds = sourceGoalIds
        self.sourceGoalWeights = sourceGoalWeights
        self.baseRevision = baseRevision
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey {
        case currentProgram, programStartDate, eventDate, sourceGoalIds, sourceGoalWeights, baseRevision
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(currentProgram, forKey: .currentProgram)
        try c.encodeIfPresent(programStartDate, forKey: .programStartDate)
        try c.encodeIfPresent(eventDate, forKey: .eventDate)
        try c.encode(sourceGoalIds, forKey: .sourceGoalIds)
        try c.encode(sourceGoalWeights, forKey: .sourceGoalWeights)
        try c.encodeIfPresent(baseRevision, forKey: .baseRevision)
        // revision / programVersionId are response-only and never in `extra`.
        try JSONValue.encode(extra, to: encoder)
    }
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

struct WatchSetLog: Codable, Equatable {
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
