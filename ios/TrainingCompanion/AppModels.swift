import Foundation

// MARK: - Goals

struct GoalProfile: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let priorities: [String: Double]
}

// MARK: - Exercises

struct AppExercise: Codable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let movementPatterns: [String]?
    let notes: String?
    let difficulty: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, notes, difficulty
        case movementPatterns = "movement_patterns"
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
    let progressionStyle: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, notes, bias
        case corePrinciples = "core_principles"
        case intensityModel = "intensity_model"
        case progressionStyle = "progression_style"
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

struct UserProfile: Codable {
    var trainingLevel: String
    var equipment: [String]
    var injuryFlags: [String]
    var customInjuryFlags: [CustomInjuryFlag]
    var dateOfBirth: String?
    var performanceLogs: [String: [PerformanceEntry]]

    enum CodingKeys: String, CodingKey {
        case trainingLevel = "training_level"
        case equipment
        case injuryFlags = "injury_flags"
        case customInjuryFlags = "custom_injury_flags"
        case dateOfBirth = "date_of_birth"
        case performanceLogs = "performance_logs"
    }

    static let `default` = UserProfile(
        trainingLevel: "intermediate",
        equipment: [],
        injuryFlags: [],
        customInjuryFlags: [],
        dateOfBirth: nil,
        performanceLogs: [:]
    )
}

// MARK: - Session Logs

struct SessionLogEntry: Codable, Identifiable {
    var id: String { sessionKey }
    let sessionKey: String
    let completedAt: String?
    let source: String?
    let notes: String?
    let fatigueRating: Int?
    let avgHR: Int?
    let peakHR: Int?

    enum CodingKeys: String, CodingKey {
        case sessionKey = "session_key"
        case completedAt = "completed_at"
        case source, notes
        case fatigueRating = "fatigue_rating"
        case avgHR = "avg_hr"
        case peakHR = "peak_hr"
    }
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

    enum CodingKeys: String, CodingKey {
        case id, name, description
    }
}

// MARK: - Program Generation

struct GenerateProgramRequest: Encodable {
    let goalId: String
    let constraints: GenerateConstraints
    let numWeeks: Int?
    let startDate: String?
    let eventDate: String?

    enum CodingKeys: String, CodingKey {
        case goalId = "goal_id"
        case constraints
        case numWeeks = "num_weeks"
        case startDate = "start_date"
        case eventDate = "event_date"
    }
}

struct GenerateConstraints: Encodable {
    var trainingLevel: String = "intermediate"
    var daysPerWeek: Int = 4
    var sessionTimeMinutes: Int = 60
    var equipment: [String] = []
    var injuryFlags: [String] = []
    var phase: String? = nil
    var preferredDays: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case trainingLevel = "training_level"
        case daysPerWeek = "days_per_week"
        case sessionTimeMinutes = "session_time_minutes"
        case equipment
        case injuryFlags = "injury_flags"
        case phase
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
    static let all: [EquipmentItem] = [
        EquipmentItem(id: "barbell", label: "Barbell", group: "Strength"),
        EquipmentItem(id: "dumbbell", label: "Dumbbells", group: "Strength"),
        EquipmentItem(id: "kettlebell", label: "Kettlebells", group: "Strength"),
        EquipmentItem(id: "pull_up_bar", label: "Pull-up Bar", group: "Bodyweight"),
        EquipmentItem(id: "rings", label: "Gymnastic Rings", group: "Bodyweight"),
        EquipmentItem(id: "resistance_bands", label: "Resistance Bands", group: "Bodyweight"),
        EquipmentItem(id: "sandbag", label: "Sandbag", group: "GPP"),
        EquipmentItem(id: "sled", label: "Sled", group: "GPP"),
        EquipmentItem(id: "rower", label: "Rowing Machine", group: "Aerobic"),
        EquipmentItem(id: "assault_bike", label: "Assault Bike", group: "Aerobic"),
        EquipmentItem(id: "treadmill", label: "Treadmill", group: "Aerobic"),
        EquipmentItem(id: "jump_rope", label: "Jump Rope", group: "Aerobic"),
        EquipmentItem(id: "cable_machine", label: "Cable Machine", group: "Strength"),
        EquipmentItem(id: "box", label: "Plyo Box", group: "GPP"),
    ]
}
