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

/// One workout against what its session's programming makes of it
/// (`analysis.planned`, src/analytics/hr_plan.py): the zone minutes that
/// count against the minutes planned for the same exercises, why when
/// nothing counts, and each exercise — its prescription and what it recorded
/// where the watch timed it. Nothing when the workout is linked to no
/// session. The web's is `PlannedZones` (lib/zonePlan.ts holds the words).
struct PlannedZonesView: View {
    let analysis: WorkoutAnalysis

    var body: some View {
        if let plan = analysis.planned {
            VStack(alignment: .leading, spacing: 10) {
                Text("Planned for \(plan.sessionName ?? "the session")")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                if plan.counts {
                    ZonePlanComparison(rows: ZonePlanComparison.rows(planned: plan.plannedMinutes,
                                                                     recorded: plan.zoneMinutes))
                }
                if let note = ZonePlan.note(plan) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !plan.slots.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(plan.slots) { slot in
                            let row = ZonePlan.row(slot, timing: plan.timing)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(row.title).font(.caption).fontWeight(.medium).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(row.prescription).font(.caption).foregroundStyle(.secondary)
                                Text(row.detail).font(.caption).monospacedDigit()
                                    .foregroundStyle(row.counted ? .primary : .secondary)
                                    .frame(minWidth: 96, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
                            .accessibilityElement(children: .combine)
                            if slot.id != plan.slots.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }
}

/// The words of a workout against its plan — the phone's copy of the web's
/// lib/zonePlan.ts, the same cases in ZonePlanTests.
enum ZonePlan {
    struct Row: Equatable {
        let title: String
        let prescription: String
        let detail: String
        let counted: Bool
    }

    private static func words(_ s: String) -> String { s.replacingOccurrences(of: "_", with: " ") }

    /// "Zone 2", "Zones 1–2", or the load word ("heavy", "max effort").
    static func prescription(_ slot: WorkoutAnalysis.Planned.Slot) -> String {
        if slot.zones.count == 1 { return "Zone \(slot.zones[0])" }
        if let first = slot.zones.first, let last = slot.zones.last { return "Zones \(first)–\(last)" }
        return words(slot.intensity ?? "load")
    }

    static func row(_ slot: WorkoutAnalysis.Planned.Slot, timing: String) -> Row {
        let role = words(slot.role)
        let title = slot.exercises.isEmpty ? role.prefix(1).uppercased() + role.dropFirst()
                                           : slot.exercises.joined(separator: ", ")
        let recorded = slot.recordedMinutes.map { Int($0.reduce(0, +).rounded()) }
        let planned = Int(slot.plannedMinutes.rounded())
        let detail: String
        if slot.prescribes == "load" {
            detail = recorded.map { "\($0) min · not counted" } ?? "not counted"
        } else if let recorded, slot.counted {
            detail = planned > 0 ? "\(recorded) of \(planned) min" : "\(recorded) min"
        } else if timing == "whole" {
            detail = planned > 0 ? "\(planned) min planned" : "counted"
        } else if timing == "untimed" {
            detail = "not timed"
        } else {
            detail = planned > 0 ? "\(planned) min planned" : ""
        }
        return Row(title: title, prescription: prescription(slot), detail: detail, counted: slot.counted)
    }

    /// The sentence under the comparison: what counted and why, or why nothing did.
    static func note(_ plan: WorkoutAnalysis.Planned) -> String? {
        switch plan.timing {
        case "whole": return nil
        case "timeline":
            return "Only the exercises that prescribe heart-rate zones count, inside the times the watch logged for them; the rest of the session is max effort."
        case "untimed":
            return "Some exercises prescribe heart-rate zones, but the watch didn't time them, so none of this workout counts in zones. Record the session on the watch to split it by exercise."
        case "unrecorded": return "No heart rate was recorded to compare."
        default: return untrackedText(plan)
        }
    }

    /// "Its programming prescribes load or effort (main: heavy), not heart-rate zones — …"
    static func untrackedText(_ plan: WorkoutAnalysis.Planned) -> String {
        if plan.source == "declared" {
            return "This session's programming doesn't track heart rate — the zones are for reference and not counted in the intensity split."
        }
        let what = plan.notZoned.isEmpty ? "" : " (\(plan.notZoned.joined(separator: ", ")))"
        return "Its programming prescribes load or effort\(what), not heart-rate zones — the zones are for reference and not counted in the intensity split."
    }
}
