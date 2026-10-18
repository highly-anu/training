import SwiftUI
import Charts

// Analytics ▸ Load's summary cards' pieces and their detail screens
// (design-system §6.37): Load Focus, Mix and Weekly. The numbers are the
// server's (`GET /health/load/summary`, `/health/load/weekly`), or the
// on-device engine's when it could not answer, which the screens say.

// MARK: - Load focus

/// One of Load Focus's three bands: base is zones 1–2, threshold zone 3,
/// anaerobic zones 4–5 (`load_summary.focus28d`), each in its zones' colour.
struct LoadFocusBand: Identifiable {
    let label: String
    let zones: String
    let minutes: Double
    let color: Color
    var id: String { label }

    static func all(_ focus: TrainingLoadFocus) -> [LoadFocusBand] {
        [LoadFocusBand(label: "Base", zones: "Z1–2", minutes: focus.baseMinutes, color: HRZoneStyle.color("z2")),
         LoadFocusBand(label: "Threshold", zones: "Z3", minutes: focus.thresholdMinutes, color: HRZoneStyle.color("z3")),
         LoadFocusBand(label: "Anaerobic", zones: "Z4–5", minutes: focus.anaerobicMinutes, color: HRZoneStyle.color("z5"))]
    }
}

/// The last 28 days' heart-rate minutes in full: each band's zones, minutes
/// and share, the total, and what the bands are.
struct LoadFocusDetailView: View {
    let focus: TrainingLoadFocus
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section {
                ForEach(LoadFocusBand.all(focus)) { band in
                    HStack(spacing: 10) {
                        Circle().fill(band.color).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(band.label)
                            Text(band.zones).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(focus.total > 0 ? "\(Int((band.minutes / focus.total * 100).rounded()))%" : "—")
                                .fontWeight(.semibold)
                            Text(LoadSummaryFormat.minutes(band.minutes)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Last 28 days")
            } footer: {
                Text("\(LoadSummaryFormat.minutes(focus.total)) with heart rate")
            }
            AboutSection(about: AboutText(terms: ["load_focus", "hr_zones"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Load Focus")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded(["load_focus", "hr_zones"]) }
    }
}

// MARK: - Mix

/// The period's minutes by modality as a ring, the largest share in its
/// hole and every segment named beneath it (colour is never the only label).
struct ModalityDonut: View {
    let shares: [ModalityShare]
    /// The detail names each segment in its rows instead.
    var showsLegend = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Chart(shares) { share in
                    SectorMark(angle: .value("Pct", share.pct), innerRadius: .ratio(0.55), angularInset: 1.5)
                        .foregroundStyle(share.color)
                        .cornerRadius(3)
                }
                if let top = shares.first {
                    VStack(spacing: 2) {
                        Text("\(top.pct)%").font(.title3).fontWeight(.bold).monospacedDigit()
                        Text(top.label).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(2)
                    }
                    // Inside the hole of the ring, however large the text.
                    .frame(maxWidth: 96)
                }
            }
            .frame(height: 180)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("By modality: " + shares.map { "\($0.label) \($0.pct) percent" }.joined(separator: ", "))
            if showsLegend {
                LegendFlow(spacing: 10, lineSpacing: 4) {
                    ForEach(shares) { share in
                        HStack(spacing: 4) {
                            Circle().fill(share.color).frame(width: 8, height: 8)
                            Text("\(share.label) \(share.pct)%").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

/// The period's hours by activity, one bar each with its hours.
struct ActivityBars: View {
    let entries: [ActivityTypeEntry]

    var body: some View {
        Chart(entries) { entry in
            BarMark(x: .value("Hours", entry.hours), y: .value("Activity", entry.name))
                .foregroundStyle(entry.color)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(String(format: "%.1fh", entry.hours))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize()
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(preset: .aligned) { value in
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(s).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: CGFloat(entries.count) * 32 + 16)
    }
}

/// The period's split both ways, with the minutes and hours behind each
/// share: by modality (what kind of training) and by activity (what the
/// watch called it).
struct MixDetailView: View {
    let modalities: [ModalityShare]
    let activities: [ActivityTypeEntry]
    let period: AnalyticsPeriod
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            if !modalities.isEmpty {
                Section {
                    ModalityDonut(shares: modalities, showsLegend: false).padding(.vertical, 6)
                    ForEach(modalities) { share in
                        HStack(spacing: 10) {
                            Circle().fill(share.color).frame(width: 10, height: 10)
                            Text(share.label)
                            Spacer()
                            if let minutes = share.minutes {
                                Text(LoadSummaryFormat.minutes(minutes)).foregroundStyle(.secondary)
                            }
                            Text("\(share.pct)%").fontWeight(.semibold)
                        }
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("By modality · \(LoadSummaryFormat.periodWords(period))")
                }
            }
            if !activities.isEmpty {
                Section {
                    ForEach(activities) { entry in
                        HStack(spacing: 10) {
                            Circle().fill(entry.color).frame(width: 10, height: 10)
                            Text(entry.name)
                            Spacer()
                            Text("\(Int(entry.sessions)) ×").foregroundStyle(.secondary)
                            Text(String(format: "%.1f h", entry.hours)).fontWeight(.semibold)
                        }
                        .monospacedDigit()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(format: "%@: %d sessions, %.1f hours", entry.name, Int(entry.sessions), entry.hours))
                    }
                } header: {
                    Text("By activity · \(LoadSummaryFormat.periodWords(period))")
                }
            }
            AboutSection(about: AboutText(terms: ["mix"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Mix")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded(["mix"]) }
    }
}

// MARK: - Weekly

/// One week's TRIMP (server, else on device) for the weekly charts.
struct WeeklyLoadBar: Identifiable {
    let id: String
    let weekStart: Date
    let trimp: Double
    let sessions: Int
}

/// Sessions a week as bars coloured by how many, with the key.
struct WeeklySessionsChart: View {
    let entries: [WeeklyConsistencyEntry]
    var height: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(entries) { entry in
                BarMark(x: .value("Week", entry.weekStart, unit: .weekOfYear),
                        y: .value("Sessions", entry.sessionCount))
                    .foregroundStyle(Self.color(entry.sessionCount))
                    .cornerRadius(4)
            }
            .chartXAxis { WeeklyAxis.months }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: height)
            .accessibilityLabel("Sessions in each of the last \(entries.count) weeks")
            HStack(spacing: 12) {
                key(Color.gray.opacity(0.3), "0")
                key(.green, "1–2")
                key(.blue, "3–4")
                key(.orange, "5–6")
                key(.red, "7+")
            }
            .font(.caption2)
            .accessibilityHidden(true)
        }
    }

    private func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }

    static func color(_ count: Int) -> Color {
        switch count {
        case 0:       return Color.gray.opacity(0.25)
        case 1...2:   return .green
        case 3...4:   return .blue
        case 5...6:   return .orange
        default:      return .red
        }
    }
}

/// TRIMP a week as bars.
struct WeeklyTRIMPChart: View {
    let bars: [WeeklyLoadBar]
    var height: CGFloat = 130

    var body: some View {
        Chart(bars) { bar in
            BarMark(x: .value("Week", bar.weekStart, unit: .weekOfYear), y: .value("TRIMP", bar.trimp))
                .foregroundStyle(Color.orange)
                .cornerRadius(4)
        }
        .chartXAxis { WeeklyAxis.months }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("TRIMP in each of the last \(bars.count) weeks")
    }
}

/// A month label on each month's first week.
enum WeeklyAxis {
    static var months: some AxisContent {
        AxisMarks(values: .stride(by: .month, count: 1)) { value in
            AxisValueLabel {
                if let d = value.as(Date.self) {
                    Text(d, format: .dateTime.month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Twelve weeks in full: sessions a week, TRIMP a week, and each week's
/// two numbers, newest first.
struct WeeklyDetailView: View {
    let consistency: [WeeklyConsistencyEntry]
    let bars: [WeeklyLoadBar]
    /// TRIMP was computed on this phone because the server did not answer.
    let onDevice: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section("Sessions a week") {
                WeeklySessionsChart(entries: consistency, height: 160).padding(.vertical, 6)
            }
            if bars.contains(where: { $0.trimp > 0 }) {
                Section {
                    WeeklyTRIMPChart(bars: bars, height: 160).padding(.vertical, 6)
                } header: {
                    Text("TRIMP a week")
                } footer: {
                    if onDevice { OnDeviceMark() }
                }
            }
            Section("Weeks") {
                ForEach(consistency.reversed()) { week in
                    // Within half a week: the server starts weeks on Monday, the
                    // on-device fallback on the locale's first day.
                    let trimp = bars.first { abs($0.weekStart.timeIntervalSince(week.weekStart)) < 3.5 * 86_400 }?.trimp
                    LabeledContent {
                        HStack(spacing: 12) {
                            Label("\(week.sessionCount)", systemImage: "figure.run").labelStyle(.inline)
                            if let trimp {
                                Label("\(Int(trimp.rounded()))", systemImage: "flame").labelStyle(.inline)
                            }
                        }
                        .monospacedDigit()
                    } label: {
                        Text(week.weekStart, format: .dateTime.day().month(.abbreviated))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Week of \(week.weekStart.formatted(.dateTime.day().month(.wide))): "
                                        + "\(week.sessionCount) sessions" + (trimp.map { ", TRIMP \(Int($0.rounded()))" } ?? ""))
                }
            }
            AboutSection(about: AboutText(terms: ["consistency", "trimp"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Weekly")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded(["consistency", "trimp"]) }
    }
}

/// "On device": a number computed on this phone because the server could
/// not be reached; the server's numbers carry no mark.
struct OnDeviceMark: View {
    var body: some View {
        Label("On device", systemImage: "iphone")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityLabel("Computed on this phone; the server could not be reached")
    }
}

/// Minutes and periods in words for Load's detail screens.
enum LoadSummaryFormat {
    /// "45 min", "8 h 20 min".
    static func minutes(_ m: Double) -> String {
        let total = Int(m.rounded())
        if total < 60 { return "\(total) min" }
        return total % 60 == 0 ? "\(total / 60) h" : "\(total / 60) h \(total % 60) min"
    }

    /// "last 30 days", "all time".
    static func periodWords(_ period: AnalyticsPeriod) -> String {
        period.days.map { "last \($0) days" } ?? "all time"
    }
}
