import SwiftUI
import Charts

/// Fitness, fatigue and form today (CTL, ATL, TSB), each with its colour —
/// the Performance Management card's summary and the top of its screen.
struct PMCNumbers: View {
    let entry: PMCEntry

    var body: some View {
        HStack(spacing: 0) {
            cell("CTL", entry.ctl, color: .blue, spoken: "Fitness")
            Spacer(minLength: 8)
            cell("ATL", entry.atl, color: .orange, spoken: "Fatigue")
            Spacer(minLength: 8)
            cell("TSB", entry.tsb, color: entry.tsb >= 0 ? .green : .red, spoken: "Form")
        }
    }

    private func cell(_ term: String, _ value: Double, color: Color, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(value.rounded()))")
                .font(.title3).fontWeight(.semibold).monospacedDigit()
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(term).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spoken), \(term), \(Int(value.rounded()))")
    }
}

/// The Performance Management chart: form as bars (green above zero, red
/// below) under fitness and fatigue as lines. `compact` is the card's
/// preview — the same marks and colours, no axes (Charting data: a small
/// chart previews the larger one in the same style); the full chart
/// scrubs to any day.
struct PMCChart: View {
    let entries: [PMCEntry]
    var compact = false
    @Binding var selected: Date?

    init(entries: [PMCEntry], compact: Bool = false, selected: Binding<Date?> = .constant(nil)) {
        self.entries = entries
        self.compact = compact
        self._selected = selected
    }

    private var selectedEntry: PMCEntry? {
        guard let selected else { return nil }
        return entries.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        Chart {
            ForEach(entries) { e in
                BarMark(x: .value("Date", e.date, unit: .day), y: .value("TSB", e.tsb))
                    .foregroundStyle(e.tsb >= 0 ? Color.green.opacity(0.5) : Color.red.opacity(0.5))
            }
            ForEach(entries) { e in
                LineMark(x: .value("Date", e.date, unit: .day), y: .value("ATL", e.atl),
                         series: .value("Series", "ATL"))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(entries) { e in
                LineMark(x: .value("Date", e.date, unit: .day), y: .value("CTL", e.ctl),
                         series: .value("Series", "CTL"))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            if let e = selectedEntry {
                RuleMark(x: .value("Date", e.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.date, format: .dateTime.day().month(.abbreviated))
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("CTL \(Int(e.ctl.rounded())) · ATL \(Int(e.atl.rounded())) · TSB \(Int(e.tsb.rounded()))")
                                .font(.caption).monospacedDigit()
                        }
                        .padding(6)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXSelection(value: compact ? .constant(nil) : $selected)
        .chartXAxis {
            if !compact {
                AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2)
                }
            }
        }
        .chartYAxis {
            if !compact {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(height: compact ? 56 : 220)
        .accessibilityLabel("Fitness, fatigue and form over \(entries.count) days")
    }
}

/// Fitness, fatigue and form in full (design-system §6.37), pushed from the
/// Performance Management card on Analytics ▸ Load: today's numbers, the
/// chart (drag across it for any day's), the key, and what each term means.
struct PMCDetailView: View {
    let entries: [PMCEntry]
    /// The numbers were computed on this phone because the server did not answer.
    let onDevice: Bool

    @EnvironmentObject var appState: AppState
    @State private var selected: Date?

    var body: some View {
        List {
            if let today = entries.last {
                Section {
                    PMCNumbers(entry: today).padding(.vertical, 4)
                } footer: {
                    if onDevice { Label("On device", systemImage: "iphone") }
                }
            }
            Section {
                PMCChart(entries: entries, selected: $selected).padding(.vertical, 6)
                HStack(spacing: 14) {
                    key(Rectangle().fill(Color.blue).frame(width: 16, height: 2), "CTL")
                    key(Rectangle().fill(Color.orange).frame(width: 16, height: 2), "ATL")
                    key(HStack(spacing: 1) {
                        Rectangle().fill(Color.green.opacity(0.5)).frame(width: 7, height: 8)
                        Rectangle().fill(Color.red.opacity(0.5)).frame(width: 7, height: 8)
                    }, "TSB")
                }
                .font(.caption)
                .accessibilityHidden(true)
            } header: {
                Text("\(entries.count) days")
            }
            AboutSection(about: AboutText(terms: ["ctl", "atl", "tsb", "trimp"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Performance Management")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded() }
    }

    private func key<Mark: View>(_ mark: Mark, _ term: String) -> some View {
        HStack(spacing: 4) {
            mark
            Text(term).foregroundStyle(.secondary)
        }
    }
}
