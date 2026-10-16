import SwiftUI

// Sections of Analytics ▸ Program the phone lacked until 2026-10-16:
// Standards and Session shapes, the web's `BenchmarkLadder` and
// `ArchetypeTable`. They lay out the server's document; nothing is computed
// here.

// MARK: - Standards

/// The standards this program is measured by, and where the athlete stands.
/// The program's own (declared, its methodology's, or already logged) show;
/// same-domain tables from other sources wait behind "More standards".
struct ProgramStandardsCard: View {
    let benchmarks: ProgramAnalytics.Benchmarks
    @State private var showMore = false

    private var own: [ProgramAnalytics.Benchmarks.Row] { benchmarks.rows.filter(\.primary) }
    private var more: [ProgramAnalytics.Benchmarks.Row] { benchmarks.rows.filter { !$0.primary } }
    private var shown: [ProgramAnalytics.Benchmarks.Row] {
        own.isEmpty ? benchmarks.rows : showMore ? own + more : own
    }

    var body: some View {
        AnalyticsCard(header: "Standards") {
            VStack(alignment: .leading, spacing: 12) {
                Text("This program's own standards, and any you have a number for."
                     + (benchmarks.bodyweightKg.map { " Bodyweight \(AnalyticsProgramTab.number($0)) kg lets ×BW standards derive from your logged sets." }
                        ?? " Log your bodyweight to derive ×BW standards from logged sets."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(shown) { row in
                    StandardRowView(row: row)
                }
                if !own.isEmpty && !more.isEmpty {
                    Button(showMore ? "Fewer standards" : "More standards (\(more.count)) — same domains, other sources") {
                        withAnimation(AppAnimation.layoutChange) { showMore.toggle() }
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct StandardRowView: View {
    let row: ProgramAnalytics.Benchmarks.Row

    private static let whyLabel = ["philosophy": "this methodology", "priority_modality": "priority modality",
                                   "declared": "declared"]

    private var valueText: String {
        var parts: [String] = []
        if let v = row.value {
            parts.append("\(AnalyticsProgramTab.number(v))\(row.unit)\(row.valueSource == "derived" ? " est." : "")")
        } else {
            parts.append("—")
        }
        if let level = row.level { parts.append(level) }
        if let next = row.next, let gap = row.gapToNext {
            parts.append("\(AnalyticsProgramTab.number(gap))\(row.unit) to \(next)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).font(.caption).fontWeight(.medium)
                Spacer()
                Text(valueText).font(.caption).foregroundStyle(.secondary)
            }
            ladder
            Text(row.why.compactMap { Self.whyLabel[$0] }.joined(separator: " · ")
                 + (row.derivedReason == "no_bodyweight_logged" ? " · est. 1RM known, bodyweight not" : ""))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// One segment per rung, filled up to the level reached, each rung's
    /// threshold under it — the web's `LevelBar`, without the marker.
    private var ladder: some View {
        let rungs = row.rungs
        let reached = rungs.firstIndex { $0.level == row.level }
        return HStack(spacing: 3) {
            ForEach(Array(rungs.enumerated()), id: \.offset) { i, rung in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(reached.map { i <= $0 } == true ? Color.accentColor : Color(.systemFill))
                        .frame(height: 5)
                    Text(AnalyticsProgramTab.number(rung.value))
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name): \(valueText)")
    }
}

// MARK: - Session shapes

/// Per session shape: done against scheduled, how far measured durations ran
/// from the archetype's estimate, heart rate, and the lead lift's est. 1RM.
struct SessionShapesCard: View {
    let rows: [ProgramAnalytics.ArchetypeRow]

    var body: some View {
        AnalyticsCard(header: "Session shapes") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if let modality = row.modality {
                                Circle().fill(ModalityStyle.color(for: modality)).frame(width: 7, height: 7)
                            }
                            Text(row.name).font(.caption).fontWeight(.medium).lineLimit(2)
                            Spacer()
                            Text("\(row.completed)/\(row.scheduled) done")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        detail(row)
                    }
                    if row.id != rows.last?.id { Divider() }
                }
            }
        }
    }

    private func detail(_ row: ProgramAnalytics.ArchetypeRow) -> some View {
        let delta = row.meanDurationDeltaPct
        return HStack(spacing: 4) {
            Text("Duration \(delta.map { "\($0 > 0 ? "+" : "")\(AnalyticsProgramTab.number($0))%" } ?? "—")")
                .foregroundStyle(delta.map { abs($0) > 25 } == true ? Color.yellow : Color.secondary)
            Text("· HR \(row.hr.flatMap { hr in hr.avg.map { "\($0) / \(hr.max.map(String.init) ?? "—")" } } ?? "—")")
            if let lift = row.leadLift, let first = lift.firstEst1rm, let latest = lift.latestEst1rm {
                Text("· \(lift.exerciseId.replacingOccurrences(of: "_", with: " ")) \(AnalyticsProgramTab.number(first)) → \(AnalyticsProgramTab.number(latest)) est 1RM")
                    .lineLimit(1)
            }
        }
        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
    }
}
