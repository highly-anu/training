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
private struct ScorecardCard: View {
    let scorecard: ProgramAnalytics.Scorecard

    var body: some View {
        AnalyticsCard(header: "Scorecard") {
            AnalyticsStatusBadge(status: scorecard.headline)
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
                    ScorecardRowView(row: row)
                }
            }
        }
    }
}

/// A modality's completion and weekly dose, in symbols: its tier, sessions
/// done of planned, minutes per week against planned, and an arrow or a
/// check for the dose against the framework's range.
private struct ScorecardRowView: View {
    let row: ProgramAnalytics.Scorecard.Row

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

private struct IntensityCard: View {
    let intensity: ProgramAnalytics.Intensity

    private struct Slice: Identifiable {
        let week: Int
        let zone: String
        let minutes: Double
        var id: String { "\(week)-\(zone)" }
    }

    /// Minutes per bucket per week. The week fields carry `_pct` in their
    /// keys but hold minutes; this chart called them "Share" and drew them
    /// against a % axis until 2026-10-16.
    private var slices: [Slice] {
        intensity.weeks.flatMap { w in
            [Slice(week: w.week, zone: "Z1–2", minutes: w.zone12Pct),
             Slice(week: w.week, zone: "Z3", minutes: w.zone3Pct),
             Slice(week: w.week, zone: "Z4–5", minutes: w.zone45Pct),
             Slice(week: w.week, zone: "Max effort", minutes: w.maxEffortPct)]
        }
    }

    var body: some View {
        AnalyticsCard(header: "Intensity split") {
            AnalyticsStatusBadge(status: intensity.status)
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
                    weeklyChart
                }
                if let pct = intensity.pct1rm, let mean = pct.meanPct {
                    Label("\(AnalyticsProgramTab.number(mean))% 1RM · \(pct.sessions) lifts", systemImage: "scalemass")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Working sets averaged \(AnalyticsProgramTab.number(mean)) percent of estimated 1RM across \(pct.sessions) logged lifts")
                }
            }
        }
    }

    /// Minutes per bucket per week — only from an older server, which sends
    /// no per-zone planned and recorded minutes.
    private var weeklyChart: some View {
        Chart(slices) { slice in
            BarMark(x: .value("Week", "W\(slice.week)"), y: .value("Minutes", slice.minutes))
                .foregroundStyle(by: .value("Zone", slice.zone))
        }
        .chartForegroundStyleScale(["Z1–2": Color.green, "Z3": Color.yellow,
                                    "Z4–5": Color.orange, "Max effort": Color.red])
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) min").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, spacing: 6)
        .frame(height: 160)
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

private struct MovementCard: View {
    let movement: ProgramAnalytics.Movement
    /// The pattern column, as wide as "Squat"/"Hinge" at the reader's text size.
    @ScaledMetric(relativeTo: .subheadline) private var patternWidth: CGFloat = 80

    var body: some View {
        AnalyticsCard(header: "Movement") {
            VStack(alignment: .leading, spacing: 12) {
                if let sets = movement.sets, !sets.rollups.isEmpty { bars("Sets", sets) }
                if let minutes = movement.minutes, !minutes.rollups.isEmpty {
                    bars("Minutes", minutes, assumed: minutes.assumed)
                }
                ForEach(movement.balance) { pair in
                    HStack(spacing: 6) {
                        Text("\(pair.a) : \(pair.b)".replacingOccurrences(of: "_", with: " "))
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
                if let unilateral = movement.unilateralShare?.done {
                    Label("Unilateral \(AnalyticsProgramTab.number(unilateral))%", systemImage: "figure.step.training")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Planned as the grey track, done over it, both against the largest row.
    /// Minutes assumed from sessions without a recorded workout are said to
    /// VoiceOver on the table's title, not as a footnote (§1.4).
    private func bars(_ title: String, _ table: ProgramAnalytics.Movement.Table, assumed: Double? = nil) -> some View {
        let rows = table.rows
        let top = max(rows.map { max($0.value.planned, $0.value.done) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .accessibilityLabel(assumed.map { $0 > 0 ? "\(title), \(AnalyticsProgramTab.number($0)) minutes assumed from completed sessions without a recorded workout" : title } ?? title)
            ForEach(rows, id: \.pattern) { row in
                HStack(spacing: 8) {
                    Text(row.pattern.capitalized).font(.subheadline)
                        .lineLimit(1)
                        .frame(width: patternWidth, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill)).frame(height: 6)
                            Capsule().fill(Color(.systemGray3))
                                .frame(width: geo.size.width * row.value.planned / top, height: 6)
                            Capsule().fill(Color.accentColor)
                                .frame(width: geo.size.width * min(row.value.done, top) / top, height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("\(AnalyticsProgramTab.number(row.value.done))/\(AnalyticsProgramTab.number(row.value.planned))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.pattern): \(AnalyticsProgramTab.number(row.value.done)) of \(AnalyticsProgramTab.number(row.value.planned)) \(title.lowercased())")
            }
        }
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
