import SwiftUI
import Charts

struct ElevationProfileView: View {
    let points: [GPSPoint]
    let gainM: Double?

    struct AltPoint {
        let elapsed: Double
        let alt: Double
    }

    @State private var chartData: [AltPoint] = []
    @State private var yLo: Double = 0
    @State private var yHi: Double = 500

    var body: some View {
        let base = yLo  // local copy — never recomputed inside the loop
        Chart {
            ForEach(Array(chartData.enumerated()), id: \.offset) { _, pt in
                AreaMark(
                    x: .value("Time", pt.elapsed),
                    yStart: .value("Base", base),
                    yEnd: .value("Alt", pt.alt)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green.opacity(0.35), .green.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", pt.elapsed),
                    y: .value("Alt", pt.alt)
                )
                .foregroundStyle(.green.opacity(0.8))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: yLo...yHi)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: strideValue)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))m").font(.caption2)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let gain = gainM, gain > 0 {
                Label("\(Int(gain)) m", systemImage: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(4)
            }
        }
        .task(id: points.count) {
            let computed = await Task.detached(priority: .userInitiated) {
                buildChartData(points)
            }.value
            chartData = computed.data
            yLo = computed.lo
            yHi = computed.hi
        }
    }

    private var strideValue: Double {
        let span = yHi - yLo
        if span < 80  { return 20 }
        if span < 200 { return 50 }
        return 100
    }
}

private func buildChartData(_ points: [GPSPoint]) -> (data: [ElevationProfileView.AltPoint], lo: Double, hi: Double) {
    guard let first = points.first else { return ([], 0, 500) }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fallback = ISO8601DateFormatter()

    guard let firstDate = iso.date(from: first.timestamp) ?? fallback.date(from: first.timestamp)
    else { return ([], 0, 500) }

    // Parse all points with altitude
    var raw: [ElevationProfileView.AltPoint] = []
    for pt in points {
        guard let alt = pt.altitude else { continue }
        let date = iso.date(from: pt.timestamp) ?? fallback.date(from: pt.timestamp)
        guard let date else { continue }
        raw.append(.init(elapsed: date.timeIntervalSince(firstDate), alt: alt))
    }
    guard !raw.isEmpty else { return ([], 0, 500) }

    // Downsample to max 500 points so Charts renders smoothly
    let data: [ElevationProfileView.AltPoint]
    if raw.count > 500 {
        let step = raw.count / 500
        data = stride(from: 0, to: raw.count, by: step).map { raw[$0] }
    } else {
        data = raw
    }

    let alts = data.map { $0.alt }
    let lo = (alts.min() ?? 0) - 15
    let hi = (alts.max() ?? 500) + 15
    return (data, lo, hi)
}
