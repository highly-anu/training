import SwiftUI

/// One day's check-in: the day, then HRV, resting HR and sleep, each in its
/// own column — a missing value leaves its column empty instead of sliding
/// the others left, where colour became the only label. The Recovery card's
/// last seven and the full list read the same row.
struct CheckInRow: View {
    let log: DailyBioLog
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 96
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 62

    var body: some View {
        HStack {
            Text(Self.dayText(log.date))
                .font(.subheadline).fontWeight(.medium)
                .frame(width: dayWidth, alignment: .leading)
            Spacer()
            cell(log.hrv.map { "\(Int($0))" }, unit: "ms", color: .cyan)
            cell(log.restingHR.map { "\(Int($0))" }, unit: "bpm", color: .red)
            cell(log.sleepDurationMin.flatMap { $0 > 0 ? SleepFormat.duration($0) : nil }, unit: "", color: .indigo)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([Self.dayText(log.date),
                             log.hrv.map { "HRV \(Int($0)) ms" },
                             log.restingHR.map { "resting HR \(Int($0)) bpm" },
                             log.sleepDurationMin.flatMap { $0 > 0 ? "sleep \(SleepFormat.duration($0))" : nil }]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func cell(_ value: String?, unit: String, color: Color) -> some View {
        HStack(spacing: 2) {
            if let value {
                Text(value).font(.subheadline).fontWeight(.medium).monospacedDigit().foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(width: valueWidth, alignment: .trailing)
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    /// "Fri 17 Oct" for the stored "2026-10-17".
    static func dayText(_ iso: String) -> String {
        isoDay.date(from: iso).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? iso
    }
}

/// Every check-in, newest first, pushed from the Check-in History card's
/// "All check-ins" row; the card shows the last seven.
struct CheckInHistoryView: View {
    let logs: [DailyBioLog]

    var body: some View {
        List(logs) { log in
            CheckInRow(log: log)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Check-ins")
        .navigationBarTitleDisplayMode(.inline)
    }
}
