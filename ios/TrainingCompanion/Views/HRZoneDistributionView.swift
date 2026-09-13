import SwiftUI
import Charts

/// Horizontal stacked bar showing time distribution across HR zones Z1–Z5.
/// Mirrors Apple Fitness HR zones presentation.
struct HRZoneDistributionView: View {
    let zones: HRZoneDistribution

    private struct ZoneRow: Identifiable {
        let id: Int
        let label: String
        let pct: Double
        let color: Color
    }

    private var rows: [ZoneRow] {
        let pcts = [zones.z1, zones.z2, zones.z3, zones.z4, zones.z5]
        let colors: [Color] = [.blue, .green, .yellow, .orange, .red]
        let labels = ["Z1 Recovery", "Z2 Aerobic", "Z3 Tempo", "Z4 Threshold", "Z5 VO₂max"]
        return (0..<5).map { i in ZoneRow(id: i + 1, label: labels[i], pct: pcts[i], color: colors[i]) }
            .filter { $0.pct > 0 }
    }

    var body: some View {
        VStack(spacing: 6) {
            Chart(rows) { row in
                BarMark(
                    x: .value("Time %", row.pct),
                    y: .value("Zone", row.label)
                )
                .foregroundStyle(row.color.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(String(format: "%.0f%%", row.pct))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(preset: .aligned) { value in
                    AxisValueLabel {
                        if let s = value.as(String.self) {
                            Text(s).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
