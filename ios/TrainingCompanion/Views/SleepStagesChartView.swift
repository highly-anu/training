import SwiftUI
import Charts

/// 30-day stacked bar chart of sleep stages (Deep / REM / Light / Awake).
/// Mirrors Apple Health sleep analysis chart.
struct SleepStagesChartView: View {
    let logs: [DailyBioLog]

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
            .chartForegroundStyleScale([
                "Deep":  Color(red: 0.2, green: 0.2, blue: 0.7),
                "REM":   Color(red: 0.4, green: 0.3, blue: 0.8),
                "Light": Color(red: 0.45, green: 0.65, blue: 0.9),
                "Awake": Color(red: 0.8, green: 0.7, blue: 0.4)
            ])
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
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bed.double")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No sleep stage data")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}
