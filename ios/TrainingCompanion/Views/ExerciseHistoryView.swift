import SwiftUI
import Charts

/// One exercise's history (design-system §6.37), pushed from its row on
/// Analytics ▸ Progress ▸ Exercises: where it stands against this week's
/// prescription, every logged session as a chart and as rows — earlier
/// programs' included — and the movement's own reference one tap away
/// (`ExerciseDetailSheet`, §6.14).
struct ExerciseHistoryView: View {
    let item: ExerciseHistoryItem
    let finding: ExerciseFinding?

    @EnvironmentObject var appState: AppState
    @State private var showReference = false

    private var metric: String { finding?.metricType ?? item.metricType ?? "weight" }
    private var unit: String { finding?.unit ?? item.unit ?? "kg" }
    private var status: String { finding?.status ?? "insufficient_data" }
    private var latest: Double? {
        finding?.actualValue ?? item.history.compactMap { $0.value(metric: metric, unit: unit) }.last
    }
    private var target: Double? { finding?.expectedValue ?? item.target?.value }

    /// The logged points with a value and a day, oldest first.
    private var points: [(date: Date, value: Double)] {
        item.history.compactMap { p in
            guard let v = p.value(metric: metric, unit: unit), let day = p.date.flatMap(Self.day) else { return nil }
            return (day, v)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        if let latest {
                            Text(Self.text(latest, unit))
                                .font(.title2).fontWeight(.bold).monospacedDigit()
                        } else {
                            Text("Log \(unit) to track").foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        TintCapsule(text: status != "insufficient_data" ? AnalyticsStatusStyle.label(status)
                                    : item.history.isEmpty ? "Not tracked" : "No trend yet",
                                    color: AnalyticsStatusStyle.color(status))
                    }
                    if let target {
                        Label(Self.text(target, unit), systemImage: "target")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityLabel("This week's target \(Self.text(target, unit))")
                    }
                    if let change = finding?.changeSummary, status != "insufficient_data", !change.isEmpty {
                        Text(change).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            if points.count >= 2 {
                Section("History") {
                    chart.padding(.vertical, 6)
                }
            }
            if !item.history.isEmpty {
                Section("Sessions") {
                    ForEach(Array(item.history.enumerated().reversed()), id: \.offset) { _, point in
                        sessionRow(point)
                    }
                }
            }
            Section {
                Button {
                    showReference = true
                } label: {
                    Label("How to do it", systemImage: "info.circle")
                }
            }
            if let description = finding?.description, !description.isEmpty {
                AboutSection(about: AboutText(measures: description, notes: finding?.waitingFor))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReference) {
            ExerciseDetailSheet(exerciseId: item.exerciseId, name: item.name)
                .environmentObject(appState)
        }
    }

    private var chart: some View {
        Chart {
            // By position: two sessions can share a day.
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("Day", p.date, unit: .day), y: .value(unit, p.value))
                    .foregroundStyle(Color.green)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", p.date, unit: .day), y: .value(unit, p.value))
                    .foregroundStyle(Color.green)
                    .symbolSize(36)
            }
            if let target {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Color.indigo)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d, format: .dateTime.day().month(.abbreviated))
                            .font(.caption2).foregroundStyle(.secondary).fixedSize()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(AnalyticsProgramTab.number(v)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityLabel("\(item.name): \(points.count) sessions, latest \(points.last.map { Self.text($0.value, unit) } ?? "none")")
    }

    /// A logged session: the day, the value, and heart rate when a workout
    /// was matched to it.
    private func sessionRow(_ point: ExerciseHistoryItem.Point) -> some View {
        let value = point.value(metric: metric, unit: unit)
        return VStack(alignment: .leading, spacing: 2) {
            LabeledContent {
                Text(value.map { Self.text($0, unit) } ?? "—").monospacedDigit()
            } label: {
                Text(point.date.flatMap(Self.day).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
                     ?? point.weekNumber.map { "Week \($0)" } ?? "—")
            }
            if point.hrAvg != nil || point.hrMax != nil {
                Label([point.hrAvg.map { "\($0) avg" }, point.hrMax.map { "\($0) max" }]
                        .compactMap { $0 }.joined(separator: " · ") + " bpm", systemImage: "heart.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func text(_ v: Double, _ unit: String) -> String {
        ProgressionView.withUnit(AnalyticsProgramTab.number(v), unit)
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The day of a stored date ("2026-10-14", or a timestamp that starts with one).
    private static func day(_ raw: String) -> Date? { isoDay.date(from: String(raw.prefix(10))) }
}
