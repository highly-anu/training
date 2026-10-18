import SwiftUI
import Charts

/// One progress measure in full (design-system §6.37), pushed from its card on
/// Analytics ▸ Progress: where it stands, the actual series against the
/// expected one for whichever exercise the athlete picks, every movement
/// practised and opened, every standard (each opens its own sheet), every line
/// of evidence, and — last — what the measure is and what to log for it, in
/// the server's words.
struct MeasureDetailView: View {
    let entry: ProgramAnalytics.ProgressEntry

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    @State private var selectedExerciseId: String?
    @State private var standard: StandardSubject?

    private var exercise: ProgramAnalytics.ExerciseResult? {
        entry.exercises.first { $0.exerciseId == selectedExerciseId } ?? entry.leadExercise
    }
    private var status: String { exercise?.status ?? entry.status }
    private var trend: ProgramAnalytics.Trend? { exercise?.trend ?? entry.trend }
    private var series: [ProgramAnalytics.SeriesPoint] { exercise?.series ?? entry.series }
    private var expected: [ProgramAnalytics.ExpectedPoint] { exercise?.expected ?? entry.expected }
    /// A bodyweight lift beside a loaded one: each exercise says its own unit.
    private var unit: String { exercise?.unit ?? entry.unit }

    var body: some View {
        List {
            Section { standingRow }
            switch entry.primitive {
            case "unlocks": unlocksSections
            case "benchmark_level": standardsSection
            default: progressSection
            }
            if !entry.evidence.isEmpty {
                Section("Evidence") {
                    ForEach(entry.evidence, id: \.self) { line in
                        Text(line).font(.subheadline)
                    }
                }
            }
            if let about = entry.about { AboutSection(about: about) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $standard) { StandardDetailSheet(subject: $0).environmentObject(appState) }
        .task { await appState.loadBenchmarksIfNeeded() }
    }

    /// The status, the trend, the headline mark and why it is not measurable.
    private var standingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AnalyticsStatusBadge(status: status)
                if let t = trend, t.direction != "insufficient_data" { MeasureTrendLabel(trend: t) }
                Spacer(minLength: 0)
                if entry.headline {
                    TintCapsule(text: "Headline", symbol: "star.fill", color: .accentColor)
                }
            }
            if let coverage = entry.coverage { CoverageNoticeView(coverage: coverage) }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Series

    @ViewBuilder
    private var progressSection: some View {
        if !entry.exercises.isEmpty || series.contains(where: { $0.value != nil }) {
            Section {
                if entry.exercises.count > 1 {
                    // A display choice inside the screen, so a menu picker (§6.8).
                    Picker("Exercise", selection: Binding(
                        get: { exercise?.exerciseId },
                        set: { id in withAnimation(AppAnimation.springStandard) { selectedExerciseId = id } }
                    )) {
                        ForEach(entry.exercises) { ex in
                            Text(ex.series.isEmpty ? ex.name : "\(ex.name) · \(ex.series.count)")
                                .tag(Optional(ex.exerciseId))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if series.contains(where: { $0.value != nil }) {
                    chart.padding(.vertical, 6)
                }
                if let ex = exercise, ex.stalled {
                    Label("Stalled · \(ex.name)", systemImage: "pause.circle.fill")
                        .font(.subheadline).foregroundStyle(.red)
                }
            } header: {
                Text("Progress")
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
                    // An easy week's point hollow, as on Blocks; it was drawn
                    // in clear and vanished where the line dips.
                    PointMark(x: .value("Point", p.x), y: .value("Actual", v))
                        .symbol {
                            if p.isDeload {
                                Circle().strokeBorder(Color.green, lineWidth: 2).frame(width: 9, height: 9)
                            } else {
                                Circle().fill(Color.green).frame(width: 7, height: 7)
                            }
                        }
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
        // From the lightest value, not from 0 kg, which flattened 55 → 90 kg
        // into the top third (the exercise history's chart does the same).
        .chartYScale(domain: .automatic(includesZero: false))
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
        .frame(height: 200)
        .accessibilityLabel("\(exercise?.name ?? entry.label): \(series.compactMap(\.value).count) points, latest \(series.compactMap(\.value).last.map { AnalyticsProgramTab.number($0) } ?? "none") \(unit)")
    }

    // MARK: - Movements

    @ViewBuilder
    private var unlocksSections: some View {
        Section {
            if entry.practised.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            }
            ForEach(entry.practised) { p in
                LabeledContent(p.name) {
                    if let n = p.sessions { Text("\(n)×").monospacedDigit() }
                }
            }
        } header: {
            Text(entry.programTotal.flatMap { $0 > 0 ? "Practised · \(entry.practised.count) of \($0)" : nil }
                 ?? "Practised · \(entry.practised.count)")
        }
        Section("Now available") {
            if entry.levelOpensAll {
                Label("All open at your level", systemImage: "lock.open")
            } else if entry.available.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            } else {
                ForEach(entry.available) { a in Text(a.name) }
            }
        }
    }

    // MARK: - Standards

    private var standardsSection: some View {
        Section("Standards") {
            ForEach(entry.benchmarks.filter { !$0.missing }) { row in
                Button { open(row.benchmarkId) } label: { standardRow(row) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the standard")
            }
        }
    }

    private func standardRow(_ row: ProgramAnalytics.BenchmarkRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(row.name ?? row.benchmarkId)
                Spacer(minLength: 4)
                if row.latest != nil { StandardLevelBadge(level: row.level, domain: row.domain) }
                Text(row.latest.map { row.latestText ?? "\(AnalyticsProgramTab.number($0))\(row.unit ?? "")" } ?? "—")
                    .monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            if let target = row.target {
                HStack(spacing: 4) {
                    Label(target, systemImage: "target").labelStyle(.inline)
                    if let met = row.met {
                        Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(met ? Color.green : Color.secondary)
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            if !row.standardsText.isEmpty {
                StandardLadder(thresholds: row.standardsText,
                               levelIndex: row.latest == nil ? nil : row.levelIndex, domain: row.domain)
            }
        }
        .contentShape(Rectangle())
    }

    /// The standard's own sheet, here; Profile ▸ Standards only when the
    /// catalog has not loaded.
    private func open(_ id: String) {
        AppHaptics.light()
        if let benchmark = appState.benchmarks.first(where: { $0.id == id }) {
            standard = .standard(benchmark)
        } else {
            router.openStandard(id)
        }
    }
}
