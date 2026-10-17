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
                HStack(spacing: 12) {
                    Label("\(method.measurable)/\(method.applicable ?? method.total)", systemImage: "ruler")
                        .fontWeight(.semibold)
                        .accessibilityLabel("\(method.measurable) of \(method.applicable ?? method.total) measures measurable")
                    if method.weight < 1 {
                        Label("\(Int((method.weight * 100).rounded()))%", systemImage: "chart.pie")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(Int((method.weight * 100).rounded())) percent of the blend")
                    }
                }
                .font(.subheadline).monospacedDigit()
                if !elsewhere.isEmpty {
                    // Folded: the measures this program does not schedule,
                    // each with the tracks that do.
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(elsewhere) { e in
                                let tracks = e.appliesIn.map(\.track)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.label).font(.subheadline)
                                    if !tracks.isEmpty {
                                        Text(tracks.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    } label: {
                        Label("\(elsewhere.count) not in this program", systemImage: "minus.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }
            ForEach(entries) { entry in
                ProgressEntryCard(entry: entry)
            }
        }
    }
}

// MARK: - Standards

/// The standards this program is measured by — what its package declares and
/// what it tests — with how far the athlete has moved this block. Standards
/// that only share a domain or cite the methodology wait behind "More
/// standards"; a result alone no longer makes a standard the program's own.
/// A row is the summary — value, level, gap, the block's line; tap it for the
/// standard's own sheet, here (§6.32), with the ladder and every result. It
/// used to jump to Profile ▸ Standards and draw a ladder on every row.
struct ProgramStandardsCard: View {
    let benchmarks: ProgramAnalytics.Benchmarks
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var appState: AppState
    @State private var showMore = false
    @State private var sheet: StandardSubject?

    private var own: [ProgramAnalytics.Benchmarks.Row] { benchmarks.rows.filter(\.primary) }
    private var more: [ProgramAnalytics.Benchmarks.Row] { benchmarks.rows.filter { !$0.primary } }
    private var shown: [ProgramAnalytics.Benchmarks.Row] { showMore ? own + more : own }

    var body: some View {
        AnalyticsCard(header: "Standards") {
            VStack(alignment: .leading, spacing: 12) {
                if own.isEmpty {
                    Text("This program declares no standards of its own.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                // ×BW standards derive from logged sets with a bodyweight.
                Label(benchmarks.bodyweightText.map { "BW \($0)" }
                      ?? benchmarks.bodyweightKg.map { "BW \(AnalyticsProgramTab.number($0)) kg" } ?? "No bodyweight",
                      systemImage: "figure.stand")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(shown) { row in
                    Button { open(row.benchmarkId) } label: { StandardRowView(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the standard")
                }
                if !more.isEmpty {
                    Button(showMore ? "Fewer standards" : "More standards (\(more.count))") {
                        withAnimation(AppAnimation.layoutChange) { showMore.toggle() }
                    }
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
        .sheet(item: $sheet) { StandardDetailSheet(subject: $0).environmentObject(appState) }
        .task { await appState.loadBenchmarksIfNeeded() }
    }

    /// The standard's sheet in place; Profile ▸ Standards only when the
    /// catalog has not loaded.
    private func open(_ id: String) {
        AppHaptics.light()
        if let benchmark = appState.benchmarks.first(where: { $0.id == id }) {
            sheet = .standard(benchmark)
        } else {
            router.openStandard(id)
        }
    }
}

private struct StandardRowView: View {
    let row: ProgramAnalytics.Benchmarks.Row

    private var valueText: String? {
        row.value.map { v in
            "\(row.valueText ?? "\(AnalyticsProgramTab.number(v))\(row.unit)")\(row.valueSource == "derived" ? " est." : "")"
        }
    }

    private var detail: String? {
        var parts: [String] = []
        if let change = StandardLevel.blockChange(levelChange: row.levelChange, hasStart: row.atBlockStart != nil,
                                                 points: row.blockHistory.count) {
            parts.append(change)
        }
        if row.value != nil, let next = row.next,
           let gap = row.gapText ?? row.gapToNext.map({ "\(AnalyticsProgramTab.number($0))\(row.unit)" }) {
            parts.append("\(gap) to \(next)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let domain = row.domain {
                    // The modality's symbol beside its colour: colour is
                    // never the only signal (§1.6).
                    Image(symbol: ModalityStyle.icon(for: domain))
                        .foregroundStyle(ModalityStyle.color(for: domain))
                        .accessibilityLabel(ModalityStyle.label(for: domain))
                }
                Text(row.name).fontWeight(.medium)
                Spacer(minLength: 6)
                Text(valueText ?? "—")
                    .monospacedDigit()
                    .fontWeight(row.value == nil ? .regular : .semibold)
                    .foregroundStyle(row.value == nil ? .secondary : .primary)
                    .accessibilityLabel(valueText ?? "No result yet")
                // It opens the standard's sheet (§6.9).
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            if row.value != nil || detail != nil {
                HStack(spacing: 6) {
                    if row.value != nil { StandardLevelBadge(level: row.level, domain: row.domain) }
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer(minLength: 0)
                    if row.blockHistory.count >= 2 {
                        Sparkline(values: row.blockHistory.map(\.value),
                                  color: row.domain.map { ModalityStyle.color(for: $0) } ?? .accentColor,
                                  width: 56, height: 16)
                            .accessibilityElement()
                            .accessibilityLabel("This block: " + row.blockHistory.map(\.valueText).joined(separator: " → "))
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Session shapes

/// Session shapes as a summary (§6.37): done of scheduled across every
/// shape, how many ran far from their estimate, and the first three shapes;
/// the screen lists every shape with its duration against the estimate,
/// heart rate and lead lift. The list grew with every archetype inline until
/// 2026-10-17.
struct SessionShapesCard: View {
    let rows: [ProgramAnalytics.ArchetypeRow]

    private var done: Int { rows.reduce(0) { $0 + $1.completed } }
    private var scheduled: Int { rows.reduce(0) { $0 + $1.scheduled } }
    /// Shapes whose measured duration ran past ±25 % of the archetype's estimate.
    private var offEstimate: Int { rows.filter { abs($0.meanDurationDeltaPct ?? 0) > 25 }.count }

    var body: some View {
        AnalyticsDetailCard(header: "Session shapes", hint: "Opens every session shape") {
            SessionShapesDetailView(rows: rows)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Label("\(done)/\(scheduled)", systemImage: "checkmark.circle")
                        .font(.title3).fontWeight(.semibold).monospacedDigit()
                        .accessibilityLabel("\(done) of \(scheduled) sessions done")
                    if offEstimate > 0 {
                        Label("\(offEstimate)", systemImage: "clock.badge.exclamationmark")
                            .font(.subheadline).foregroundStyle(.yellow)
                            .accessibilityLabel("\(offEstimate) shapes ran far from their estimate")
                    }
                }
                ForEach(rows.prefix(3)) { row in SessionShapeRow(row: row, showsDetail: false) }
                if rows.count > 3 {
                    Text("+\(rows.count - 3)").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityLabel("\(rows.count - 3) more shapes")
                }
            }
        }
    }
}

/// Every session shape, pushed from its card.
struct SessionShapesDetailView: View {
    let rows: [ProgramAnalytics.ArchetypeRow]

    var body: some View {
        List(rows) { row in
            SessionShapeRow(row: row, showsDetail: true).padding(.vertical, 2)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Session shapes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One shape: its modality's symbol, name and done of scheduled; with
/// `showsDetail`, duration against the archetype's estimate (amber past
/// ±25 %), average and peak HR, and the lead lift's est. 1RM — as symbols.
private struct SessionShapeRow: View {
    let row: ProgramAnalytics.ArchetypeRow
    let showsDetail: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let modality = row.modality {
                    // The modality's symbol, not a dot: colour is never the
                    // only signal (§1.6).
                    Image(symbol: ModalityStyle.icon(for: modality))
                        .foregroundStyle(ModalityStyle.color(for: modality))
                        .accessibilityLabel(ModalityStyle.label(for: modality))
                }
                Text(row.name).fontWeight(.medium).lineLimit(2)
                Spacer()
                Label("\(row.completed)/\(row.scheduled)", systemImage: "checkmark.circle")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel("\(row.completed) of \(row.scheduled) done")
            }
            .font(.subheadline)
            if showsDetail { detail }
        }
        // Compact labels in a List too, which otherwise gives each an icon column.
        .labelStyle(.titleAndIcon)
    }

    private var detail: some View {
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
        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
}
