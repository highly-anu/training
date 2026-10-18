import SwiftUI

/// One recovery reading in full — HRV or resting heart rate (design-system
/// §6.37), pushed from its card on Analytics ▸ Recovery: thirty days as points
/// under the 7-day average, the latest, the average and the range, each day's
/// reading, and what the reading is.
struct RecoveryTrendDetailView: View {
    let logs: [DailyBioLog]
    let metric: RecoveryTrendChartView.Metric

    @EnvironmentObject var appState: AppState

    var body: some View {
        let points = RecoveryTrendChartView.points(logs, metric: metric)
        List {
            Section {
                RecoveryTrendChartView(logs: logs, metric: metric).padding(.vertical, 6)
            }
            if let last = points.last {
                Section("Last 30 days") {
                    LabeledContent("Latest") { Text(value(last.value)).monospacedDigit() }
                    if let avg = last.rollingAvg {
                        LabeledContent("7-day average") { Text(value(avg)).monospacedDigit() }
                    }
                    if let lo = points.map(\.value).min(), let hi = points.map(\.value).max() {
                        LabeledContent("Range") { Text("\(Int(lo))–\(Int(hi)) \(metric.unit)").monospacedDigit() }
                    }
                    if let trend = RecoveryTrendChartView.trend(logs, metric: metric) {
                        LabeledContent("This week") { RecoveryTrendBadge(trend: trend, metric: metric) }
                    }
                }
                Section("Days") {
                    ForEach(points.reversed()) { p in
                        LabeledContent(p.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) {
                            Text(value(p.value)).monospacedDigit()
                        }
                    }
                }
            }
            AboutSection(about: AboutText(terms: [metric == .hrv ? "hrv" : "resting_hr"], from: appState.analyticsTerms))
        }
        .listStyle(.insetGrouped)
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await appState.loadAnalyticsTermsIfNeeded([metric == .hrv ? "hrv" : "resting_hr"]) }
    }

    private func value(_ v: Double) -> String { "\(Int(v.rounded())) \(metric.unit)" }
}
