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
