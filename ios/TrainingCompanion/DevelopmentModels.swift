import Foundation
import SwiftUI

/// `GET /api/analytics/development` — how the athlete has developed across
/// programs: the history tables (`program_activations`, `planned_sessions`,
/// logs and matches keyed by `session_uid`) read as one document by
/// `src/analytics/development.py`. The web's Analytics ▸ Development lays
/// out the same one; nothing is computed on the phone.
///
/// Decoded tolerantly, like `ProgramAnalytics`: a list element that fails
/// is dropped, a section that fails is empty, and a field the engine adds
/// later cannot blank the screen.
struct DevelopmentAnalytics: Decodable {
    let status: String                 // "ok" | "no_history"
    let generatedAt: String?
    let windowFrom: String
    let windowTo: String
    let blocks: [Block]
    let lifts: [Lift]
    let currencies: [Currency]
    let weeklyLoad: [WeeklyLoad]
    let benchmarks: [Benchmark]

    var hasHistory: Bool { status != "no_history" && !blocks.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case status, generatedAt, window, blocks, lifts, currencies, load, benchmarks
    }
    private struct Window: Decodable { let from: String?; let to: String? }
    private struct Load: Decodable { let weekly: [Lossy<WeeklyLoad>]? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "ok"
        generatedAt = try? c.decodeIfPresent(String.self, forKey: .generatedAt)
        let window = try? c.decodeIfPresent(Window.self, forKey: .window)
        windowFrom = window?.from ?? ""
        windowTo = window?.to ?? ""
        blocks = ((try? c.decodeIfPresent([Lossy<Block>].self, forKey: .blocks)) ?? [])?.compactMap(\.value) ?? []
        lifts = ((try? c.decodeIfPresent([Lossy<Lift>].self, forKey: .lifts)) ?? [])?.compactMap(\.value) ?? []
        currencies = ((try? c.decodeIfPresent([Lossy<Currency>].self, forKey: .currencies)) ?? [])?.compactMap(\.value) ?? []
        weeklyLoad = ((try? c.decodeIfPresent(Load.self, forKey: .load))??.weekly ?? []).compactMap(\.value)
        benchmarks = ((try? c.decodeIfPresent([Lossy<Benchmark>].self, forKey: .benchmarks)) ?? [])?.compactMap(\.value) ?? []
    }

    // MARK: Blocks — the activation timeline, oldest first

    struct Block: Decodable, Identifiable {
        let id: Int
        let versionId: String
        let label: String
        let methodologies: [Methodology]
        let from: String
        let to: String?                // nil while active
        let isActive: Bool
        let weeks: Int
        let plannedTotal: Int
        let planned: Int
        let completed: Int
        let completionPct: Int?
        let source: String?

        struct Methodology: Decodable, Identifiable {
            let id: String
            let name: String
        }

        /// The methodology names, else the server's label.
        var name: String {
            let names = methodologies.map(\.name).joined(separator: " + ")
            return names.isEmpty ? label : names
        }

        private enum CodingKeys: String, CodingKey {
            case id, versionId, label, methodologies, from, to, isActive, weeks, plannedTotal, planned, completed, completionPct, source
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            versionId = (try? c.decodeIfPresent(String.self, forKey: .versionId)) ?? ""
            label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
            methodologies = ((try? c.decodeIfPresent([Lossy<Methodology>].self, forKey: .methodologies)) ?? [])?.compactMap(\.value) ?? []
            from = try c.decode(String.self, forKey: .from)
            to = try? c.decodeIfPresent(String.self, forKey: .to)
            isActive = (try? c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? false
            weeks = (try? c.decodeIfPresent(Int.self, forKey: .weeks)) ?? 0
            plannedTotal = (try? c.decodeIfPresent(Int.self, forKey: .plannedTotal)) ?? 0
            planned = (try? c.decodeIfPresent(Int.self, forKey: .planned)) ?? 0
            completed = (try? c.decodeIfPresent(Int.self, forKey: .completed)) ?? 0
            completionPct = (try? c.decodeIfPresent(Double.self, forKey: .completionPct)).map { Int($0.rounded()) }
            source = try? c.decodeIfPresent(String.self, forKey: .source)
        }
    }

    // MARK: Lifts and currencies — one series across every block

    struct Trend: Decodable {
        let direction: String          // improving | stable | declining | insufficient_data
        let slopePct: Double
        let pointsUsed: Int

        private enum CodingKeys: String, CodingKey { case direction, slopePct, pointsUsed }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            direction = (try? c.decodeIfPresent(String.self, forKey: .direction)) ?? "insufficient_data"
            slopePct = (try? c.decodeIfPresent(Double.self, forKey: .slopePct)) ?? 0
            pointsUsed = (try? c.decodeIfPresent(Int.self, forKey: .pointsUsed)) ?? 0
        }
    }

    struct PerBlock: Decodable, Identifiable {
        let blockId: Int
        let sessions: Int
        let first: Double
        let last: Double
        let best: Double
        let delta: Double
        var id: Int { blockId }
    }

    struct LiftPoint: Decodable, Identifiable {
        let date: String
        let blockId: Int?
        let weight: Double
        let reps: Int?
        let est1rm: Double?
        let isDeload: Bool
        var id: String { date }
        /// What the chart plots: the estimated 1RM where there is one, else the weight.
        var value: Double { est1rm ?? weight }

        private enum CodingKeys: String, CodingKey { case date, blockId, weight, reps, est1rm, isDeload }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(String.self, forKey: .date)
            blockId = try? c.decodeIfPresent(Int.self, forKey: .blockId)
            weight = (try? c.decodeIfPresent(Double.self, forKey: .weight)) ?? 0
            reps = try? c.decodeIfPresent(Int.self, forKey: .reps)
            est1rm = try? c.decodeIfPresent(Double.self, forKey: .est1rm)
            isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
        }
    }

    struct Lift: Decodable, Identifiable {
        let exerciseId: String
        let name: String
        let unit: String
        let points: [LiftPoint]
        let perBlock: [PerBlock]
        let trend: Trend
        let blocks: Int
        var id: String { exerciseId }

        private enum CodingKeys: String, CodingKey { case exerciseId, name, unit, points, perBlock, trend, blocks }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            exerciseId = try c.decode(String.self, forKey: .exerciseId)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? exerciseId
            unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? "kg"
            points = ((try? c.decodeIfPresent([Lossy<LiftPoint>].self, forKey: .points)) ?? [])?.compactMap(\.value) ?? []
            perBlock = ((try? c.decodeIfPresent([Lossy<PerBlock>].self, forKey: .perBlock)) ?? [])?.compactMap(\.value) ?? []
            trend = try c.decode(Trend.self, forKey: .trend)
            blocks = (try? c.decodeIfPresent(Int.self, forKey: .blocks)) ?? 0
        }
    }

    struct CurrencyPoint: Decodable, Identifiable {
        let date: String
        let blockId: Int?
        let value: Double
        let isDeload: Bool
        var id: String { date }

        private enum CodingKeys: String, CodingKey { case date, blockId, value, isDeload }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = try c.decode(String.self, forKey: .date)
            blockId = try? c.decodeIfPresent(Int.self, forKey: .blockId)
            value = try c.decode(Double.self, forKey: .value)
            isDeload = (try? c.decodeIfPresent(Bool.self, forKey: .isDeload)) ?? false
        }
    }

    struct Currency: Decodable, Identifiable {
        let exerciseId: String
        let name: String
        let metric: String             // rounds | minutes | km
        let points: [CurrencyPoint]
        let perBlock: [PerBlock]
        let trend: Trend
        var id: String { "\(exerciseId):\(metric)" }

        var unit: String {
            switch metric {
            case "minutes": return "min"
            default: return metric
            }
        }

        private enum CodingKeys: String, CodingKey { case exerciseId, name, metric, points, perBlock, trend }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            exerciseId = try c.decode(String.self, forKey: .exerciseId)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? exerciseId
            metric = (try? c.decodeIfPresent(String.self, forKey: .metric)) ?? "rounds"
            points = ((try? c.decodeIfPresent([Lossy<CurrencyPoint>].self, forKey: .points)) ?? [])?.compactMap(\.value) ?? []
            perBlock = ((try? c.decodeIfPresent([Lossy<PerBlock>].self, forKey: .perBlock)) ?? [])?.compactMap(\.value) ?? []
            trend = try c.decode(Trend.self, forKey: .trend)
        }
    }

    // MARK: Load — weekly TRIMP with the block each week fell in

    struct WeeklyLoad: Decodable, Identifiable {
        let week: String               // ISO week, "2026-W38"
        let trimp: Double
        let sessions: Int
        let blockId: Int?
        var id: String { week }

        private enum CodingKeys: String, CodingKey { case week, trimp, sessions, blockId }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            week = try c.decode(String.self, forKey: .week)
            trimp = (try? c.decodeIfPresent(Double.self, forKey: .trimp)) ?? 0
            sessions = (try? c.decodeIfPresent(Int.self, forKey: .sessions)) ?? 0
            blockId = try? c.decodeIfPresent(Int.self, forKey: .blockId)
        }

        /// The Monday of an ISO week, for the chart's time axis.
        var weekStart: Date? {
            let parts = week.split(separator: "-W")
            guard parts.count == 2, let year = Int(parts[0]), let number = Int(parts[1]) else { return nil }
            var cal = Calendar(identifier: .iso8601)
            cal.timeZone = TimeZone.current
            return cal.date(from: DateComponents(weekday: 2, weekOfYear: number, yearForWeekOfYear: year))
        }
    }

    // MARK: Standards over time

    struct Benchmark: Decodable, Identifiable {
        struct Entry: Decodable, Identifiable {
            let date: String
            let value: Double
            let level: String?
            let levelIndex: Int
            var id: String { date }

            private enum CodingKeys: String, CodingKey { case date, value, level, levelIndex }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                date = try c.decode(String.self, forKey: .date)
                value = try c.decode(Double.self, forKey: .value)
                level = try? c.decodeIfPresent(String.self, forKey: .level)
                levelIndex = (try? c.decodeIfPresent(Int.self, forKey: .levelIndex)) ?? -1
            }
        }
        let benchmarkId: String
        let name: String
        let unit: String
        let lowerIsBetter: Bool
        let history: [Entry]
        let latestLevel: String?
        let levelsGained: Int
        var id: String { benchmarkId }

        private enum CodingKeys: String, CodingKey { case benchmarkId, name, unit, lowerIsBetter, history, latestLevel, levelsGained }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            benchmarkId = try c.decode(String.self, forKey: .benchmarkId)
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? benchmarkId
            unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
            lowerIsBetter = (try? c.decodeIfPresent(Bool.self, forKey: .lowerIsBetter)) ?? false
            history = ((try? c.decodeIfPresent([Lossy<Entry>].self, forKey: .history)) ?? [])?.compactMap(\.value) ?? []
            latestLevel = try? c.decodeIfPresent(String.self, forKey: .latestLevel)
            levelsGained = (try? c.decodeIfPresent(Int.self, forKey: .levelsGained)) ?? 0
        }
    }

    // MARK: Shaping — pure, so the view only lays out and a test can pin it

    /// Five hues, cycled in block order; a block keeps its colour on every
    /// chart. The same palette as the web's `lib/developmentShaping.ts`.
    static let palette: [Color] = [
        Color(red: 0.39, green: 0.40, blue: 0.95),   // indigo
        Color(red: 0.06, green: 0.73, blue: 0.51),   // emerald
        Color(red: 0.96, green: 0.62, blue: 0.04),   // amber
        Color(red: 0.93, green: 0.28, blue: 0.60),   // pink
        Color(red: 0.05, green: 0.65, blue: 0.91),   // sky
    ]

    /// The palette index of a block, nil for an unknown or missing id.
    func paletteIndex(of blockId: Int?) -> Int? {
        guard let blockId, let idx = blocks.firstIndex(where: { $0.id == blockId }) else { return nil }
        return idx % Self.palette.count
    }

    func color(of blockId: Int?) -> Color {
        paletteIndex(of: blockId).map { Self.palette[$0] } ?? Color.secondary
    }

    func block(_ id: Int?) -> Block? {
        guard let id else { return nil }
        return blocks.first { $0.id == id }
    }

    /// A date string "2026-09-25" (or a longer ISO stamp) as a local-midnight Date.
    static func day(_ value: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(value.prefix(10)))
    }

    /// A block's span on the time axis; the active block runs to the window's end.
    func span(of block: Block) -> ClosedRange<Date>? {
        guard let start = Self.day(block.from), let end = Self.day(block.to ?? windowTo), end >= start else { return nil }
        return start...end
    }

    /// A block's share of the whole timeline, for the strip at the top.
    func share(of block: Block) -> Double {
        guard let first = blocks.first.flatMap(span(of:)), let last = blocks.last.flatMap(span(of:)),
              let own = span(of: block) else { return 0 }
        let total = max(1, last.upperBound.timeIntervalSince(first.lowerBound))
        return own.upperBound.timeIntervalSince(own.lowerBound) / total
    }

    /// One plotted point: a lift's est-1RM (else weight) or a currency's value, on a real date.
    struct ChartPoint: Identifiable, Equatable {
        let date: Date
        let value: Double
        let blockId: Int?
        let isDeload: Bool
        let detail: String?            // "57.5 kg × 5" for a lift
        var id: Date { date }
    }

    static func chartPoints(_ lift: Lift) -> [ChartPoint] {
        lift.points.compactMap { p in
            guard let date = day(p.date) else { return nil }
            let detail = p.reps.map { "\(p.weight.formatted(.number.precision(.fractionLength(0...1)))) kg × \($0)" }
            return ChartPoint(date: date, value: p.value, blockId: p.blockId, isDeload: p.isDeload, detail: detail)
        }
    }

    static func chartPoints(_ currency: Currency) -> [ChartPoint] {
        currency.points.compactMap { p in
            guard let date = day(p.date) else { return nil }
            return ChartPoint(date: date, value: p.value, blockId: p.blockId, isDeload: p.isDeload, detail: nil)
        }
    }

    /// "+12.5" / "−3" / "0" for a per-block delta.
    static func formatDelta(_ delta: Double) -> String {
        let magnitude = abs(delta).formatted(.number.precision(.fractionLength(0...1)))
        if delta > 0 { return "+\(magnitude)" }
        if delta < 0 { return "−\(magnitude)" }
        return "0"
    }
}
