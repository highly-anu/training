import SwiftUI
import Charts

struct PaceTimelineView: View {
    let points: [GPSPoint]
    let distanceKm: Double?

    struct PacePoint {
        let elapsed: Double
        let paceSecPerKm: Double
    }

    @State private var chartData: [PacePoint] = []
    @State private var avgPace: Double? = nil
    @State private var yLo: Double = 180
    @State private var yHi: Double = 600
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chartData.isEmpty {
                Text("No pace data")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart {
                    ForEach(Array(chartData.enumerated()), id: \.offset) { _, pt in
                        LineMark(
                            x: .value("Time", pt.elapsed),
                            y: .value("Pace", pt.paceSecPerKm)
                        )
                        .foregroundStyle(.blue.opacity(0.8))
                        .interpolationMethod(.linear)
                    }
                    if let avg = avgPace {
                        RuleMark(y: .value("Avg", avg))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .annotation(position: .trailing, alignment: .leading) {
                                Text(formatPace(avg))
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                    }
                }
                // Inverted: faster pace (lower sec/km) at top
                .chartYScale(domain: yHi...yLo)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .stride(by: 60)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatPace(v)).font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
            }
        }
        .task(id: points.count) {
            let result = await Task.detached(priority: .userInitiated) {
                Self.buildData(points: points, distanceKm: distanceKm)
            }.value
            chartData = result.data
            avgPace   = result.avgPace
            yLo       = result.lo
            yHi       = result.hi
            isLoading = false
        }
    }

    private func formatPace(_ secPerKm: Double) -> String {
        String(format: "%d:%02d", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }

    static func buildData(points: [GPSPoint], distanceKm: Double?)
        -> (data: [PacePoint], avgPace: Double?, lo: Double, hi: Double)
    {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()

        guard let first = points.first,
              let firstDate = iso.date(from: first.timestamp) ?? fallback.date(from: first.timestamp)
        else { return ([], nil, 180, 600) }

        var raw: [(elapsed: Double, pace: Double)] = []
        for pt in points {
            guard let spd = pt.speed, spd > 0.3 else { continue }
            let date = iso.date(from: pt.timestamp) ?? fallback.date(from: pt.timestamp)
            guard let date else { continue }
            let pace = Swift.min(Swift.max(1000.0 / spd, 90), 1200)
            raw.append((elapsed: date.timeIntervalSince(firstDate), pace: pace))
        }
        guard raw.count >= 5 else { return ([], nil, 180, 600) }

        // Rolling average (window = 15 points)
        let window = 15
        var smoothed: [PacePoint] = []
        for i in raw.indices {
            let lo = Swift.max(0, i - window / 2)
            let hi = Swift.min(raw.count - 1, i + window / 2)
            let avg = raw[lo...hi].map { $0.pace }.reduce(0, +) / Double(hi - lo + 1)
            smoothed.append(PacePoint(elapsed: raw[i].elapsed, paceSecPerKm: avg))
        }

        // Downsample to 60 pts max — pace is already smoothed, 60 pts is sufficient
        let data: [PacePoint]
        if smoothed.count > 60 {
            let step = smoothed.count / 60
            data = stride(from: 0, to: smoothed.count, by: step).map { smoothed[$0] }
        } else {
            data = smoothed
        }

        // Avg pace from distance + elapsed time
        var avg: Double? = nil
        if let km = distanceKm, km > 0, let lastPt = points.last,
           let lastDate = iso.date(from: lastPt.timestamp) ?? fallback.date(from: lastPt.timestamp) {
            let elapsed = lastDate.timeIntervalSince(firstDate)
            if elapsed > 0 { avg = elapsed / km }
        }

        let paces = data.map { $0.paceSecPerKm }
        let lo = Swift.max(60,   (paces.min() ?? 180) - 20)
        let hi = Swift.min(1200, (paces.max() ?? 600) + 20)
        return (data, avg, lo, hi)
    }
}
