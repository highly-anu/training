import SwiftUI

struct AnalyticsRecoveryTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var showBioEntry: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                readinessCard
                sleepDebtCard
                lastNightSleepCard
                sleepStagesCard
                hrvCard
                rhrCard
                checkInHistoryCard
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .refreshable {
            AppHaptics.light()
            await appState.loadRecentBioLogs()
            await appState.loadReadiness()
            AppHaptics.success()
        }
    }

    // MARK: - Readiness Card

    private var readinessCard: some View {
        cardContainer(header: "Today's Readiness") {
            HStack(spacing: 16) {
                if let info = appState.readinessInfo(from: appState.recentBioLogs) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(info.signalColor.gradient)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Image(systemName: info.signalIcon)
                                    .foregroundStyle(.white).font(.headline)
                            )
                        Text("Readiness").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let latest = appState.recentBioLogs.first {
                    VStack(alignment: .leading, spacing: 6) {
                        if let hrv = latest.hrv {
                            recoveryMetric(label: "HRV", value: "\(Int(hrv)) ms")
                        }
                        if let hr = latest.restingHR {
                            recoveryMetric(label: "Resting HR", value: "\(Int(hr)) bpm")
                        }
                        if let sleep = latest.sleepDurationMin, sleep > 0 {
                            let h = sleep / 60; let m = sleep % 60
                            recoveryMetric(label: "Sleep", value: m > 0 ? "\(h)h \(m)m" : "\(h)h")
                        }
                    }
                }
                Spacer()
                if let result = appState.readinessResult {
                    VStack(spacing: 4) {
                        Text("\(result.score)")
                            .font(.title2).fontWeight(.bold)
                            .foregroundStyle(result.statusColor)
                        Text(result.statusLabel)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func recoveryMetric(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":").font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).fontWeight(.medium)
        }
    }

    // MARK: - Sleep Debt Card (Whoop-style)

    private var sleepDebtCard: some View {
        let targetPerNight = 480  // 8 hours in minutes
        let recent = appState.recentBioLogs.prefix(7)
        guard !recent.isEmpty else { return AnyView(EmptyView()) }
        let totalActual = recent.compactMap(\.sleepDurationMin).reduce(0, +)
        let totalTarget = targetPerNight * min(recent.count, 7)
        let debtMin = Swift.max(0, totalTarget - totalActual)
        let debtHours = Double(debtMin) / 60.0
        let maxDebt = Double(targetPerNight * 7) / 60.0

        return AnyView(cardContainer(header: "Sleep Debt") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1fh", debtHours))
                            .font(.title2).fontWeight(.bold)
                            .foregroundStyle(debtHours < 2 ? .green : debtHours < 5 ? .orange : .red)
                        Text("7-day sleep debt").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Gauge(value: Swift.min(debtHours, maxDebt), in: 0...maxDebt) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(debtHours < 2 ? .green : debtHours < 5 ? .orange : .red)
                    .frame(width: 52, height: 52)
                }
                Text("Target 8h/night · \(recent.count) nights tracked")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        })
    }

    // MARK: - Last Night Sleep Card

    @ViewBuilder
    private var lastNightSleepCard: some View {
        if let latest = appState.recentBioLogs.first,
           let sleep = latest.sleepDurationMin, sleep > 0 {
            cardContainer(header: "Last Night") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            let h = sleep / 60; let m = sleep % 60
                            Text(m > 0 ? "\(h)h \(m)m" : "\(h)h")
                                .font(.title2).fontWeight(.bold)
                            if let start = latest.sleepStart, let end = latest.sleepEnd {
                                Text("\(formatTime(start)) – \(formatTime(end))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "moon.fill")
                            .font(.title2).foregroundStyle(.indigo)
                    }
                    // Stage pills
                    HStack(spacing: 8) {
                        if let deep = latest.deepSleepMin, deep > 0 {
                            stagePill(label: "Deep", minutes: deep, color: Color(red: 0.2, green: 0.2, blue: 0.7))
                        }
                        if let rem = latest.remSleepMin, rem > 0 {
                            stagePill(label: "REM", minutes: rem, color: Color(red: 0.4, green: 0.3, blue: 0.8))
                        }
                        if let light = latest.lightSleepMin, light > 0 {
                            stagePill(label: "Light", minutes: light, color: Color(red: 0.45, green: 0.65, blue: 0.9))
                        }
                        if let awake = latest.awakeMins, awake > 0 {
                            stagePill(label: "Awake", minutes: awake, color: .orange.opacity(0.8))
                        }
                    }
                    if latest.spo2Avg != nil || latest.respiratoryRateAvg != nil {
                        HStack(spacing: 16) {
                            if let spo2 = latest.spo2Avg {
                                Label(String(format: "%.0f%% SpO₂", spo2), systemImage: "lungs.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let rr = latest.respiratoryRateAvg {
                                Label(String(format: "%.1f/min resp", rr), systemImage: "waveform")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func stagePill(label: String, minutes: Int, color: Color) -> some View {
        let h = minutes / 60; let m = minutes % 60
        return VStack(spacing: 2) {
            Text(m > 0 ? "\(h)h\(m)m" : "\(h)h")
                .font(.caption).fontWeight(.medium).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sleep Stages Chart

    @ViewBuilder
    private var sleepStagesCard: some View {
        let hasData = appState.recentBioLogs.contains { $0.deepSleepMin != nil || $0.remSleepMin != nil }
        if hasData {
            cardContainer(header: "Sleep Stages") {
                SleepStagesChartView(logs: appState.recentBioLogs)
            }
        }
    }

    // MARK: - HRV Chart

    @ViewBuilder
    private var hrvCard: some View {
        let hasHRV = appState.recentBioLogs.contains { $0.hrv != nil }
        if hasHRV {
            cardContainer(header: "HRV Trend") {
                HRVTrendChartView(logs: appState.recentBioLogs)
            }
        }
    }

    // MARK: - RHR Chart

    @ViewBuilder
    private var rhrCard: some View {
        let hasRHR = appState.recentBioLogs.contains { $0.restingHR != nil }
        if hasRHR {
            cardContainer(header: "Resting Heart Rate") {
                RHRTrendChartView(logs: appState.recentBioLogs)
            }
        }
    }

    // MARK: - Check-in History

    private var checkInHistoryCard: some View {
        cardContainer(header: "Check-in History") {
            VStack(spacing: 0) {
                if appState.recentBioLogs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("No bio data yet")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Sync from Apple Watch or add a manual entry.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)
                } else {
                    ForEach(appState.recentBioLogs.prefix(30)) { log in
                        bioRow(log)
                        if log.id != appState.recentBioLogs.prefix(30).last?.id {
                            Divider().padding(.leading, 90)
                        }
                    }
                }
                Divider()
                Button {
                    AppHaptics.light()
                    showBioEntry = true
                } label: {
                    Label("Add Entry", systemImage: "plus.circle")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private func bioRow(_ log: DailyBioLog) -> some View {
        HStack {
            Text(log.date)
                .font(.subheadline).fontWeight(.medium)
                .frame(width: 90, alignment: .leading)
            Spacer()
            if let hrv = log.hrv { bioChip(value: "\(Int(hrv))", unit: "ms", color: .cyan) }
            if let hr = log.restingHR { bioChip(value: "\(Int(hr))", unit: "bpm", color: .red) }
            if let sleep = log.sleepDurationMin, sleep > 0 {
                bioChip(value: "\(sleep / 60)h", unit: "", color: .indigo)
            }
        }
        .padding(.vertical, 8)
    }

    private func bioChip(value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(value).font(.caption).fontWeight(.medium).foregroundStyle(color)
            if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(width: 52, alignment: .trailing)
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

    // MARK: - Helpers

    private func formatTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }
}
