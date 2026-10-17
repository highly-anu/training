import Foundation

// MARK: - The athlete's results on the standards

/// `GET /api/standards/results` (`src/standards.py`): per standard the current
/// and the best result, each placed on its ladder by the server, and every
/// entry. The phone used to work the level out itself from the thresholds, and
/// disagreed with the web — no "below entry", 1.25×BW printed as "1.3".
struct StandardResults: Decodable {
    let sex: String?
    let standards: [String: StandardResult]
    let bodyweight: Bodyweight?
    /// The program timeline, oldest first, so a history chart can shade each block.
    let blocks: [Block]
    /// The current program's own standards (declared or tested), in order,
    /// for Profile's "This program".
    let programStandards: [String]

    struct Bodyweight: Decodable {
        let value: Double
        let valueText: String
        let date: String?
        /// Every weight logged, so one can be corrected.
        let entries: [StandardResult.Entry]

        private enum CodingKeys: String, CodingKey { case value, valueText, date, entries }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            value = try c.decode(Double.self, forKey: .value)
            valueText = try c.decode(String.self, forKey: .valueText)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            entries = ((try? c.decodeIfPresent([Lossy<StandardResult.Entry>].self, forKey: .entries)) ?? nil)?
                .compactMap(\.value) ?? []
        }
    }

    struct Block: Decodable, Identifiable {
        let id: Int
        let name: String
        let from: String
        let to: String?
    }

    private struct ProgramStandard: Decodable { let id: String }
    private enum CodingKeys: String, CodingKey { case sex, standards, bodyweight, blocks, programStandards }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sex = try? c.decodeIfPresent(String.self, forKey: .sex)
        let lossy = ((try? c.decodeIfPresent([String: Lossy<StandardResult>].self, forKey: .standards)) ?? nil) ?? [:]
        standards = lossy.compactMapValues(\.value)
        bodyweight = try? c.decodeIfPresent(Bodyweight.self, forKey: .bodyweight)
        blocks = ((try? c.decodeIfPresent([Lossy<Block>].self, forKey: .blocks)) ?? nil)?.compactMap(\.value) ?? []
        programStandards = ((try? c.decodeIfPresent([Lossy<ProgramStandard>].self, forKey: .programStandards)) ?? nil)?
            .compactMap(\.value?.id) ?? []
    }
}

/// One value placed on a standard's ladder. `level` nil is below entry.
struct StandardPoint: Decodable {
    let value: Double
    let valueText: String
    let date: String?
    let level: String?
    let levelIndex: Int
    let next: String?
    let nextText: String?
    let gapText: String?
}

struct StandardResult: Decodable {
    /// One result, placed on its ladder by the server.
    struct Entry: Decodable, Identifiable {
        struct BlockRef: Decodable { let id: Int; let name: String }

        let entryId: Int?
        let value: Double
        let valueText: String
        /// The athlete's day it counts for.
        let date: String?
        let level: String?
        let levelIndex: Int
        /// manual | session | garmin | apple_watch | workout
        let source: String
        let note: String?
        /// "140 kg × 2 at 82 kg · est." for a ×BW result logged as a load.
        let inputText: String?
        /// The program block in force that day (or the test session's).
        let block: BlockRef?
        var id: String { entryId.map(String.init) ?? "\(date ?? "")-\(value)" }

        private enum CodingKeys: String, CodingKey {
            case entryId = "id", value, valueText, date, level, levelIndex, source, note, inputText, block
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            entryId = try? c.decodeIfPresent(Int.self, forKey: .entryId)
            value = try c.decode(Double.self, forKey: .value)
            valueText = try c.decode(String.self, forKey: .valueText)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            level = try? c.decodeIfPresent(String.self, forKey: .level)
            levelIndex = ((try? c.decodeIfPresent(Int.self, forKey: .levelIndex)) ?? nil) ?? 0
            source = ((try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil) ?? "manual"
            note = try? c.decodeIfPresent(String.self, forKey: .note)
            inputText = try? c.decodeIfPresent(String.self, forKey: .inputText)
            block = try? c.decodeIfPresent(BlockRef.self, forKey: .block)
        }

        /// Who logged it, in words.
        var sourceText: String {
            ["manual": "Typed in", "session": "From a session", "garmin": "Garmin",
             "apple_watch": "Apple Watch", "workout": "From a workout"][source] ?? source
        }
    }
    let current: StandardPoint
    let best: StandardPoint
    let count: Int
    let entries: [Entry]
}

/// What a result is sent as: typed text ("4:58"), or for a ×BW standard the
/// load lifted; the server reads and converts it. Nil fields are left out.
struct StandardResultInput: Encodable {
    var text: String? = nil
    var kg: Double? = nil
    var reps: Int? = nil
    /// The athlete's day (YYYY-MM-DD); today when nil.
    var loggedOn: String? = nil
    var note: String? = nil
}

// MARK: - Suggestions

/// A result a logged session suggests — a test slot's outcome, or a single
/// that beats the current result on a ×BW standard — waiting for the athlete
/// (`GET /api/standards/suggestions`, `src/standard_results.py`). It is not a
/// result until confirmed; every word is the server's.
struct StandardSuggestion: Decodable, Identifiable {
    let id: Int
    let benchmarkId: String
    let name: String
    /// The name without its parenthesis: "1-Mile Run".
    let shortName: String?
    let domain: String?
    let value: Double
    let valueText: String
    let level: String?
    let levelIndex: Int
    let next: String?
    let nextText: String?
    /// "20 + 7" for a partial round, the load for a single.
    let inputText: String?
    /// The result it would follow.
    let current: StandardPoint?
    let bestText: String?
    let isBest: Bool
    /// A re-logged value reopened a saved suggestion: the result saving it corrects.
    let replacesText: String?
    /// test_slot | derived_single | best_effort
    let origin: String
    /// pending | confirmed | dismissed
    let status: String
    let loggedOn: String?
    let sessionUid: String?
    let sessionKey: String?
    let sessionName: String?

    private enum CodingKeys: String, CodingKey {
        case id, benchmarkId, name, shortName, domain, value, valueText, level, levelIndex, next, nextText, inputText
        case current, bestText, isBest, replacesText, origin, status, loggedOn, sessionUid, sessionKey, sessionName
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        benchmarkId = try c.decode(String.self, forKey: .benchmarkId)
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? benchmarkId
        shortName = try? c.decodeIfPresent(String.self, forKey: .shortName)
        domain = try? c.decodeIfPresent(String.self, forKey: .domain)
        value = try c.decode(Double.self, forKey: .value)
        valueText = try c.decode(String.self, forKey: .valueText)
        level = try? c.decodeIfPresent(String.self, forKey: .level)
        levelIndex = ((try? c.decodeIfPresent(Int.self, forKey: .levelIndex)) ?? nil) ?? 0
        next = try? c.decodeIfPresent(String.self, forKey: .next)
        nextText = try? c.decodeIfPresent(String.self, forKey: .nextText)
        inputText = try? c.decodeIfPresent(String.self, forKey: .inputText)
        current = try? c.decodeIfPresent(StandardPoint.self, forKey: .current)
        bestText = try? c.decodeIfPresent(String.self, forKey: .bestText)
        isBest = ((try? c.decodeIfPresent(Bool.self, forKey: .isBest)) ?? nil) ?? false
        replacesText = try? c.decodeIfPresent(String.self, forKey: .replacesText)
        origin = ((try? c.decodeIfPresent(String.self, forKey: .origin)) ?? nil) ?? "test_slot"
        status = ((try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil) ?? "pending"
        loggedOn = try? c.decodeIfPresent(String.self, forKey: .loggedOn)
        sessionUid = try? c.decodeIfPresent(String.self, forKey: .sessionUid)
        sessionKey = try? c.decodeIfPresent(String.self, forKey: .sessionKey)
        sessionName = try? c.decodeIfPresent(String.self, forKey: .sessionName)
    }

    /// Whether it came from the test slot of the session with this key. The
    /// web logs under the day ("3-Monday"), the phone under the session
    /// ("3-Monday-0"); a day has one test, so the day decides.
    func isFromTest(sessionKey key: String) -> Bool {
        origin == "test_slot" && Self.dayKey(sessionKey ?? "") == Self.dayKey(key)
    }

    /// "3-Monday" from "3-Monday" or "3-Monday-0".
    static func dayKey(_ key: String) -> String {
        let parts = key.split(separator: "-")
        if parts.count >= 3, Int(parts.last!) != nil { return parts.dropLast().joined(separator: "-") }
        return key
    }
}

/// `{suggestions: [...]}`, one bad row dropped rather than the list.
struct StandardSuggestionList: Decodable {
    let suggestions: [StandardSuggestion]
    private enum CodingKeys: String, CodingKey { case suggestions }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = ((try? c.decodeIfPresent([Lossy<StandardSuggestion>].self, forKey: .suggestions)) ?? nil)?
            .compactMap(\.value) ?? []
    }
}

/// What a session-log save says about the standards it bears on: the
/// suggestions it produced, and any problem in words.
struct SessionLogStandards: Decodable {
    let pending: [StandardSuggestion]
    let error: String?
    private enum CodingKeys: String, CodingKey { case pending, error }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pending = ((try? c.decodeIfPresent([Lossy<StandardSuggestion>].self, forKey: .pending)) ?? nil)?
            .compactMap(\.value) ?? []
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - Words

enum StandardLevel {
    static let all = ["entry", "intermediate", "advanced", "elite"]

    /// A level in words: "Advanced", or "Below entry" under the first rung.
    static func name(_ level: String?) -> String {
        guard let level, let first = level.first else { return "Below entry" }
        return first.uppercased() + level.dropFirst()
    }

    /// How a standard moved this block, in words, from the server's numbers:
    /// "+1 level this block", "first result this block", "not retested this
    /// block" — or nil (the web's `blockChangeText`).
    static func blockChange(levelChange: Int?, hasStart: Bool, points: Int) -> String? {
        if let n = levelChange {
            if n == 0 { return "same level as at the block's start" }
            return "\(n > 0 ? "+" : "−")\(abs(n)) level\(abs(n) == 1 ? "" : "s") this block"
        }
        if !hasStart && points > 0 { return "first result this block" }
        if hasStart && points <= 1 { return "not retested this block" }
        return nil
    }

    /// A local calendar day as the server's YYYY-MM-DD.
    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// A server day (YYYY-MM-DD) as a local date at noon, for pickers and charts.
    static func date(_ iso: String?) -> Date? {
        guard let iso, iso.count >= 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: String(iso.prefix(10)) + " 12:00")
    }

    /// "17 Oct 2026" for a server day (YYYY-MM-DD), the day itself otherwise.
    static func day(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        return d.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

// MARK: - Tests in the program

/// A session that tests the phase's standards (`test` on the session,
/// src/generator._plan_week_tests), read from the keys the program round-trips.
struct SessionTestInfo {
    let archetypeId: String?
    let standards: [String]
    /// The session it stands in for, by name.
    let insteadOf: String?
}

extension JSONValue {
    fileprivate var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

extension ProgramSession {
    var testInfo: SessionTestInfo? {
        guard let t = extra["test"]?.objectValue else { return nil }
        return SessionTestInfo(
            archetypeId: t["archetype"]?.stringValue,
            standards: (t["standards"]?.arrayValue ?? []).compactMap(\.stringValue),
            insteadOf: t["instead_of"]?.objectValue?["name"]?.stringValue)
    }
}

extension ProgramExerciseAssignment {
    /// The standard this slot measures, when it is a test's scored slot.
    var standardId: String? { extra["standard"]?.objectValue?["id"]?.stringValue }
    /// The result kind it is logged as (duration, rounds, reps, hold, load, distance).
    var standardResult: String? { extra["standard"]?.objectValue?["result"]?.stringValue }
}
