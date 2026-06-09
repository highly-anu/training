import SwiftUI
import Charts

struct AnalyticsOverviewTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var period: AnalyticsPeriod

    @State private var pmcEntries: [PMCEntry] = []
    @State private var isLoadingPMC = false

    private var filtered: [ImportedWorkout] {
        AnalyticsEngine.filter(appState.importedWorkouts, withinDays: period.days)
    }

    private var stats: WorkoutPeriodStats {
        AnalyticsEngine.periodStats(for: filtered, period: period, allWorkouts: appState.importedWorkouts)
    }

    private var loadFocus: TrainingLoadFocus {
        AnalyticsEngine.trainingLoadFocus(workouts: appState.importedWorkouts,
                                          hrConfig: appState.profile.hrConfig,
                                          dateOfBirth: appState.profile.dateOfBirth)
    }

    private var modalities: [ModalityShare] {
        AnalyticsEngine.modalityBreakdown(workouts: filtered)
    }

    private var activities: [ActivityTypeEntry] {
        AnalyticsEngine.activityTypeBreakdown(workouts: filtered)
    }

    private var consistency: [WeeklyConsistencyEntry] {
        AnalyticsEngine.weeklyConsistency(allWorkouts: appState.importedWorkouts)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                periodSelector
                kpiGrid
                if loadFocus.total > 0 { loadFocusCard }
                if !modalities.isEmpty { modalityDonutCard }
                if !activities.isEmpty { activityBarCard }
                consistencyCard
                if !pmcEntries.isEmpty { pmcCard }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .task(id: appState.importedWorkouts.count) {
            await recomputePMC()
        }
        .refreshable {
            AppHaptics.light()
            await appState.loadWorkouts()
            await recomputePMC()
            AppHaptics.success()
        }
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(spacing: 6) {
            ForEach(AnalyticsPeriod.allCases) { p in
                Button {
                    AppHaptics.selection()
                    withAnimation(AppAnimation.springSnappy) { period = p }
                } label: {
                    Text(p.label)
                        .font(.subheadline).fontWeight(period == p ? .semibold : .regular)
                        .foregroundStyle(period == p ? .white : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(period == p ? Color.blue : Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - KPI Grid (Apple Fitness-style with trend arrows)

    private var kpiGrid: some View {
        cardContainer(header: "Totals") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                kpiCell(
                    label: "Sessions",
                    value: "\(Int(stats.sessions))",
                    unit: "",
                    prev: stats.prevSessions,
                    curr: stats.sessions,
                    higherIsBetter: true
                )
                kpiCell(
                    label: "Hours",
                    value: String(format: "%.1f", stats.totalMinutes / 60),
                    unit: "h",
                    prev: stats.prevMinutes,
                    curr: stats.totalMinutes,
                    higherIsBetter: true
                )
                kpiCell(
                    label: "Distance",
                    value: String(format: "%.0f", stats.totalDistanceKm),
                    unit: "km",
                    prev: stats.prevDistanceKm,
                    curr: stats.totalDistanceKm,
                    higherIsBetter: true
                )
                kpiCell(
                    label: "Elevation",
                    value: stats.totalElevationGainM >= 1000
                        ? String(format: "%.1fk", stats.totalElevationGainM / 1000)
                        : "\(Int(stats.totalElevationGainM))",
                    unit: "m",
                    prev: nil, curr: nil, higherIsBetter: true
                )
                kpiCell(
                    label: "Avg Duration",
                    value: stats.sessions > 0 ? "\(Int(stats.totalMinutes / stats.sessions))" : "—",
                    unit: "min",
                    prev: nil, curr: nil, higherIsBetter: true
                )
                kpiCell(
                    label: "Per Week",
                    value: period == .all
                        ? "—"
                        : String(format: "%.1f", stats.sessions / max(1, Double(period.days ?? 1) / 7.0)),
                    unit: "",
                    prev: nil, curr: nil, higherIsBetter: true
                )
            }
        }
    }

    private func kpiCell(label: String, value: String, unit: String,
                          prev: Double?, curr: Double?, higherIsBetter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 2) {
                Text(value).font(.title3).fontWeight(.semibold)
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                }
                Spacer(minLength: 0)
                if let p = prev, let c = curr, p > 0, period != .all {
                    trendArrow(prev: p, curr: c, higherIsBetter: higherIsBetter)
                }
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func trendArrow(prev: Double, curr: Double, higherIsBetter: Bool) -> some View {
        let delta = curr - prev
        let isPositive = delta > 0
        let isGood = higherIsBetter ? isPositive : !isPositive
        let pct = prev > 0 ? abs(delta / prev * 100) : 0

        return Group {
            if abs(delta) > 0.01 {
                HStack(spacing: 1) {
                    Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text(String(format: "%.0f%%", pct)).font(.caption2)
                }
                .foregroundStyle(isGood ? .green : .red)
            }
        }
    }

    // MARK: - Training Load Focus (Garmin-style)

    private var loadFocusCard: some View {
        cardContainer(header: "Training Load Focus") {
            VStack(spacing: 10) {
                let total = loadFocus.total
                let rows: [(label: String, minutes: Double, color: Color)] = [
                    ("Base", loadFocus.baseMinutes, .blue),
                    ("Threshold", loadFocus.thresholdMinutes, .orange),
                    ("Anaerobic", loadFocus.anaerobicMinutes, .red)
                ]
                ForEach(rows, id: \.label) { row in
                    HStack(spacing: 10) {
                        Text(row.label).font(.caption).frame(width: 72, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray5)).frame(height: 8)
                                Capsule()
                                    .fill(row.color.gradient)
                                    .frame(width: total > 0 ? geo.size.width * row.minutes / total : 0, height: 8)
                            }
                        }
                        .frame(height: 8)
                        Text(total > 0 ? String(format: "%.0f%%", row.minutes / total * 100) : "—")
                            .font(.caption2).foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                    }
                }
                Text("Last 28 days · Based on HR zone distribution")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Modality Donut

    private var modalityDonutCard: some View {
        cardContainer(header: "By Modality") {
            ZStack {
                Chart(modalities) { share in
                    SectorMark(
                        angle: .value("Pct", share.pct),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .foregroundStyle(share.color)
                    .cornerRadius(3)
                }
                if let top = modalities.first {
                    VStack(spacing: 2) {
                        Text("\(top.pct)%").font(.title3).fontWeight(.bold)
                        Text(top.label).font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 80)
                }
            }
            .frame(height: 180)
            .padding(.vertical, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(modalities.prefix(6)) { share in
                        HStack(spacing: 4) {
                            Circle().fill(share.color).frame(width: 8, height: 8)
                            Text("\(share.label) \(share.pct)%")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Activity Bar

    private var activityBarCard: some View {
        cardContainer(header: "By Activity") {
            Chart(activities) { entry in
                BarMark(
                    x: .value("Hours", entry.hours),
                    y: .value("Activity", entry.name)
                )
                .foregroundStyle(entry.color.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(String(format: "%.1fh", entry.hours))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
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
            .frame(height: CGFloat(activities.count) * 32 + 16)
        }
    }

    // MARK: - Weekly Consistency

    private var consistencyCard: some View {
        cardContainer(header: "Weekly Volume") {
            Chart(consistency) { entry in
                BarMark(
                    x: .value("Week", entry.weekLabel),
                    y: .value("Sessions", entry.sessionCount)
                )
                .foregroundStyle(consistencyColor(entry.sessionCount).gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 3)) { value in
                    AxisValueLabel {
                        if let s = value.as(String.self) {
                            Text(s).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 130)
            HStack(spacing: 12) {
                legendDot(color: .quaternary, label: "0")
                legendDot(color: .green,      label: "1–2")
                legendDot(color: .blue,       label: "3–4")
                legendDot(color: .orange,     label: "5–6")
                legendDot(color: .red,        label: "7+")
            }
            .font(.caption2)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func consistencyColor(_ count: Int) -> Color {
        switch count {
        case 0:       return Color.gray.opacity(0.25)
        case 1...2:   return .green
        case 3...4:   return .blue
        case 5...6:   return .orange
        default:      return .red
        }
    }

    // MARK: - PMC Chart

    private var pmcCard: some View {
        cardContainer(header: "Performance Management") {
            if isLoadingPMC {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Chart {
                        ForEach(pmcEntries) { e in
                            BarMark(x: .value("Date", e.date, unit: .day),
                                    y: .value("TSB", e.tsb))
                                .foregroundStyle(e.tsb >= 0 ? Color.green.opacity(0.5) : Color.red.opacity(0.5))
                        }
                        ForEach(pmcEntries) { e in
                            LineMark(x: .value("Date", e.date, unit: .day),
                                     y: .value("ATL", e.atl))
                                .foregroundStyle(.orange)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.catmullRom)
                        }
                        ForEach(pmcEntries) { e in
                            LineMark(x: .value("Date", e.date, unit: .day),
                                     y: .value("CTL", e.ctl))
                                .foregroundStyle(.blue)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 160)
                    HStack(spacing: 12) {
                        legendLine(color: .blue,   label: "CTL (fitness)")
                        legendLine(color: .orange, label: "ATL (fatigue)")
                        legendLine(color: .green,  label: "TSB (form)")
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private func legendLine(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 16, height: 2)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Card Container

    private func cardContainer<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.footnote).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
        .padding(AppMetrics.cardPadding)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }

    // MARK: - PMC Computation

    private func recomputePMC() async {
        isLoadingPMC = true
        let workouts = appState.importedWorkouts
        let hrConfig = appState.profile.hrConfig
        let dob = appState.profile.dateOfBirth
        let result = await Task.detached(priority: .userInitiated) {
            AnalyticsEngine.computePMC(workouts: workouts, hrConfig: hrConfig, dateOfBirth: dob)
        }.value
        pmcEntries = result
        isLoadingPMC = false
    }
}

