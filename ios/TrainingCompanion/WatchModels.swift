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

    // The methodology's own phase, which the server adds to every week it
    // generates. Read from `extra` so the keys round-trip untouched; absent on
    // weeks generated before philosophies owned their phases, where `phase`
    // (the kind) is all there is.
    var phaseId: String? { extra["phase_id"]?.stringValue }
    var phaseName: String? { extra["phase_name"]?.stringValue }
    var trackId: String? { extra["track_id"]?.stringValue }
    /// The framework that built this week (the phase's), round-tripped in `extra`.
    var frameworkId: String? { extra["framework"]?.stringValue }

    /// What to call this week's phase: the methodology's name for it, else
    /// the kind, capitalised.
    var phaseLabel: String {
        phaseName ?? phase.replacingOccurrences(of: "_", with: " ").capitalized
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

    /// The string this value holds, if it is one.
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
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
    /// The week's phase and framework (see `SubstituteRequest`).
    var phaseId: String? = nil
    var frameworkId: String? = nil
    enum CodingKeys: String, CodingKey {
        case primarySources = "primary_sources"
        case modality, phase
        case weekInPhase    = "week_in_phase"
        case isDeload       = "is_deload"
        case constraints
        case archetypeId    = "archetype_id"
        case phaseId        = "phase_id"
        case frameworkId    = "framework_id"
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

// MARK: - Watch payload (the server's day, relayed by the iPhone)

/// One session as `GET /user/today-session` encodes it for both watches
/// (`api.encode_watch_session`). The phone used to build these itself from
/// `/user/program`, with its own week and day maths, slot-type guesses and
/// load wording; now it forwards the server's.
struct WatchSession: Codable, Identifiable, Hashable {
    var id: String { sessionId }
    let sessionId: String           // "\(weekNumber)-\(dayName)-\(sessionIndex)"
    let modalityId: String
    let archetypeName: String
    let estimatedMinutes: Int
    let isDeload: Bool
    let exercises: [WatchExercise]
    /// Done on any device: a log with a completion time or a matched workout.
    var completed: Bool = false
    /// The package whose screens draw it (the archetype's owner), and those
    /// screens, keyed as each exercise's `screen` names them (`?spec=1`).
    var packageId: String? = nil
    var screens: [String: WatchScreenSpec]? = nil

    enum CodingKeys: String, CodingKey {
        case sessionId, modalityId, archetypeName, estimatedMinutes, isDeload, exercises, completed
        case packageId, screens
    }
}

extension WatchSession {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        modalityId = try c.decodeIfPresent(String.self, forKey: .modalityId) ?? ""
        archetypeName = try c.decodeIfPresent(String.self, forKey: .archetypeName) ?? modalityId
        estimatedMinutes = c.lenientInt(.estimatedMinutes) ?? 45
        isDeload = try c.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
        exercises = try c.decodeIfPresent([WatchExercise].self, forKey: .exercises) ?? []
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        packageId = try? c.decodeIfPresent(String.self, forKey: .packageId)
        // An odd spec costs the screens (each step falls back to its slot
        // type's), never the session.
        screens = try? c.decodeIfPresent([String: WatchScreenSpec].self, forKey: .screens)
    }

    /// The screen an exercise is drawn with (`WatchScreen.forExercise`).
    func screen(for exercise: WatchExercise) -> WatchScreen {
        WatchScreen.forExercise(slotType: exercise.slotType, key: exercise.screen, screens: screens)
    }
}

extension KeyedDecodingContainer {
    /// A count the YAML may write as 7.5 or "8": the whole day failed to
    /// decode over one such number when the phone forwarded it as JSON.
    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }
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

    /// What was done last time ("24kg × 10"), from today-session's `last`
    /// (src/last_time.py); nil on a first time.
    var lastTime: String? = nil

    /// A test's scored slot: the standard it measures, its best and the
    /// number for the next level, from today-session's `standard`; nil on
    /// every other step.
    var standard: WatchStandard? = nil

    // The rest of the server's exercise (`api._encode_watch_exercise`), for
    // the package's screens (WatchSpecText) — what the Garmin reads too.
    var category: String? = nil
    var movementPattern: String? = nil
    /// false: a unilateral movement, counted per side.
    var bilateral: Bool? = nil
    var targetRpm: Int? = nil
    var workSec: Int? = nil
    var intervalRestSec: Int? = nil
    var distanceM: Int? = nil
    var repsPerRound: Int? = nil
    var packLoadKg: Double? = nil
    var focus: String? = nil
    var parentSlotRole: String? = nil
    /// Bells held at once; the server does not send it yet (demo data does).
    var bells: Int? = nil
    /// A hand switch inside a work period; demo data only for now.
    var switchAtSec: Int? = nil
    /// A rest that ends when HR drops below this; demo data only for now.
    var restUntilHr: Int? = nil
    /// The key of its screen in the session's `screens`.
    var screen: String? = nil

    enum CodingKeys: String, CodingKey {
        case exerciseId, name, slotType, slotRole, isMeta, loadDescription, loadNote, coachingCue
        case sets, reps, weightKg, targetRpe, durationMinutes, zoneTarget, timeMinutes, targetRounds
        case emomFormat, holdSeconds, distanceKm, restSeconds, prescribedZoneLower, prescribedZoneUpper
        case lastTime = "last", standard
        case category, movementPattern, bilateral, targetRpm, workSec, intervalRestSec, distanceM
        case repsPerRound, packLoadKg, focus, parentSlotRole, bells, switchAtSec, restUntilHr, screen
    }
}

extension WatchExercise {
    /// The server's exercise (`api._encode_watch_exercise`). Its slot type
    /// is already resolved — the server infers one for a slot that names
    /// none — so the watch no longer guesses it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        // A block with no exercise (a BJJ round, a circuit's wrapper) has no
        // id; it is logged by its name, as the Garmin logs it (Wire.mc).
        exerciseId = try c.decodeIfPresent(String.self, forKey: .exerciseId) ?? name
        slotType = try c.decodeIfPresent(String.self, forKey: .slotType) ?? "sets_reps"
        slotRole = try c.decodeIfPresent(String.self, forKey: .slotRole) ?? ""
        isMeta = try c.decodeIfPresent(Bool.self, forKey: .isMeta) ?? false
        loadDescription = try c.decodeIfPresent(String.self, forKey: .loadDescription) ?? ""
        loadNote = try c.decodeIfPresent(String.self, forKey: .loadNote)
        coachingCue = try c.decodeIfPresent(String.self, forKey: .coachingCue)
        sets = c.lenientInt(.sets)
        reps = (try? c.decodeIfPresent(String.self, forKey: .reps)) ?? c.lenientInt(.reps).map(String.init)
        weightKg = try? c.decodeIfPresent(Double.self, forKey: .weightKg)
        targetRpe = c.lenientInt(.targetRpe)
        durationMinutes = c.lenientInt(.durationMinutes)
        zoneTarget = try c.decodeIfPresent(String.self, forKey: .zoneTarget)
        timeMinutes = c.lenientInt(.timeMinutes)
        targetRounds = c.lenientInt(.targetRounds)
        emomFormat = try c.decodeIfPresent(String.self, forKey: .emomFormat)
        holdSeconds = c.lenientInt(.holdSeconds)
        distanceKm = try? c.decodeIfPresent(Double.self, forKey: .distanceKm)
        restSeconds = c.lenientInt(.restSeconds)
        prescribedZoneLower = c.lenientInt(.prescribedZoneLower)
        prescribedZoneUpper = c.lenientInt(.prescribedZoneUpper)
        lastTime = try c.decodeIfPresent(String.self, forKey: .lastTime)
        standard = try c.decodeIfPresent(WatchStandard.self, forKey: .standard)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        movementPattern = try? c.decodeIfPresent(String.self, forKey: .movementPattern)
        bilateral = try? c.decodeIfPresent(Bool.self, forKey: .bilateral)
        targetRpm = c.lenientInt(.targetRpm)
        workSec = c.lenientInt(.workSec)
        intervalRestSec = c.lenientInt(.intervalRestSec)
        distanceM = c.lenientInt(.distanceM)
        repsPerRound = c.lenientInt(.repsPerRound)
        packLoadKg = try? c.decodeIfPresent(Double.self, forKey: .packLoadKg)
        focus = try? c.decodeIfPresent(String.self, forKey: .focus)
        parentSlotRole = try? c.decodeIfPresent(String.self, forKey: .parentSlotRole)
        bells = c.lenientInt(.bells)
        switchAtSec = c.lenientInt(.switchAtSec)
        restUntilHr = c.lenientInt(.restUntilHr)
        screen = try? c.decodeIfPresent(String.self, forKey: .screen)
    }
}

/// A test step's standard as the server words it for the watches
/// (`standards.watch_standard`): "2km Row", best "7:32", "7:00 for advanced".
struct WatchStandard: Codable, Hashable {
    let id: String
    let name: String
    /// How the step is read: duration | rounds | reps | hold | distance.
    var result: String? = nil
    var best: String? = nil
    var target: String? = nil
}

/// What a step produced that is not a set — a for-time clock, an AMRAP's
/// rounds, a distance — in the session log's per-exercise keys.
nonisolated struct WatchOutcome: Codable, Equatable {
    var rounds: Int? = nil
    var durationSec: Int? = nil
    var distanceKm: Double? = nil
}

/// A test step's captured value, read the way the server reads it
/// (`src/standard_results.read_result`), and how the watch prints it.
enum WatchResults {
    /// In the step's own terms: seconds for a clock or a hold, a count of
    /// reps or rounds, km; nil when nothing was captured.
    static func value(_ ex: WatchExercise, sets: [WatchSetLog], outcome: WatchOutcome?) -> Double? {
        switch ex.standard?.result {
        case "duration": return outcome?.durationSec.map(Double.init)
        case "rounds":   return outcome?.rounds.map(Double.init)
        case "distance": return outcome?.distanceKm
        case "hold":
            return sets.filter(\.completed).compactMap(\.durationSeconds).max().map(Double.init)
        case "reps":
            let reps = sets.filter(\.completed).compactMap(\.repsActual).filter { $0 > 0 }
            guard !reps.isEmpty else { return nil }
            // Reps in a window add up (a pentathlon set); otherwise the best set.
            let timed = ["time_domain", "skill_practice"].contains(ex.slotType)
            return Double(timed ? reps.reduce(0, +) : reps.max()!)
        default: return nil
        }
    }

    /// "7:32", "102 reps", "20 rounds", "45 s", "2.00 km".
    static func text(_ ex: WatchExercise, value: Double) -> String {
        let n = Int(value.rounded())
        switch ex.standard?.result {
        case "duration": return String(format: "%d:%02d", n / 60, n % 60)
        case "distance": return String(format: "%.2f km", value)
        case "hold":     return "\(n) s"
        case "rounds":   return "\(n) round\(n == 1 ? "" : "s")"
        default:         return "\(n) rep\(n == 1 ? "" : "s")"
        }
    }
}

// MARK: - Post-workout summary (Watch → iPhone → API)

/// Compact HR sample — uses integer second offsets from startedAt to save ~20 bytes/sample
/// versus full ISO timestamps. Expanded back to ISO on the iPhone before sending to the API.
nonisolated struct HRSamplePoint: Codable {
    let t: Int   // seconds from session startedAt
    let b: Int   // bpm
}

/// Compact GPS point with optional altitude and HR at that moment.
nonisolated struct GPSTrackPoint: Codable {
    let lat: Double
    let lng: Double
    let alt: Double?
    let t: Int      // seconds from session startedAt
    let b: Int?     // bpm at this point (nil if no HR sample close in time)
}

/// Per-exercise time window with HR summary, used to correlate bio data to specific exercises.
nonisolated struct ExerciseTimelineEntry: Codable {
    let exerciseId: String
    let startOffset: Int    // seconds from startedAt — when the first set of this exercise began
    let endOffset: Int      // seconds from startedAt — when the exercise was marked complete
    let avgHRDuring: Int?   // mean bpm during [startOffset, endOffset] from hrSamples
}

nonisolated struct WatchWorkoutSummary: Codable {
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
    /// exerciseId → what a step produced that is not a set (a for-time clock,
    /// an AMRAP's rounds). Optional, so a summary from an older watch decodes.
    var outcomes: [String: WatchOutcome]? = nil
    /// standard id → "save" | "dismiss": the Results answer on the watch; the
    /// server makes each a result only then (src/standard_results.py).
    var standardResults: [String: String]? = nil
}

/// What the watch sends the phone after a session, in one shape whichever
/// way it travels: live (`sendMessage`) while the phone is reachable — the
/// phone stores it on the server and answers `stored` — and queued
/// (`transferUserInfo`) otherwise or when no such answer comes. Queued alone,
/// a workout reached the server whenever the system delivered it, and
/// between simulators never: the phone's daemon took the transfer and did
/// not hand it on. A delivery that arrives both ways is stored once: the
/// workout's id is deterministic, the log merges exercise by exercise and
/// the match is an upsert.
nonisolated enum WatchUploadMessage {
    static let workout = "workout_complete"
    static let sessionDone = "session_marked_complete"
    /// A summary past this goes as a file: a message, live or queued, is
    /// capped near 65 KB.
    static let maxMessageBytes = 50_000

    static func message(_ summary: WatchWorkoutSummary) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(summary),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        dict["type"] = workout
        return dict
    }

    static func summary(from message: [String: Any]) -> WatchWorkoutSummary? {
        guard message["type"] as? String == workout,
              let data = try? JSONSerialization.data(withJSONObject: message) else { return nil }
        return try? JSONDecoder().decode(WatchWorkoutSummary.self, from: data)
    }

    static func sessionDone(_ sessionId: String, at date: Date = Date()) -> [String: Any] {
        ["type": sessionDone, "sessionId": sessionId, "markedAt": ISO8601DateFormatter().string(from: date)]
    }

    /// The phone's answer: the server has it.
    static func reply(stored: Bool) -> [String: Any] { ["stored": stored] }
    static func stored(_ reply: [String: Any]) -> Bool { reply["stored"] as? Bool == true }
}

nonisolated struct WatchSetLog: Codable, Equatable {
    let setIndex: Int
    let repsActual: Int?
    let weightKg: Double?
    let rpe: Int?
    let completed: Bool
    let durationSeconds: Int?
    let startOffset: Int?   // seconds from session startedAt when this set began
    let endOffset: Int?     // seconds from session startedAt when this set was logged
}

// MARK: - The day (GET /user/today-session?spec=1&week=1, relayed as it is)

/// What the server says about the athlete's day — the payload both watches
/// read (docs/watch.md). The phone forwards it unchanged and the watch
/// decodes it here, so a key the server adds reaches the Apple Watch with no
/// phone code, as it reaches the Garmin.
struct WatchDay: Codable {
    /// ok | no_program | not_started | program_expired
    let status: String
    var date: String? = nil
    /// The first day of a program that has not started (`not_started`).
    var startsOn: String? = nil
    var weekNumber: Int? = nil
    var totalWeeks: Int? = nil
    var dayName: String? = nil
    var sessions: [WatchSession]? = nil
    var readiness: WatchReadiness? = nil
    var tomorrow: WatchTomorrow? = nil
    var progress: WatchProgress? = nil
    /// Today and the six days after it, inside the program (`week=1`).
    var days: [WatchDayAhead]? = nil
    /// hrConfig, else 220 − age, for the zone alerts.
    var maxHR: Int? = nil

    enum CodingKeys: String, CodingKey {
        case status, date, startsOn, weekNumber, totalWeeks, dayName, sessions
        case readiness, tomorrow, progress, days, maxHR
    }
}

extension WatchDay {
    /// The sessions must decode; each block beside them is read on its own,
    /// so an odd readiness or progress costs that block, not the day.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        date = try? c.decodeIfPresent(String.self, forKey: .date)
        startsOn = try? c.decodeIfPresent(String.self, forKey: .startsOn)
        weekNumber = c.lenientInt(.weekNumber)
        totalWeeks = c.lenientInt(.totalWeeks)
        dayName = try? c.decodeIfPresent(String.self, forKey: .dayName)
        sessions = try c.decodeIfPresent([WatchSession].self, forKey: .sessions)
        readiness = try? c.decodeIfPresent(WatchReadiness.self, forKey: .readiness)
        tomorrow = try? c.decodeIfPresent(WatchTomorrow.self, forKey: .tomorrow)
        progress = try? c.decodeIfPresent(WatchProgress.self, forKey: .progress)
        days = try? c.decodeIfPresent([WatchDayAhead].self, forKey: .days)
        maxHR = c.lenientInt(.maxHR)
    }
}

/// The server's readiness: a 0–100 score and green | yellow | red.
struct WatchReadiness: Codable, Hashable {
    let score: Double
    let status: String
}

struct WatchTomorrow: Codable, Hashable {
    let dayName: String
    let sessionCount: Int
    var modalityId: String? = nil
    var archetypeName: String? = nil
    var estimatedMinutes: Int? = nil
}

/// This program week's sessions done of those due and of all it holds, the
/// program's so far, and the methodology's headline (`api._watch_progress`).
struct WatchProgress: Codable, Hashable {
    struct Week: Codable, Hashable { let number: Int; let of: Int; let done: Int; let due: Int; let sessions: Int }
    struct Program: Codable, Hashable { let done: Int; let due: Int; var pct: Int? = nil }
    struct Headline: Codable, Hashable {
        var label: String? = nil; var text: String? = nil; var trendText: String? = nil; var status: String? = nil
    }
    let week: Week
    var program: Program? = nil
    var headline: Headline? = nil
}

/// One day of the week ahead: "Strength A +1", its sessions (no screens).
struct WatchDayAhead: Codable, Hashable, Identifiable {
    var id: String { date }
    let offset: Int
    let date: String
    let title: String
    let sessions: [WatchSession]
}

/// The day on the wire between the phone and the watch: the server's JSON,
/// compressed, under one key. A dictionary of the JSON could not carry its
/// nulls (`transferUserInfo` takes property-list types only), and a week of
/// sessions is past the size a message may be uncompressed.
enum WatchDayMessage {
    static let type = "watch_day"

    static func payload(json: Data) -> [String: Any]? {
        guard let packed = try? (json as NSData).compressed(using: .lzfse) else { return nil }
        return ["type": type, "day": packed as Data]
    }

    /// The day and its JSON, or nil for any other message.
    static func day(from message: [String: Any]) -> (day: WatchDay, json: Data)? {
        guard message["type"] as? String == type, let packed = message["day"] as? Data,
              let json = try? (packed as NSData).decompressed(using: .lzfse) as Data,
              let day = try? JSONDecoder().decode(WatchDay.self, from: json) else { return nil }
        return (day, json)
    }
}
