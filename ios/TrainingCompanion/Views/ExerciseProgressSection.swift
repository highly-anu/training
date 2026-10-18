import SwiftUI
import Charts

/// Analytics ▸ Progress's exercises: three named counts — in the program, so
/// far, with data — a filter on them, and a card per exercise. The web's
/// `ProgressionTab` exercise grid and `ExerciseProgressCard`; the phone had
/// neither until 2026-10-16. The target is this week's stored prescription
/// (`progression_tracker.prescribed_trajectory`), the status the analytics
/// engine's finding for the exercise when it has one.
struct ExerciseProgressSection: View {
    let response: ExerciseHistoryResponse
    let findings: [ExerciseFinding]

    enum Filter: String, CaseIterable, Identifiable {
        case data, soFar, all
        var id: String { rawValue }
    }
    @State private var filter: Filter? = nil

    private var withData: [ExerciseHistoryItem] { response.exercises.filter { !$0.history.isEmpty } }
    private var soFar: [ExerciseHistoryItem] { response.exercises.filter(\.scheduledSoFar) }

    /// The first filter that shows something, until the athlete picks one.
    private var active: Filter {
        filter ?? (!withData.isEmpty ? .data : !soFar.isEmpty ? .soFar : .all)
    }

    private var visible: [ExerciseHistoryItem] {
        switch active {
        case .data: return withData
        case .soFar: return soFar
        case .all: return response.exercises
        }
    }

    var body: some View {
        let counts = response.resolvedCounts
        AnalyticsCard(header: "Exercises") {
            Picker("Exercises", selection: Binding(get: { active }, set: { filter = $0 })) {
                Text("With data (\(counts.withData))").tag(Filter.data)
                Text("So far (\(counts.soFar))").tag(Filter.soFar)
                Text("All (\(counts.inProgram))").tag(Filter.all)
            }
            .pickerStyle(.segmented)
            if visible.isEmpty {
                Text(active == .data ? "No data yet" : "None yet")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { item in
                    ExerciseProgressCardView(item: item, finding: findings.first { $0.exerciseId == item.exerciseId })
                    if item.id != visible.last?.id { Divider() }
                }
            }
        }
    }
}

struct ExerciseProgressCardView: View {
    let item: ExerciseHistoryItem
    let finding: ExerciseFinding?

    private var metric: String { finding?.metricType ?? item.metricType ?? "weight" }
    private var unit: String { finding?.unit ?? item.unit ?? "kg" }
    private var status: String { finding?.status ?? "insufficient_data" }
    private var values: [Double] { item.history.compactMap { $0.value(metric: metric, unit: unit) } }
    private var latest: Double? { finding?.actualValue ?? values.last }
    private var target: Double? { finding?.expectedValue ?? item.target?.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                if !item.history.isEmpty, item.history.allSatisfy({ $0.source == "matched_workout" }) {
                    // Every point from a recorded workout: a symbol, not a
                    // boxed 9 pt word (§4.1).
                    Image(systemName: "location.fill")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("From recorded workouts")
                }
                Spacer()
                TintCapsule(text: status != "insufficient_data" ? AnalyticsStatusStyle.label(status)
                            : item.history.isEmpty ? "Not tracked" : "No trend yet",
                            color: AnalyticsStatusStyle.color(status))
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let latest {
                        Text(ProgressionView.withUnit(AnalyticsProgramTab.number(latest), unit))
                            .font(.title3).fontWeight(.bold).monospacedDigit()
                        if let target {
                            Label(ProgressionView.withUnit(AnalyticsProgramTab.number(target), unit), systemImage: "target")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Target \(ProgressionView.withUnit(AnalyticsProgramTab.number(target), unit))")
                        }
                    } else {
                        Text("Log \(unit) to track").font(.footnote).foregroundStyle(.secondary)
                        if let target {
                            Label(ProgressionView.withUnit(AnalyticsProgramTab.number(target), unit), systemImage: "target")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Prescribed \(ProgressionView.withUnit(AnalyticsProgramTab.number(target), unit))")
                        }
                    }
                }
                Spacer()
                if values.count >= 2 {
                    Chart(Array(values.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("Point", i), y: .value("Value", v))
                            .foregroundStyle(AnalyticsStatusStyle.color(status))
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 72, height: 26)
                    .accessibilityHidden(true)
                }
            }
            if let last = item.history.last, last.hrAvg != nil || last.hrMax != nil {
                Label([last.hrAvg.map { "\($0) avg" }, last.hrMax.map { "\($0) max" }]
                        .compactMap { $0 }.joined(separator: " · ") + " bpm", systemImage: "heart.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let change = finding?.changeSummary, status != "insufficient_data" {
                Text(change).font(.caption).foregroundStyle(.secondary)
            }
        }
        // No dimming of the whole row: its badge already says "No trend yet",
        // and dimmed secondary text is too faint to read (§4.1).
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
