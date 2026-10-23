import SwiftUI
import Charts

/// Analytics ▸ Program's Scorecard in full (design-system §6.37): the
/// completion and this week's, each week's, each tier's, and every modality
/// with its minutes against its range — then what completion and the gate
/// are, in the server's words.
struct ScorecardDetailView: View {
    let scorecard: ProgramAnalytics.Scorecard
    @EnvironmentObject var appState: AppState

    private static let tiers = ["committed", "core", "supplementary", "unscheduled"]

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    if let overall = scorecard.overallPct {
                        Label("\(Int(overall.rounded()))%", systemImage: "checkmark.circle")
                            .labelStyle(.inline)
                            .font(.title2).fontWeight(.bold).monospacedDigit()
                            .accessibilityLabel("\(Int(overall.rounded())) percent of the sessions due are done")
                    }
                    Spacer()
                    AnalyticsStatusBadge(status: scorecard.headline)
                }
                if let done = scorecard.completedSessions, let due = scorecard.plannedSessions {
                    LabeledContent("Sessions due so far") { Text("\(done) of \(due)").monospacedDigit() }
                }
                if let week = scorecard.currentWeek {
                    LabeledContent("Week \(week.weekNumber)") {
                        Text("\(week.completed) of \(week.due) · \(week.total) in the week").monospacedDigit()
                    }
                    .accessibilityLabel("Week \(week.weekNumber): \(week.completed) of \(week.due) due so far, \(week.total) in the week")
                }
            }
            if !scorecard.weeks.isEmpty {
                Section("By week") {
                    // By array index: an old program repeats week numbers
                    // (1, 1, 2, 3), which stacked two weeks in one bar.
                    Chart(scorecard.weeks, id: \.weekIndex) { w in
                        BarMark(x: .value("Week", String(w.weekIndex)), y: .value("Done", w.pct ?? 0))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(3)
                            .annotation(position: .top) {
                                Text("\(w.completed)/\(w.planned)")
                                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                    }
                    .chartYScale(domain: 0...110)
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let s = value.as(String.self), let i = Int(s),
                                   let w = scorecard.weeks.first(where: { $0.weekIndex == i }) {
                                    Text("W\(w.weekNumber)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text("\(v)%").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 160)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(scorecard.weeks.map { "Week \($0.weekNumber): \($0.completed) of \($0.planned)" }
                        .joined(separator: ", "))
                }
            }
            let tiers = Self.tiers.compactMap { id in scorecard.tiers[id].map { (id, $0) } }
            if !tiers.isEmpty {
                Section("Tiers") {
                    ForEach(tiers, id: \.0) { id, tier in
                        LabeledContent {
                            Text("\(tier.completed) of \(tier.planned)" + (tier.pct.map { " · \(Int($0.rounded()))%" } ?? ""))
                                .monospacedDigit()
                        } label: {
                            Label(id.capitalized, systemImage: ScorecardRowView.tierIcon(id) ?? "circle")
                                .labelStyle(.inline)
                        }
                    }
                }
            }
            if !scorecard.modalities.isEmpty {
                Section("Modalities") {
                    ForEach(scorecard.modalities) { row in
                        ScorecardRowView(row: row).padding(.vertical, 4)
                    }
                }
            }
            AboutSection(about: AboutText(terms: ["completion", "weekly_dose"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded(["completion", "weekly_dose"]) }
    }
}

/// Analytics ▸ Program's Intensity split in full (design-system §6.37):
/// planned against recorded minutes per zone, each week's minutes, each
/// framework's split against its plan, the share of 1RM on working sets, and
/// what counts as zone time.
struct IntensityDetailView: View {
    let intensity: ProgramAnalytics.Intensity
    @EnvironmentObject var appState: AppState

    private static let buckets: [(key: String, label: String)] = [
        ("zone1_2_pct", "Z1–2"), ("zone3_pct", "Z3"), ("zone4_5_pct", "Z4–5"), ("max_effort_pct", "Max effort")]

    var body: some View {
        List {
            if let coverage = intensity.coverage {
                Section {
                    LabeledContent {
                        Text("\(coverage.measured) of \(coverage.inScope)").monospacedDigit()
                    } label: {
                        Label("Sessions measured", systemImage: "ruler").labelStyle(.inline)
                    }
                } footer: {
                    if coverage.measured < coverage.inScope, let reason = coverage.reason {
                        Text(AnalyticsStatusStyle.coverageReason(reason))
                    }
                }
            }
            if !intensity.zones.isEmpty {
                Section {
                    ZonePlanComparison(rows: intensity.zones.map {
                        .init(zone: $0.zone, label: $0.label, planned: $0.plannedMinutes, recorded: $0.actualMinutes)
                    })
                    .padding(.vertical, 4)
                } header: {
                    Text("Zones · completed sessions")
                } footer: {
                    if let maxHr = intensity.maxHr {
                        Label("Max HR \(maxHr) bpm", systemImage: "heart")
                    }
                }
            }
            if !intensity.weeks.isEmpty {
                Section("By week") {
                    IntensityWeeksChart(weeks: intensity.weeks, height: 200).padding(.vertical, 6)
                }
            }
            if !intensity.byFramework.isEmpty {
                Section {
                    ForEach(Array(intensity.byFramework.enumerated()), id: \.offset) { _, fw in
                        frameworkSplit(fw)
                    }
                } header: {
                    Text("Done and planned")
                }
            }
            if let pct = intensity.pct1rm, let mean = pct.meanPct {
                Section {
                    LabeledContent {
                        Text("\(AnalyticsProgressTab.number(mean))% of 1RM").monospacedDigit()
                    } label: {
                        Label("Working sets", systemImage: "scalemass").labelStyle(.inline)
                    }
                } footer: {
                    Text("\(pct.sessions) logged lifts")
                }
            }
            AboutSection(about: AboutText(terms: ["intensity", "hr_zones"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Intensity split")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded(["intensity", "hr_zones"]) }
    }

    /// One framework's share per bucket: done, then planned, in a grid.
    private func frameworkSplit(_ fw: ProgramAnalytics.Intensity.ByFramework) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let id = fw.frameworkId {
                Text(ProgramHeader.words(id)).font(.subheadline).fontWeight(.semibold)
            }
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(Self.buckets, id: \.key) { Text($0.label) }
                }
                .font(.caption).foregroundStyle(.secondary)
                GridRow {
                    Text("Done").foregroundStyle(.secondary)
                    ForEach(Self.buckets, id: \.key) { b in
                        Text(Self.percent((fw.actualPct[b.key] ?? nil)))
                    }
                }
                GridRow {
                    Text("Planned").foregroundStyle(.secondary)
                    ForEach(Self.buckets, id: \.key) { b in
                        Text(Self.percent(fw.plannedPct?[b.key]))
                    }
                }
            }
            .font(.subheadline).monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.buckets.map { b in
            "\(b.label): done \(Self.percent((fw.actualPct[b.key] ?? nil))), planned \(Self.percent(fw.plannedPct?[b.key]))"
        }.joined(separator: "; "))
    }

    private static func percent(_ v: Double?) -> String {
        v.map { "\(Int($0.rounded()))%" } ?? "—"
    }
}
