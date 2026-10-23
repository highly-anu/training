import SwiftUI

/// One progress measure in full (design-system §6.37), pushed from its row on
/// Analytics ▸ Progress: where it stands, each exercise's status, every
/// movement practised and opened, every standard (each opens its own sheet),
/// every line of evidence, and — last — what the measure is and what to log
/// for it, in the server's words. Its line is on the Progress chart.
struct MeasureDetailView: View {
    let entry: ProgramAnalytics.ProgressEntry

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    @State private var standard: StandardSubject?

    private var status: String { entry.leadExercise?.status ?? entry.status }
    private var trend: ProgramAnalytics.Trend? { entry.leadExercise?.trend ?? entry.trend }

    var body: some View {
        List {
            Section { standingRow }
            switch entry.primitive {
            case "unlocks": unlocksSections
            case "benchmark_level": standardsSection
            default: progressSection
            }
            if !entry.evidence.isEmpty {
                Section("Evidence") {
                    ForEach(entry.evidence, id: \.self) { line in
                        Text(line).font(.subheadline)
                    }
                }
            }
            if let about = entry.about { AboutSection(about: about) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $standard) { StandardDetailSheet(subject: $0).environmentObject(appState) }
        .task { await appState.loadBenchmarksIfNeeded() }
    }

    /// The status, the trend, the headline mark and why it is not measurable.
    private var standingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AnalyticsStatusBadge(status: status)
                if let t = trend, t.direction != "insufficient_data" { MeasureTrendLabel(trend: t) }
                Spacer(minLength: 0)
                if entry.headline {
                    TintCapsule(text: "Headline", symbol: "star.fill", color: .accentColor)
                }
            }
            if let coverage = entry.coverage { CoverageNoticeView(coverage: coverage) }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Exercises

    /// Each exercise's status in words; the lines themselves are on the
    /// Progress chart (this screen had its own until 2026-10-23).
    @ViewBuilder
    private var progressSection: some View {
        if !entry.exercises.isEmpty {
            Section("Exercises") {
                ForEach(entry.exercises) { ex in
                    HStack(spacing: 8) {
                        Text(ex.name)
                        Spacer(minLength: 4)
                        if ex.stalled {
                            Label("Stalled", systemImage: "pause.circle.fill")
                                .labelStyle(.inline).font(.footnote).foregroundStyle(.red)
                        }
                        AnalyticsStatusBadge(status: ex.status)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: - Movements

    @ViewBuilder
    private var unlocksSections: some View {
        Section {
            if entry.practised.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            }
            ForEach(entry.practised) { p in
                LabeledContent(p.name) {
                    if let n = p.sessions { Text("\(n)×").monospacedDigit() }
                }
            }
        } header: {
            Text(entry.programTotal.flatMap { $0 > 0 ? "Practised · \(entry.practised.count) of \($0)" : nil }
                 ?? "Practised · \(entry.practised.count)")
        }
        Section("Now available") {
            if entry.levelOpensAll {
                Label("All open at your level", systemImage: "lock.open")
            } else if entry.available.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            } else {
                ForEach(entry.available) { a in Text(a.name) }
            }
        }
    }

    // MARK: - Standards

    private var standardsSection: some View {
        Section("Standards") {
            ForEach(entry.benchmarks.filter { !$0.missing }) { row in
                Button { open(row.benchmarkId) } label: { standardRow(row) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the standard")
            }
        }
    }

    private func standardRow(_ row: ProgramAnalytics.BenchmarkRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(row.name ?? row.benchmarkId)
                Spacer(minLength: 4)
                if row.latest != nil { StandardLevelBadge(level: row.level, domain: row.domain) }
                Text(row.latest.map { row.latestText ?? "\(AnalyticsProgressTab.number($0))\(row.unit ?? "")" } ?? "—")
                    .monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            if let target = row.target {
                HStack(spacing: 4) {
                    Label(target, systemImage: "target").labelStyle(.inline)
                    if let met = row.met {
                        Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(met ? Color.green : Color.secondary)
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            if !row.standardsText.isEmpty {
                StandardLadder(thresholds: row.standardsText,
                               levelIndex: row.latest == nil ? nil : row.levelIndex, domain: row.domain)
            }
        }
        .contentShape(Rectangle())
    }

    /// The standard's own sheet, here; Profile ▸ Standards only when the
    /// catalog has not loaded.
    private func open(_ id: String) {
        AppHaptics.light()
        if let benchmark = appState.benchmarks.first(where: { $0.id == id }) {
            standard = .standard(benchmark)
        } else {
            router.openStandard(id)
        }
    }
}
