import SwiftUI

/// Sleep durations as the Recovery screens write them: "7h 20m", "45m".
enum SleepFormat {
    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    /// The last seven days' shortfall against 8 h a night, over the nights
    /// that recorded sleep — the debt the card and the screen both show.
    struct Debt {
        let hours: Double
        let nights: Int
        /// The most it can be: 8 h owed on each of seven nights.
        static let maximum = 56.0
        static let targetMinutes = 480

        init(logs: [DailyBioLog]) {
            let nights = logs.prefix(7).compactMap(\.sleepDurationMin)
            self.nights = nights.count
            self.hours = Double(max(0, Self.targetMinutes * nights.count - nights.reduce(0, +))) / 60
        }

        var color: Color { hours < 2 ? .green : hours < 5 ? .orange : .red }
    }
}

/// Sleep in full (design-system §6.37), pushed from the Sleep card on
/// Analytics ▸ Recovery: last night with its stages, SpO₂ and breathing, the
/// week's debt, thirty nights of stages, and what sleep debt is. Sleep Debt,
/// Last Night and Sleep Stages were three cards until 2026-10-17.
struct SleepDetailView: View {
    let logs: [DailyBioLog]

    @EnvironmentObject var appState: AppState

    private var lastNight: DailyBioLog? { logs.first { ($0.sleepDurationMin ?? 0) > 0 } }

    var body: some View {
        let debt = SleepFormat.Debt(logs: logs)
        List {
            if let night = lastNight, let minutes = night.sleepDurationMin {
                Section("Last night") {
                    LabeledContent("Asleep") { Text(SleepFormat.duration(minutes)).monospacedDigit() }
                    if let range = SleepDetailView.timeRange(night) {
                        LabeledContent("In bed") { Text(range).monospacedDigit() }
                    }
                    ForEach(SleepDetailView.stages(night), id: \.name) { stage in
                        LabeledContent {
                            Text(SleepFormat.duration(stage.minutes)).monospacedDigit()
                        } label: {
                            Label {
                                Text(stage.name)
                            } icon: {
                                Circle().fill(SleepStagesChartView.stageColors[stage.name] ?? .secondary)
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                    if let spo2 = night.spo2Avg {
                        LabeledContent("SpO₂") { Text(String(format: "%.0f%%", spo2)).monospacedDigit() }
                    }
                    if let rr = night.respiratoryRateAvg {
                        LabeledContent("Breathing") { Text(String(format: "%.1f /min", rr)).monospacedDigit() }
                    }
                }
            }
            if debt.nights > 0 {
                Section("Last 7 days") {
                    LabeledContent("Sleep debt") {
                        Text(String(format: "%.1fh", debt.hours)).monospacedDigit().foregroundStyle(debt.color)
                    }
                    LabeledContent("Target") { Text("8h a night") }
                    LabeledContent("Nights recorded") { Text("\(debt.nights)").monospacedDigit() }
                }
            }
            if logs.contains(where: { $0.deepSleepMin != nil || $0.remSleepMin != nil }) {
                Section("Stages · 30 nights") {
                    SleepStagesChartView(logs: logs).padding(.vertical, 6)
                }
            }
            AboutSection(about: AboutText(terms: ["sleep_debt"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded() }
    }

    static func stages(_ log: DailyBioLog) -> [(name: String, minutes: Int)] {
        [("Deep", log.deepSleepMin), ("REM", log.remSleepMin), ("Light", log.lightSleepMin), ("Awake", log.awakeMins)]
            .compactMap { name, minutes in minutes.flatMap { $0 > 0 ? (name, $0) : nil } }
    }

    /// "23:10 – 06:30" on the reader's own clock.
    static func timeRange(_ log: DailyBioLog) -> String? {
        guard let start = log.sleepStart.flatMap(time), let end = log.sleepEnd.flatMap(time) else { return nil }
        return "\(start) – \(end)"
    }

    /// The server sends Postgres's text form, "2026-10-17 01:40:00+02:00",
    /// which an ISO parser rejects for its space; the old Last Night card
    /// never showed its time range for that reason.
    private static func time(_ raw: String) -> String? {
        let iso = raw.replacingOccurrences(of: " ", with: "T")
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return date?.formatted(date: .omitted, time: .shortened)
    }
}
