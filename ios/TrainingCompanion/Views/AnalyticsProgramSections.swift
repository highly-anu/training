import SwiftUI

// Sections of the `/analytics/program` document shared by Analytics ▸
// Program and Analytics ▸ Progress: a methodology's own measures, Standards
// and Session shapes — the web's `MethodologySection`, `BenchmarkLadder` and
// `ArchetypeTable`. They lay out the server's document; nothing is computed
// here.

// MARK: - Methodology

/// One philosophy's measures: its name as the label above them (with its
/// share in a blend), a `ProgressEntryCard` per measure that applies,
/// headline first, and — when there are any — a row to the measures this
/// program does not schedule. The name was a card of its own with
/// "measurable / applicable" until 2026-10-18; that count is the Score
/// detail's now, and each measure's card says itself when it cannot be read.
/// Lives on Progress (it was on Program until 2026-10-16).
struct MethodologySectionView: View {
    let method: ProgramAnalytics.Methodology
    let doc: ProgramAnalytics

    var body: some View {
        let name = doc.frame?.philosophies.first { $0.id == method.philosophy }?.name ?? method.philosophy
        let mine = doc.progress.filter { $0.philosophy == method.philosophy }
        let entries = mine.filter(\.applies).sorted { $0.headline && !$1.headline }
        let elsewhere = mine.filter { !$0.applies }
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: method.weight < 1 ? "\(name) · \(Int((method.weight * 100).rounded()))%" : name)
                .accessibilityLabel(method.weight < 1
                                    ? "\(name), \(Int((method.weight * 100).rounded())) percent of the blend" : name)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(entries) { entry in
                    ProgressEntryCard(entry: entry)
                }
                if !elsewhere.isEmpty {
                    NavigationLink {
                        MeasuresElsewhereView(name: name, entries: elsewhere)
                    } label: {
                        HStack(spacing: 8) {
                            Label("\(elsewhere.count) not in this program", systemImage: "minus.circle")
                                .labelStyle(.inline)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption).fontWeight(.semibold).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, AppMetrics.cardPadding)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the measures this program does not schedule")
                }
            }
        }
    }
}

/// A group's name above its cards, styled as an inset list's section header
/// and aligned with the cards' text — not a card: it says what follows,
/// nothing of its own.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, AppMetrics.cardPadding)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The measures a methodology declares that no session of this program is in
/// scope for, each with the tracks that schedule it.
struct MeasuresElsewhereView: View {
    let name: String
    let entries: [ProgramAnalytics.ProgressEntry]

    var body: some View {
        List {
            Section {
                ForEach(entries) { e in
                    let tracks = e.appliesIn.map(\.track)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.label)
                        if !tracks.isEmpty {
                            Label(tracks.joined(separator: ", "), systemImage: "arrow.triangle.branch")
                                .labelStyle(.inline)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if let measures = e.about?.measures, !measures.isEmpty {
                            Text(measures).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(name)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Not in this program")
        .navigationBarTitleDisplayMode(.inline)
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
        .labelStyle(.inline)
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
