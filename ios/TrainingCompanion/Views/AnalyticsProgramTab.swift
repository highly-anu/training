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
                           message: "Generate a program and this section measures your training against what it is for.",
                           actionLabel: "Go to Program") { router.show(.program) }
            }
        }
        // Reload whenever the stored program changes revision; the server
        // caches the document, so a visit with nothing new is one cheap read.
        .task(id: appState.serverProgram?.revision) { await appState.loadProgramAnalytics() }
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
                ForEach(doc.methodologies) { method in
                    methodologySection(method, doc: doc)
                }
                if let movement = doc.movement, !movement.balance.isEmpty { MovementCard(movement: movement) }
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

    private func frameCard(_ frame: ProgramAnalytics.Frame) -> some View {
        AnalyticsCard(header: "Where you are") {
            VStack(alignment: .leading, spacing: 8) {
                Text(frame.philosophies.map(\.name).joined(separator: " + "))
                    .font(.subheadline).fontWeight(.semibold)
                if let framework = frame.framework {
                    Text(framework.name)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let phase = frame.phase {
                    HStack(spacing: 6) {
                        Text(phase.name.capitalized)
                            .font(.caption).fontWeight(.semibold)
                        Text("· week \(phase.weekInProgram) of \(phase.totalWeeks)")
                            .font(.caption).foregroundStyle(.secondary)
                        if phase.isDeload {
                            Text("deload")
                                .font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
                if !frame.planFidelity.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(frame.planFidelity) { row in
                            HStack {
                                Text(Self.fidelityLabel(row.field))
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Self.number(row.actual)) \(row.unit) · ideal \(Self.number(row.ideal))")
                                    .font(.caption)
                                    .foregroundStyle(row.status == "meets_ideal" ? Color.primary
                                                     : row.status == "below_minimum" ? Color.red : Color.yellow)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    static func fidelityLabel(_ field: String) -> String {
        switch field {
        case "days_per_week": return "Days per week"
        case "session_time_minutes": return "Session length"
        case "num_weeks", "weeks": return "Weeks"
        default: return field.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: - Methodology

    private func methodologySection(_ method: ProgramAnalytics.Methodology, doc: ProgramAnalytics) -> some View {
        let name = doc.frame?.philosophies.first { $0.id == method.philosophy }?.name ?? method.philosophy
        let entries = doc.progress
            .filter { $0.philosophy == method.philosophy }
            .sorted { $0.headline && !$1.headline }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                HStack(spacing: 6) {
                    Text("\(method.measurable) of \(method.total) metrics measurable")
                    if method.weight < 1 { Text("· \(Int((method.weight * 100).rounded()))% of the blend") }
                    Text(method.analytics == "declared" ? "declared" : "default spec")
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                ProgressEntryCard(entry: entry)
            }
        }
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
                HStack(alignment: .top) {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    AnalyticsStatusBadge(status: scorecard.headline)
                }
                if scorecard.headline == "off_plan" {
                    Text("Under 70 % of the committed work has been done. Everything else is secondary to that.")
                        .font(.caption).foregroundStyle(.yellow)
                }
                ForEach(scorecard.modalities) { row in
                    ScorecardRowView(row: row)
                }
            }
        }
    }

    private var summary: String {
        var parts = ["\(scorecard.elapsedWeeks) week\(scorecard.elapsedWeeks == 1 ? "" : "s") elapsed"]
        if let committed = scorecard.tiers["committed"] {
            parts.append("committed work \(committed.completed)/\(committed.planned)")
        }
        if let overall = scorecard.overallPct {
            parts.append("\(Int(overall.rounded()))% overall")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ScorecardRowView: View {
    let row: ProgramAnalytics.Scorecard.Row

    var body: some View {
        let colour = ModalityStyle.color(for: row.modality)
        let pct = min(100, max(0, row.completionPct ?? 0))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(ModalityStyle.label(for: row.modality))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(colour)
                Text(row.tier == "unscheduled" ? "—" : row.tier)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(row.completedSessions) / \(row.plannedSessions) sessions")
                    .font(.caption).foregroundStyle(.secondary)
                if let p = row.completionPct {
                    Text("· \(Int(p.rounded()))%").font(.caption).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(colour).frame(width: geo.size.width * pct / 100)
                }
            }
            .frame(height: 6)
            HStack(spacing: 8) {
                Text("\(Int((row.weeklyActualMinutes ?? 0).rounded())) min/wk actual · \(Int((row.weeklyPlannedMinutes ?? 0).rounded())) planned")
                if let minMin = row.minWeeklyMinutes, let maxMin = row.maxWeeklyMinutes {
                    Text("\(doseLabel) (\(Int(minMin))–\(Int(maxMin)) min/wk)")
                        .foregroundStyle(row.doseStatus == "under" ? Color.yellow
                                         : row.doseStatus == "over" ? Color.red : Color.secondary)
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.modality) \(row.completedSessions) of \(row.plannedSessions) planned sessions completed")
    }

    private var doseLabel: String {
        switch row.doseStatus {
        case "under": return "under dose"
        case "on": return "in range"
        case "over": return "over dose"
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
        let pct: Double
        var id: String { "\(week)-\(zone)" }
    }

    private var slices: [Slice] {
        intensity.weeks.flatMap { w in
            [Slice(week: w.week, zone: "Z1–2", pct: w.zone12Pct),
             Slice(week: w.week, zone: "Z3", pct: w.zone3Pct),
             Slice(week: w.week, zone: "Z4–5", pct: w.zone45Pct),
             Slice(week: w.week, zone: "Max effort", pct: w.maxEffortPct)]
        }
    }

    var body: some View {
        AnalyticsCard(header: "Intensity") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let dev = intensity.maxDeviationPts, intensity.status != "insufficient_data" {
                        Text("Largest deviation from plan: \(Int(dev.rounded())) pts")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    AnalyticsStatusBadge(status: intensity.status)
                }
                if let coverage = intensity.coverage { CoverageNoticeView(coverage: coverage) }
                if !intensity.weeks.isEmpty {
                    Chart(slices) { slice in
                        BarMark(x: .value("Week", "W\(slice.week)"), y: .value("Share", slice.pct))
                            .foregroundStyle(by: .value("Zone", slice.zone))
                    }
                    .chartForegroundStyleScale(["Z1–2": Color.green, "Z3": Color.yellow,
                                                "Z4–5": Color.orange, "Max effort": Color.red])
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v))%").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartLegend(position: .bottom, spacing: 6)
                    .frame(height: 160)
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
                    Text(entry.label).font(.subheadline).fontWeight(.semibold)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
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
                    Text("Stalled: \(ex.name) has not moved for the last sessions this methodology allows.")
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

    private var subtitle: String {
        var parts = [entry.metric.replacingOccurrences(of: "_", with: " ")]
        if !entry.unit.isEmpty { parts.append(entry.unit) }
        if let t = trend, t.direction != "insufficient_data" {
            parts.append("\(t.direction) (\(t.slopePct > 0 ? "+" : "")\(AnalyticsProgramTab.number(t.slopePct))%/pt)")
        }
        if entry.headline { parts.append("headline") }
        return parts.joined(separator: " · ")
    }

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
                        Text("\(AnalyticsProgramTab.number(v))\(entry.unit.isEmpty ? "" : " \(entry.unit)")")
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
                Text("Practised (\(entry.practised.count))").font(.caption).fontWeight(.semibold)
                ForEach(entry.practised.prefix(6)) { p in
                    Text(p.sessions.map { "\(p.name) · \($0)×" } ?? p.name)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("Now available (\(entry.available.count))").font(.caption).fontWeight(.semibold)
                ForEach(entry.available.prefix(6)) { a in
                    Text(a.name).font(.caption2).foregroundStyle(.secondary)
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
            Text("No completed sessions in scope yet.")
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
            Text("Measured on \(coverage.measured) of \(coverage.inScope) completed sessions (\(Int(coverage.pct.rounded()))%).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Movement

private struct MovementCard: View {
    let movement: ProgramAnalytics.Movement

    var body: some View {
        AnalyticsCard(header: "Movement balance") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(movement.balance) { pair in
                    HStack {
                        Text("\(pair.a) / \(pair.b)".replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                        if pair.declared {
                            Text("declared").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(pair.ratio.map { "\(AnalyticsProgramTab.number($0)) (\(AnalyticsProgramTab.number(pair.min))–\(AnalyticsProgramTab.number(pair.max)))" }
                             ?? "not measured")
                            .font(.caption)
                            .foregroundStyle(pair.outside ? (pair.level == "warning" ? Color.red : Color.yellow) : Color.secondary)
                    }
                }
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
                if let note = load.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if let readiness = load.readiness {
                    Text("Readiness \(readiness.score) · \(readiness.status)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
