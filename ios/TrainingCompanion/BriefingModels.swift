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
        /// Exercise by exercise: each one's line today and its own earlier
        /// ones. Empty from a server that does not send it yet.
        var exercises: [Exercise]
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
            case id, title, today, exercises, history, times, metric, cycle, suggestion, standard, notes
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
            exercises = ((try? c.decodeIfPresent([Lossy<Exercise>].self, forKey: .exercises)) ?? []).compactMap(\.value)
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
    }

    struct Exercise: Decodable, Equatable, Identifiable {
        var id: String { exerciseId }
        var exerciseId: String
        var name: String
        var todayText: String
        /// Today's number in `metric`, when the plan has one.
        var todayValue: Double?
        var history: [Occurrence]
        /// Every earlier time, oldest first, each with its `value` in
        /// `metric`. Nil from a server that sends only `history`.
        var run: [Occurrence]?
        var times: Int?
        var timesText: String?
        var metric: Metric?

        private enum Keys: String, CodingKey { case exerciseId, name, today, history, run, times, timesText, metric }
        private enum TodayKeys: String, CodingKey { case text, value }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            exerciseId = try c.decode(String.self, forKey: .exerciseId)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? exerciseId
            let today = try? c.nestedContainer(keyedBy: TodayKeys.self, forKey: .today)
            todayText = (try? today?.decodeIfPresent(String.self, forKey: .text)) ?? ""
            todayValue = try? today?.decodeIfPresent(Double.self, forKey: .value)
            history = ((try? c.decodeIfPresent([Lossy<Occurrence>].self, forKey: .history)) ?? []).compactMap(\.value)
            run = (try? c.decodeIfPresent([Lossy<Occurrence>].self, forKey: .run))?.compactMap(\.value)
            times = try? c.decodeIfPresent(Int.self, forKey: .times)
            timesText = try? c.decodeIfPresent(String.self, forKey: .timesText)
            metric = try? c.decodeIfPresent(Metric.self, forKey: .metric)
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
        /// A run's point: this time's number in the run's metric.
        var value: Double?

        private enum Keys: String, CodingKey { case date, dayText, text, status, isDeload, sessionKey, values, value }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            date = try c.decode(String.self, forKey: .date)
            dayText = (try? c.decodeIfPresent(String.self, forKey: .dayText)) ?? date
            text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
            status = Status(rawValue: (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "") ?? .logged
            isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
            sessionKey = try? c.decodeIfPresent(String.self, forKey: .sessionKey)
            values = (try? c.decodeIfPresent([String: Double].self, forKey: .values)) ?? [:]
            value = try? c.decodeIfPresent(Double.self, forKey: .value)
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

    // MARK: - Rows

    /// One mark of a row's strip: an earlier time.
    struct Mark: Equatable {
        var value: Double?
        var status: Status
        var isDeload: Bool
    }

    /// The screen's unit (§6.61): one exercise — its name, today's numbers
    /// and every earlier time as one mark each. The dated lines, the chart,
    /// the standard and the note are the row's sheet.
    struct Row: Equatable, Identifiable {
        var id: String
        /// The item's name over its first row, when the item has several
        /// exercises; `headerDetail` is its cycle position.
        var header: String?
        var headerDetail: String?
        var name: String
        var todayText: String
        var todayValue: Double?
        /// Every earlier time, oldest first.
        var run: [Occurrence]
        var metric: Metric?
        /// "6 sessions", "First time"; an item of one exercise in a cycle,
        /// "Step 7 of 32".
        var caption: String
        /// The item's one suggestion, under its last row.
        var suggestion: Suggestion?
        var item: Item

        var marks: [Mark] { run.map { Mark(value: $0.value, status: $0.status, isDeload: $0.isDeload) } }

        /// The marks a strip of `count` places draws: the newest.
        func marks(fitting count: Int) -> [Mark] { Array(marks.suffix(max(0, count))) }

        /// The sheet's chart: every earlier time's number, then today's as
        /// planned. Fewer than three points is a list, not a chart, and so
        /// is a run that never changes.
        var series: [SeriesPoint] {
            var out = run.compactMap { o in
                o.value.map { SeriesPoint(label: o.date, value: $0, planned: false, isDeload: o.isDeload) }
            }
            if let todayValue { out.append(SeriesPoint(label: "Today", value: todayValue, planned: true, isDeload: false)) }
            return out.count >= 3 && Set(out.map(\.value)).count > 1 ? out : []
        }

        /// One sentence for VoiceOver over the sheet's chart.
        var seriesSummary: String? {
            let s = series
            guard let first = s.first, let last = s.last, let metric else { return nil }
            let earlier = last.planned ? Array(s.dropLast()) : s
            guard let latest = earlier.last else { return nil }
            var text = "\(earlier.count) earlier sessions, from \(Self.number(first.value)) to \(Self.number(latest.value)) \(metric.unit)"
            if last.planned { text += "; today \(Self.number(last.value))" }
            return text + "."
        }

        /// The row read aloud as one element.
        var accessibilityLabel: String {
            var parts = ["\(name). Today: \(todayText)", caption]
            if !run.isEmpty, !caption.contains("session") {
                parts.append(run.count == 1 ? "1 earlier session" : "\(run.count) earlier sessions")
            }
            if let last = run.last {
                parts.append("Last, \(last.dayText): \(last.text), \(last.status.label.lowercased())")
            }
            if let suggestion { parts.append(suggestion.text) }
            return parts.joined(separator: ". ")
        }

        static func number(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    }

    /// How tall a strip's mark is, as a share of the strip: the run's lowest
    /// number a third, its highest the whole, so a small step still shows;
    /// a mark without a number, or a run that never moves, sits in between.
    static func markHeight(_ value: Double?, in values: [Double]) -> Double {
        guard let value, let lo = values.min(), let hi = values.max(), hi > lo else { return 0.6 }
        return 1.0 / 3 + (2.0 / 3) * (value - lo) / (hi - lo)
    }

    /// The rows of the screen, in the session's order. An item of one
    /// exercise is one row under the item's name, its cycle position the
    /// short caption ("Step 7 of 32" — the stages are the sheet's); an item of
    /// several is headed once. A session to confirm holds up every module
    /// of the day: that sentence is said by the first and not again.
    var rows: [Row] {
        var said = Set<String>()
        return items.flatMap { item -> [Row] in
            let several = item.exercises.count > 1
            let suggestion = item.suggestion.flatMap { $0.kind != "confirm_pending" || said.insert($0.text).inserted ? $0 : nil }
            let cycle: String? = item.cycleStep.flatMap { step in item.cycleOf.map { "Step \(step) of \($0)" } } ?? item.cycleText
            func caption(_ times: Int, _ text: String?) -> String {
                text ?? (times == 0 ? "First time" : times == 1 ? "1 session" : "\(times) sessions")
            }
            guard !item.exercises.isEmpty else {
                // A server that sends no exercises: the item is its own row.
                let key = item.metric?.id
                let run = item.history.map { o -> Occurrence in
                    var o = o; o.value = key.flatMap { o.values[$0] }; return o
                }
                return [Row(id: item.id, header: nil, headerDetail: nil, name: item.title,
                            todayText: item.lines.first?.text ?? item.todayText,
                            todayValue: key.flatMap { item.todayValues[$0] }, run: run, metric: item.metric,
                            caption: cycle ?? caption(item.times, nil), suggestion: suggestion, item: item)]
            }
            return item.exercises.enumerated().map { index, exercise in
                let key = exercise.metric?.id ?? (several ? nil : item.metric?.id)
                let run = exercise.run ?? exercise.history.map { o -> Occurrence in
                    var o = o; o.value = key.flatMap { o.values[$0] }; return o
                }
                return Row(id: "\(item.id)/\(exercise.exerciseId)",
                           header: several && index == 0 ? item.title : nil,
                           headerDetail: several && index == 0 ? item.cycleText : nil,
                           name: several ? exercise.name : item.title,
                           todayText: exercise.todayText.isEmpty ? item.todayText : exercise.todayText,
                           todayValue: exercise.todayValue ?? (exercise.run == nil ? key.flatMap { item.todayValues[$0] } : nil),
                           run: run, metric: exercise.metric ?? (several ? nil : item.metric),
                           caption: (several ? nil : cycle)
                               ?? caption(exercise.times ?? (several ? run.count : item.times), exercise.timesText),
                           suggestion: index == item.exercises.count - 1 ? suggestion : nil, item: item)
            }
        }
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
