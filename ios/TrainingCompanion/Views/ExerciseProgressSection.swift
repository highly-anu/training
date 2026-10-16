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
        VStack(alignment: .leading, spacing: 10) {
            Text("EXERCISES")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            Picker("Exercises", selection: Binding(get: { active }, set: { filter = $0 })) {
                Text("With data (\(counts.withData))").tag(Filter.data)
                Text("So far (\(counts.soFar))").tag(Filter.soFar)
                Text("All (\(counts.inProgram))").tag(Filter.all)
            }
            .pickerStyle(.segmented)
            if visible.isEmpty {
                Text(active == .data ? "No data yet" : "None yet")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { item in
                    ExerciseProgressCardView(item: item, finding: findings.first { $0.exerciseId == item.exerciseId })
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
                    Text("GPS").font(.system(size: 9)).foregroundStyle(.secondary)
                        .padding(.horizontal, 3).overlay(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
                }
                Spacer()
                Text(status != "insufficient_data" ? AnalyticsStatusStyle.label(status)
                     : item.history.isEmpty ? "Not tracked" : "No trend yet")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(AnalyticsStatusStyle.color(status))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(AnalyticsStatusStyle.color(status).opacity(0.12))
                    .clipShape(Capsule())
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let latest {
                        Text(ProgressionView.withUnit(AnalyticsProgramTab.number(latest), unit))
                            .font(.title3).fontWeight(.bold).monospacedDigit()
                        if let target {
                            Label(ProgressionView.withUnit(AnalyticsProgramTab.number(target), unit), systemImage: "target")
                                .font(.caption2).foregroundStyle(.secondary)
                                .accessibilityLabel("Target \(ProgressionView.withUnit(AnalyticsProgramTab.number(target), unit))")
                        }
                    } else {
                        Text("Log \(unit) to track").font(.caption).italic().foregroundStyle(.secondary)
                        if let target {
                            Label(ProgressionView.withUnit(AnalyticsProgramTab.number(target), unit), systemImage: "target")
                                .font(.caption2).foregroundStyle(.secondary)
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
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let change = finding?.changeSummary, status != "insufficient_data" {
                Text(change).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(status == "insufficient_data" ? 0.75 : 1)
    }
}
