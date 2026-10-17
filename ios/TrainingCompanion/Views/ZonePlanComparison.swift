import SwiftUI

/// Planned against recorded minutes per heart-rate zone (design-system §6.35):
/// what the programming planned as an outline, what the heart rate recorded
/// filled over it, both against the largest value so the longest bar spans the
/// track. Analytics ▸ Program's intensity split draws it over the block; the
/// workout screen and the Workout complete sheet draw it for one session
/// (`PlannedZonesView`). The web's is `components/bio/ZonePlanComparison.tsx`.
struct ZonePlanComparison: View {
    struct Row: Identifiable {
        let zone: String          // z1 … z5
        let label: String
        let planned: Double
        let recorded: Double
        var id: String { zone }
    }

    let rows: [Row]

    /// Rows from the five-zone arrays the server sends, only the zones with
    /// either side.
    static func rows(planned: [Double], recorded: [Double]) -> [Row] {
        (0..<5).compactMap { i in
            let p = i < planned.count ? planned[i] : 0
            let r = i < recorded.count ? recorded[i] : 0
            guard p.rounded() > 0 || r.rounded() > 0 else { return nil }
            return Row(zone: "z\(i + 1)", label: "Z\(i + 1)", planned: p, recorded: r)
        }
    }

    private static func minutes(_ v: Double) -> String { "\(Int(v.rounded()))" }

    var body: some View {
        let top = max(rows.map { max($0.recorded, $0.planned) }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                let color = HRZoneStyle.color(row.zone)
                HStack(spacing: 8) {
                    Text(row.label)
                        .font(.caption).fontWeight(.medium)
                        .frame(width: 64, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            if row.planned > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(color, lineWidth: 1.5)
                                    .frame(width: max(geo.size.width * row.planned / top, 6))
                            }
                            if row.recorded > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color.opacity(0.85))
                                    .frame(width: max(geo.size.width * row.recorded / top, 4))
                                    .padding(.vertical, 3)
                            }
                        }
                    }
                    .frame(height: 18)
                    Text("\(Self.minutes(row.recorded))/\(Self.minutes(row.planned)) min")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label): \(Self.minutes(row.recorded)) minutes recorded, \(Self.minutes(row.planned)) planned")
            }
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary).frame(width: 14, height: 8)
                    Text("Recorded")
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(Color.secondary, lineWidth: 1.5)
                        .frame(width: 14, height: 10)
                    Text("Planned")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }
}

/// One workout against what its session planned (`analysis.planned`,
/// src/analytics/hr_plan.py). When the session's programming prescribes
/// heart-rate zones: planned against recorded per zone. When it prescribes
/// load or effort instead (a heavy lifting day): one line saying its heart
/// rate is shown for reference and not counted in the intensity split.
/// Nothing when the workout is linked to no session.
struct PlannedZonesView: View {
    let analysis: WorkoutAnalysis

    var body: some View {
        if let plan = analysis.planned {
            VStack(alignment: .leading, spacing: 8) {
                Text("Planned for \(plan.sessionName ?? "the session")")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                if plan.track, let recorded = analysis.zones?.minutes {
                    ZonePlanComparison(rows: ZonePlanComparison.rows(planned: plan.plannedMinutes,
                                                                     recorded: recorded))
                } else if plan.track {
                    Text("No heart rate was recorded to compare.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(Self.untrackedText(plan))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Its programming prescribes load (main: heavy), not heart-rate zones —
    /// the heart rate is for reference and not counted in the intensity split."
    static func untrackedText(_ plan: WorkoutAnalysis.Planned) -> String {
        let what = (plan.notZoned ?? []).isEmpty ? "" : " (\((plan.notZoned ?? []).joined(separator: ", ")))"
        if plan.source == "declared" {
            return "This session's programming doesn't track heart rate — the zones are for reference and not counted in the intensity split."
        }
        return "Its programming prescribes load or effort\(what), not heart-rate zones — the zones are for reference and not counted in the intensity split."
    }
}
