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

    struct Bodyweight: Decodable {
        let value: Double
        let valueText: String
        let date: String?
    }

    private enum CodingKeys: String, CodingKey { case sex, standards, bodyweight }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sex = try? c.decodeIfPresent(String.self, forKey: .sex)
        let lossy = ((try? c.decodeIfPresent([String: Lossy<StandardResult>].self, forKey: .standards)) ?? nil) ?? [:]
        standards = lossy.compactMapValues(\.value)
        bodyweight = try? c.decodeIfPresent(Bodyweight.self, forKey: .bodyweight)
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
    struct Entry: Decodable, Identifiable {
        let entryId: Int?
        let value: Double
        let valueText: String
        let date: String?
        let level: String?
        let levelIndex: Int
        var id: String { entryId.map(String.init) ?? "\(date ?? "")-\(value)" }

        private enum CodingKeys: String, CodingKey { case entryId = "id", value, valueText, date, level, levelIndex }
    }
    let current: StandardPoint
    let best: StandardPoint
    let count: Int
    let entries: [Entry]
}

// MARK: - Words

enum StandardLevel {
    static let all = ["entry", "intermediate", "advanced", "elite"]

    /// A level in words: "Advanced", or "Below entry" under the first rung.
    static func name(_ level: String?) -> String {
        guard let level, let first = level.first else { return "Below entry" }
        return first.uppercased() + level.dropFirst()
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
