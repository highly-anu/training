import Combine
import Foundation

/// Before a session: today's numbers beside the earlier times the same
/// session was done (`GET /api/sessions/briefing`, src/briefing.py). Every
/// sentence is the server's; nothing here formats a number. Each field is
/// read on its own, so a document with a key this build does not know, or
/// one it lacks, still shows the rest.
struct SessionBriefing: Decodable, Equatable {
    var headline: String?
    var items: [Item]
    var pending: [Pending]

    struct Item: Decodable, Equatable, Identifiable {
        var id: String
        var title: String
        var todayText: String
        var lines: [Line]
        var conditional: Bool
        var todayValues: [String: Double]
        var history: [Occurrence]
        var times: Int
        var metric: Metric?
        var cycleText: String?
        var cycleStep: Int?
        var cycleOf: Int?
        var suggestion: Suggestion?
        var standard: Standard?
        var notes: String?

        private enum Keys: String, CodingKey {
            case id, title, today, history, times, metric, cycle, suggestion, standard, notes
        }
        private enum TodayKeys: String, CodingKey { case text, lines, conditional, values }
        private enum CycleKeys: String, CodingKey { case text, step, of }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decode(String.self, forKey: .id)
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            let today = try? c.nestedContainer(keyedBy: TodayKeys.self, forKey: .today)
            todayText = (try? today?.decodeIfPresent(String.self, forKey: .text)) ?? ""
            lines = ((try? today?.decodeIfPresent([Lossy<Line>].self, forKey: .lines)) ?? []).compactMap(\.value)
            conditional = (try? today?.decodeIfPresent(Bool.self, forKey: .conditional)) ?? false
            todayValues = (try? today?.decodeIfPresent([String: Double].self, forKey: .values)) ?? [:]
            history = ((try? c.decodeIfPresent([Lossy<Occurrence>].self, forKey: .history)) ?? []).compactMap(\.value)
            times = (try? c.decodeIfPresent(Int.self, forKey: .times)) ?? history.count
            metric = try? c.decodeIfPresent(Metric.self, forKey: .metric)
            let cycle = try? c.nestedContainer(keyedBy: CycleKeys.self, forKey: .cycle)
            cycleText = try? cycle?.decodeIfPresent(String.self, forKey: .text)
            cycleStep = try? cycle?.decodeIfPresent(Int.self, forKey: .step)
            cycleOf = try? cycle?.decodeIfPresent(Int.self, forKey: .of)
            suggestion = try? c.decodeIfPresent(Suggestion.self, forKey: .suggestion)
            standard = try? c.decodeIfPresent(Standard.self, forKey: .standard)
            notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        }

        /// The series a chart draws: each earlier occurrence's value of the
        /// item's metric, then today's as planned. Fewer than three points
        /// is a list, not a line.
        var series: [SeriesPoint] {
            guard let key = metric?.id else { return [] }
            var out = history.compactMap { h in
                h.values[key].map { SeriesPoint(label: h.dayText, value: $0, planned: false, isDeload: h.isDeload) }
            }
            if let v = todayValues[key] { out.append(SeriesPoint(label: "Today", value: v, planned: true, isDeload: false)) }
            return out.count >= 3 ? out : []
        }
    }

    struct Line: Decodable, Equatable {
        var exerciseId: String
        var name: String
        var text: String
    }

    struct Occurrence: Decodable, Equatable, Identifiable {
        var id: String { date + (sessionKey ?? "") + text }
        var date: String
        var dayText: String
        var text: String
        var status: Status
        var isDeload: Bool
        var sessionKey: String?
        var values: [String: Double]

        private enum Keys: String, CodingKey { case date, dayText, text, status, isDeload, sessionKey, values }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            date = try c.decode(String.self, forKey: .date)
            dayText = (try? c.decodeIfPresent(String.self, forKey: .dayText)) ?? date
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
            status = Status(rawValue: (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "") ?? .logged
            isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
            sessionKey = try? c.decodeIfPresent(String.self, forKey: .sessionKey)
            values = (try? c.decodeIfPresent([String: Double].self, forKey: .values)) ?? [:]
        }
    }

    /// What an earlier occurrence was. A status this build does not know
    /// reads as logged.
    enum Status: String {
        case clean, made, missed, logged, unconfirmed

        var label: String {
            switch self {
            case .clean: return "Clean"
            case .made: return "Made"
            case .missed: return "Missed"
            case .logged: return "Logged"
            case .unconfirmed: return "Not confirmed"
            }
        }

        var symbol: String {
            switch self {
            case .clean, .made: return "checkmark.circle.fill"
            case .missed: return "xmark.circle"
            case .logged: return "circle.fill"
            case .unconfirmed: return "questionmark.circle"
            }
        }
    }

    struct Metric: Decodable, Equatable {
        var id: String
        var label: String
        var unit: String
    }

    struct Suggestion: Decodable, Equatable {
        var kind: String
        var text: String
    }

    struct Standard: Decodable, Equatable {
        var id: String?
        var name: String?
        var best: String?
        var target: String?
    }

    struct Pending: Decodable, Equatable, Identifiable {
        var id: String { sessionKey }
        var sessionKey: String
        var date: String
        var text: String
    }

    struct SeriesPoint: Equatable, Identifiable {
        var id: String { "\(label)-\(planned)" }
        var label: String
        var value: Double
        var planned: Bool
        var isDeload: Bool
    }

    private enum Keys: String, CodingKey { case headline, items, pending }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        headline = try? c.decodeIfPresent(String.self, forKey: .headline)
        items = ((try? c.decodeIfPresent([Lossy<Item>].self, forKey: .items)) ?? []).compactMap(\.value)
        pending = ((try? c.decodeIfPresent([Lossy<Pending>].self, forKey: .pending)) ?? []).compactMap(\.value)
    }

    /// Whether there is anything beyond the prescription to say: an earlier
    /// occurrence, a suggestion, a cycle, a standard.
    var saysSomething: Bool {
        !pending.isEmpty || items.contains {
            $0.times > 0 || $0.suggestion != nil || $0.cycleText != nil || $0.standard != nil
        }
    }

    /// One sentence for VoiceOver over an item's chart.
    static func seriesSummary(_ item: Item) -> String? {
        let s = item.series
        guard let first = s.first, let last = s.last, let m = item.metric else { return nil }
        func n(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
        return "\(s.count - 1) earlier sessions, from \(n(first.value)) to \(n(s[s.count - 2].value)) \(m.unit); today \(n(last.value))."
    }
}

/// Loads one session's briefing and says how that went (§6.3): the view
/// shows loading, the failure with a retry, or the document.
@MainActor
final class SessionBriefingLoader: ObservableObject {
    @Published private(set) var briefing: SessionBriefing?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var loadedKey: String?

    func load(api: APIClient?, sessionKey: String, date: String?, force: Bool = false) async {
        let key = "\(sessionKey)|\(date ?? "")"
        guard let api, force || loadedKey != key || (briefing == nil && !isLoading) else { return }
        loadedKey = key
        isLoading = true
        defer { isLoading = false }
        do {
            briefing = try await api.fetchBriefing(sessionKey: sessionKey, date: date)
            error = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { loadedKey = nil; return }
            self.error = "Your earlier sessions could not be read."
        }
    }
}
