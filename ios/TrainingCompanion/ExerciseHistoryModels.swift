import Foundation

/// `GET /api/progression/exercises` — each exercise of the program with its
/// logged history (earlier programs' included), the stored prescription week
/// by week, and three counts: in the program, so far, with data. The web's
/// `ExerciseHistoryResponse`; the Progress tab's exercise cards on both.
struct ExerciseHistoryResponse: Decodable {
    struct Counts: Decodable {
        let inProgram: Int
        let soFar: Int
        let withData: Int
    }
    let exercises: [ExerciseHistoryItem]
    let counts: Counts?

    private enum CodingKeys: String, CodingKey { case exercises, counts }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exercises = ((try? c.decodeIfPresent([Lossy<ExerciseHistoryItem>].self, forKey: .exercises)) ?? [])?
            .compactMap(\.value) ?? []
        counts = try? c.decodeIfPresent(Counts.self, forKey: .counts)
    }

    /// The server's counts, else the same three from the rows.
    var resolvedCounts: Counts {
        counts ?? Counts(inProgram: exercises.count,
                         soFar: exercises.filter(\.scheduledSoFar).count,
                         withData: exercises.filter { !$0.history.isEmpty }.count)
    }
}

struct ExerciseHistoryItem: Decodable, Identifiable {
    struct Point: Decodable {
        let date: String?
        let weekNumber: Int?
        let bestWeightKg: Double?
        let bestReps: Int?
        let durationSec: Double?
        let distanceKm: Double?
        let roundsCompleted: Double?
        let hrAvg: Int?
        let hrMax: Int?
        let source: String?

        private enum CodingKeys: String, CodingKey {
            case date, source
            case weekNumber = "week_number", bestWeightKg = "best_weight_kg", bestReps = "best_reps"
            case durationSec = "duration_sec", distanceKm = "distance_km"
            case roundsCompleted = "rounds_completed", hrAvg = "hr_avg", hrMax = "hr_max"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            weekNumber = try? c.decodeIfPresent(Int.self, forKey: .weekNumber)
            bestWeightKg = try? c.decodeIfPresent(Double.self, forKey: .bestWeightKg)
            bestReps = try? c.decodeIfPresent(Int.self, forKey: .bestReps)
            durationSec = try? c.decodeIfPresent(Double.self, forKey: .durationSec)
            distanceKm = try? c.decodeIfPresent(Double.self, forKey: .distanceKm)
            roundsCompleted = try? c.decodeIfPresent(Double.self, forKey: .roundsCompleted)
            hrAvg = try? c.decodeIfPresent(Int.self, forKey: .hrAvg)
            hrMax = try? c.decodeIfPresent(Int.self, forKey: .hrMax)
            source = try? c.decodeIfPresent(String.self, forKey: .source)
        }

        /// The value the card plots, in the card's metric — the web's
        /// `primaryValue`.
        func value(metric: String, unit: String) -> Double? {
            switch metric {
            case "weight": return bestWeightKg
            case "time":
                guard let s = durationSec else { return nil }
                return unit == "s" ? s : (s / 60 * 10).rounded() / 10
            case "distance": return distanceKm
            case "rounds": return roundsCompleted
            case "reps": return bestReps.map(Double.init)
            default: return bestWeightKg
            }
        }
    }
    struct Target: Decodable {
        let value: Double?
        let weekNumber: Int?
    }

    let exerciseId: String
    let name: String
    let history: [Point]
    let metricType: String?
    let unit: String?
    let target: Target?
    let scheduledSoFar: Bool
    var id: String { exerciseId }

    private enum CodingKeys: String, CodingKey { case exerciseId, name, history, metricType, unit, target, scheduledSoFar }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? exerciseId
        history = ((try? c.decodeIfPresent([Lossy<Point>].self, forKey: .history)) ?? [])?.compactMap(\.value) ?? []
        metricType = try? c.decodeIfPresent(String.self, forKey: .metricType)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        target = try? c.decodeIfPresent(Target.self, forKey: .target)
        scheduledSoFar = (try? c.decodeIfPresent(Bool.self, forKey: .scheduledSoFar)) ?? true
    }
}
