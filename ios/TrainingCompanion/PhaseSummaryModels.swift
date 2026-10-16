import Foundation

/// How a program's sessions and exercises change from phase to phase — the
/// server's `currentProgram.phase_summary` (src/phase_summary.py), computed on
/// every read and never stored. The web's Program ▸ Overview lays out the same
/// document; nothing here is counted on the phone.
///
/// Every field decodes on its own, so a summary missing a key still shows the
/// rest, as `ProgramAnalyticsModels` does.
struct PhaseSummary: Decodable, Identifiable, Equatable {
    struct Item: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let modality: String
        let sessions: Int
        /// "new" or "continued"; nil in the first phase.
        let status: String?

        enum CodingKeys: String, CodingKey { case id, name, modality, sessions, status }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = (try? c.decode(String.self, forKey: .name)) ?? id
            modality = (try? c.decode(String.self, forKey: .modality)) ?? ""
            sessions = (try? c.decode(Int.self, forKey: .sessions)) ?? 0
            status = try? c.decodeIfPresent(String.self, forKey: .status)
        }
    }

    struct Lift: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let firstKg: Double
        let lastKg: Double

        enum CodingKeys: String, CodingKey { case id, name, firstKg = "first_kg", lastKg = "last_kg" }
    }

    struct Dropped: Decodable, Equatable {
        let archetypes: [Item]
        let exercises: [Item]

        init(archetypes: [Item] = [], exercises: [Item] = []) {
            self.archetypes = archetypes
            self.exercises = exercises
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            archetypes = (try? c.decode([Item].self, forKey: .archetypes)) ?? []
            exercises = (try? c.decode([Item].self, forKey: .exercises)) ?? []
        }

        enum CodingKeys: String, CodingKey { case archetypes, exercises }
    }

    let phaseId: String
    let name: String
    let kind: String
    let weekStart: Int
    let weeks: Int
    /// Sessions per modality, averaged over the phase's working weeks.
    let sessionsPerWeek: [String: Double]
    let minutesMean: Int
    let archetypes: [Item]
    let exercises: [Item]
    let lifts: [Lift]
    let dropped: Dropped
    /// Plain lines naming what differs from the previous phase.
    let changes: [String]

    var id: String { "\(phaseId)-\(weekStart)" }

    enum CodingKeys: String, CodingKey {
        case phaseId = "phase_id", name, kind, weekStart = "week_start", weeks
        case sessionsPerWeek = "sessions_per_week", minutes = "minutes_per_week"
        case archetypes, exercises, lifts, dropped, changes
    }

    private struct Minutes: Decodable { let mean: Int? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phaseId = try c.decode(String.self, forKey: .phaseId)
        name = (try? c.decode(String.self, forKey: .name)) ?? phaseId
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
        weekStart = (try? c.decode(Int.self, forKey: .weekStart)) ?? 0
        weeks = (try? c.decode(Int.self, forKey: .weeks)) ?? 0
        sessionsPerWeek = (try? c.decode([String: Double].self, forKey: .sessionsPerWeek)) ?? [:]
        minutesMean = (try? c.decode(Minutes.self, forKey: .minutes))?.mean ?? 0
        archetypes = (try? c.decode([Item].self, forKey: .archetypes)) ?? []
        exercises = (try? c.decode([Item].self, forKey: .exercises)) ?? []
        lifts = (try? c.decode([Lift].self, forKey: .lifts)) ?? []
        dropped = (try? c.decode(Dropped.self, forKey: .dropped)) ?? Dropped()
        changes = (try? c.decode([String].self, forKey: .changes)) ?? []
    }

    /// Sessions per week, most frequent first.
    var shape: [(modality: String, perWeek: Double)] {
        sessionsPerWeek.map { ($0.key, $0.value) }.sorted { $0.perWeek > $1.perWeek }
    }

    var newArchetypes: [Item] { archetypes.filter { $0.status == "new" } }

    /// Appearances per week of one archetype or exercise in this phase, or nil.
    func perWeek(_ itemId: String, exercises useExercises: Bool = false) -> Double? {
        guard let item = (useExercises ? exercises : archetypes).first(where: { $0.id == itemId }) else { return nil }
        return (Double(item.sessions) / Double(max(weeks, 1)) * 10).rounded() / 10
    }

    /// The program's summaries, read from the stored program's extras.
    static func list(from extra: [String: JSONValue]?) -> [PhaseSummary] {
        guard let value = extra?["phase_summary"],
              let data = try? JSONEncoder().encode(value) else { return [] }
        return (try? JSONDecoder().decode([Lossy].self, from: data))?.compactMap(\.value) ?? []
    }

    /// One summary that fails to decode drops alone, not the list.
    private struct Lossy: Decodable {
        let value: PhaseSummary?
        init(from decoder: Decoder) throws { value = try? PhaseSummary(from: decoder) }
    }

    /// The summary for the i-th phase segment. Both list the program's phases
    /// in order, grouped the same way; when the counts differ (an older server)
    /// nothing is matched rather than the wrong phase.
    static func forSegment(_ index: Int, of summaries: [PhaseSummary], segmentCount: Int) -> PhaseSummary? {
        guard summaries.count == segmentCount, summaries.indices.contains(index) else { return nil }
        return summaries[index]
    }
}
