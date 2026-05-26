import SwiftUI
import Charts

struct HRTimelineView: View {
    let samples: [HRSample]
    let avgHR: Int?
    var maxHR: Int? = nil
    var hrConfig: HRConfig? = nil

    struct HRPoint {
        let elapsed: Double
        let bpm: Int
    }

    @State private var chartData: [HRPoint] = []
    @State private var yLo: Int = 60
    @State private var yHi: Int = 180

    // Default Friel zone fractions (lo..hi), includes sub-60% band as Z1 floor
    private static let defaultBoundaries: [Double] = [0.60, 0.70, 0.80, 0.90]
    private static let zoneColors: [Color] = [
        Color(hex: "#94a3b8"),  // Z1 slate-400
        Color(hex: "#38bdf8"),  // Z2 sky-400
        Color(hex: "#fbbf24"),  // Z3 amber-400
        Color(hex: "#f97316"),  // Z4 orange-500
        Color(hex: "#ef4444"),  // Z5 red-500
    ]

    // Build zone bands from hrConfig boundaries (or defaults)
    private var zoneFractions: [(lo: Double, hi: Double, color: Color)] {
        let bounds = hrConfig?.zoneBoundaries ?? Self.defaultBoundaries
        // Prepend 0.0 and append 1.0 to form 5 bands
        let edges = [0.0] + bounds + [1.0]
        return (0..<5).map { i in
            (lo: edges[i], hi: edges[i + 1], color: Self.zoneColors[i])
        }
    }

    private var effectiveMaxHR: Int? {
        if let override = hrConfig?.maxHROverride { return override }
        return maxHR
    }

    var body: some View {
        let lo = yLo
        let hi = yHi
        Chart {
            // Zone bands derived from hrConfig
            if let maxHRValue = effectiveMaxHR {
                ForEach(0..<zoneFractions.count, id: \.self) { i in
                    let zone = zoneFractions[i]
                    let zoneLo = Int(Double(maxHRValue) * zone.lo)
                    let zoneHi = Int(Double(maxHRValue) * zone.hi)
                    let clampedLo = Swift.max(zoneLo, lo)
                    let clampedHi = Swift.min(zoneHi, hi)
                    if clampedLo < clampedHi {
                        RectangleMark(
                            xStart: nil, xEnd: nil,
                            yStart: .value("lo", clampedLo),
                            yEnd: .value("hi", clampedHi)
                        )
                        .foregroundStyle(zone.color.opacity(0.07))
                    }
                }
            }

            // HR line
            ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Time", point.elapsed),
                    y: .value("HR", point.bpm)
                )
                .foregroundStyle(.red.opacity(0.8))
                .interpolationMethod(.catmullRom)
            }

            // Avg rule
            if let avg = avgHR {
                RuleMark(y: .value("Avg", avg))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(avg)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 20)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bpm = value.as(Int.self) {
                        Text("\(bpm)").font(.caption2)
                    }
                }
            }
        }
        .task(id: samples.count) {
            let result = await Task.detached(priority: .userInitiated) {
                Self.buildData(samples: samples)
            }.value
            chartData = result.data
            yLo = result.lo
            yHi = result.hi
        }
    }

    static func buildData(samples: [HRSample]) -> (data: [HRPoint], lo: Int, hi: Int) {
        guard let first = samples.first else { return ([], 60, 180) }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let firstDate = iso.date(from: first.timestamp) ?? fallback.date(from: first.timestamp)
        else { return ([], 60, 180) }

        var data: [HRPoint] = []
        for s in samples {
            let date = iso.date(from: s.timestamp) ?? fallback.date(from: s.timestamp)
            guard let date else { continue }
            data.append(HRPoint(elapsed: date.timeIntervalSince(firstDate), bpm: s.bpm))
        }

        // Downsample to 500 pts max
        if data.count > 500 {
            let step = data.count / 500
            data = stride(from: 0, to: data.count, by: step).map { data[$0] }
        }

        guard !data.isEmpty else { return ([], 60, 180) }
        let lo = (data.map { $0.bpm }.min() ?? 60) - 10
        let hi = (data.map { $0.bpm }.max() ?? 180) + 10
        return (data, lo, hi)
    }
}
