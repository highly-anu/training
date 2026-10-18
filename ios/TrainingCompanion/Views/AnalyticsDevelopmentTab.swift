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

                ForEach(doc.blocks) { block in
                    // The block as it was planned, week by week (§6.37) — the
                    // screen Program ▸ History opens.
                    NavigationLink {
                        ProgramVersionDetailView(versionId: block.versionId, title: block.name)
                    } label: {
                        HStack(spacing: 8) {
                            blockRow(block)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption).fontWeight(.semibold).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the block, week by week")
                }
            }
        }
    }

    private func blockRow(_ block: DevelopmentAnalytics.Block) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(doc.color(of: block.id)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(block.name).font(.subheadline).fontWeight(.semibold).lineLimit(2)
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
    /// The day the athlete is touching on the chart, if any.
    @State private var touched: Date?

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
        var name: String {
            switch self {
            case .lift(let l): return l.name
            case .currency(let c): return c.name
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

    /// The summary (§6.37): which series, its chart across the blocks (touch
    /// it for a session's set), the trend, and a row to the per-block numbers.
    /// A row of chips picked the series and every block's row sat under the
    /// chart until 2026-10-17.
    var body: some View {
        AnalyticsCard(header: "Lifts across blocks") {
            if let option = current {
                VStack(alignment: .leading, spacing: 10) {
                    if options.count > 1 {
                        // A display choice inside the card, so a menu (§6.8).
                        LabeledContent {
                            Picker("Series", selection: Binding(get: { current?.id }, set: { id in
                                withAnimation(AppAnimation.springStandard) { selected = id; touched = nil }
                            })) {
                                ForEach(options) { o in Text(o.label).tag(Optional(o.id)) }
                            }
                            .pickerStyle(.menu)
                        } label: {
                            Text(option.name).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                        }
                    } else {
                        Text(option.name).font(.subheadline).fontWeight(.semibold)
                    }
                    chart(option)
                    TrendText(trend: option.trend)
                    if !option.perBlock.isEmpty {
                        Divider()
                        NavigationLink {
                            SeriesBlocksView(title: option.name, unit: option.unit, rows: option.perBlock, doc: doc)
                        } label: {
                            HStack {
                                Text("By block").font(.subheadline)
                                Spacer()
                                Text("\(option.perBlock.count)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption).fontWeight(.semibold).foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens \(option.name) block by block")
                    }
                }
            } else {
                Text("Nothing logged yet")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func chart(_ option: Option) -> some View {
        let points = option.points
        let touchedPoint = touched.flatMap { day in
            points.min { abs($0.date.timeIntervalSince(day)) < abs($1.date.timeIntervalSince(day)) }
        }
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
                // A deload point is hollow, as on Progress: a fill in the
                // page's background read as a dark dot on the card.
                PointMark(x: .value("Date", p.date), y: .value(option.unit, p.value))
                    .symbol {
                        if p.isDeload {
                            Circle().strokeBorder(doc.color(of: p.blockId), lineWidth: 2).frame(width: 9, height: 9)
                        } else {
                            Circle().fill(doc.color(of: p.blockId)).frame(width: 8, height: 8)
                        }
                    }
            }
            if let p = touchedPoint {
                RuleMark(x: .value("Date", p.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.date, format: .dateTime.day().month(.abbreviated))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(p.detail ?? "\(number(p.value)) \(option.unit)")
                                .font(.caption).monospacedDigit()
                        }
                        .padding(6)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXSelection(value: $touched)
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
        .accessibilityLabel("\(option.name): \(points.count) sessions across \(doc.blocks.count) blocks")
    }

    private func number(_ v: Double) -> String { AnalyticsProgramTab.number(v) }
}

/// One series block by block (§6.37), pushed from "By block" on Lifts across
/// blocks: per block its first and last value, best, sessions and the change.
private struct SeriesBlocksView: View {
    let title: String
    let unit: String
    let rows: [DevelopmentAnalytics.PerBlock]
    let doc: DevelopmentAnalytics

    var body: some View {
        List(rows) { row in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(doc.color(of: row.blockId)).frame(width: 10, height: 10)
                    Text(doc.block(row.blockId)?.name ?? "Block \(row.blockId)")
                        .font(.subheadline).fontWeight(.semibold).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(DevelopmentAnalytics.formatDelta(row.delta))
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(row.delta > 0 ? Color.green : row.delta < 0 ? Color.yellow : Color.secondary)
                }
                HStack(spacing: 14) {
                    Text("\(number(row.first)) → \(number(row.last)) \(unit)")
                    Label(number(row.best), systemImage: "trophy")
                    Label("\(row.sessions)", systemImage: "list.bullet")
                }
                .labelStyle(.inline)
                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(doc.block(row.blockId)?.name ?? "Block"): \(number(row.first)) to \(number(row.last)) \(unit), best \(number(row.best)), \(row.sessions) sessions, change \(DevelopmentAnalytics.formatDelta(row.delta))")
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(doc.blocks) { block in
                        HStack(spacing: 4) {
                            Circle().fill(doc.color(of: block.id)).frame(width: 8, height: 8)
                            Text(block.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Standards over time

/// Every standard with a result in the window — results belong to the
/// athlete, so they run through every program. A row is the summary: the
/// name, the latest result, the level, the levels gained and a line of the
/// results; it opens the standard's sheet here (§6.32), whose chart has the
/// blocks as bands. The current program's own come first; the rest fold
/// behind "More standards". Each row drew a 120 pt chart, inside a button
/// that left for Profile, until 2026-10-17.
private struct StandardsCard: View {
    let doc: DevelopmentAnalytics
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var appState: AppState
    @State private var showMore = false
    @State private var sheet: StandardSubject?

    private var own: [DevelopmentAnalytics.Benchmark] { doc.benchmarks.filter(\.inCurrentProgram) }
    private var other: [DevelopmentAnalytics.Benchmark] { doc.benchmarks.filter { !$0.inCurrentProgram } }
    /// With none of the program's own, the others lead and nothing folds.
    private var shown: [DevelopmentAnalytics.Benchmark] { own.isEmpty || showMore ? own + other : own }

    var body: some View {
        AnalyticsCard(header: "Standards over time") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { benchmark in
                    if benchmark.id != shown.first?.id { Divider() }
                    Button { open(benchmark.benchmarkId) } label: { row(benchmark) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the standard")
                }
                if !own.isEmpty && !other.isEmpty {
                    Button(showMore ? "Fewer standards" : "More standards (\(other.count))") {
                        withAnimation(AppAnimation.layoutChange) { showMore.toggle() }
                    }
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                Button { router.showProfile(.standards) } label: {
                    Label("Log a result", systemImage: "plus.circle")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .font(.footnote)
                .accessibilityHint("Opens Profile, Standards")
            }
        }
        .sheet(item: $sheet) { StandardDetailSheet(subject: $0).environmentObject(appState) }
        .task { await appState.loadBenchmarksIfNeeded() }
    }

    private func row(_ b: DevelopmentAnalytics.Benchmark) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(b.name).font(.subheadline).fontWeight(.semibold).lineLimit(1)
                HStack(spacing: 6) {
                    StandardLevelBadge(level: b.latestLevel, domain: b.domain)
                    if let gained = gainedText(b) {
                        Text(gained).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 6)
            if b.history.count >= 2 {
                Sparkline(values: b.history.map(\.value),
                          color: b.domain.map { ModalityStyle.color(for: $0) } ?? .accentColor,
                          width: 56, height: 18)
                    .accessibilityHidden(true)
            }
            if let last = b.history.last {
                Text(last.valueText ?? AnalyticsProgramTab.number(last.value))
                    .font(.subheadline).fontWeight(.semibold).monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The standard's sheet in place; Profile ▸ Standards only when the
    /// catalog has not loaded.
    private func open(_ id: String) {
        AppHaptics.light()
        if let benchmark = appState.benchmarks.first(where: { $0.id == id }) {
            sheet = .standard(benchmark)
        } else {
            router.openStandard(id)
        }
    }

    private func gainedText(_ b: DevelopmentAnalytics.Benchmark) -> String? {
        guard b.levelsGained != 0 else { return nil }
        let n = abs(b.levelsGained)
        return "\(b.levelsGained > 0 ? "+" : "−")\(n) level\(n == 1 ? "" : "s")"
    }
}
