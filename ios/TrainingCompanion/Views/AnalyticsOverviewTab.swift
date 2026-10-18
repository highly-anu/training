import SwiftUI
import Charts

struct AnalyticsOverviewTab: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    @Binding var period: AnalyticsPeriod
    /// A detail pushed from outside (a deep link); the cards push their own.
    @State private var route: AppRouter.AnalyticsDetail?

    @State private var pmcEntries: [PMCEntry] = []
    @State private var isLoadingPMC = false
    /// Where the load numbers came from. The server is the source of truth —
    /// the web reads the same endpoints — and the on-device engine is the
    /// fallback when it cannot be reached, so the chart says which it was.
    @State private var loadSource: LoadSource = .server
    /// Load Focus's label and share columns, at the reader's text size.
    @ScaledMetric(relativeTo: .subheadline) private var focusLabelWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .subheadline) private var focusShareWidth: CGFloat = 48

    private enum LoadSource { case server, device }

    private var weeklyLoadBars: [WeeklyLoadBar] {
        if let server = appState.serverWeeklyLoad, !server.isEmpty {
            return server.compactMap { entry in
                entry.weekStart.map { WeeklyLoadBar(id: entry.week, weekStart: $0,
                                                    trimp: entry.trimp, sessions: entry.sessions) }
            }
        }
        let cal = Calendar.current
        return AnalyticsEngine.weeklyLoad(workouts: appState.importedWorkouts,
                                          hrConfig: appState.profile.hrConfig,
                                          dateOfBirth: appState.profile.dateOfBirth)
            .enumerated().compactMap { offset, entry in
                guard let ref = cal.date(byAdding: .weekOfYear, value: offset - 11, to: Date()),
                      let monday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: ref))
                else { return nil }
                return WeeklyLoadBar(id: entry.week, weekStart: monday, trimp: entry.trimp,
                                     sessions: Int(entry.sessions))
            }
    }

    // Totals, mixes, consistency and the 28-day focus are the server's
    // (`GET /health/load/summary`), the document the web's Load tab reads;
    // AnalyticsEngine computes them only when that request failed.
    private var summary: LoadSummary? { appState.loadSummaries[period] }

    private var filtered: [ImportedWorkout] {
        AnalyticsEngine.filter(appState.importedWorkouts, withinDays: period.days)
    }

    private var stats: WorkoutPeriodStats {
        summary?.stats
            ?? AnalyticsEngine.periodStats(for: filtered, period: period, allWorkouts: appState.importedWorkouts)
    }

    private var loadFocus: TrainingLoadFocus {
        summary?.loadFocus
            ?? AnalyticsEngine.trainingLoadFocus(workouts: appState.importedWorkouts,
                                                 hrConfig: appState.profile.hrConfig,
                                                 dateOfBirth: appState.profile.dateOfBirth)
    }

    private var modalities: [ModalityShare] {
        summary?.modalityShares ?? AnalyticsEngine.modalityBreakdown(workouts: filtered)
    }

    private var activities: [ActivityTypeEntry] {
        summary?.activityEntries ?? AnalyticsEngine.activityTypeBreakdown(workouts: filtered)
    }

    private var consistency: [WeeklyConsistencyEntry] {
        summary?.consistencyEntries ?? AnalyticsEngine.weeklyConsistency(allWorkouts: appState.importedWorkouts)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                AnalyticsPeriodPicker(period: $period)
                kpiGrid
                if loadFocus.total > 0 { loadFocusCard }
                if !modalities.isEmpty || !activities.isEmpty { mixCard }
                weeklyCard
                if !pmcEntries.isEmpty || isLoadingPMC { pmcCard }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .task(id: appState.importedWorkouts.count) {
            await recomputePMC()
            applyPendingDetail()
        }
        .navigationDestination(item: $route) { detail($0) }
        .onChange(of: router.pendingAnalyticsDetail) { applyPendingDetail() }
        .onChange(of: summary?.totals.sessions) { applyPendingDetail() }
        .task(id: period) {
            await appState.loadIfStale("loadSummary-\(period.rawValue)") { await appState.loadLoadSummary(period) }
        }
        .refreshable {
            await AppRefresh.perform {
                await appState.loadWorkouts()
                await appState.loadLoadAnalytics()   // past loadIfStale: asked for
                await recomputePMC()
                await appState.loadLoadSummary(period)
            }
        }
    }

    // MARK: - KPI Grid (Apple Fitness-style with trend arrows)

    private var kpiGrid: some View {
        // "On device" beside the header when the server could not answer.
        AnalyticsCard(header: "Totals") {
            if summary == nil && appState.loadSummaryFailed.contains(period) { onDeviceMark }
        } content: {
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
                Text(value).font(.title3).fontWeight(.semibold).monospacedDigit()
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                Spacer(minLength: 0)
                if let p = prev, let c = curr, p > 0, period != .all {
                    trendArrow(prev: p, curr: c, higherIsBetter: higherIsBetter)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
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
                    Text(String(format: "%.0f%%", pct)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(isGood ? .green : .red)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(format: "%.0f percent %@ than the previous period", pct, isPositive ? "more" : "less"))
            }
        }
    }

    // MARK: - Training Load Focus (Garmin-style)

    /// The last 28 days' heart-rate minutes in three bands, as shares; the
    /// minutes and which zones each band is are `LoadFocusDetailView`'s.
    private var loadFocusCard: some View {
        AnalyticsDetailCard(header: "Load Focus · 28 days", hint: "Opens load focus") {
            LoadFocusDetailView(focus: loadFocus)
        } content: {
            VStack(spacing: 10) {
                let total = loadFocus.total
                ForEach(LoadFocusBand.all(loadFocus)) { row in
                    HStack(spacing: 10) {
                        Text(row.label).font(.subheadline).lineLimit(1)
                            .frame(width: focusLabelWidth, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray5)).frame(height: 8)
                                Capsule()
                                    .fill(row.color)
                                    .frame(width: total > 0 ? geo.size.width * row.minutes / total : 0, height: 8)
                            }
                        }
                        .frame(height: 8)
                        Text(total > 0 ? String(format: "%.0f%%", row.minutes / total * 100) : "—")
                            .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                            .fixedSize()
                            .frame(minWidth: focusShareWidth, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Mix

    /// The period's minutes by modality, as a ring; by activity too, and the
    /// minutes and hours behind each share, are `MixDetailView`'s. The card
    /// had a Modality/Activity picker until 2026-10-18 — a summary card holds
    /// no controls (§6.37).
    private var mixCard: some View {
        AnalyticsDetailCard(header: "Mix", hint: "Opens the mix by modality and activity") {
            MixDetailView(modalities: modalities, activities: activities, period: period)
        } content: {
            if modalities.isEmpty {
                ActivityBars(entries: activities)
            } else {
                ModalityDonut(shares: modalities)
            }
        }
    }

    // MARK: - Weekly

    /// Twelve weeks of sessions a week; TRIMP a week and each week's numbers
    /// are `WeeklyDetailView`'s. Weekly Volume and Weekly TRIMP were two
    /// cards, then one with a picker, until 2026-10-18.
    private var weeklyCard: some View {
        AnalyticsDetailCard(header: "Weekly · 12 weeks", hint: "Opens sessions and TRIMP per week") {
            WeeklyDetailView(consistency: consistency, bars: weeklyLoadBars,
                             onDevice: (appState.serverWeeklyLoad ?? []).isEmpty)
        } content: {
            WeeklySessionsChart(entries: consistency)
        }
    }

    /// Shown only when a number was computed on this phone because the
    /// server could not answer; the server's numbers carry no mark.
    private var onDeviceMark: some View {
        OnDeviceMark()
    }

    // MARK: - PMC

    /// Today's fitness, fatigue and form as numbers over a small chart of
    /// the two lines; the full chart, the value on any day and what the
    /// terms mean are `PMCDetailView`'s. The card had only the chart and a
    /// legend of glosses — no number to read (§1.4).
    @ViewBuilder
    private var pmcCard: some View {
        if isLoadingPMC {
            AnalyticsCard(header: "Performance Management") {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
        } else {
            AnalyticsDetailCard(header: "Performance Management", hint: "Opens fitness, fatigue and form") {
                if loadSource == .device { onDeviceMark }
            } destination: {
                PMCDetailView(entries: pmcEntries, onDevice: loadSource == .device)
            } content: {
                VStack(alignment: .leading, spacing: 10) {
                    if let today = pmcEntries.last { PMCNumbers(entry: today) }
                    PMCChart(entries: pmcEntries, compact: true)
                }
            }
        }
    }

    @ViewBuilder
    private func detail(_ detail: AppRouter.AnalyticsDetail) -> some View {
        switch detail {
        case .pmc: PMCDetailView(entries: pmcEntries, onDevice: loadSource == .device)
        case .loadFocus: LoadFocusDetailView(focus: loadFocus)
        case .mix: MixDetailView(modalities: modalities, activities: activities, period: period)
        case .weekly:
            WeeklyDetailView(consistency: consistency, bars: weeklyLoadBars,
                             onDevice: (appState.serverWeeklyLoad ?? []).isEmpty)
        default: EmptyView()
        }
    }

    /// Push what a deep link asked for once there is something to show.
    private func applyPendingDetail() {
        guard let pending = router.pendingAnalyticsDetail, pending.section == .load else { return }
        switch pending {
        case .pmc: guard !pmcEntries.isEmpty else { return }
        default: guard summary != nil || !appState.importedWorkouts.isEmpty else { return }
        }
        route = pending
        router.clearPendingAnalyticsDetail()
    }

    // MARK: - PMC Computation

    /// The server first; the on-device engine only when it cannot answer.
    private func recomputePMC() async {
        isLoadingPMC = true
        await appState.loadIfStale("loadAnalytics") { await appState.loadLoadAnalytics() }
        if let server = appState.serverPMC, !server.isEmpty {
            pmcEntries = server
            loadSource = .server
            isLoadingPMC = false
            return
        }
        loadSource = .device
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

