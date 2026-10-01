import Foundation

// MARK: - Archetypes

struct AppArchetype: Codable, Identifiable {
    let id: String
    let name: String
    let modality: String
    let category: String
    let durationEstimateMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, modality, category
        case durationEstimateMinutes = "duration_estimate_minutes"
    }
}

// MARK: - Exercises

struct AppExercise: Codable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let movementPatterns: [String]?
    let notes: String?
    let difficulty: String?
    let equipment: [String]?
    /// Concept or exercise ids the athlete should know first.
    let requires: [String]?
    let unlocks: [String]?
    let effort: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, notes, difficulty, equipment, requires, unlocks, effort
        case movementPatterns = "movement_patterns"
    }
}

/// A package's demo and coaching notes for one exercise
/// (`GET /api/exercises/<id>/media`, merged from `exercise_media.yaml`).
/// Every field is optional and decoded on its own, so one odd entry cannot
/// blank the sheet.
struct ExerciseMedia: Decodable {
    struct Animation: Decodable {
        let type: String?
        let gifUrl: String?
        let gifAlt: String?
        let gifSource: String?

        enum CodingKeys: String, CodingKey {
            case type
            case gifUrl    = "gif_url"
            case gifAlt    = "gif_alt"
            case gifSource = "gif_source"
        }
    }

    let animation: Animation?
    let description: String?
    let coachingFocus: String?
    let cuePoints: [String]?
    let commonErrors: [String]?
    let musclesPrimary: [String]?
    let musclesSecondary: [String]?

    enum CodingKeys: String, CodingKey {
        case animation, description
        case coachingFocus    = "coaching_focus"
        case cuePoints        = "cue_points"
        case commonErrors     = "common_errors"
        case musclesPrimary   = "muscles_primary"
        case musclesSecondary = "muscles_secondary"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        animation        = try? c.decodeIfPresent(Animation.self, forKey: .animation)
        description      = try? c.decodeIfPresent(String.self, forKey: .description)
        coachingFocus    = try? c.decodeIfPresent(String.self, forKey: .coachingFocus)
        cuePoints        = try? c.decodeIfPresent([String].self, forKey: .cuePoints)
        commonErrors     = try? c.decodeIfPresent([String].self, forKey: .commonErrors)
        musclesPrimary   = try? c.decodeIfPresent([String].self, forKey: .musclesPrimary)
        musclesSecondary = try? c.decodeIfPresent([String].self, forKey: .musclesSecondary)
    }

    /// The demo, when the package ships one (`type: gif`).
    var gifURL: URL? {
        guard animation?.type == "gif", let s = animation?.gifUrl else { return nil }
        return URL(string: s)
    }

    var isEmpty: Bool {
        gifURL == nil && (description ?? "").isEmpty && (coachingFocus ?? "").isEmpty
            && (cuePoints ?? []).isEmpty && (commonErrors ?? []).isEmpty
    }
}

// MARK: - Benchmarks

struct BenchmarkStandards: Codable {
    let entry: Double?
    let intermediate: Double?
    let advanced: Double?
    let elite: Double?
}

struct AppBenchmark: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let unit: String?
    let standards: BenchmarkStandards?
    let higherIsBetter: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, category, unit, standards
        case higherIsBetter = "higher_is_better"
    }
}

// MARK: - Philosophies

struct PhilosophyCard: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let notes: String?
    let bias: [String]?
    let corePrinciples: [String]?
    let intensityModel: String?
    /// `progression_philosophy` in philosophy.yaml (`load_based`, `time_based`, …).
    let progressionPhilosophy: String?

    /// What a card shows under the name. Packages write a folded `notes`
    /// paragraph; none has a `description`.
    var summary: String? { description ?? notes }

    enum CodingKeys: String, CodingKey {
        case id, name, description, notes, bias
        case corePrinciples = "core_principles"
        case intensityModel = "intensity_model"
        case progressionPhilosophy = "progression_philosophy"
    }
}

// MARK: - User Profile

struct CustomInjuryFlag: Codable, Identifiable {
    let id: String
    let description: String
}

struct PerformanceEntry: Codable {
    let value: Double
    let date: String  // "YYYY-MM-DD"
}

enum SessionType: String, Codable, CaseIterable {
    case rest, short, long, mobility
}

struct DaySchedule: Codable {
    var session1: SessionType
    var session2: SessionType
    var session3: SessionType
    var session4: SessionType
}

typealias WeeklySchedule = [String: DaySchedule]

// Top-level keys must be camelCase to match the server's GET /api/profile response.
// Do NOT add CodingKeys here — Swift encodes camelCase by default, which is what
// the server expects on PUT and returns on GET.
//
// performanceLogs is NOT part of the server profile payload; it is loaded separately
// from GET /api/health/snapshot and stored locally.
struct HRConfig: Codable {
    var maxHROverride: Int?
    var zoneBoundaries: [Double]?  // 4 upper-boundary fractions, e.g. [0.60, 0.70, 0.80, 0.90]
}

/// Whether a source may import automatically. Mirrors `integrations` in the
/// server profile (see `default_integrations()` in api.py).
struct IntegrationSource: Codable {
    var enabled: Bool
}

struct IntegrationSettings: Codable {
    /// Master switch over every source.
    var autoImport: Bool
    var sources: [String: IntegrationSource]

    static let `default` = IntegrationSettings(
        autoImport: true,
        sources: [
            "garmin": IntegrationSource(enabled: true),
            "strava": IntegrationSource(enabled: true),
            "appleHealth": IntegrationSource(enabled: true),
        ]
    )

    func allows(_ source: String) -> Bool {
        autoImport && (sources[source]?.enabled ?? true)
    }
}

struct UserProfile: Codable {
    var trainingLevel: String
    var equipment: [String]
    var injuryFlags: [String]
    var customInjuryFlags: [CustomInjuryFlag]
    var dateOfBirth: String?
    var performanceLogs: [String: [PerformanceEntry]]?
    var weeklySchedule: WeeklySchedule?
    var hrConfig: HRConfig?
    /// Present so a save from this app does not drop it. The server merges
    /// per-key now, but round-tripping what we read is still the honest thing
    /// for a client to do.
    var activeGoalId: String?
    var integrations: IntegrationSettings?
    /// "male" | "female" | nil — which benchmark standards apply.
    var sex: String?
    /// IANA zone, e.g. "Europe/Zurich". The server dates a FIT file by it when
    /// the file carries no local timestamp; filled from the device when unset.
    var timezone: String?

    static let `default` = UserProfile(
        trainingLevel: "intermediate",
        equipment: [],
        injuryFlags: [],
        customInjuryFlags: [],
        dateOfBirth: nil,
        performanceLogs: nil,
        weeklySchedule: nil,
        hrConfig: nil,
        activeGoalId: nil,
        integrations: nil,
        sex: nil,
        timezone: nil
    )
}

// MARK: - Session Logs

/// What the athlete logged for one exercise of a session — the web's
/// `ExercisePerformance`: sets for sets × reps (and hold) slots, the slot's
/// own currency — rounds, seconds, kilometres — for the rest, which is what
/// the analytics primitives read. Written through `PUT /health/sessions/<key>`
/// as `{exercises: {<exercise id>: …}}`; the server merges per exercise.
struct ExercisePerformanceLog: Codable, Equatable {
    var sets: [WatchSetLog]
    var rounds: Int?
    var durationSec: Int?
    var distanceKm: Double?
    var rpe: Int?
    var notes: String?

    init(sets: [WatchSetLog] = [], rounds: Int? = nil, durationSec: Int? = nil,
         distanceKm: Double? = nil, rpe: Int? = nil, notes: String? = nil) {
        self.sets = sets
        self.rounds = rounds
        self.durationSec = durationSec
        self.distanceKm = distanceKm
        self.rpe = rpe
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case sets, rounds, durationSec, distanceKm, rpe, notes }

    /// Rows were written by three clients over time; a malformed set is
    /// dropped and a number stored as 1800.0 reads as 1800.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sets = ((try? c.decodeIfPresent([Lossy<WatchSetLog>].self, forKey: .sets)) ?? [])?.compactMap(\.value) ?? []
        rounds = Self.whole(c, .rounds)
        durationSec = Self.whole(c, .durationSec)
        distanceKm = try? c.decodeIfPresent(Double.self, forKey: .distanceKm)
        rpe = Self.whole(c, .rpe)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }

    private static func whole(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        return nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sets, forKey: .sets)
        try c.encodeIfPresent(rounds, forKey: .rounds)
        try c.encodeIfPresent(durationSec, forKey: .durationSec)
        try c.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try c.encodeIfPresent(rpe, forKey: .rpe)
        try c.encodeIfPresent(notes, forKey: .notes)
    }

    var isEmpty: Bool {
        sets.isEmpty && rounds == nil && durationSec == nil && distanceKm == nil
    }
}

struct SessionLogEntry: Codable, Identifiable {
    var id: String { sessionKey }
    let sessionKey: String
    let completedAt: String?
    let source: String?
    let notes: String?
    let fatigueRating: Int?
    let avgHR: Int?
    let peakHR: Int?
    let matchedWorkoutId: String?
    /// Per exercise, what was logged (`GET /health/sessions/recent` carries it).
    var exercises: [String: ExercisePerformanceLog]
    /// What the log was logged against, from the `planned_sessions` row its
    /// `session_uid` names (`GET /health/sessions/recent` annotates it). Set
    /// for logs of earlier programs too, whose keys resolve to nothing in the
    /// current one — so the Log tab can still say what the session was.
    let plannedName: String?
    let plannedModality: String?
    let plannedDate: String?           // YYYY-MM-DD
    let programVersionId: String?
    let weekIndex: Int?
    let dayName: String?

    init(sessionKey: String, completedAt: String?, source: String?, notes: String?,
         fatigueRating: Int?, avgHR: Int?, peakHR: Int?, matchedWorkoutId: String?,
         exercises: [String: ExercisePerformanceLog] = [:],
         plannedName: String? = nil, plannedModality: String? = nil, plannedDate: String? = nil,
         programVersionId: String? = nil, weekIndex: Int? = nil, dayName: String? = nil) {
        self.sessionKey = sessionKey
        self.completedAt = completedAt
        self.source = source
        self.notes = notes
        self.fatigueRating = fatigueRating
        self.avgHR = avgHR
        self.peakHR = peakHR
        self.matchedWorkoutId = matchedWorkoutId
        self.exercises = exercises
        self.plannedName = plannedName
        self.plannedModality = plannedModality
        self.plannedDate = plannedDate
        self.programVersionId = programVersionId
        self.weekIndex = weekIndex
        self.dayName = dayName
    }

    enum CodingKeys: String, CodingKey {
        case sessionKey = "session_key"
        case completedAt = "completed_at"
        case source, notes, exercises
        case fatigueRating = "fatigue_rating"
        case avgHR = "avg_hr"
        case peakHR = "peak_hr"
        case matchedWorkoutId = "matched_workout_id"
        case plannedName = "planned_name"
        case plannedModality = "planned_modality"
        case plannedDate = "planned_date"
        case programVersionId = "program_version_id"
        case weekIndex = "week_index"
        case dayName = "day_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionKey = try c.decode(String.self, forKey: .sessionKey)
        completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        fatigueRating = try? c.decodeIfPresent(Int.self, forKey: .fatigueRating)
        avgHR = try? c.decodeIfPresent(Int.self, forKey: .avgHR)
        peakHR = try? c.decodeIfPresent(Int.self, forKey: .peakHR)
        matchedWorkoutId = try? c.decodeIfPresent(String.self, forKey: .matchedWorkoutId)
        exercises = (try? c.decodeIfPresent([String: Lossy<ExercisePerformanceLog>].self, forKey: .exercises))??
            .compactMapValues(\.value) ?? [:]
        plannedName = try? c.decodeIfPresent(String.self, forKey: .plannedName)
        plannedModality = try? c.decodeIfPresent(String.self, forKey: .plannedModality)
        plannedDate = try? c.decodeIfPresent(String.self, forKey: .plannedDate)
        programVersionId = try? c.decodeIfPresent(String.self, forKey: .programVersionId)
        weekIndex = try? c.decodeIfPresent(Int.self, forKey: .weekIndex)
        dayName = try? c.decodeIfPresent(String.self, forKey: .dayName)
    }
}

/// MARK: - Imported Workout (.fit / Apple Health)

struct ImportedWorkout: Codable, Identifiable {
    let id: String
    let source: String
    let date: String             // YYYY-MM-DD
    let startTime: String?
    /// Required by the server: `workouts.end_time` is NOT NULL. Omitting it
    /// made every upload fail — first as a swallowed KeyError, then as a
    /// constraint violation. Every producer knows the value; send it.
    let endTime: String?
    let durationMinutes: Double?
    let activityType: String
    let inferredModalityId: String?
    let heartRate: WorkoutHRData?
    let calories: Double?
    let distance: WorkoutDistance?
    let gpsTrack: [GPSPoint]?
    let elevation: WorkoutElevation?

    enum CodingKeys: String, CodingKey {
        case id, source, date, calories, distance, elevation
        case startTime = "startTime"
        case endTime = "endTime"
        case durationMinutes = "durationMinutes"
        case activityType = "activityType"
        case inferredModalityId = "inferredModalityId"
        case heartRate = "heartRate"
        case gpsTrack = "gpsTrack"
    }
}

/// Identity is the deterministic id from `WorkoutID`, never the contents:
/// navigation must treat the trimmed list row and the re-fetched full row as
/// the same workout, and a synthesised `==` would compare tracks that run to
/// tens of thousands of points.
extension ImportedWorkout: Hashable {
    static func == (lhs: ImportedWorkout, rhs: ImportedWorkout) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A confirmed link between an imported workout and a planned session.
///
/// Mirrors a `workout_matches` row. `confidence` is "auto" | "manual" | a
/// stringified number, depending on which writer created it; the only value
/// with meaning here is "rejected", which `fetchWorkoutMatches` filters out.
struct WorkoutMatch {
    let workoutId: String
    let sessionKey: String
    let confidence: String
}

/// One row of `GET /health/snapshot`'s `matches`, as the server emits it.
/// The writers have disagreed on the confidence column's type — this app once
/// wrote the number 1.0, the web writes "manual", the server "auto" — so it
/// is read as a string or a number and compared only against "rejected".
struct WorkoutMatchRecord: Decodable, Equatable {
    let importedWorkoutId: String
    let sessionKey: String
    let sessionUid: String?
    let matchConfidence: String
    let matchedAt: String?

    enum CodingKeys: String, CodingKey { case importedWorkoutId, sessionKey, sessionUid, matchConfidence, matchedAt }

    init(importedWorkoutId: String, sessionKey: String, sessionUid: String? = nil,
         matchConfidence: String, matchedAt: String? = nil) {
        self.importedWorkoutId = importedWorkoutId
        self.sessionKey = sessionKey
        self.sessionUid = sessionUid
        self.matchConfidence = matchConfidence
        self.matchedAt = matchedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        importedWorkoutId = try c.decode(String.self, forKey: .importedWorkoutId)
        sessionKey = try c.decode(String.self, forKey: .sessionKey)
        sessionUid = try? c.decodeIfPresent(String.self, forKey: .sessionUid)
        if let s = try? c.decodeIfPresent(String.self, forKey: .matchConfidence) {
            matchConfidence = s
        } else if let d = try? c.decodeIfPresent(Double.self, forKey: .matchConfidence) {
            matchConfidence = String(d)
        } else {
            matchConfidence = ""
        }
        matchedAt = try? c.decodeIfPresent(String.self, forKey: .matchedAt)
    }

    /// The app's match, or nil for a rejected decision.
    var asMatch: WorkoutMatch? {
        guard matchConfidence != "rejected" else { return nil }
        return WorkoutMatch(workoutId: importedWorkoutId, sessionKey: sessionKey, confidence: matchConfidence)
    }
}

/// Decodes to nil instead of failing, so one bad element of a server list
/// does not throw the whole list away.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct WorkoutHRData: Codable {
    let avg: Int?
    let max: Int?
    let samples: [HRSample]

    init(avg: Int?, max: Int?, samples: [HRSample]) {
        self.avg = avg
        self.max = max
        self.samples = samples
    }

    private enum CodingKeys: String, CodingKey { case avg, max, samples }

    /// Averages may arrive as 142 or 142.0 depending on which path wrote the
    /// row; a summary carries no samples at all.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        avg = Self.wholeNumber(c, .avg)
        max = Self.wholeNumber(c, .max)
        samples = (try? c.decodeIfPresent([Lossy<HRSample>].self, forKey: .samples))??.compactMap(\.value) ?? []
    }

    private static func wholeNumber(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        return nil
    }
}

struct HRSample: Codable {
    let timestamp: String
    let bpm: Int
}

struct GPSPoint: Codable {
    let lat: Double
    let lng: Double
    let altitude: Double?
    let timestamp: String
    let bpm: Int?
    let speed: Double?   // m/s
}

struct WorkoutDistance: Codable {
    let value: Double
    let unit: String
}

struct WorkoutElevation: Codable {
    let gain: Double?
    let loss: Double?
}

// MARK: - Daily Bio Log

struct DailyBioLog: Codable, Identifiable {
    var id: String { date }
    let date: String  // "YYYY-MM-DD"
    let restingHR: Double?
    let hrv: Double?
    let sleepDurationMin: Int?
    let deepSleepMin: Int?
    let remSleepMin: Int?
    let lightSleepMin: Int?
    let awakeMins: Int?
    let sleepStart: String?
    let sleepEnd: String?
    let spo2Avg: Double?
    let respiratoryRateAvg: Double?
    let notes: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case date
        case restingHR = "resting_hr"
        case hrv
        case sleepDurationMin = "sleep_duration_min"
        case deepSleepMin = "deep_sleep_min"
        case remSleepMin = "rem_sleep_min"
        case lightSleepMin = "light_sleep_min"
        case awakeMins = "awake_mins"
        case sleepStart = "sleep_start"
        case sleepEnd = "sleep_end"
        case spo2Avg = "spo2_avg"
        case respiratoryRateAvg = "respiratory_rate_avg"
        case notes, source
    }
}

// MARK: - Readiness (API-computed)

struct ReadinessResult: Codable {
    let score: Int
    let status: String   // "green" | "yellow" | "red"
    let flags: [String]
    let components: ReadinessComponents
}

struct ReadinessComponents: Codable {
    let rhr: Int
    let hrv: Int
    let sleep: Int
    let fatigue: Int
}

// MARK: - Constraint Definitions

struct EquipmentProfileDef: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let available: [String]?
}

struct InjuryFlagDef: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let excludedMovementPatterns: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case excludedMovementPatterns = "excluded_movement_patterns"
    }
}

// MARK: - Program Generation

struct GenerateProgramRequest: Encodable {
    /// The methodology the program is generated from. Programs have been
    /// philosophy-driven since the goals layer was removed (2026-04-25); the
    /// builder picks this from `GET /api/philosophies`. A blend sends
    /// `philosophyIds` + `philosophyWeights` instead (the web's shape).
    let philosophyId: String?
    let philosophyIds: [String]?
    let philosophyWeights: [String: Double]?
    let constraints: GenerateConstraints
    let numWeeks: Int?
    /// `week_number` of the first generated week: a partial regenerate passes
    /// the kept head's length + 1 so the tail continues the numbering.
    let weekInProgram: Int?
    let startDate: String?
    let eventDate: String?
    /// Tells the server this generate is a commit and should replace the
    /// stored program. Unlike the web app, this app has no separate save step
    /// after generating — it generates and then re-fetches — so it must opt in.
    /// The server no longer persists by default, so that an exploratory or
    /// failed generate cannot silently replace an athlete's program.
    var persist: Bool = true

    init(philosophyId: String? = nil, philosophyIds: [String]? = nil, philosophyWeights: [String: Double]? = nil,
         constraints: GenerateConstraints, numWeeks: Int?, weekInProgram: Int? = nil,
         startDate: String?, eventDate: String?, persist: Bool = true) {
        self.philosophyId = philosophyId
        self.philosophyIds = philosophyIds
        self.philosophyWeights = philosophyWeights
        self.constraints = constraints
        self.numWeeks = numWeeks
        self.weekInProgram = weekInProgram
        self.startDate = startDate
        self.eventDate = eventDate
        self.persist = persist
    }

    enum CodingKeys: String, CodingKey {
        // The backend requires `philosophy_id` (or `philosophy_ids` with
        // weights) and answers 400 to anything else (see _generate_program_inner).
        case philosophyId = "philosophy_id"
        case philosophyIds = "philosophy_ids"
        case philosophyWeights = "philosophy_weights"
        case constraints
        case numWeeks = "num_weeks"
        case weekInProgram = "week_in_program"
        case startDate = "start_date"
        case eventDate = "event_date"
        case persist
    }
}

struct GenerateConstraints: Encodable {
    var trainingLevel: String = "intermediate"
    var daysPerWeek: Int = 4
    var sessionTimeMinutes: Int = 60
    var equipment: [String] = []
    var injuryFlags: [String] = []
    var phase: String? = nil
    /// The web's name for the phase; sent alongside `phase`.
    var trainingPhase: String? = nil
    /// Week within the phase a partial regenerate continues from.
    var periodizationWeek: Int? = nil
    var preferredDays: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case trainingLevel = "training_level"
        case daysPerWeek = "days_per_week"
        case sessionTimeMinutes = "session_time_minutes"
        case equipment
        case injuryFlags = "injury_flags"
        case phase
        case trainingPhase = "training_phase"
        case periodizationWeek = "periodization_week"
        case preferredDays = "preferred_days"
    }
}

// MARK: - Equipment item list (used in profile + builder)

struct EquipmentItem: Identifiable {
    let id: String
    let label: String
    let group: String
}

extension EquipmentItem {
    // IDs and group names must exactly match ConstraintsForm.tsx (frontend/src/components/builder/ConstraintsForm.tsx)
    static let all: [EquipmentItem] = [
        // Strength
        EquipmentItem(id: "barbell", label: "Barbell", group: "Strength"),
        EquipmentItem(id: "rack",    label: "Rack",    group: "Strength"),
        EquipmentItem(id: "plates",  label: "Plates",  group: "Strength"),
        // Power & Kettlebell
        EquipmentItem(id: "kettlebell", label: "Kettlebell", group: "Power & Kettlebell"),
        EquipmentItem(id: "dumbbell",   label: "Dumbbell",   group: "Power & Kettlebell"),
        // Bodyweight & Gymnastics
        EquipmentItem(id: "pull_up_bar", label: "Pull-up Bar", group: "Bodyweight & Gymnastics"),
        EquipmentItem(id: "rings",       label: "Rings",       group: "Bodyweight & Gymnastics"),
        EquipmentItem(id: "parallettes", label: "Parallettes", group: "Bodyweight & Gymnastics"),
        EquipmentItem(id: "dip_bar",     label: "Dip Bar",     group: "Bodyweight & Gymnastics"),
        // Aerobic & Conditioning
        EquipmentItem(id: "rower",        label: "Rower",        group: "Aerobic & Conditioning"),
        EquipmentItem(id: "assault_bike", label: "Assault Bike", group: "Aerobic & Conditioning"),
        EquipmentItem(id: "ski_erg",      label: "Ski Erg",      group: "Aerobic & Conditioning"),
        EquipmentItem(id: "jump_rope",    label: "Jump Rope",    group: "Aerobic & Conditioning"),
        EquipmentItem(id: "pool",         label: "Pool",         group: "Aerobic & Conditioning"),
        // GPP & Durability
        EquipmentItem(id: "ruck_pack",     label: "Ruck Pack",     group: "GPP & Durability"),
        EquipmentItem(id: "sandbag",       label: "Sandbag",       group: "GPP & Durability"),
        EquipmentItem(id: "sled",          label: "Sled",          group: "GPP & Durability"),
        EquipmentItem(id: "medicine_ball", label: "Medicine Ball", group: "GPP & Durability"),
        EquipmentItem(id: "box",           label: "Box",           group: "GPP & Durability"),
        // Mobility & Prehab
        EquipmentItem(id: "resistance_band", label: "Resistance Band", group: "Mobility & Prehab"),
        EquipmentItem(id: "foam_roller",     label: "Foam Roller",     group: "Mobility & Prehab"),
        EquipmentItem(id: "ghd",             label: "GHD",             group: "Mobility & Prehab"),
        // General
        EquipmentItem(id: "rope",       label: "Rope",       group: "General"),
        EquipmentItem(id: "open_space", label: "Open Space", group: "General"),
    ]
}


// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


// MARK: - Progression Review

struct ProgressionReview: Codable {
    let periodKey: String
    let periodType: String
    let generatedAt: String?
    let overallScore: Int?
    let readinessTrend: String
    let avgReadiness: Int?
    let compliancePct: Int
    let exerciseFindings: [ExerciseFinding]
    let flags: [String]
    let recommendations: [String]
    let adjustments: [ProgressionAdjustment]

    enum CodingKeys: String, CodingKey {
        case periodKey       = "period_key"
        case periodType      = "period_type"
        case generatedAt     = "generated_at"
        case overallScore    = "overall_score"
        case readinessTrend  = "readiness_trend"
        case avgReadiness    = "avg_readiness"
        case compliancePct   = "compliance_pct"
        case exerciseFindings = "exercise_findings"
        case flags, recommendations, adjustments
    }
}

struct ExerciseFinding: Codable, Identifiable {
    let exerciseId: String
    let name: String
    let metricType: String
    let expectedValue: Double?
    let actualValue: Double?
    let unit: String
    let status: String   // "ahead" | "on_track" | "behind" | "stalled" | "insufficient_data"
    let trend: String    // "improving" | "stable" | "declining"
    let changeSummary: String

    var id: String { exerciseId }

    enum CodingKeys: String, CodingKey {
        case exerciseId    = "exercise_id"
        case name
        case metricType    = "metric_type"
        case expectedValue = "expected_value"
        case actualValue   = "actual_value"
        case unit, status, trend
        case changeSummary = "change_summary"
    }
}

struct ProgressionAdjustment: Codable, Identifiable {
    let type: String
    let target: String
    let direction: String
    let reason: String
    let magnitude: String?

    var id: String { "\(type)-\(target)" }
}

extension WorkoutDistance {
    /// Distance worth showing.
    ///
    /// A strength or mobility session recorded on a watch still carries a
    /// distance field, and it is noise: "0.0 km" under a flexibility workout
    /// tells the athlete nothing and crowds out the numbers that do. The
    /// threshold is in kilometres, so a mile-unit record is converted first.
    var isMeaningful: Bool {
        let km = unit.lowercased().hasPrefix("mi") ? value * 1.609344 : value
        return km > 0.1
    }
}


// MARK: - Program history (GET /api/programs/history)

/// One activation of one program: what was in force, and when.
///
/// The server used to keep a single program row per athlete and overwrite it, so
/// a replaced plan left nothing behind and a workout dated inside one could
/// never be matched to what had actually been planned for that day.
struct ProgramHistoryEntry: Codable, Identifiable {
    let activationId: Int
    let versionId: String
    let lineageId: String
    let label: String
    let goalName: String?
    let sourceGoalIds: [String]
    let effectiveFrom: String
    let effectiveTo: String?
    let isActive: Bool
    let startDate: String?
    let weekCount: Int
    let sessionCount: Int
    let matchedCount: Int
    let loggedCount: Int

    var id: Int { activationId }

    /// What to call this block on screen.
    var displayName: String {
        if let goalName, !goalName.isEmpty { return goalName }
        let ids = sourceGoalIds.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
        return ids.isEmpty ? "Program" : ids.joined(separator: " + ")
    }
}

/// A session as it was planned, flattened onto the calendar day it fell on.
struct PlannedSessionRecord: Codable, Identifiable {
    let sessionUid: String
    let date: String
    let weekIndex: Int
    let weekNumber: Int?
    let dayName: String
    let sessionIndex: Int
    let sessionKey: String
    let modality: String
    let archetypeId: String?
    let archetypeName: String?
    let durationMinutes: Int
    let phase: String?
    let isDeload: Bool
    /// False for weeks a plan never reached, because it was replaced first.
    let wasEffective: Bool?
    let matchedWorkoutId: String?
    let completedAt: String?

    var id: String { sessionUid }
}

struct ProgramHistoryDetail: Codable {
    let versionId: String
    let startDate: String
    let weekCount: Int
    let activations: [ProgramHistoryEntry]
    let sessions: [PlannedSessionRecord]
}

extension ImportedWorkout {
    /// What the device recorded — never the name of the session it was matched
    /// to. The watch pipeline's placeholder activity types fall back to the
    /// inferred modality. Shared by the workouts list and the Today card.
    var recordedTitle: String {
        let raw = activityType
        let placeholders = ["apple_watch_live", "watch", "workout"]
        if !placeholders.contains(raw.lowercased()) && !raw.hasPrefix("watch_") {
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let modality = inferredModalityId {
            return ModalityStyle.label(for: modality)
        }
        return "Workout"
    }
}

// MARK: - Match suggestions

/// A weak server-side match waiting for the athlete's decision. Keys are
/// camelCase on the wire (`GET /api/health/matches/suggestions`).
struct MatchSuggestion: Codable, Identifiable {
    let importedWorkoutId: String
    let sessionKey: String
    let sessionUid: String?
    let score: Double
    let createdAt: String
    var id: String { importedWorkoutId }
}

// MARK: - Sheet items

/// A session plus the program-relative key and index a sheet needs to log
/// against it. Identity is the key, so re-rendering does not re-present.
struct SessionWithKey: Identifiable {
    var id: String { key }
    let session: ProgramSession
    let key: String
    var dateLabel: String = ""
    var sessionIndex: Int = 0
}
