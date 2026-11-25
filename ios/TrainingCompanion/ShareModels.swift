import Foundation

// Shared links (docs/roadmap.md item 25): a method, a program or a session as
// `<web>/s/<token>`, opened in the app as `trainingcompanion://share?token=…`.
// The server's document (GET /api/shares/<token>) says what the link is and
// what the reader has of what it needs; these decode it, section by section,
// and `ShareWords` words it. The web's copy: api/shares.ts, lib/shareRefusal.ts.

/// A workout block as the server reads a session (src/session_blocks.py):
/// what opens it, what repeats in rounds, the rest, what closes it. Every
/// word is the server's.
struct SessionBlock: Decodable, Identifiable, Hashable {
    struct Movement: Decodable, Hashable {
        struct Exercise: Decodable, Hashable { let id: String; let name: String }
        let role: String
        let name: String
        let count: String?
        let eachSide: Bool
        let note: String?
        let exercises: [Exercise]

        enum CodingKeys: String, CodingKey { case role, name, count, eachSide, note, exercises }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decode(String.self, forKey: .role)
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            // A count is words ("21-15-9") or a bare number, as the slot wrote it.
            count = (try? c.decode(String.self, forKey: .count)) ?? (try? c.decode(Int.self, forKey: .count)).map(String.init)
            eachSide = (try? c.decode(Bool.self, forKey: .eachSide)) ?? false
            note = try? c.decode(String.self, forKey: .note)
            exercises = (try? c.decode([Exercise].self, forKey: .exercises)) ?? []
        }
    }
    struct Rest: Decodable, Hashable { let between: String?; let text: String? }
    struct Group: Decodable, Hashable { let id: String; let kind: String }

    let id: String
    let stage: String
    let stageLabel: String
    let shape: String
    let title: String?
    let headline: String?
    let again: String?
    let load: String?
    let note: String?
    let rest: Rest?
    let group: Group?
    let movements: [Movement]

    enum CodingKeys: String, CodingKey {
        case id, stage, stageLabel, shape, title, headline, again, load, note, rest, group, movements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        stage = (try? c.decode(String.self, forKey: .stage)) ?? "main"
        stageLabel = (try? c.decode(String.self, forKey: .stageLabel)) ?? ""
        shape = (try? c.decode(String.self, forKey: .shape)) ?? "sets"
        title = try? c.decode(String.self, forKey: .title)
        headline = try? c.decode(String.self, forKey: .headline)
        again = try? c.decode(String.self, forKey: .again)
        load = try? c.decode(String.self, forKey: .load)
        note = try? c.decode(String.self, forKey: .note)
        rest = try? c.decode(Rest.self, forKey: .rest)
        group = try? c.decode(Group.self, forKey: .group)
        movements = (try? c.decode([Movement].self, forKey: .movements)) ?? []
    }

    /// Whether its movements run in a loop: rounds, an AMRAP, every minute, for time.
    var isLoop: Bool { ["rounds", "amrap", "emom", "for_time", "interval"].contains(shape) && movements.count > 1 }

    /// What ends a round: its rest, and what sends it round again.
    var foot: String? {
        let parts = [rest?.between == "rounds" ? rest?.text : nil, again].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Blocks out of a value the phone keeps unmodelled (a session's `extra["blocks"]`).
    static func list(from value: JSONValue?) -> [SessionBlock] {
        guard let value, let data = try? JSONEncoder().encode(value) else { return [] }
        return (try? JSONDecoder().decode([SessionBlock].self, from: data)) ?? []
    }

    /// Consecutive blocks of one stage, in the session's order.
    static func stages(_ blocks: [SessionBlock]) -> [(label: String, blocks: [SessionBlock])] {
        var out: [(label: String, blocks: [SessionBlock])] = []
        for block in blocks {
            if let last = out.last, last.blocks.first?.stage == block.stage {
                out[out.count - 1].blocks.append(block)
            } else {
                out.append((block.stageLabel, [block]))
            }
        }
        return out
    }
}

extension ProgramSession {
    /// Its blocks, derived by the server on every read and never stored.
    var blocks: [SessionBlock] { SessionBlock.list(from: extra["blocks"]) }
}

struct SharedMethodRef: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let isPrivate: Bool
    enum CodingKeys: String, CodingKey { case id, name, isPrivate = "private" }
}

struct ShareAvailability: Decodable, Hashable {
    struct Method: Decodable, Hashable, Identifiable {
        let id: String
        let name: String
        /// shipped · have · different · missing
        let state: String
        let savable: Bool
    }
    let yours: Bool
    let methods: [Method]
    let ready: Bool
    let toSave: Int
    let canSave: Bool
}

/// generate's body as the server wrote it for the reader (src/sharing.recipe_for).
struct ShareRecipe: Decodable, Hashable {
    struct Lane: Decodable, Hashable {
        let philosophyId: String
        let trackId: String?
        let weight: Double?
        let startPhase: String?
        enum CodingKeys: String, CodingKey {
            case philosophyId = "philosophy_id", trackId = "track_id", weight, startPhase = "start_phase"
        }
    }
    let numWeeks: Int?
    let philosophyId: String?
    let philosophyIds: [String]?
    let philosophyWeights: [String: Double]?
    let lanes: [Lane]?
    let trackId: String?
    let startPhase: String?
    let contractOptions: [String: String]?

    enum CodingKeys: String, CodingKey {
        case numWeeks = "num_weeks", philosophyId = "philosophy_id", philosophyIds = "philosophy_ids"
        case philosophyWeights = "philosophy_weights", lanes, trackId = "track_id", startPhase = "start_phase"
        case contractOptions = "contract_options"
    }

    /// The tracks the program builder starts from (BuilderStart): one a
    /// method, weights on the builder's 0–100 scale. Empty when the recipe
    /// names no method.
    var builderLanes: [BuilderLane] {
        if let lanes, lanes.count > 1 {
            return lanes.map { BuilderLane(philosophyId: $0.philosophyId, trackId: $0.trackId,
                                           weight: (($0.weight ?? 0) * 100).rounded(), startPhaseId: $0.startPhase) }
        }
        if let ids = philosophyIds, ids.count > 1 {
            return ids.enumerated().map { i, id in
                BuilderLane(philosophyId: id, trackId: i == 0 ? trackId : nil,
                            weight: ((philosophyWeights?[id] ?? 1 / Double(ids.count)) * 100).rounded(),
                            startPhaseId: i == 0 ? startPhase : nil)
            }
        }
        guard let id = philosophyId ?? philosophyIds?.first else { return [] }
        return [BuilderLane(philosophyId: id, trackId: trackId, startPhaseId: startPhase)]
    }
}

/// A shared program's recipe as the builder opens on it.
struct BuilderStart: Hashable, Identifiable {
    let id = UUID()
    let lanes: [BuilderLane]
    let numWeeks: Int?
    let contractOptions: [String: String]

    init?(recipe: ShareRecipe?) {
        guard let recipe, !recipe.builderLanes.isEmpty else { return nil }
        lanes = recipe.builderLanes
        numWeeks = recipe.numWeeks
        contractOptions = recipe.contractOptions ?? [:]
    }
}

struct SharedSessionDoc: Decodable {
    struct Week: Decodable {
        let weekNumber: Int?
        let phase: String?
        let phaseName: String?
        let isDeload: Bool?
        enum CodingKeys: String, CodingKey {
            case weekNumber = "week_number", phase, phaseName = "phase_name", isDeload = "is_deload"
        }
    }
    struct Method: Decodable { let id: String; let name: String }
    let name: String
    let session: ProgramSession
    let day: String?
    let week: Week?
    let method: Method?
}

struct SharedProgramSummary: Decodable {
    struct Phase: Decodable, Hashable {
        let name: String?
        let kind: String?
        let weeks: Int
    }
    struct Track: Decodable, Hashable { let name: String?; let weight: Double? }
    let name: String?
    let weeks: Int
    let phases: [Phase]
    let tracks: [Track]
    let daysPerWeek: Int?
    let sessionsPerWeek: Int?
}

/// The Explore document a method's link carries (src/explore_philosophy.py),
/// as much of it as the phone lays out.
struct SharedMethodDescribe: Decodable {
    struct Span: Decodable { let min: Int?; let ideal: Int? }
    struct Glance: Decodable {
        let weeks: Span?
        let daysPerWeek: Span?
        let sessionMinutes: Span?
        let levels: [String]?
    }
    struct Phase: Decodable, Hashable {
        let name: String?
        let kind: String?
        let weeks: Int?
        let focus: String?
    }
    struct Track: Decodable, Identifiable {
        let id: String
        let name: String?
        let description: String?
        let weeks: Int?
        let phases: [Phase]?
    }
    struct Group: Decodable, Identifiable {
        let id: String
        let name: String?
        let modality: String?
        let sessions: [String]
    }
    struct Session: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let minutes: Int?
        let modality: String?
        let note: String?
        let icon: String?
        let blocks: [SessionBlock]?
        static func == (a: Session, b: Session) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    let name: String
    let summary: String?
    let principles: [String]?
    let glance: Glance?
    let tracks: [Track]?
    let groups: [Group]?
    let sessions: [String: Session]?
}

struct SharedMethodDoc: Decodable {
    let id: String
    let name: String
    let shipped: Bool
    let describe: SharedMethodDescribe?
}

struct ShareDocument: Decodable {
    let token: String
    /// package · program · session
    let kind: String
    let title: String?
    let session: SharedSessionDoc?
    let method: SharedMethodDoc?
    let program: SharedProgramSummary?
    let methods: [SharedMethodRef]?
    let availability: ShareAvailability?
    let recipe: ShareRecipe?
}

/// A link the athlete made (POST /api/shares, GET /api/shares).
struct ShareLinkInfo: Decodable, Identifiable, Hashable {
    let token: String
    let kind: String
    let title: String?
    let createdAt: String?
    let url: String
    var id: String { token }
}

struct ShareLinkList: Decodable { let shares: [ShareLinkInfo] }

/// What the athlete shares (POST /api/shares' body).
enum ShareRequest: Hashable {
    case package(String)
    case program
    case session(key: String, date: String?)

    var body: [String: String] {
        switch self {
        case .package(let id): return ["kind": "package", "package_id": id]
        case .program: return ["kind": "program"]
        case .session(let key, let date):
            var out = ["kind": "session", "key": key]
            if let date { out["date"] = date }
            return out
        }
    }
}

/// How a save ended.
enum ShareSaveOutcome: Equatable {
    case saved([String])
    /// The reader holds another version: offered as Replace, never done unasked.
    case different([String])
    case refused(String)
}

/// The shared-link screens' words (the web's lib/shareRefusal.ts, MethodsNeeded: change both).
enum ShareWords {
    static func kind(_ kind: String) -> String {
        ["session": "Shared session", "package": "Shared method", "program": "Shared program"][kind] ?? "Shared link"
    }

    static func listKind(_ kind: String) -> String {
        ["session": "Session", "package": "Method", "program": "Program"][kind] ?? "Link"
    }

    static func state(_ state: String) -> String {
        ["shipped": "In the app", "have": "You have it", "different": "You have another version",
         "missing": "Not saved yet"][state] ?? ""
    }

    /// The day a link was made, from the server's timestamp ("2026-11-25T08:00:00Z" → "25 Nov 2026").
    static func day(_ stamp: String?) -> String? {
        guard let stamp, stamp.count >= 10 else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(stamp.prefix(10))) else { return nil }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    static let gone = "This link is no longer shared. Whoever sent it removed it, or the address is incomplete."

    /// Where a session stood: "Week 3 · Monday".
    static func place(week: Int?, day: String?) -> String {
        [week.map { "Week \($0)" }, day].compactMap { $0 }.joined(separator: " · ")
    }

    /// A method's size in a line: "12–16 weeks · 4–5 days a week · 60–90 min".
    static func span(_ span: SharedMethodDescribe.Span?, unit: String) -> String? {
        guard let low = span?.min ?? span?.ideal else { return nil }
        let high = span?.ideal ?? low
        return low == high ? "\(low) \(unit)" : "\(low)–\(high) \(unit)"
    }

    /// POST /api/shares/<token>/save, answered.
    static func saveOutcome(status: Int, body: Data) -> ShareSaveOutcome {
        struct Named: Decodable { let name: String }
        struct Problem: Decodable { let message: String }
        struct Answer: Decodable {
            let installed: [Named]?
            let error: String?
            let busy: Bool?
            let olderEngine: Bool?
            let name: String?
            let methods: [Named]?
            let problems: [Problem]?
            let detail: String?
        }
        let answer = try? JSONDecoder().decode(Answer.self, from: body)
        if (200...299).contains(status) { return .saved(answer?.installed?.map(\.name) ?? []) }
        if answer?.busy == true { return .refused("The server is busy with another check. Try again in a moment.") }
        let name = answer?.name ?? "This method"
        switch answer?.error {
        case "different": return .different(answer?.methods?.map(\.name) ?? [])
        case "too_many_packages":
            return .refused("You keep the most methods an account can hold. Remove one, then save this.")
        case "not_enabled": return .refused("Saving methods is not available for this account.")
        case "not_found": return .refused("This link is no longer shared.")
        case "not_installable":
            if answer?.olderEngine == true {
                return .refused("\(name) was written for an earlier version of the app and no longer passes its checks. Ask for a new link.")
            }
            if let first = answer?.problems?.first?.message { return .refused("\(name) did not pass the app's checks: \(first)") }
            return .refused("\(name) did not pass the app's checks.")
        default:
            return .refused(answer?.detail ?? "The method could not be saved. Try again.")
        }
    }
}
