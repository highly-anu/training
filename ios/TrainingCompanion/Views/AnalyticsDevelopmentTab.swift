import SwiftUI
import Charts

/// Analytics ▸ Development: how the athlete has developed across programs.
/// The Program section is the current block; this is every block — the
/// activation timeline, each lift and currency across the whole span with
/// the blocks as bands, weekly load coloured by block, and the standards
/// ladder over time. Lays out the server's `/analytics/development`
/// document (`src/analytics/development.py`), which the web's Analytics ▸
/// Development reads too; nothing is computed here (design-system §6.20).
struct AnalyticsDevelopmentTab: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter

    /// The lift or currency on the chart; nil means the first one.
    @State private var selectedSeries: String? = nil

    var body: some View {
        Group {
            if let doc = appState.developmentAnalytics, doc.hasHistory {
                content(doc)
            } else if appState.isLoadingDevelopment && appState.developmentAnalytics == nil {
                ProgressView("Reading the history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.developmentError, appState.developmentAnalytics == nil {
                emptyState(icon: "exclamationmark.triangle", title: "Could not load",
                           message: error, actionLabel: "Try again") {
                    Task { await appState.loadDevelopmentAnalytics() }
                }
            } else {
                emptyState(icon: "clock.arrow.circlepath", title: "No program history yet",
                           message: "Blocks appear here as programs are saved.",
                           actionLabel: "Go to Program") { router.showProgram(.calendar) }
            }
        }
        // A new revision means a program was saved or generated, which is
        // what moves the history; the server caches the document otherwise.
        .task(id: appState.serverProgram?.revision) { await appState.loadIfStale("development") { await appState.loadDevelopmentAnalytics() } }
        .refreshable {
            await AppRefresh.perform { await appState.loadDevelopmentAnalytics(fresh: true) }
        }
    }

    // MARK: - Layout

    private func content(_ doc: DevelopmentAnalytics) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                BlocksCard(doc: doc)
                SeriesCard(doc: doc, selected: $selectedSeries)
                if !doc.weeklyLoad.isEmpty { LoadByBlockCard(doc: doc) }
                if !doc.benchmarks.isEmpty { StandardsCard(doc: doc) }
                Spacer(minLength: 24)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    private func emptyState(icon: String, title: String, message: String,
                            actionLabel: String, action: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            Button(actionLabel, action: action).buttonStyle(.bordered)
        }
    }
}

// MARK: - Blocks

private struct BlocksCard: View {
    let doc: DevelopmentAnalytics

    var body: some View {
        AnalyticsCard(header: "Blocks") {
            VStack(alignment: .leading, spacing: 10) {
                // The strip: each block's share of the span, in its colour.
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(doc.blocks) { block in
                            Rectangle()
                                .fill(doc.color(of: block.id))
                                .frame(width: max(4, geo.size.width * doc.share(of: block)))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                .accessibilityLabel("Program timeline, \(doc.blocks.count) blocks")

                ForEach(doc.blocks) { block in blockRow(block) }
            }
        }
    }

    private func blockRow(_ block: DevelopmentAnalytics.Block) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(doc.color(of: block.id)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(block.name).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                    if block.isActive {
                        TintCapsule(text: "current", color: .accentColor)
                    }
                }
                Label(spanText(block), systemImage: "calendar")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    // Done of planned; the percentage is the same fact, said to VoiceOver.
                    Label("\(block.completed)/\(block.planned)", systemImage: "checkmark.circle")
                        .accessibilityLabel("\(block.completed) of \(block.planned) sessions done"
                                            + (block.completionPct.map { ", \($0) percent" } ?? ""))
                    if block.plannedTotal > block.planned {
                        Label("\(block.plannedTotal - block.planned)", systemImage: "forward.end")
                            .accessibilityLabel("\(block.plannedTotal - block.planned) sessions never reached")
                    }
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private func spanText(_ block: DevelopmentAnalytics.Block) -> String {
        let from = DevelopmentAnalytics.day(block.from).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? block.from
        let to = block.to.flatMap(DevelopmentAnalytics.day).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "now"
        return "\(from)–\(to) · \(block.weeks) wk"
    }

}

// MARK: - Lifts and currencies across blocks

private struct SeriesCard: View {
    let doc: DevelopmentAnalytics
    @Binding var selected: String?

    private enum Option: Identifiable {
        case lift(DevelopmentAnalytics.Lift)
        case currency(DevelopmentAnalytics.Currency)

        var id: String {
            switch self {
            case .lift(let l): return "lift:\(l.id)"
            case .currency(let c): return "cur:\(c.id)"
            }
        }
        var label: String {
            switch self {
            case .lift(let l): return l.blocks > 1 ? "\(l.name) · \(l.blocks) blocks" : l.name
            case .currency(let c): return "\(c.name) · \(c.unit)"
            }
        }
        var unit: String {
            switch self {
            case .lift(let l): return l.unit
            case .currency(let c): return c.unit
            }
        }
        var points: [DevelopmentAnalytics.ChartPoint] {
            switch self {
            case .lift(let l): return DevelopmentAnalytics.chartPoints(l)
            case .currency(let c): return DevelopmentAnalytics.chartPoints(c)
            }
        }
        var perBlock: [DevelopmentAnalytics.PerBlock] {
            switch self {
            case .lift(let l): return l.perBlock
            case .currency(let c): return c.perBlock
            }
        }
        var trend: DevelopmentAnalytics.Trend {
            switch self {
            case .lift(let l): return l.trend
            case .currency(let c): return c.trend
            }
        }
    }

    private var options: [Option] {
        doc.lifts.map(Option.lift) + doc.currencies.map(Option.currency)
    }

    private var current: Option? {
        options.first { $0.id == selected } ?? options.first
    }

    var body: some View {
        AnalyticsCard(header: "Lifts across blocks") {
            if let option = current {
                VStack(alignment: .leading, spacing: 10) {
                    chips
                    chart(option)
                    TrendText(trend: option.trend)
                    perBlockRows(option)
                }
            } else {
                Text("Nothing logged yet")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options) { option in
                    let isOn = option.id == current?.id
                    Button {
                        withAnimation(AppAnimation.springStandard) { selected = option.id }
                    } label: {
                        Text(option.label)
                            .font(.footnote).fontWeight(isOn ? .semibold : .regular)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(isOn ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                            .clipShape(Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private func chart(_ option: Option) -> some View {
        let points = option.points
        return Chart {
            ForEach(doc.blocks) { block in
                if let span = doc.span(of: block) {
                    RectangleMark(xStart: .value("From", span.lowerBound), xEnd: .value("To", span.upperBound))
                        .foregroundStyle(doc.color(of: block.id).opacity(0.10))
                }
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(option.unit, p.value))
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", p.date), y: .value(option.unit, p.value))
                    .foregroundStyle(p.isDeload ? Color(.systemBackground) : doc.color(of: p.blockId))
                    .symbolSize(50)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        // fixedSize: a label at the trailing edge would otherwise truncate to "28 S…".
                        Text(d, format: .dateTime.day().month(.abbreviated))
                            .font(.caption2).foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    private func perBlockRows(_ option: Option) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(option.perBlock) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(doc.color(of: row.blockId)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(doc.block(row.blockId)?.name ?? "Block \(row.blockId)")
                            .font(.subheadline).fontWeight(.semibold).lineLimit(1)
                        HStack(spacing: 10) {
                            Text("\(number(row.first)) → \(number(row.last)) \(option.unit)")
                            Label(number(row.best), systemImage: "trophy")
                            Label("\(row.sessions)", systemImage: "list.bullet")
                        }
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(number(row.first)) to \(number(row.last)) \(option.unit), best \(number(row.best)), \(row.sessions) sessions")
                    }
                    Spacer(minLength: 4)
                    Text(DevelopmentAnalytics.formatDelta(row.delta))
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(row.delta > 0 ? Color.green : row.delta < 0 ? Color.yellow : Color.secondary)
                }
            }
        }
    }

    private func number(_ v: Double) -> String { AnalyticsProgramTab.number(v) }
}

/// A trend in words, in the status colour the engine's direction maps to.
private struct TrendText: View {
    let trend: DevelopmentAnalytics.Trend

    private var status: String {
        switch trend.direction {
        case "improving": return "on_track"
        case "declining": return "behind"
        case "stable": return "stable_by_design"
        default: return "insufficient_data"
        }
    }

    var body: some View {
        if trend.direction == "insufficient_data" {
            Label("No trend yet", systemImage: "hourglass").font(.footnote).foregroundStyle(.secondary)
        } else {
            Label("\(trend.slopePct > 0 ? "+" : "")\(AnalyticsProgramTab.number(trend.slopePct))%/session",
                  systemImage: trend.direction == "improving" ? "arrow.up.right"
                    : trend.direction == "declining" ? "arrow.down.right" : "arrow.right")
                .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(AnalyticsStatusStyle.color(status))
                .accessibilityLabel("\(trend.direction), \(AnalyticsProgramTab.number(trend.slopePct)) percent per session over \(trend.pointsUsed) points")
        }
    }
}

// MARK: - Load across blocks

private struct LoadByBlockCard: View {
    let doc: DevelopmentAnalytics

    private struct Bar: Identifiable {
        let id: String
        let weekStart: Date
        let trimp: Double
        let blockId: Int?
    }

    private var bars: [Bar] {
        doc.weeklyLoad.compactMap { w in
            w.weekStart.map { Bar(id: w.week, weekStart: $0, trimp: w.trimp, blockId: w.blockId) }
        }
    }

    var body: some View {
        AnalyticsCard(header: "TRIMP per week by block") {
            Chart(bars) { bar in
                BarMark(x: .value("Week", bar.weekStart, unit: .weekOfYear),
                        y: .value("TRIMP", bar.trimp))
                    .foregroundStyle(doc.color(of: bar.blockId).opacity(bar.blockId == nil ? 0.4 : 0.85))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 1)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d, format: .dateTime.month(.abbreviated))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 130)
        }
    }
}

// MARK: - Standards over time

/// Every standard with a result in the window, as a small chart across the
/// blocks — results belong to the athlete, so they run through every program.
/// The current program's own first; a gain is said in words, the level in the
/// standard's modality colour. Tap one for its history.
private struct StandardsCard: View {
    let doc: DevelopmentAnalytics
    @EnvironmentObject private var router: AppRouter

    private var own: [DevelopmentAnalytics.Benchmark] { doc.benchmarks.filter(\.inCurrentProgram) }
    private var other: [DevelopmentAnalytics.Benchmark] { doc.benchmarks.filter { !$0.inCurrentProgram } }

    var body: some View {
        AnalyticsCard(header: "Standards over time") {
            VStack(alignment: .leading, spacing: 14) {
                group(title: !own.isEmpty && !other.isEmpty ? "This program" : nil, rows: own)
                group(title: !own.isEmpty ? "Other standards" : nil, rows: other)
                Button { router.showProfile(.standards) } label: {
                    Label("Log a result", systemImage: "plus.circle")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.footnote)
                .accessibilityHint("Opens Profile, Standards")
            }
        }
    }

    @ViewBuilder
    private func group(title: String?, rows: [DevelopmentAnalytics.Benchmark]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let title {
                    Text(title.uppercased()).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                }
                ForEach(rows) { benchmark in
                    Button { router.openStandard(benchmark.benchmarkId) } label: { row(benchmark) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens Profile, Standards")
                }
            }
        }
    }

    private func row(_ b: DevelopmentAnalytics.Benchmark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(b.name).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 4)
                // The latest result is the row's number; the chart is its history.
                if let last = b.history.last {
                    Text(last.valueText ?? AnalyticsProgramTab.number(last.value))
                        .font(.subheadline).monospacedDigit()
                }
                StandardLevelBadge(level: b.latestLevel, domain: b.domain)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            if let gained = gainedText(b) {
                Text(gained).font(.caption).foregroundStyle(.secondary)
            }
            StandardHistoryChart(
                points: b.history.compactMap { StandardChartPoint(id: $0.id, day: $0.date, value: $0.value,
                                                                  valueText: $0.valueText ?? AnalyticsProgramTab.number($0.value),
                                                                  level: $0.level) },
                levels: StandardChartLevel.from(standards: b.standards, texts: b.standardsText),
                domain: b.domain,
                bands: doc.blocks.map { StandardChartBand(from: $0.from, to: $0.to) })
                .frame(height: 120)
        }
        .contentShape(Rectangle())
    }

    private func gainedText(_ b: DevelopmentAnalytics.Benchmark) -> String? {
        guard b.levelsGained != 0 else { return nil }
        let n = abs(b.levelsGained)
        return "\(b.levelsGained > 0 ? "+" : "−")\(n) level\(n == 1 ? "" : "s")"
    }
}
