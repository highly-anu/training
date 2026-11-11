import SwiftUI
import Charts

/// 30-day stacked bar chart of sleep stages (Deep / REM / Light / Awake).
/// Mirrors Apple Health sleep analysis chart.
struct SleepStagesChartView: View {
    let logs: [DailyBioLog]

    /// One colour per stage, for this chart and Last Night's stage row —
    /// "Awake" was tan here and orange there.
    static let stageColors: [String: Color] = [
        "Deep":  AppColor.Sleep.deep,
        "REM":   AppColor.Sleep.rem,
        "Light": AppColor.Sleep.light,
        "Awake": AppColor.Sleep.awake,
    ]

    private struct SleepPoint: Identifiable {
        let id = UUID()
        let date: Date
        let stage: String
        let minutes: Int
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var points: [SleepPoint] {
        let recent = logs.prefix(30).reversed()
        var out: [SleepPoint] = []
        for log in recent {
            guard let date = Self.dateFmt.date(from: log.date) else { continue }
            if let v = log.deepSleepMin,  v > 0 { out.append(.init(date: date, stage: "Deep",  minutes: v)) }
            if let v = log.remSleepMin,   v > 0 { out.append(.init(date: date, stage: "REM",   minutes: v)) }
            if let v = log.lightSleepMin, v > 0 { out.append(.init(date: date, stage: "Light", minutes: v)) }
            if let v = log.awakeMins,     v > 0 { out.append(.init(date: date, stage: "Awake", minutes: v)) }
        }
        return out
    }

    /// "12 nights, average a night: Deep 62 minutes, REM 95 minutes, …"
    private static func summary(_ points: [SleepPoint]) -> String? {
        let nights = Set(points.map(\.date)).count
        guard nights > 0 else { return nil }
        let parts = ["Deep", "REM", "Light", "Awake"].compactMap { stage -> String? in
            let total = points.filter { $0.stage == stage }.reduce(0) { $0 + $1.minutes }
            return total > 0 ? "\(stage) \(total / nights) minutes" : nil
        }
        return "\(nights) night\(nights == 1 ? "" : "s"), average a night: " + parts.joined(separator: ", ")
    }

    var body: some View {
        if points.isEmpty {
            emptyState
        } else {
            Chart(points) { pt in
                BarMark(
                    x: .value("Date", pt.date, unit: .day),
                    y: .value("Minutes", pt.minutes)
                )
                .foregroundStyle(by: .value("Stage", pt.stage))
                .cornerRadius(2)
            }
            .appChartEntry()
            .chartForegroundStyleScale(domain: ["Deep", "REM", "Light", "Awake"],
                                       range: ["Deep", "REM", "Light", "Awake"].map { Self.stageColors[$0]! })
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let m = value.as(Int.self) {
                            Text("\(m / 60)h").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .center, spacing: 8)
            .frame(height: 160)
            .appChartSummary("Sleep stages by night", Self.summary(points))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bed.double")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No sleep stage data")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}
