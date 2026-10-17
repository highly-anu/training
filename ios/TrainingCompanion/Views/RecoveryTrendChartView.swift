import SwiftUI
import Charts

/// Thirty days of one recovery reading — HRV or resting heart rate — as daily
/// points under a 7-day rolling average (Analytics ▸ Recovery). One view for
/// both: they were two near-identical copies that differed only in colour and
/// in which way is better. The trend sits beside the card's header
/// (`RecoveryTrendBadge`), not in a second title inside the card.
struct RecoveryTrendChartView: View {
    enum Metric {
        case hrv, restingHR

        var name: String { self == .hrv ? "HRV" : "Resting HR" }
        var unit: String { self == .hrv ? "ms" : "bpm" }
        var symbol: String { self == .hrv ? "waveform.path.ecg" : "heart.fill" }
        var color: Color { self == .hrv ? .cyan : .red }
        /// A falling resting heart rate is the better way; a rising HRV.
        var lowerIsBetter: Bool { self == .restingHR }

        func value(_ log: DailyBioLog) -> Double? { self == .hrv ? log.hrv : log.restingHR }
    }

    struct Point: Identifiable {
        let date: Date
        let value: Double
        let rollingAvg: Double?
        var id: Date { date }
    }

    /// How the 7-day average moved over the last seven readings.
    struct Trend: Equatable {
        let delta: Double
        let lowerIsBetter: Bool
        var isBetter: Bool { lowerIsBetter ? delta < 0 : delta > 0 }
    }

    let logs: [DailyBioLog]
    let metric: Metric

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    /// The last 30 logs that carry the reading, oldest first, each with the
    /// mean of itself and the six before it.
    static func points(_ logs: [DailyBioLog], metric: Metric) -> [Point] {
        let readings = logs.prefix(30).reversed().compactMap { log -> (Date, Double)? in
            guard let date = dateFmt.date(from: log.date), let v = metric.value(log) else { return nil }
            return (date, v)
        }
        return readings.enumerated().map { i, reading in
            let window = readings[Swift.max(0, i - 6)...i].map(\.1)
            return Point(date: reading.0, value: reading.1, rollingAvg: window.reduce(0, +) / Double(window.count))
        }
    }

    /// Nil under seven readings, as before.
    static func trend(_ logs: [DailyBioLog], metric: Metric) -> Trend? {
        let pts = points(logs, metric: metric)
        guard pts.count >= 7 else { return nil }
        let averages = pts.suffix(7).compactMap(\.rollingAvg)
        guard let first = averages.first, let last = averages.last, averages.count >= 2 else { return nil }
        return Trend(delta: last - first, lowerIsBetter: metric.lowerIsBetter)
    }

    var body: some View {
        let points = Self.points(logs, metric: metric)
        if points.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: metric.symbol).font(.title2).foregroundStyle(.secondary)
                Text("No \(metric.name) data").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            Chart(points) { pt in
                PointMark(x: .value("Date", pt.date, unit: .day), y: .value(metric.name, pt.value))
                    .foregroundStyle(metric.color.opacity(0.5))
                    .symbolSize(30)
                if let avg = pt.rollingAvg {
                    LineMark(x: .value("Date", pt.date, unit: .day), y: .value("7d Avg", avg))
                        .foregroundStyle(metric.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                }
            }
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
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 130)
            .accessibilityLabel("\(metric.name), last \(points.count) readings, latest \(Int(points.last?.value ?? 0)) \(metric.unit)")
        }
    }
}

/// A recovery trend as an arrow and the 7-day average's change — "+4 ms" —
/// green when it moved the better way. It replaced "↑ Improving" / "↓ Lower"
/// in a second title inside the card (§1.4).
struct RecoveryTrendBadge: View {
    let trend: RecoveryTrendChartView.Trend
    let metric: RecoveryTrendChartView.Metric

    var body: some View {
        let rounded = Int(trend.delta.rounded())
        Label("\(rounded > 0 ? "+" : rounded < 0 ? "−" : "±")\(abs(rounded)) \(metric.unit)",
              systemImage: rounded > 0 ? "arrow.up.right" : rounded < 0 ? "arrow.down.right" : "arrow.right")
            // Compact everywhere: a List gives a Label an icon column otherwise.
            .labelStyle(.titleAndIcon)
            .font(.caption).fontWeight(.semibold).monospacedDigit()
            .foregroundStyle(rounded == 0 ? Color.secondary : trend.isBetter ? Color.green : Color.orange)
            .accessibilityLabel("7-day average \(rounded >= 0 ? "up" : "down") \(abs(rounded)) \(metric.unit)\(rounded == 0 ? "" : trend.isBetter ? ", better" : ", worse")")
    }
}
