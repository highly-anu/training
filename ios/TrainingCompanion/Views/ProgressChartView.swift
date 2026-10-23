import SwiftUI
import Charts

/// Analytics ▸ Progress's one chart (design-system §6.41): every exercise of
/// the program, each metric done against prescribed, and each methodology
/// measure against its expectation, on one date axis. A menu picks the series,
/// a segmented row its metric; touching the chart shows that session's
/// prescription and what was done. The series are the server's
/// (`exerciseSeries`, `progress`), lined up by `ProgressChartModel`. It
/// replaced the measure cards' sparklines, the measure screen's chart and the
/// exercise cards and their screen (2026-10-23).
struct ProgressChartView: View {
    let doc: ProgramAnalytics
    @Binding var selection: ProgressChartModel.Selection?
    var finding: ExerciseFinding? = nil

    @EnvironmentObject private var appState: AppState
    @State private var touched: Date?
    @State private var showReference = false

    private var series: ProgressChartModel.Series? {
        selection.flatMap { ProgressChartModel.series($0, in: doc) }
    }
    private var exercise: ProgramAnalytics.ExerciseSeries.Exercise? {
        guard case .exercise(let id, _) = selection else { return nil }
        return doc.exerciseSeries?.exercises.first { $0.exerciseId == id }
    }

    var body: some View {
        AnalyticsCard(header: "Progress") {
            VStack(alignment: .leading, spacing: 12) {
                picker
                if let exercise, exercise.metrics.count > 1 { metricPicker(exercise) }
                if let series {
                    summary(series)
                    if series.points.contains(where: { $0.done != nil || $0.planned != nil }) {
                        chart(series)
                    } else {
                        Text("No values for this metric yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    if let point = touchedPoint(series) { detail(point, series) }
                    if let summary = finding?.changeSummary, !summary.isEmpty {
                        Text(summary).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nothing to chart yet: this program has no exercises with a prescription.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showReference) {
            if let exercise {
                ExerciseDetailSheet(exerciseId: exercise.exerciseId, name: exercise.name)
                    .environmentObject(appState)
            }
        }
    }

    // MARK: - Pickers

    private var picker: some View {
        HStack(spacing: 8) {
            Menu {
                if let exercises = doc.exerciseSeries?.exercises, !exercises.isEmpty {
                    Section("Exercises") {
                        ForEach(exercises) { ex in
                            Button {
                                choose(.exercise(id: ex.exerciseId, metric: ex.defaultMetric))
                            } label: {
                                Text(ex.logged > 0 ? "\(ex.name) · \(ex.logged) logged" : ex.name)
                            }
                        }
                    }
                }
                let measures = ProgressChartModel.chartableMeasures(doc)
                if !measures.isEmpty {
                    Section("Measures") {
                        // Keyed philosophy:id — a blend repeats entry ids.
                        ForEach(measures.map { (ProgressChartModel.key($0), $0.label) }, id: \.0) { key, label in
                            Button(label) { choose(.measure(id: key)) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(series?.label ?? "Choose").font(.headline).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Series, \(series?.label ?? "none")")
            Spacer(minLength: 0)
            if let exercise {
                Button { showReference = true } label: {
                    Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("About \(exercise.name)")
            }
        }
    }

    private func metricPicker(_ exercise: ProgramAnalytics.ExerciseSeries.Exercise) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(exercise.metrics, id: \.self) { id in
                    let active: Bool = { if case .exercise(_, let m) = selection { return m == id }; return false }()
                    Button {
                        choose(.exercise(id: exercise.exerciseId, metric: id))
                    } label: {
                        Text(doc.exerciseSeries?.metric(id)?.label ?? id)
                            .font(.footnote).fontWeight(active ? .semibold : .regular)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1),
                                        in: Capsule())
                            .foregroundStyle(active ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
    }

    private func choose(_ s: ProgressChartModel.Selection) {
        AppHaptics.light()
        touched = nil
        withAnimation(AppAnimation.springStandard) { selection = s }
    }

    // MARK: - Summary, chart, the touched session

    private func summary(_ series: ProgressChartModel.Series) -> some View {
        let latest = series.points.last { $0.done != nil }
        return HStack(alignment: .firstTextBaseline) {
            if let latest, let done = latest.done {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AnalyticsProgressTab.withUnit(AnalyticsProgressTab.number(done), series.unit))
                        .font(.title3).fontWeight(.semibold).monospacedDigit()
                    Text("Last done \(latest.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Nothing logged yet: the dashed line is the plan.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let exercise {
                Text("\(exercise.logged)/\(exercise.scheduled) logged")
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("\(exercise.logged) of \(exercise.scheduled) sessions logged")
            }
        }
    }

    private func chart(_ series: ProgressChartModel.Series) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let dates = series.points.map(\.date)
        return Chart {
            ForEach(series.points.filter(\.isDeload)) { p in
                RectangleMark(xStart: .value("Day", p.date.addingTimeInterval(-43_200)),
                              xEnd: .value("Day", p.date.addingTimeInterval(43_200)))
                    .foregroundStyle(Color.secondary.opacity(0.12))
            }
            if let first = dates.first, let last = dates.last, today >= first, today <= last {
                RuleMark(x: .value("Today", today))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            ForEach(series.points) { p in
                if let v = p.planned {
                    LineMark(x: .value("Day", p.date), y: .value(series.plannedLabel, v),
                             series: .value("Series", series.plannedLabel))
                        .foregroundStyle(by: .value("Series", series.plannedLabel))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            ForEach(series.points) { p in
                if let v = p.done {
                    LineMark(x: .value("Day", p.date), y: .value("Done", v), series: .value("Series", "Done"))
                        .foregroundStyle(by: .value("Series", "Done"))
                    // An easy week's point hollow, as on Blocks.
                    PointMark(x: .value("Day", p.date), y: .value("Done", v))
                        .symbol {
                            if p.isDeload {
                                Circle().strokeBorder(Color.green, lineWidth: 2).frame(width: 9, height: 9)
                            } else {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                            }
                        }
                }
            }
            if let t = touched {
                RuleMark(x: .value("Selected", t)).foregroundStyle(Color.primary.opacity(0.25))
            }
        }
        // The legend names the dashed line only when there is one: a lift the
        // method works up on the day has no prescribed kg.
        .chartForegroundStyleScale(series.points.contains { $0.planned != nil }
                                   ? ["Done": Color.green, series.plannedLabel: Color.indigo]
                                   : ["Done": Color.green])
        // From the lightest value, not from 0 kg, which flattened 55 → 90 kg
        // into the top third.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXSelection(value: $touched)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(AnalyticsProgressTab.withUnit(AnalyticsProgressTab.number(v), series.unit))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.caption2)
            }
        }
        .frame(height: 220)
        .accessibilityLabel(accessibilitySummary(series))
    }

    /// The session nearest the finger.
    private func touchedPoint(_ series: ProgressChartModel.Series) -> ProgressChartModel.Point? {
        guard let t = touched else { return nil }
        return series.points.min { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) }
    }

    private func detail(_ p: ProgressChartModel.Point, _ series: ProgressChartModel.Series) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([p.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), p.sessionName,
                  p.isDeload ? "deload" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.footnote).fontWeight(.semibold)
            LabeledContent(series.plannedLabel) {
                Text(p.prescribedText ?? p.planned.map { AnalyticsProgressTab.withUnit(AnalyticsProgressTab.number($0), series.unit) } ?? "—")
            }
            if p.elapsed {
                LabeledContent("Done") {
                    Text(p.doneText ?? p.done.map { AnalyticsProgressTab.withUnit(AnalyticsProgressTab.number($0), series.unit) } ?? "Not logged")
                }
            }
        }
        .font(.footnote)
        .padding(10)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func accessibilitySummary(_ series: ProgressChartModel.Series) -> String {
        let done = series.points.compactMap(\.done)
        let latest = done.last.map { AnalyticsProgressTab.withUnit(AnalyticsProgressTab.number($0), series.unit) } ?? "nothing logged"
        return "\(series.label): \(done.count) sessions done of \(series.points.count), latest \(latest)"
    }
}
