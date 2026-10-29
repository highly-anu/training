import Foundation

/// `GET /philosophies/compare?ids=a,b[,c]` (src/explore_compare.compare): two
/// or three philosophies' glances side by side, what they share, what only one
/// has, and how alike each pair is. The phone lays it out as the web does
/// (design-system §6.42); nothing is compared on the device.
struct PhilosophyCompare: Decodable {
    let ids: [String]
    let philosophies: [CompareGlance]
    let trackWeeks: Int
    let pairs: [ComparePair]
    /// Which rows read alike across every column ("Only differences" hides them).
    let same: [String: Bool]
    let bias: CompareSplit<String>
    let equipment: CompareSplit<CompareNamed>
    let standards: CompareSplit<CompareStandard>

    private enum CodingKeys: String, CodingKey { case ids, philosophies, scale, pairs, same, bias, equipment, standards }
    private struct Scale: Decodable { let trackWeeks: Int? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ids = try c.decode([String].self, forKey: .ids)
        philosophies = (try c.decode([Lossy<CompareGlance>].self, forKey: .philosophies)).compactMap(\.value)
        trackWeeks = (try? c.decode(Scale.self, forKey: .scale))?.trackWeeks ?? 0
        pairs = ((try? c.decode([Lossy<ComparePair>].self, forKey: .pairs)) ?? []).compactMap(\.value)
        same = (try? c.decode([String: Bool].self, forKey: .same)) ?? [:]
        bias = (try? c.decode(CompareSplit<String>.self, forKey: .bias)) ?? .empty
        equipment = (try? c.decode(CompareSplit<CompareNamed>.self, forKey: .equipment)) ?? .empty
        standards = (try? c.decode(CompareSplit<CompareStandard>.self, forKey: .standards)) ?? .empty
    }

    func isSame(_ row: String) -> Bool { same[row] ?? false }
}

struct CompareNamed: Decodable, Hashable {
    let id: String
    let name: String
}

struct CompareStandard: Decodable, Hashable {
    let id: String?
    let name: String
    let domain: String?
    /// On a standard only one philosophy has: one of its phases tests it.
    let tested: Bool?
    /// On a shared one: the philosophies whose phases test it.
    let testedBy: [String]?

    var isTested: Bool { tested == true || !(testedBy ?? []).isEmpty }
}

/// `shared` by every column, `only` one (per id), and with three, what two hold.
struct CompareSplit<T: Decodable>: Decodable {
    struct Some: Decodable {
        let item: T
        let ids: [String]
    }
    let shared: [T]
    let only: [String: [T]]
    let some: [Some]

    static var empty: CompareSplit<T> { CompareSplit(shared: [], only: [:], some: []) }

    init(shared: [T], only: [String: [T]], some: [Some]) {
        self.shared = shared; self.only = only; self.some = some
    }

    private enum CodingKeys: String, CodingKey { case shared, only, some }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shared = (try? c.decode([T].self, forKey: .shared)) ?? []
        only = (try? c.decode([String: [T]].self, forKey: .only)) ?? [:]
        some = (try? c.decode([Some].self, forKey: .some)) ?? []
    }

    /// What column `id` shows: its own, then what it shares with one other.
    func column(_ id: String) -> [T] { (only[id] ?? []) + some.filter { $0.ids.contains(id) }.map(\.item) }
}

struct ComparePair: Decodable {
    struct Reason: Decodable { let label: String; let detail: String }
    let a: String
    let b: String
    let score: Double
    let primary: Reason
    let secondary: Reason
}

struct CompareSpan: Decodable {
    let min: Double
    let ideal: Double

    func text(_ unit: String = "") -> String {
        let f = { (n: Double) in n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n) }
        return min == ideal ? "\(f(ideal))\(unit)" : "\(f(min))–\(f(ideal))\(unit)"
    }
}

struct CompareMix: Decodable, Hashable {
    let modality: String
    let perWeek: Double
    let share: Double?
}

struct CompareGlance: Decodable, Identifiable {
    struct Measures: Decodable { let headline: String? }
    struct Models: Decodable { let intensity: String?; let progression: String? }
    struct Phase: Decodable, Identifiable {
        let id: String
        let name: String
        let kind: String
        let weeks: Int
    }
    struct Track: Decodable, Identifiable {
        let id: String
        let name: String
        let weeks: Int
        let repeatable: Bool?
        let requires: [String]?
        let kettlebellPair: Bool?
        let phases: [Phase]
    }

    let id: String
    let name: String
    let bias: [String]
    let levels: [String]
    let weeks: CompareSpan?
    let daysPerWeek: CompareSpan?
    let sessionMinutes: CompareSpan?
    let longSessionMinutes: Int?
    let equipment: [CompareNamed]
    let primaryTrackId: String?
    let mix: [CompareMix]
    let intensity: [String: Double]
    let measures: Measures?
    let models: Models?
    let tracks: [Track]

    var primaryTrack: Track? { tracks.first { $0.id == primaryTrackId } ?? tracks.first }
}

/// `POST /philosophies/<id>/for-me` (explore_compare.for_athlete): one track
/// generated on the athlete's profile, never saved, in the comparison's numbers.
struct PhilosophyForMe: Decodable {
    struct Assumed: Decodable { let key: String; let text: String }
    struct Reason: Decodable { let message: String }
    struct PerWeek: Decodable { let days: Double; let sessions: Double; let minutes: Double? }
    struct Mix: Decodable { let modality: String; let perWeek: Double }
    struct HeldBack: Decodable { let slots: Int; let sessions: Int }
    struct Gaps: Decodable {
        struct Substituted: Decodable { let modality: String?; let insteadOf: String? }
        let sessions: Int
        let slots: Int
        let substituted: [Substituted]
    }
    struct Tests: Decodable {
        struct Skipped: Decodable { let week: Int?; let why: String }
        let placed: Int
        let skipped: [Skipped]
    }
    struct Warning: Decodable { let message: String }
    struct Phase: Decodable { let name: String?; let kind: String?; let weeks: Int?; let sessions: Double?; let minutes: Double? }

    let id: String
    let trackId: String
    let trackName: String
    let feasible: Bool
    let weeks: Int
    let ofWeeks: Int
    let trackWeeks: Int?
    let assumed: [Assumed]
    let missingEquipment: [CompareNamed]
    let reasons: [Reason]
    let perWeek: PerWeek?
    let intensity: [String: Double]?
    let mix: [Mix]?
    let heldBack: HeldBack?
    let skippedForEquipment: Int?
    let sessionCount: Int?
    let gaps: Gaps?
    let tests: Tests?
    let warnings: [Warning]?
    let phases: [Phase]?
}
