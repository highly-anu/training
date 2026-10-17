import SwiftUI

struct AnalyticsRecoveryTab: View {
    @EnvironmentObject var appState: AppState
    @Binding var showBioEntry: Bool
    /// Check-in history's day and value columns, at the reader's text size.
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 62

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
            await AppRefresh.perform {
                await appState.loadRecentBioLogs()
                await appState.loadReadiness()
            }
        }
    }

    // MARK: - Readiness Card

    private var readinessCard: some View {
        // The server's score, as on Today, with its status once — as the
        // badge. A coloured circle, the score's colour and a status word
        // under it said the same thing three times.
        AnalyticsCard(header: "Today's Readiness") {
            if let result = appState.readinessResult {
                TintCapsule(text: result.statusLabel, symbol: result.statusIcon, color: result.statusColor)
            }
        } content: {
          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                if let result = appState.readinessResult {
                    Text("\(result.score)")
                        .font(.largeTitle).fontWeight(.bold).fontDesign(.rounded).monospacedDigit()
                        .foregroundStyle(result.statusColor)
                        .accessibilityLabel("Readiness \(result.score), \(result.statusLabel)")
                }
                if let latest = appState.recentBioLogs.first {
                    VStack(alignment: .leading, spacing: 6) {
                        if let hrv = latest.hrv {
                            recoveryMetric(symbol: "waveform.path.ecg", name: "HRV", value: "\(Int(hrv)) ms")
                        }
                        if let hr = latest.restingHR {
                            recoveryMetric(symbol: "heart.fill", name: "Resting HR", value: "\(Int(hr)) bpm")
                        }
                        if let sleep = latest.sleepDurationMin, sleep > 0 {
                            let h = sleep / 60; let m = sleep % 60
                            recoveryMetric(symbol: "moon.fill", name: "Sleep", value: m > 0 ? "\(h)h \(m)m" : "\(h)h")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let result = appState.readinessResult {
                ReadinessFlagChips(flags: result.flags)
                ReadinessSourceNote(result: result)
            }
          }
        }
    }

    /// A reading as its symbol and number; the name is for VoiceOver (§1.4).
    private func recoveryMetric(symbol: String, name: String, value: String) -> some View {
        Label {
            Text(value).fontWeight(.medium).monospacedDigit()
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value)")
    }

    // MARK: - Sleep Debt Card (Whoop-style)

    private var sleepDebtCard: some View {
        let targetPerNight = 480  // 8 hours in minutes
        let recent = appState.recentBioLogs.prefix(7)
        guard !recent.isEmpty else { return AnyView(EmptyView()) }
        let sleepNights = recent.compactMap(\.sleepDurationMin)
        let totalActual = sleepNights.reduce(0, +)
        let totalTarget = targetPerNight * sleepNights.count
        let debtMin = Swift.max(0, totalTarget - totalActual)
        let debtHours = Double(debtMin) / 60.0
        let maxDebt = Double(targetPerNight * 7) / 60.0

        return AnyView(AnalyticsCard(header: "Sleep Debt · 7 days") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(format: "%.1fh", debtHours))
                        .font(.title2).fontWeight(.bold).monospacedDigit()
                        .foregroundStyle(debtHours < 2 ? .green : debtHours < 5 ? .orange : .red)
                    Spacer()
                    Gauge(value: Swift.min(debtHours, maxDebt), in: 0...maxDebt) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(debtHours < 2 ? .green : debtHours < 5 ? .orange : .red)
                    .frame(width: 52, height: 52)
                    .accessibilityLabel(String(format: "%.1f of %.0f hours of sleep owed this week", debtHours, maxDebt))
                }
                HStack(spacing: 12) {
                    Label("8h", systemImage: "target")
                    Label("\(sleepNights.count) nights", systemImage: "moon")
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Target 8 hours a night, \(sleepNights.count) nights tracked")
            }
        })
    }

    // MARK: - Last Night Sleep Card

    @ViewBuilder
    private var lastNightSleepCard: some View {
        if let latest = appState.recentBioLogs.first,
           let sleep = latest.sleepDurationMin, sleep > 0 {
            AnalyticsCard(header: "Last Night") {
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
                            .accessibilityHidden(true)
                    }
                    // The stages as labelled dots in the chart's colours — a
                    // tile per stage was a card inside the card (§6.15).
                    HStack(spacing: 12) {
                        if let deep = latest.deepSleepMin, deep > 0 { stage("Deep", minutes: deep) }
                        if let rem = latest.remSleepMin, rem > 0 { stage("REM", minutes: rem) }
                        if let light = latest.lightSleepMin, light > 0 { stage("Light", minutes: light) }
                        if let awake = latest.awakeMins, awake > 0 { stage("Awake", minutes: awake) }
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

    private func stage(_ name: String, minutes: Int) -> some View {
        let h = minutes / 60; let m = minutes % 60
        let duration = h > 0 ? (m > 0 ? "\(h)h\(m)m" : "\(h)h") : "\(m)m"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(SleepStagesChartView.stageColors[name] ?? .secondary).frame(width: 8, height: 8)
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
            Text(duration).font(.subheadline).fontWeight(.medium).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(duration)")
    }

    // MARK: - Sleep Stages Chart

    @ViewBuilder
    private var sleepStagesCard: some View {
        let hasData = appState.recentBioLogs.contains { $0.deepSleepMin != nil || $0.remSleepMin != nil }
        if hasData {
            AnalyticsCard(header: "Sleep Stages") {
                SleepStagesChartView(logs: appState.recentBioLogs)
            }
        }
    }

    // MARK: - HRV Chart

    @ViewBuilder
    private var hrvCard: some View {
        let hasHRV = appState.recentBioLogs.contains { $0.hrv != nil }
        if hasHRV {
            AnalyticsCard(header: "HRV Trend") {
                if let trend = RecoveryTrendChartView.trend(appState.recentBioLogs, metric: .hrv) {
                    RecoveryTrendBadge(trend: trend, metric: .hrv)
                }
            } content: {
                RecoveryTrendChartView(logs: appState.recentBioLogs, metric: .hrv)
            }
        }
    }

    // MARK: - RHR Chart

    @ViewBuilder
    private var rhrCard: some View {
        let hasRHR = appState.recentBioLogs.contains { $0.restingHR != nil }
        if hasRHR {
            AnalyticsCard(header: "Resting Heart Rate") {
                if let trend = RecoveryTrendChartView.trend(appState.recentBioLogs, metric: .restingHR) {
                    RecoveryTrendBadge(trend: trend, metric: .restingHR)
                }
            } content: {
                RecoveryTrendChartView(logs: appState.recentBioLogs, metric: .restingHR)
            }
        }
    }

    // MARK: - Check-in History

    private var checkInHistoryCard: some View {
        AnalyticsCard(header: "Check-in History") {
            VStack(spacing: 0) {
                if appState.recentBioLogs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title).foregroundStyle(.secondary)
                        Text("No bio data yet")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    // Adding an entry is the toolbar's "+"; a second button
                    // here did the same thing.
                    ForEach(appState.recentBioLogs.prefix(30)) { log in
                        bioRow(log)
                        if log.id != appState.recentBioLogs.prefix(30).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    /// A day's check-in: the day, then HRV, resting HR and sleep, each in its
    /// own column — a missing value leaves its column empty instead of
    /// sliding the others left, where colour became the only label.
    private func bioRow(_ log: DailyBioLog) -> some View {
        HStack {
            Text(Self.dayText(log.date))
                .font(.subheadline).fontWeight(.medium)
                .frame(width: dayWidth, alignment: .leading)
            Spacer()
            bioChip(value: log.hrv.map { "\(Int($0))" }, unit: "ms", color: .cyan)
            bioChip(value: log.restingHR.map { "\(Int($0))" }, unit: "bpm", color: .red)
            bioChip(value: log.sleepDurationMin.flatMap { $0 > 0 ? Self.hours($0) : nil }, unit: "", color: .indigo)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([Self.dayText(log.date),
                             log.hrv.map { "HRV \(Int($0)) ms" },
                             log.restingHR.map { "resting HR \(Int($0)) bpm" },
                             log.sleepDurationMin.flatMap { $0 > 0 ? "sleep \(Self.hours($0))" : nil }]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func bioChip(value: String?, unit: String, color: Color) -> some View {
        HStack(spacing: 2) {
            if let value {
                Text(value).font(.subheadline).fontWeight(.medium).monospacedDigit().foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(width: valueWidth, alignment: .trailing)
    }

    /// "7h 20m" — sleep was cut to whole hours.
    private static func hours(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    /// "Fri 17 Oct" for the stored "2026-10-17".
    private static func dayText(_ iso: String) -> String {
        isoDay.date(from: iso).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? iso
    }

    // MARK: - Card Container

    // MARK: - Helpers

    private func formatTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        // The reader's own clock, 12- or 24-hour; it was always "h:mm a".
        return date.formatted(date: .omitted, time: .shortened)
    }
}
