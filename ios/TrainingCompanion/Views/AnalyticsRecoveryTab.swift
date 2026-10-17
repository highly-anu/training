import SwiftUI

/// Analytics ▸ Recovery: readiness, sleep, HRV, resting heart rate and the
/// check-ins, each as a summary card that opens its own screen
/// (design-system §6.37) — the full chart, every reading, where it came from
/// and what it is. Until 2026-10-17 the section was seven cards with every
/// chart and thirty check-in rows inline.
struct AnalyticsRecoveryTab: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    @Binding var showBioEntry: Bool
    /// A detail pushed from outside (a deep link); the cards push their own.
    @State private var route: AppRouter.AnalyticsDetail?

    private var logs: [DailyBioLog] { appState.recentBioLogs }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                readinessCard
                sleepCard
                trendCard(.hrv, header: "HRV")
                trendCard(.restingHR, header: "Resting Heart Rate")
                checkInHistoryCard
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .refreshable {
            await AppRefresh.perform {
                await appState.loadRecentBioLogs()
                await appState.loadReadiness()
            }
        }
        .navigationDestination(item: $route) { detail($0) }
        .task { applyPendingDetail() }
        .onChange(of: router.pendingAnalyticsDetail) { applyPendingDetail() }
        .onChange(of: appState.recentBioLogs.count) { applyPendingDetail() }
        .onChange(of: appState.readinessResult?.score) { applyPendingDetail() }
    }

    @ViewBuilder
    private func detail(_ detail: AppRouter.AnalyticsDetail) -> some View {
        switch detail {
        case .readiness:
            if let result = appState.readinessResult { ReadinessDetailView(result: result, latest: logs.first) }
        case .sleep: SleepDetailView(logs: logs)
        case .hrv: RecoveryTrendDetailView(logs: logs, metric: .hrv)
        case .restingHR: RecoveryTrendDetailView(logs: logs, metric: .restingHR)
        case .checkIns: CheckInHistoryView(logs: logs)
        default: EmptyView()
        }
    }

    /// Push what a deep link asked for once there is something to show.
    private func applyPendingDetail() {
        guard let pending = router.pendingAnalyticsDetail, pending.section == .recovery else { return }
        if pending == .readiness {
            guard appState.readinessResult != nil else { return }
        } else if logs.isEmpty {
            return
        }
        route = pending
        router.clearPendingAnalyticsDetail()
    }

    // MARK: - Readiness

    /// The server's score, as on Today, with its status once — as the badge —
    /// and the morning's readings as symbols and numbers. Its parts, the
    /// watch's readings and where each came from are the detail's.
    @ViewBuilder
    private var readinessCard: some View {
        if let result = appState.readinessResult {
            AnalyticsDetailCard(header: "Today's Readiness", hint: "Opens readiness") {
                TintCapsule(text: result.statusLabel, symbol: result.statusIcon, color: result.statusColor)
            } destination: {
                ReadinessDetailView(result: result, latest: logs.first)
            } content: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 16) {
                        Text("\(result.score)")
                            .font(.largeTitle).fontWeight(.bold).fontDesign(.rounded).monospacedDigit()
                            .foregroundStyle(result.statusColor)
                            .accessibilityLabel("Readiness \(result.score), \(result.statusLabel)")
                        if let latest = logs.first {
                            VStack(alignment: .leading, spacing: 6) {
                                if let hrv = latest.hrv {
                                    reading(symbol: "waveform.path.ecg", name: "HRV", value: "\(Int(hrv)) ms")
                                }
                                if let hr = latest.restingHR {
                                    reading(symbol: "heart.fill", name: "Resting HR", value: "\(Int(hr)) bpm")
                                }
                                if let sleep = latest.sleepDurationMin, sleep > 0 {
                                    reading(symbol: "moon.fill", name: "Sleep", value: SleepFormat.duration(sleep))
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    ReadinessFlagChips(flags: result.flags)
                }
            }
        }
    }

    /// A reading as its symbol and number; the name is for VoiceOver (§1.4).
    private func reading(symbol: String, name: String, value: String) -> some View {
        Label {
            Text(value).fontWeight(.medium).monospacedDigit()
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value)")
    }

    // MARK: - Sleep

    /// Last night and the week's debt; the stages, thirty nights of them,
    /// SpO₂ and breathing are the detail's. Sleep Debt, Last Night and Sleep
    /// Stages were three cards.
    @ViewBuilder
    private var sleepCard: some View {
        let debt = SleepFormat.Debt(logs: logs)
        let lastNight = logs.first { ($0.sleepDurationMin ?? 0) > 0 }
        if lastNight != nil || debt.nights > 0 {
            AnalyticsDetailCard(header: "Sleep", hint: "Opens sleep") {
                SleepDetailView(logs: logs)
            } content: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let night = lastNight, let minutes = night.sleepDurationMin {
                            Text(SleepFormat.duration(minutes))
                                .font(.title2).fontWeight(.bold).monospacedDigit()
                                .accessibilityLabel("Last night \(SleepFormat.duration(minutes))")
                            if let range = SleepDetailView.timeRange(night) {
                                Text(range).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if debt.nights > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Label(String(format: "%.1fh", debt.hours), systemImage: "moon.zzz")
                                .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                                .foregroundStyle(debt.color)
                            Text("\(debt.nights) nights").font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(format: "%.1f hours of sleep debt over %d nights", debt.hours, debt.nights))
                    }
                }
            }
        }
    }

    // MARK: - HRV and resting HR

    /// The latest reading, its 7-day average and a sparkline; the trend sits
    /// beside the header. The chart and every day's reading are the detail's.
    @ViewBuilder
    private func trendCard(_ metric: RecoveryTrendChartView.Metric, header: String) -> some View {
        let points = RecoveryTrendChartView.points(logs, metric: metric)
        if let last = points.last {
            AnalyticsDetailCard(header: header, hint: "Opens \(metric.name)") {
                if let trend = RecoveryTrendChartView.trend(logs, metric: metric) {
                    RecoveryTrendBadge(trend: trend, metric: metric)
                }
            } destination: {
                RecoveryTrendDetailView(logs: logs, metric: metric)
            } content: {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(last.value.rounded())) \(metric.unit)")
                            .font(.title2).fontWeight(.bold).monospacedDigit()
                        if let avg = last.rollingAvg {
                            Label("\(Int(avg.rounded()))", systemImage: "chart.line.flattrend.xyaxis")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .accessibilityLabel("7-day average \(Int(avg.rounded())) \(metric.unit)")
                        }
                    }
                    Spacer(minLength: 0)
                    if points.count >= 2 {
                        Sparkline(values: points.map(\.value), color: metric.color)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    // MARK: - Check-ins

    private var checkInHistoryCard: some View {
        AnalyticsCard(header: "Check-in History") {
            VStack(spacing: 0) {
                if logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title).foregroundStyle(.secondary)
                        Text("No bio data yet")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // The last week; every check-in is a level down. Adding an
                    // entry is the toolbar's "+".
                    ForEach(logs.prefix(7)) { log in
                        CheckInRow(log: log)
                        if log.id != logs.prefix(7).last?.id { Divider() }
                    }
                    if logs.count > 7 {
                        Divider()
                        NavigationLink {
                            CheckInHistoryView(logs: logs)
                        } label: {
                            HStack {
                                Text("All check-ins").font(.subheadline)
                                Spacer()
                                Text("\(logs.count)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption).fontWeight(.semibold).foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
