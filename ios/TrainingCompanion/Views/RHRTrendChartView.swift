import SwiftUI
import Charts

/// 30-day Resting Heart Rate trend: daily points + 7-day rolling average line.
/// Trend label is inverted vs HRV — lower RHR is better.
struct RHRTrendChartView: View {
    let logs: [DailyBioLog]

    private struct DataPoint: Identifiable {
        let id = UUID()
        let date: String
        let value: Double
        let rollingAvg: Double?
    }

    private var points: [DataPoint] {
        let recent = logs.prefix(30).reversed().filter { $0.restingHR != nil }
        var out: [DataPoint] = []
        let arr = Array(recent)
        for (i, log) in arr.enumerated() {
            let window = arr[Swift.max(0, i - 6)...i].compactMap(\.restingHR)
            let avg = window.isEmpty ? nil : window.reduce(0, +) / Double(window.count)
            out.append(DataPoint(date: log.date, value: log.restingHR!, rollingAvg: avg))
        }
        return out
    }

    private var trend: String {
        guard points.count >= 7 else { return "" }
        let last7 = Array(points.suffix(7)).compactMap(\.rollingAvg)
        guard last7.count >= 2 else { return "" }
        // Lower RHR = better
        return last7.last! < last7.first! ? "↓ Better" : "↑ Higher"
    }

    private var trendColor: Color {
        trend.hasPrefix("↓") ? .green : .orange
    }

    var body: some View {
        if points.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Resting HR").font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    if !trend.isEmpty {
                        Text(trend).font(.caption).foregroundStyle(trendColor)
                    }
                }

                Chart(points) { pt in
                    PointMark(
                        x: .value("Date", pt.date),
                        y: .value("RHR", pt.value)
                    )
                    .foregroundStyle(Color.red.opacity(0.5))
                    .symbolSize(30)

                    if let avg = pt.rollingAvg {
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("7d Avg", avg)
                        )
                        .foregroundStyle(Color.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 7)) { value in
                        AxisValueLabel {
                            if let s = value.as(String.self) {
                                Text(s.suffix(5)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
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
                .frame(height: 130)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("No resting HR data").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
