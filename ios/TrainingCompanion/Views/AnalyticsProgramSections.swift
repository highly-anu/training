import SwiftUI

// Sections of the `/analytics/program` document shared by Analytics ▸
// Program and Analytics ▸ Progress: a methodology's own measures, Standards
// and Session shapes — the web's `MethodologySection`, `BenchmarkLadder` and
// `ArchetypeTable`. They lay out the server's document; nothing is computed
// here.

// MARK: - Methodology

/// One philosophy's section: measurable of applicable, a way to its
/// description, a `ProgressEntryCard` per measure that applies, headline
/// first, and one line for the measures this program does not schedule.
/// Lives on Progress (it was on Program until 2026-10-16).
struct MethodologySectionView: View {
    @EnvironmentObject var appState: AppState
    let method: ProgramAnalytics.Methodology
    let doc: ProgramAnalytics
    @State private var sheet: PhilosophyCard?

    var body: some View {
        let name = doc.frame?.philosophies.first { $0.id == method.philosophy }?.name ?? method.philosophy
        let mine = doc.progress.filter { $0.philosophy == method.philosophy }
        let entries = mine.filter(\.applies).sorted { $0.headline && !$1.headline }
        let elsewhere = mine.filter { !$0.applies }
        let card = appState.philosophies.first { $0.id == method.philosophy }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    // The web links into Explore; the phone's methodology
                    // reference is the sheet (design-system §6.18).
                    if let card {
                        Button { sheet = card } label: {
                            HStack(spacing: 2) {
                                Text("About this methodology")
                                Image(systemName: "chevron.right").imageScale(.small)
                            }
                        }
                        .font(.caption2)
                    }
                }
                HStack(spacing: 6) {
                    Text("\(method.measurable) of \(method.applicable ?? method.total) metrics measurable")
                    if method.weight < 1 { Text("· \(Int((method.weight * 100).rounded()))% of the blend") }
                    Text(method.analytics == "declared" ? "declared" : "default spec")
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                ProgressEntryCard(entry: entry)
            }
            if !elsewhere.isEmpty {
                Text("Not in this program: " + elsewhere.map { e in
                    let tracks = e.appliesIn.map(\.track)
                    return tracks.isEmpty ? e.label : "\(e.label) (\(tracks.joined(separator: ", ")))"
                }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task { await appState.loadPhilosophiesIfNeeded() }
        .sheet(item: $sheet) { philosophy in
            PhilosophyDetailSheet(philosophy: philosophy)
        }
    }
}

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
