import SwiftUI

// Sections of the `/analytics/program` document shared by Analytics ▸
// Program and Analytics ▸ Progress: a methodology's own measures, Standards
// and Session shapes — the web's `MethodologySection`, `BenchmarkLadder` and
// `ArchetypeTable`. They lay out the server's document; nothing is computed
// here.

// MARK: - Methodology

/// One philosophy's section: measurable of applicable, a
/// `ProgressEntryCard` per measure that applies, headline first, and the
/// measures this program does not schedule, folded. Its description opens
/// from the book on Analytics ▸ Program's Program card.
/// Lives on Progress (it was on Program until 2026-10-16).
struct MethodologySectionView: View {
    let method: ProgramAnalytics.Methodology
    let doc: ProgramAnalytics

    var body: some View {
        let name = doc.frame?.philosophies.first { $0.id == method.philosophy }?.name ?? method.philosophy
        let mine = doc.progress.filter { $0.philosophy == method.philosophy }
        let entries = mine.filter(\.applies).sorted { $0.headline && !$1.headline }
        let elsewhere = mine.filter { !$0.applies }
        // A card for the methodology — what is measurable, what the program
        // does not schedule — then a card per measure, as the other
        // Analytics sections lay out theirs (§6.15).
        return VStack(alignment: .leading, spacing: 16) {
            AnalyticsCard(header: name) {
                HStack(spacing: 10) {
                    Label("\(method.measurable)/\(method.applicable ?? method.total) measurable", systemImage: "ruler")
                    if method.weight < 1 {
                        Label("\(Int((method.weight * 100).rounded()))%", systemImage: "chart.pie")
                            .accessibilityLabel("\(Int((method.weight * 100).rounded())) percent of the blend")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                if !elsewhere.isEmpty {
                    // Folded: the measures this program does not schedule,
                    // each with the tracks that do.
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(elsewhere) { e in
                                let tracks = e.appliesIn.map(\.track)
                                Text(tracks.isEmpty ? e.label : "\(e.label) · \(tracks.joined(separator: ", "))")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    } label: {
                        Label("\(elsewhere.count) not in this program", systemImage: "minus.circle")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(entries) { entry in
                ProgressEntryCard(entry: entry)
            }
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
                // ×BW standards derive from logged sets with a bodyweight.
                Label(benchmarks.bodyweightKg.map { "BW \(AnalyticsProgramTab.number($0)) kg" } ?? "No bodyweight",
                      systemImage: "figure.stand")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(shown) { row in
                    StandardRowView(row: row)
                }
                if !own.isEmpty && !more.isEmpty {
                    Button(showMore ? "Fewer standards" : "More standards (\(more.count))") {
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
                            Label("\(row.completed)/\(row.scheduled)", systemImage: "checkmark.circle")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                .accessibilityLabel("\(row.completed) of \(row.scheduled) done")
                        }
                        detail(row)
                    }
                    if row.id != rows.last?.id { Divider() }
                }
            }
        }
    }

    /// Duration against the archetype's estimate (amber past ±25 %), average
    /// and peak HR, and the lead lift's est. 1RM — as symbols.
    private func detail(_ row: ProgramAnalytics.ArchetypeRow) -> some View {
        let delta = row.meanDurationDeltaPct
        return HStack(spacing: 12) {
            if let delta {
                Label("\(delta > 0 ? "+" : "")\(Int(delta.rounded()))%", systemImage: "clock")
                    .foregroundStyle(abs(delta) > 25 ? Color.yellow : Color.secondary)
                    .accessibilityLabel("Duration \(Int(delta.rounded())) percent against the estimate")
            }
            if let avg = row.hr?.avg {
                Label("\(avg)\(row.hr?.max.map { "/\($0)" } ?? "")", systemImage: "heart.fill")
                    .accessibilityLabel("Heart rate \(avg) average\(row.hr?.max.map { ", \($0) max" } ?? "")")
            }
            if let lift = row.leadLift, let first = lift.firstEst1rm, let latest = lift.latestEst1rm {
                Label("\(AnalyticsProgramTab.number(first))→\(AnalyticsProgramTab.number(latest))", systemImage: "dumbbell")
                    .lineLimit(1)
                    .accessibilityLabel("\(lift.exerciseId.replacingOccurrences(of: "_", with: " ")) est 1RM \(AnalyticsProgramTab.number(first)) to \(AnalyticsProgramTab.number(latest))")
            }
        }
        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
    }
}
