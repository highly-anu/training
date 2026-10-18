import SwiftUI
import Charts

/// Analytics ▸ Program: how the athlete is doing against what the active
/// program is *for* — per methodology, in that methodology's own currency.
/// Lays out the server's `/analytics/program` document (the engine is
/// `src/analytics/`); the web's Analytics ▸ Program tab reads the same one,
/// so the two platforms cannot disagree. Nothing is computed here.
struct AnalyticsProgramTab: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    /// A detail pushed from outside (a deep link); the cards push their own.
    @State private var route: AppRouter.AnalyticsDetail?

    var body: some View {
        Group {
            if let doc = appState.programAnalytics, doc.hasProgram {
                content(doc)
            } else if appState.isLoadingProgramAnalytics && appState.programAnalytics == nil {
                ProgressView("Measuring the program…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = appState.programAnalyticsError, appState.programAnalytics == nil {
                emptyState(icon: "exclamationmark.triangle", title: "Could not load",
                           message: error, actionLabel: "Try again") {
                    Task { await appState.loadProgramAnalytics() }
                }
            } else {
                emptyState(icon: "chart.bar.doc.horizontal", title: "No active program",
                           message: "Generate a program to measure it here.",
                           actionLabel: "Go to Program") { router.showProgram(.calendar) }
            }
        }
        // Reload whenever the stored program changes revision; the server
        // caches the document, so a visit with nothing new is one cheap read.
        .task(id: appState.serverProgram?.revision) { await appState.loadIfStale("programAnalytics") { await appState.loadProgramAnalytics() } }
        .task { await appState.loadPhilosophiesIfNeeded() }
        .refreshable {
            await AppRefresh.perform { await appState.loadProgramAnalytics(fresh: true) }
        }
        .navigationDestination(item: $route) { detail($0) }
        .task { applyPendingDetail() }
        .onChange(of: router.pendingAnalyticsDetail) { applyPendingDetail() }
        .onChange(of: appState.programAnalytics?.progress.count) { applyPendingDetail() }
    }

    @ViewBuilder
    private func detail(_ detail: AppRouter.AnalyticsDetail) -> some View {
        switch detail {
        case .movement:
            if let movement = appState.programAnalytics?.movement { MovementDetailView(movement: movement) }
        case .sessionShapes:
            if let rows = appState.programAnalytics?.archetypes { SessionShapesDetailView(rows: rows) }
        case .scorecard:
            if let scorecard = appState.programAnalytics?.scorecard { ScorecardDetailView(scorecard: scorecard) }
        case .intensity:
            if let intensity = appState.programAnalytics?.intensity { IntensityDetailView(intensity: intensity) }
        default:
            EmptyView()
        }
    }

    /// Push what a deep link asked for once the document has loaded.
    private func applyPendingDetail() {
        guard let pending = router.pendingAnalyticsDetail, pending.section == .program,
              let doc = appState.programAnalytics else { return }
        switch pending {
        case .movement where doc.movement != nil, .sessionShapes where doc.archetypes != nil,
             .scorecard where doc.scorecard != nil, .intensity where doc.intensity != nil:
            route = pending
        default:
            break
        }
        router.clearPendingAnalyticsDetail()
    }

    // MARK: - Layout

    private func content(_ doc: ProgramAnalytics) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let frame = doc.frame { frameCard(frame) }
                if let scorecard = doc.scorecard { ScorecardCard(scorecard: scorecard) }
                if let intensity = doc.intensity { IntensityCard(intensity: intensity) }
                if let movement = doc.movement, !movement.isEmpty { MovementCard(movement: movement) }
                if let shapes = doc.archetypes, !shapes.isEmpty { SessionShapesCard(rows: shapes) }
                if let load = doc.load { LoadCard(load: load) }
                if !doc.sectionErrors.isEmpty { sectionErrorsCard(doc.sectionErrors) }
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

    // MARK: - Frame

    /// The shared program header (§6.28) with plan fidelity as its footer:
    /// each field actual / ideal with a mark for whether it meets the ideal.
    /// The phase's focus is on Program ▸ Overview.
    private func frameCard(_ frame: ProgramAnalytics.Frame) -> some View {
        ProgramHeaderCard(
            name: frame.philosophies.map(\.name).joined(separator: " + "),
            methodologies: appState.programMethodologies(),
            phase: frame.phase.map { .init(label: $0.displayName, kind: $0.name, week: $0.weekInProgram,
                                           totalWeeks: $0.totalWeeks, isDeload: $0.isDeload) },
            tags: Self.frameTags(frame)
        ) {
            if !frame.planFidelity.isEmpty {
                HStack(spacing: 0) {
                    ForEach(frame.planFidelity) { row in
                        fidelityCell(row)
                        if row.id != frame.planFidelity.last?.id { Spacer(minLength: 8) }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// One fidelity field: its symbol, actual / ideal, and a mark.
    private func fidelityCell(_ row: ProgramAnalytics.Frame.Fidelity) -> some View {
        let meets = row.status == "meets_ideal"
        let color: Color = meets ? .green : row.status == "below_minimum" ? .red : .yellow
        return ProgramHeaderStat(
            icon: Self.fidelityIcon(row.field),
            value: "\(Self.number(row.actual))/\(Self.number(row.ideal))",
            unit: row.unit,
            accessibility: "\(Self.fidelityLabel(row.field)): \(Self.number(row.actual)) \(row.unit), ideal \(Self.number(row.ideal))"
        ) {
            Image(systemName: meets ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(color)
        }
    }

    static func fidelityIcon(_ field: String) -> String {
        switch field {
        case "days_per_week": return "calendar"
        case "session_time_minutes": return "clock"
        case "num_weeks", "weeks": return "calendar.badge.clock"
        default: return "slider.horizontal.3"
        }
    }

    /// How the lead methodology progresses, its intensity model, the framework.
    static func frameTags(_ frame: ProgramAnalytics.Frame) -> [ProgramHeader.Tag] {
        var tags: [ProgramHeader.Tag] = []
        let lead = frame.philosophies.first
        if let how = lead?.progressionPhilosophy {
            tags.append(.init(icon: "chart.line.uptrend.xyaxis", text: ProgramHeader.words(how)))
        }
        if let model = lead?.intensityModel {
            tags.append(.init(icon: "gauge.with.dots.needle.33percent", text: ProgramHeader.words(model)))
        }
        if let framework = frame.framework { tags.append(.init(icon: "square.grid.2x2", text: framework.name)) }
        return tags
    }

    static func fidelityLabel(_ field: String) -> String {
        switch field {
        case "days_per_week": return "Days per week"
        case "session_time_minutes": return "Session length"
        case "num_weeks", "weeks": return "Weeks"
        default: return field.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Up to two decimals, trailing zeros dropped: ×BW standards sit at
    /// 0.75 and 1.25, which one decimal showed as 0.8 and 1.2.
    static func number(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    // MARK: - Section errors

    private func sectionErrorsCard(_ errors: [String: String]) -> some View {
        AnalyticsCard(header: "Not computed") {
            VStack(alignment: .leading, spacing: 6) {
                // The section's name and a mark; the engine's own message
                // (an exception's text, at worst) is for VoiceOver (§1.4).
                ForEach(errors.keys.sorted(), id: \.self) { key in
                    Label(key.capitalized, systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel("\(key.capitalized) not computed: \(errors[key] ?? "")")
                }
            }
        }
    }
}

// MARK: - Scorecard

/// Did you train what this program is for. The headline is a gate, not a
/// weighted sum: under 70 % of the committed work is off plan regardless.
/// The summary is the completion and each modality's sessions; the weeks,
/// the tiers, the minutes against each modality's range and what it all
/// means are `ScorecardDetailView`'s (§6.37).
private struct ScorecardCard: View {
    let scorecard: ProgramAnalytics.Scorecard

    var body: some View {
        AnalyticsDetailCard(header: "Scorecard", hint: "Opens the scorecard") {
            AnalyticsStatusBadge(status: scorecard.headline)
        } destination: {
            ScorecardDetailView(scorecard: scorecard)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let overall = scorecard.overallPct {
                        Label("\(Int(overall.rounded()))%", systemImage: "checkmark.circle")
                            .font(.title3).fontWeight(.semibold)
                            .accessibilityLabel("\(Int(overall.rounded())) percent overall")
                    }
                    if let committed = scorecard.tiers["committed"] {
                        Label("\(committed.completed)/\(committed.planned)", systemImage: "pin.fill")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityLabel("Committed work \(committed.completed) of \(committed.planned)")
                    }
                }
                .monospacedDigit()
                ForEach(scorecard.modalities) { row in
                    ScorecardRowView(row: row, showsDose: false)
                }
            }
        }
    }
}

/// A modality's completion and weekly dose, in symbols: its tier, sessions
/// done of planned, minutes per week against planned, and an arrow or a
/// check for the dose against the framework's range. The card leaves the
/// minutes out (`showsDose`); the detail shows them.
struct ScorecardRowView: View {
    let row: ProgramAnalytics.Scorecard.Row
    var showsDose = true

    var body: some View {
        let colour = ModalityStyle.color(for: row.modality)
        let pct = min(100, max(0, row.completionPct ?? 0))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(symbol: ModalityStyle.icon(for: row.modality))
                    .foregroundStyle(colour)
                Text(ModalityStyle.label(for: row.modality))
                    .fontWeight(.semibold)
                    .foregroundStyle(colour)
                    .lineLimit(1)
                if let icon = Self.tierIcon(row.tier) {
                    Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(row.completedSessions)/\(row.plannedSessions)")
                    .monospacedDigit().foregroundStyle(.secondary)
                if let p = row.completionPct {
                    Text("\(Int(p.rounded()))%")
                        .fontWeight(.semibold).monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            .font(.subheadline)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(colour).frame(width: geo.size.width * pct / 100)
                }
            }
            .frame(height: 6)
            if showsDose {
                HStack(spacing: 6) {
                    Label("\(Int((row.weeklyActualMinutes ?? 0).rounded()))/\(Int((row.weeklyPlannedMinutes ?? 0).rounded())) min/wk",
                          systemImage: "clock")
                    Spacer()
                    if let minMin = row.minWeeklyMinutes, let maxMin = row.maxWeeklyMinutes, let dose = doseIcon {
                        Image(systemName: dose.icon).foregroundStyle(dose.color)
                        Text("\(Int(minMin))–\(Int(maxMin))")
                    }
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ModalityStyle.label(for: row.modality)), \(row.tier): \(row.completedSessions) of \(row.plannedSessions) sessions, \(Int((row.weeklyActualMinutes ?? 0).rounded())) of \(Int((row.weeklyPlannedMinutes ?? 0).rounded())) minutes a week\(doseWords)")
    }

    /// committed · core · supplementary; nothing for unscheduled.
    static func tierIcon(_ tier: String) -> String? {
        switch tier {
        case "committed": return "pin.fill"
        case "core": return "circle.inset.filled"
        case "supplementary": return "plus.circle"
        default: return nil
        }
    }

    private var doseIcon: (icon: String, color: Color)? {
        switch row.doseStatus {
        case "under": return ("arrow.down.circle.fill", .yellow)
        case "on": return ("checkmark.circle.fill", .green)
        case "over": return ("arrow.up.circle.fill", .red)
        default: return nil
        }
    }

    private var doseWords: String {
        switch row.doseStatus {
        case "under": return ", under dose"
        case "on": return ", in range"
        case "over": return ", over dose"
        default: return ""
        }
    }
}

// MARK: - Intensity

/// Planned against recorded minutes per heart-rate zone, over the completed
/// sessions; the weeks, each framework's split, the share of 1RM and what
/// counts as zone time are `IntensityDetailView`'s (§6.37).
private struct IntensityCard: View {
    let intensity: ProgramAnalytics.Intensity

    var body: some View {
        AnalyticsDetailCard(header: "Intensity split", hint: "Opens the intensity split") {
            AnalyticsStatusBadge(status: intensity.status)
        } destination: {
            IntensityDetailView(intensity: intensity)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if let coverage = intensity.coverage { CoverageNoticeView(coverage: coverage) }
                if !intensity.zones.isEmpty {
                    // Sessions whose programming prescribes zones; one that
                    // prescribes load (a heavy day) counts as max effort.
                    ZonePlanComparison(rows: intensity.zones.map {
                        .init(zone: $0.zone, label: $0.label, planned: $0.plannedMinutes, recorded: $0.actualMinutes)
                    })
                } else if !intensity.weeks.isEmpty {
                    IntensityWeeksChart(weeks: intensity.weeks)
                }
            }
        }
    }
}

/// Minutes per bucket per week, stacked. The week fields carry `_pct` in
/// their keys but hold minutes; this chart called them "Share" and drew them
/// against a % axis until 2026-10-16.
struct IntensityWeeksChart: View {
    let weeks: [ProgramAnalytics.Intensity.Week]
    var height: CGFloat = 160

    /// Keyed by position: an old program repeats week numbers, which stacked
    /// two weeks in one bar; the axis still names each by its number.
    private struct Slice: Identifiable {
        let position: Int
        let zone: String
        let minutes: Double
        var id: String { "\(position)-\(zone)" }
    }

    private var slices: [Slice] {
        weeks.enumerated().flatMap { i, w in
            [Slice(position: i, zone: "Z1–2", minutes: w.zone12Pct),
             Slice(position: i, zone: "Z3", minutes: w.zone3Pct),
             Slice(position: i, zone: "Z4–5", minutes: w.zone45Pct),
             Slice(position: i, zone: "Max effort", minutes: w.maxEffortPct)]
        }
    }

    var body: some View {
        Chart(slices) { slice in
            BarMark(x: .value("Week", String(slice.position)), y: .value("Minutes", slice.minutes))
                .foregroundStyle(by: .value("Zone", slice.zone))
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let s = value.as(String.self), let i = Int(s), weeks.indices.contains(i) {
                        Text("W\(weeks[i].week)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartForegroundStyleScale(["Z1–2": Color.green, "Z3": Color.yellow,
                                    "Z4–5": Color.orange, "Max effort": Color.red])
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        // Up to two decimals: a first week's minutes read 0, 0, 1.
                        Text("\(AnalyticsProgramTab.number(v)) min").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 6)
        .frame(height: height)
        .accessibilityLabel("Minutes per zone in each of \(weeks.count) weeks")
    }
}

// MARK: - Progress entry

/// One progress entry — a methodology's own metric, in its own currency — as
/// a summary (design-system §6.37): its status beside the header, where it
/// stands now and which way it is moving, a sparkline, and why it cannot be
/// measured yet if it cannot. The chart, the exercises, every movement and
/// standard, the evidence and what the measure is are `MeasureDetailView`'s,
/// one tap away. Until 2026-10-17 the card carried all of that inline.
struct ProgressEntryCard: View {
    let entry: ProgramAnalytics.ProgressEntry

    /// The card reads the lead exercise; the detail lets the athlete pick another.
    private var lead: ProgramAnalytics.ExerciseResult? { entry.leadExercise }
    private var status: String { lead?.status ?? entry.status }
    private var trend: ProgramAnalytics.Trend? { lead?.trend ?? entry.trend }
    private var values: [Double] { (lead?.series ?? entry.series).compactMap(\.value) }
    private var unit: String { lead?.unit ?? entry.unit }

    var body: some View {
        AnalyticsDetailCard(header: entry.label, hint: "Opens \(entry.label)") {
            AnalyticsStatusBadge(status: status)
        } destination: {
            MeasureDetailView(entry: entry)
        } content: {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    standing
                    HStack(spacing: 10) {
                        if let t = trend, t.direction != "insufficient_data" {
                            MeasureTrendLabel(trend: t)
                        }
                        if entry.headline {
                            TintCapsule(text: "Headline", symbol: "star.fill", color: .accentColor)
                        }
                    }
                }
                Spacer(minLength: 0)
                if values.count >= 2 {
                    Sparkline(values: values, color: AnalyticsStatusStyle.color(status) == .secondary
                              ? .green : AnalyticsStatusStyle.color(status))
                        .accessibilityHidden(true)
                }
            }
            if let coverage = entry.coverage, coverage.inScope == 0 || coverage.measured == 0 {
                CoverageNoticeView(coverage: coverage)
            }
        }
    }

    /// Where the measure stands, in its own currency: the latest value and the
    /// exercise it is for; movements practised of the program's; standards met
    /// of those with a target (or with a result).
    @ViewBuilder
    private var standing: some View {
        switch entry.primitive {
        case "unlocks":
            HStack(spacing: 14) {
                Label(entry.programTotal.flatMap { $0 > 0 ? "\(entry.practised.count)/\($0)" : nil }
                      ?? "\(entry.practised.count)", systemImage: "checkmark.circle")
                    .accessibilityLabel("Practised \(entry.practised.count)"
                                        + (entry.programTotal.map { " of \($0)" } ?? ""))
                if !entry.levelOpensAll {
                    Label("\(entry.available.count)", systemImage: "lock.open")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(entry.available.count) now available")
                }
            }
            .font(.title3).fontWeight(.semibold).monospacedDigit()
        case "benchmark_level":
            let rows = entry.benchmarks.filter { !$0.missing }
            let targeted = rows.filter { $0.target != nil }
            if !targeted.isEmpty {
                let met = targeted.filter { $0.met == true }.count
                Label("\(met)/\(targeted.count)", systemImage: "target")
                    .font(.title3).fontWeight(.semibold).monospacedDigit()
                    .accessibilityLabel("\(met) of \(targeted.count) standards at target")
            } else if !rows.isEmpty {
                let logged = rows.filter { $0.latest != nil }.count
                Label("\(logged)/\(rows.count)", systemImage: "checkmark.circle")
                    .font(.title3).fontWeight(.semibold).monospacedDigit()
                    .accessibilityLabel("\(logged) of \(rows.count) standards with a result")
            }
        default:
            if let latest = values.last {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ProgressionView.withUnit(AnalyticsProgramTab.number(latest), unit))
                        .font(.title3).fontWeight(.semibold).monospacedDigit()
                    if let name = lead?.name {
                        Text(name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A measure's trend as an arrow and its slope per point, as the summary card
/// and the detail screen both say it.
struct MeasureTrendLabel: View {
    let trend: ProgramAnalytics.Trend

    var body: some View {
        Label("\(trend.slopePct > 0 ? "+" : "")\(AnalyticsProgramTab.number(trend.slopePct))%/pt",
              systemImage: trend.direction == "improving" ? "arrow.up.right"
                : trend.direction == "declining" ? "arrow.down.right" : "arrow.right")
            .labelStyle(.inline)
            .font(.subheadline).fontWeight(.semibold).monospacedDigit()
            .accessibilityLabel("\(trend.direction), \(AnalyticsProgramTab.number(trend.slopePct)) percent per point")
    }
}

/// "Not measurable yet — and here is why." Coverage is the share of completed
/// in-scope sessions that produced the metric.
struct CoverageNoticeView: View {
    let coverage: ProgramAnalytics.Coverage

    var body: some View {
        if coverage.inScope == 0 {
            Label("No sessions yet", systemImage: "hourglass").labelStyle(.inline)
                .font(.caption).foregroundStyle(.secondary)
        } else if coverage.measured == 0 {
            // One line of what to log, no box: a bordered panel inside the
            // card was a card inside a card (§6.15).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not measurable yet").fontWeight(.semibold)
                    Text(AnalyticsStatusStyle.coverageReason(coverage.reason))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else if coverage.pct < 100 {
            Label("\(coverage.measured)/\(coverage.inScope)", systemImage: "ruler").labelStyle(.inline)
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel("\(coverage.measured) of \(coverage.inScope) sessions measured")
        }
    }
}

// MARK: - Movement

/// Movement as a summary (§6.37): the three patterns the program plans most,
/// done against planned, and any balance out of its range — the detail has
/// both tables in full, every pair, the unilateral share and the minutes
/// assumed. The card carried all of it inline until 2026-10-17.
private struct MovementCard: View {
    let movement: ProgramAnalytics.Movement

    private var table: (title: String, table: ProgramAnalytics.Movement.Table)? {
        if let sets = movement.sets, !sets.rollups.isEmpty { return ("Sets", sets) }
        if let minutes = movement.minutes, !minutes.rollups.isEmpty { return ("Minutes", minutes) }
        return nil
    }
    private var outside: [ProgramAnalytics.Movement.Balance] { movement.balance.filter(\.outside) }

    var body: some View {
        AnalyticsDetailCard(header: "Movement", hint: "Opens movement") {
            if !outside.isEmpty {
                TintCapsule(text: "\(outside.count) out of range", symbol: "exclamationmark.triangle.fill",
                            color: outside.contains { $0.level == "warning" } ? .red : .yellow)
            }
        } destination: {
            MovementDetailView(movement: movement)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let table {
                    MovementBars(title: table.title, rows: Array(table.table.rows.prefix(3)),
                                 top: table.table.rows.first.map { max($0.value.planned, $0.value.done) } ?? 1)
                }
                ForEach(outside) { pair in BalanceRow(pair: pair) }
                if outside.isEmpty && !movement.balance.isEmpty {
                    Label("Balance in range", systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Movement in full, pushed from its card: sets and minutes by pattern, done
/// over planned; every balance pair against its range; the unilateral share;
/// the minutes assumed from sessions without a recorded workout.
struct MovementDetailView: View {
    let movement: ProgramAnalytics.Movement

    var body: some View {
        List {
            if let sets = movement.sets, !sets.rollups.isEmpty {
                Section("Sets") { MovementBars(title: nil, rows: sets.rows, top: Self.top(sets)).padding(.vertical, 4) }
            }
            if let minutes = movement.minutes, !minutes.rollups.isEmpty {
                Section {
                    MovementBars(title: nil, rows: minutes.rows, top: Self.top(minutes)).padding(.vertical, 4)
                } header: {
                    Text("Minutes")
                } footer: {
                    if let assumed = minutes.assumed, assumed > 0 {
                        Text("\(AnalyticsProgramTab.number(assumed)) min assumed from completed sessions without a recorded workout.")
                    }
                }
            }
            if !movement.balance.isEmpty {
                Section("Balance") {
                    ForEach(movement.balance) { pair in BalanceRow(pair: pair) }
                }
            }
            // Not for a program with no single-leg or single-arm work, where
            // it read "0% of 0% planned".
            if let unilateral = movement.unilateralShare?.done,
               unilateral > 0 || (movement.unilateralShare?.planned ?? 0) > 0 {
                Section {
                    LabeledContent("Unilateral") {
                        Text("\(AnalyticsProgramTab.number(unilateral))%"
                             + (movement.unilateralShare?.planned.map { " of \(AnalyticsProgramTab.number($0))% planned" } ?? ""))
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Movement")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func top(_ table: ProgramAnalytics.Movement.Table) -> Double {
        max(table.rows.map { max($0.value.planned, $0.value.done) }.max() ?? 1, 1)
    }
}

/// Patterns as bars — planned in grey, done over it, both against `top` so
/// a summary of three keeps the scale of the whole table. A grid, so every
/// row's track is as long as the others: the widest numbers set their
/// column. Planned sat on a full-width grey track that dark mode drew in the
/// same grey, so 27 of 27 sets read as a fifth done, and each row's numbers
/// shortened its own track (until 2026-10-18).
private struct MovementBars: View {
    let title: String?
    let rows: [(pattern: String, value: ProgramAnalytics.Movement.Rollup)]
    let top: Double

    /// "hip_hinge" → "Hip Hinge", for the bars and the balance pairs alike.
    static func name(_ pattern: String) -> String {
        pattern.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var body: some View {
        let scale = max(top, 1)
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(rows, id: \.pattern) { row in
                    // VoiceOver reads the row once, from its first cell (a
                    // GridRow hands its modifiers to every cell).
                    GridRow {
                        Text(Self.name(row.pattern)).font(.subheadline).lineLimit(1)
                            .accessibilityLabel("\(Self.name(row.pattern)): \(AnalyticsProgramTab.number(row.value.done)) of \(AnalyticsProgramTab.number(row.value.planned))\(title.map { " \($0.lowercased())" } ?? "")")
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray4))
                                    .frame(width: geo.size.width * min(row.value.planned, scale) / scale, height: 6)
                                Capsule().fill(Color.accentColor)
                                    .frame(width: geo.size.width * min(row.value.done, scale) / scale, height: 6)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                        Text("\(AnalyticsProgramTab.number(row.value.done))/\(AnalyticsProgramTab.number(row.value.planned))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .fixedSize()
                            .gridColumnAlignment(.trailing)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

/// A balance pair, its ratio against the range, and a mark when it is out.
private struct BalanceRow: View {
    let pair: ProgramAnalytics.Movement.Balance

    var body: some View {
        HStack(spacing: 6) {
            // Named as the bars name them ("Push : Pull", not "push : pull").
            Text("\(MovementBars.name(pair.a)) : \(MovementBars.name(pair.b))")
            if pair.declared {
                Image(systemName: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("declared")
            }
            Spacer()
            // Out of range is a mark as well as a colour (§1.6).
            if pair.outside {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(pair.level == "warning" ? Color.red : Color.yellow)
                    .accessibilityLabel("out of range")
            }
            Text(pair.ratio.map { "\(AnalyticsProgramTab.number($0)) (\(AnalyticsProgramTab.number(pair.min))–\(AnalyticsProgramTab.number(pair.max)))" }
                 ?? "—")
                .monospacedDigit()
                .foregroundStyle(pair.outside ? (pair.level == "warning" ? Color.red : Color.yellow) : Color.secondary)
        }
        .font(.subheadline)
    }
}

// MARK: - Load

private struct LoadCard: View {
    let load: ProgramAnalytics.Load

    var body: some View {
        // The reading beside the header; the phase is the program card's pill.
        AnalyticsCard(header: "Load") {
            if let reading = load.reading { AnalyticsStatusBadge(status: reading) }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let tsb = load.tsb {
                    Text("TSB \(AnalyticsProgramTab.number(tsb))")
                        .font(.title3).fontWeight(.semibold).monospacedDigit()
                }
                if let readiness = load.readiness {
                    // Readiness's own words, as Recovery and Today say them.
                    Label("\(readiness.score) · \(ReadinessResult.statusLabel(readiness.status))", systemImage: "heart.circle")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("Readiness \(readiness.score), \(ReadinessResult.statusLabel(readiness.status))")
                }
            }
        }
    }
}
