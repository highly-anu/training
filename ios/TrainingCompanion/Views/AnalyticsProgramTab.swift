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
                           actionLabel: "Go to Program") { router.show(.program) }
            }
        }
        // Reload whenever the stored program changes revision; the server
        // caches the document, so a visit with nothing new is one cheap read.
        .task(id: appState.serverProgram?.revision) { await appState.loadIfStale("programAnalytics") { await appState.loadProgramAnalytics() } }
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

    // MARK: - Frame

    /// The methodology, then symbols: how it progresses, the framework, the
    /// phase and week, and each plan-fidelity field as actual / ideal with a
    /// mark for whether it meets the ideal. The phase's focus is on Program ▸
    /// Overview.
    private func frameCard(_ frame: ProgramAnalytics.Frame) -> some View {
        AnalyticsCard(header: "Program") {
            VStack(alignment: .leading, spacing: 10) {
                Text(frame.philosophies.map(\.name).joined(separator: " + "))
                    .font(.subheadline).fontWeight(.semibold)
                if let phase = frame.phase {
                    HStack(spacing: 6) {
                        Text(phase.displayName)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(PhaseStyle.color(for: phase.name))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(PhaseStyle.color(for: phase.name).opacity(0.15))
                            .clipShape(Capsule())
                        Label("\(phase.weekInProgram)/\(phase.totalWeeks)", systemImage: "calendar")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .accessibilityLabel("Week \(phase.weekInProgram) of \(phase.totalWeeks)")
                        if phase.isDeload {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption).foregroundStyle(.blue)
                                .accessibilityLabel("Deload")
                        }
                    }
                }
                let tags = Self.frameTags(frame)
                if !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tags, id: \.text) { tag in
                            Label(tag.text, systemImage: tag.icon)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
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
    }

    /// One fidelity field: its symbol, actual / ideal, and a mark.
    private func fidelityCell(_ row: ProgramAnalytics.Frame.Fidelity) -> some View {
        let color: Color = row.status == "meets_ideal" ? .green
            : row.status == "below_minimum" ? .red : .yellow
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: Self.fidelityIcon(row.field)).foregroundStyle(.secondary)
                Text("\(Self.number(row.actual))/\(Self.number(row.ideal))")
                    .fontWeight(.semibold).monospacedDigit()
                Image(systemName: row.status == "meets_ideal" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(color)
            }
            .font(.caption)
            Text(row.unit).font(.caption2).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.fidelityLabel(row.field)): \(Self.number(row.actual)) \(row.unit), ideal \(Self.number(row.ideal))")
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
    static func frameTags(_ frame: ProgramAnalytics.Frame) -> [(icon: String, text: String)] {
        var tags: [(icon: String, text: String)] = []
        let lead = frame.philosophies.first
        if let how = lead?.progressionPhilosophy { tags.append(("chart.line.uptrend.xyaxis", words(how))) }
        if let model = lead?.intensityModel { tags.append(("gauge.with.dots.needle.33percent", words(model))) }
        if let framework = frame.framework { tags.append(("square.grid.2x2", framework.name)) }
        return tags
    }

    static func words(_ id: String) -> String {
        let s = id.replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
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
            VStack(alignment: .leading, spacing: 4) {
                ForEach(errors.keys.sorted(), id: \.self) { key in
                    Text("\(key.capitalized): \(errors[key] ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Label("\(scorecard.elapsedWeeks) wk", systemImage: "calendar")
                        .accessibilityLabel("\(scorecard.elapsedWeeks) weeks elapsed")
                    if let committed = scorecard.tiers["committed"] {
                        Label("\(committed.completed)/\(committed.planned)", systemImage: "pin.fill")
                            .accessibilityLabel("Committed work \(committed.completed) of \(committed.planned)")
                    }
                    if let overall = scorecard.overallPct {
                        Label("\(Int(overall.rounded()))%", systemImage: "checkmark.circle")
                            .accessibilityLabel("\(Int(overall.rounded())) percent overall")
                    }
                    Spacer()
                    AnalyticsStatusBadge(status: scorecard.headline)
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
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
            HStack(spacing: 5) {
                Image(systemName: ModalityStyle.icon(for: row.modality))
                    .font(.caption2).foregroundStyle(colour)
                Text(ModalityStyle.label(for: row.modality))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(colour)
                    .lineLimit(1)
                if let icon = Self.tierIcon(row.tier) {
                    Image(systemName: icon).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(row.completedSessions)/\(row.plannedSessions)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if let p = row.completionPct {
                    Text("\(Int(p.rounded()))%")
                        .font(.caption).fontWeight(.semibold).monospacedDigit()
                        .frame(minWidth: 36, alignment: .trailing)
                }
            }
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
            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
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

    /// The server's bucket keys, labels and the chart's colours.
    private static let buckets: [(key: String, label: String, color: Color)] = [
        ("zone1_2_pct", "Z1–2", .green), ("zone3_pct", "Z3", .yellow),
        ("zone4_5_pct", "Z4–5", .orange), ("max_effort_pct", "Max effort", .red),
    ]

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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    AnalyticsStatusBadge(status: intensity.status)
                }
                if let coverage = intensity.coverage { CoverageNoticeView(coverage: coverage) }
                if !intensity.weeks.isEmpty {
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
                if let current = intensity.byFramework.last, let planned = current.plannedPct,
                   let dev = current.deviationPts {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Self.buckets, id: \.key) { b in
                            let d = dev[b.key] ?? 0
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(b.color).frame(width: 8, height: 8)
                                Text("\(b.label) \(AnalyticsProgramTab.number((current.actualPct[b.key] ?? nil) ?? 0))% vs \(AnalyticsProgramTab.number(planned[b.key] ?? 0))%")
                                Text("(\(d > 0 ? "+" : "")\(AnalyticsProgramTab.number(d)))")
                                    .foregroundStyle(abs(d) > 10 ? Color.yellow : Color.secondary)
                            }
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                if let pct = intensity.pct1rm, let mean = pct.meanPct {
                    Label("\(AnalyticsProgramTab.number(mean))% 1RM · \(pct.sessions) lifts", systemImage: "scalemass")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("Working sets averaged \(AnalyticsProgramTab.number(mean)) percent of estimated 1RM across \(pct.sessions) logged lifts")
                }
            }
        }
    }
}

// MARK: - Progress entry

/// One progress entry — a methodology's own metric, in its own currency:
/// status, why it cannot be measured yet if it cannot, and the actual series
/// against the expected one.
struct ProgressEntryCard: View {
    let entry: ProgramAnalytics.ProgressEntry
    @State private var selectedExerciseId: String?

    private var exercise: ProgramAnalytics.ExerciseResult? {
        entry.exercises.first { $0.exerciseId == selectedExerciseId } ?? entry.leadExercise
    }
    private var status: String { exercise?.status ?? entry.status }
    private var trend: ProgramAnalytics.Trend? { exercise?.trend ?? entry.trend }
    private var series: [ProgramAnalytics.SeriesPoint] { exercise?.series ?? entry.series }
    private var expected: [ProgramAnalytics.ExpectedPoint] { exercise?.expected ?? entry.expected }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if entry.headline {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(Color.accentColor)
                                .accessibilityLabel("Headline")
                        }
                        Text(entry.label).font(.subheadline).fontWeight(.semibold)
                    }
                    if let t = trend, t.direction != "insufficient_data" {
                        Label("\(t.slopePct > 0 ? "+" : "")\(AnalyticsProgramTab.number(t.slopePct))%/pt",
                              systemImage: t.direction == "improving" ? "arrow.up.right"
                                : t.direction == "declining" ? "arrow.down.right" : "arrow.right")
                            .font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("\(t.direction), \(AnalyticsProgramTab.number(t.slopePct)) percent per point")
                    }
                }
                Spacer()
                AnalyticsStatusBadge(status: status)
            }
            if let coverage = entry.coverage { CoverageNoticeView(coverage: coverage) }

            switch entry.primitive {
            case "unlocks": unlocksBody
            case "benchmark_level": benchmarksBody
            default:
                if entry.exercises.count > 1 { exercisePicker }
                if series.contains(where: { $0.value != nil }) { chart }
                if let ex = exercise, ex.stalled {
                    Label("Stalled · \(ex.name)", systemImage: "pause.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            if !entry.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.evidence.prefix(4), id: \.self) { line in
                        Text(line).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(AppMetrics.cardPadding)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius)
                .strokeBorder(entry.headline ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    /// A bodyweight lift beside a loaded one: each exercise says its own unit.
    private var unit: String { exercise?.unit ?? entry.unit }

    private var exercisePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(entry.exercises) { ex in
                    let selected = ex.exerciseId == exercise?.exerciseId
                    Button {
                        withAnimation(AppAnimation.springStandard) { selectedExerciseId = ex.exerciseId }
                    } label: {
                        Text(ex.series.isEmpty ? ex.name : "\(ex.name) · \(ex.series.count)")
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { p in
                if let v = p.value {
                    LineMark(x: .value("Point", p.x), y: .value("Actual", v), series: .value("Series", "Actual"))
                        .foregroundStyle(by: .value("Series", "Actual"))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Point", p.x), y: .value("Actual", v))
                        .foregroundStyle(p.isDeload ? Color.clear : Color.green)
                        .symbol(.circle)
                        .symbolSize(p.isDeload ? 50 : 36)
                }
            }
            ForEach(expected) { e in
                if let v = e.value {
                    LineMark(x: .value("Point", e.x), y: .value("Expected", v), series: .value("Series", "Expected"))
                        .foregroundStyle(by: .value("Series", "Expected"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartForegroundStyleScale(["Actual": Color.green, "Expected": Color.indigo])
        .chartLegend(expected.contains { $0.value != nil } ? .visible : .hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(AnalyticsProgramTab.number(v))\(unit.isEmpty ? "" : " \(unit)")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.caption2) }
        }
        .frame(height: 160)
    }

    private var unlocksBody: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.programTotal.flatMap { $0 > 0 ? "Practised (\(entry.practised.count) of \($0) in this program)" : nil }
                     ?? "Practised (\(entry.practised.count))").font(.caption).fontWeight(.semibold)
                ForEach(entry.practised.prefix(6)) { p in
                    Text(p.sessions.map { "\(p.name) · \($0)×" } ?? p.name)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Now available (\(entry.available.count))").font(.caption).fontWeight(.semibold)
                if entry.levelOpensAll {
                    Label("All open at your level", systemImage: "lock.open")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(entry.available.prefix(6)) { a in
                        Text(a.name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var benchmarksBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entry.benchmarks.filter { !$0.missing }) { row in
                HStack {
                    Text(row.name ?? row.benchmarkId).font(.caption)
                    Spacer()
                    Text(benchmarkSummary(row)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func benchmarkSummary(_ row: ProgramAnalytics.BenchmarkRow) -> String {
        var s = row.latest.map { "\(AnalyticsProgramTab.number($0))\(row.unit ?? "")" } ?? "no PR"
        if let level = row.level { s += " · \(level)" }
        if let target = row.target {
            s += " · target \(target)"
            if let met = row.met { s += met ? " ✓" : " ✗" }
        }
        return s
    }
}

/// "Not measurable yet — and here is why." Coverage is the share of completed
/// in-scope sessions that produced the metric.
struct CoverageNoticeView: View {
    let coverage: ProgramAnalytics.Coverage

    var body: some View {
        if coverage.inScope == 0 {
            Label("No sessions yet", systemImage: "hourglass")
                .font(.caption).foregroundStyle(.secondary)
        } else if coverage.measured == 0 {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not measurable yet").font(.caption).fontWeight(.semibold)
                    Text(AnalyticsStatusStyle.coverageReason(coverage.reason))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            )
        } else if coverage.pct < 100 {
            Label("\(coverage.measured)/\(coverage.inScope) sessions measured", systemImage: "ruler")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Movement

private struct MovementCard: View {
    let movement: ProgramAnalytics.Movement

    var body: some View {
        AnalyticsCard(header: "Movement") {
            VStack(alignment: .leading, spacing: 12) {
                if let sets = movement.sets, !sets.rollups.isEmpty { bars("Sets", sets) }
                if let minutes = movement.minutes, !minutes.rollups.isEmpty { bars("Minutes", minutes) }
                ForEach(movement.balance) { pair in
                    HStack {
                        Text("\(pair.a) : \(pair.b)".replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                        if pair.declared {
                            Image(systemName: "checkmark.seal").font(.caption2).foregroundStyle(.secondary)
                                .accessibilityLabel("declared")
                        }
                        Spacer()
                        Text(pair.ratio.map { "\(AnalyticsProgramTab.number($0)) (\(AnalyticsProgramTab.number(pair.min))–\(AnalyticsProgramTab.number(pair.max)))" }
                             ?? "—")
                            .font(.caption)
                            .foregroundStyle(pair.outside ? (pair.level == "warning" ? Color.red : Color.yellow) : Color.secondary)
                    }
                }
                if let unilateral = movement.unilateralShare?.done {
                    Label("Unilateral \(AnalyticsProgramTab.number(unilateral))%", systemImage: "figure.step.training")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let assumed = movement.minutes?.assumed, assumed > 0 {
                    Label("\(AnalyticsProgramTab.number(assumed)) min assumed", systemImage: "questionmark.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("\(AnalyticsProgramTab.number(assumed)) minutes assumed from completed sessions without a recorded workout")
                }
            }
        }
    }

    /// Planned as the grey track, done over it, both against the largest row.
    private func bars(_ title: String, _ table: ProgramAnalytics.Movement.Table) -> some View {
        let rows = table.rows
        let top = max(rows.map { max($0.value.planned, $0.value.done) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
            ForEach(rows, id: \.pattern) { row in
                HStack(spacing: 8) {
                    Text(row.pattern.capitalized).font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
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
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
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
        AnalyticsCard(header: "Load") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let tsb = load.tsb {
                        Text("TSB \(AnalyticsProgramTab.number(tsb))")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    if let phase = load.phase {
                        Text("· \(phase.capitalized)\(load.isDeload ? " (deload)" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let reading = load.reading { AnalyticsStatusBadge(status: reading) }
                }
                if let readiness = load.readiness {
                    Label("Readiness \(readiness.score)", systemImage: "heart.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
