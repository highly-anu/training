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
                           message: "Programs are recorded from the moment they are generated or saved. Development across them appears once there is a second block.",
                           actionLabel: "Go to Program") { router.show(.program) }
            }
        }
        // A new revision means a program was saved or generated, which is
        // what moves the history; the server caches the document otherwise.
        .task(id: appState.serverProgram?.revision) { await appState.loadDevelopmentAnalytics() }
        .refreshable {
            await AppRefresh.perform { await appState.loadDevelopmentAnalytics(fresh: true) }
        }
    }

    // MARK: - Layout

    private func content(_ doc: DevelopmentAnalytics) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                BlocksCard(doc: doc)
                if doc.blocks.count < 2 { singleBlockNote }
                SeriesCard(doc: doc, selected: $selectedSeries)
                if !doc.weeklyLoad.isEmpty { LoadByBlockCard(doc: doc) }
                if !doc.benchmarks.isEmpty { StandardsCard(doc: doc) }
                Spacer(minLength: 24)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    private var singleBlockNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("One block so far. Development across programs fills in when the next one starts.")
            Button("This program's own progress →") { router.showAnalytics(.progress) }
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func emptyState(icon: String, title: String, message: String,
                            actionLabel: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionLabel, action: action)
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Text("current")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(spanText(block)).font(.caption).foregroundStyle(.secondary)
                Text(sessionsText(block)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func spanText(_ block: DevelopmentAnalytics.Block) -> String {
        let from = DevelopmentAnalytics.day(block.from).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? block.from
        let to = block.to.flatMap(DevelopmentAnalytics.day).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "now"
        return "\(from) → \(to) · \(block.weeks) wk"
    }

    private func sessionsText(_ block: DevelopmentAnalytics.Block) -> String {
        var text = "\(block.completed) / \(block.planned) sessions"
        if let pct = block.completionPct { text += " · \(pct)%" }
        if block.plannedTotal > block.planned { text += " · \(block.plannedTotal - block.planned) never reached" }
        return text
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
        var caption: String {
            switch self {
            case .lift: return "Estimated 1RM of the heaviest completed set per session; the band is the block."
            case .currency: return "The logged value per session; the band is the block."
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
                    Text(option.caption).font(.caption2).foregroundStyle(.tertiary)
                    chart(option)
                    TrendText(trend: option.trend)
                    perBlockRows(option)
                }
            } else {
                Text("Nothing logged yet. Sets logged on a session appear here across every block that trained the lift.")
                    .font(.caption).foregroundStyle(.secondary)
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
                            .font(.caption).fontWeight(isOn ? .semibold : .regular)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(isOn ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
                            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
                            .font(.caption).fontWeight(.semibold).lineLimit(1)
                        Text("\(row.sessions) session\(row.sessions == 1 ? "" : "s") · \(number(row.first)) → \(number(row.last)) \(option.unit) · best \(number(row.best))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(DevelopmentAnalytics.formatDelta(row.delta))
                        .font(.caption).fontWeight(.semibold).monospacedDigit()
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
            Text("Not enough points for a trend").font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("\(trend.direction.capitalized) · \(trend.slopePct > 0 ? "+" : "")\(AnalyticsProgramTab.number(trend.slopePct))%/session over \(trend.pointsUsed)")
                .font(.caption2)
                .foregroundStyle(AnalyticsStatusStyle.color(status))
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
        AnalyticsCard(header: "Load across blocks") {
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
            Text("TRIMP per week, coloured by block")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Standards over time

private struct StandardsCard: View {
    let doc: DevelopmentAnalytics

    var body: some View {
        AnalyticsCard(header: "Standards over time") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(doc.benchmarks) { benchmark in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(benchmark.name).font(.caption).fontWeight(.semibold).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(levelText(benchmark))
                                .font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background((benchmark.levelsGained > 0 ? Color.green : Color.secondary).opacity(0.15))
                                .foregroundStyle(benchmark.levelsGained > 0 ? Color.green : Color.secondary)
                                .clipShape(Capsule())
                        }
                        Text(historyText(benchmark)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func levelText(_ b: DevelopmentAnalytics.Benchmark) -> String {
        var text = b.latestLevel ?? "below entry"
        if b.levelsGained > 0 { text += " · +\(b.levelsGained) level\(b.levelsGained == 1 ? "" : "s")" }
        return text
    }

    private func historyText(_ b: DevelopmentAnalytics.Benchmark) -> String {
        b.history.map { entry in
            let when = DevelopmentAnalytics.day(entry.date).map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? entry.date
            return "\(AnalyticsProgramTab.number(entry.value))\(b.unit) (\(entry.level ?? "below entry"), \(when))"
        }.joined(separator: " → ")
    }
}
