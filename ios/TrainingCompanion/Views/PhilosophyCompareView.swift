import SwiftUI

/// Two or three philosophies side by side (design-system §6.42): the server's
/// comparison (`GET /philosophies/compare`) as rows, each row's label above
/// one cell per philosophy, so three fit a phone without scrolling sideways;
/// and on request, each one generated on the athlete's profile
/// (`POST /philosophies/<id>/for-me`), one after another. Pushed from the
/// builder's methodology step and the methodology sheet; `compare?ids=a,b`
/// opens it from a deep link. The web's Explore ▸ Compare lays out the same
/// document.
struct PhilosophyCompareView: View {
    let ids: [String]
    @EnvironmentObject var appState: AppState

    @State private var doc: PhilosophyCompare?
    @State private var failed: String?
    @State private var onlyDifferences = false
    @State private var tracks: [String: String] = [:]
    @State private var forMe: [String: PhilosophyForMe] = [:]
    @State private var forMeFailed: [String: String] = [:]
    @State private var running: String?
    @State private var asked = false

    var body: some View {
        ScrollView {
            if let doc {
                content(doc)
            } else if let failed {
                ContentUnavailableView("Couldn't compare", systemImage: "exclamationmark.triangle",
                                       description: Text(failed))
                    .padding(.top, 60)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ids) { await load() }
    }

    private func load() async {
        guard let api = appState.api else { failed = "Sign in to compare."; return }
        do {
            doc = try await api.fetchPhilosophyCompare(ids: ids)
        } catch {
            failed = error.localizedDescription
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ doc: PhilosophyCompare) -> some View {
        let cols = doc.philosophies
        VStack(alignment: .leading, spacing: 18) {
            heads(cols)
            Toggle("Only differences", isOn: $onlyDifferences)
                .font(.subheadline)

            section("At a glance") {
                row("Weeks", same: doc.isSame("weeks"), cols) { Text($0.weeks?.text() ?? "—").monospacedDigit() }
                row("Days a week", same: doc.isSame("daysPerWeek"), cols) { Text($0.daysPerWeek?.text() ?? "—").monospacedDigit() }
                row("A session", same: doc.isSame("sessionMinutes"), cols) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.sessionMinutes?.text("′") ?? "—").monospacedDigit()
                        if let long = g.longSessionMinutes {
                            Text("long \(long)′").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                row("Level", same: doc.isSame("levels"), cols) { LevelPipsView(levels: $0.levels) }
            }

            section("Shape") {
                row("Fingerprint", same: doc.isSame("mix"), cols) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        MixStrip(mix: g.mix)
                        MixLegendView(mix: g.mix.map { ($0.modality, $0.perWeek) })
                    }
                }
                if !doc.bias.shared.isEmpty && !onlyDifferences {
                    sharedLine(cols.count) { ForEach(doc.bias.shared, id: \.self) { ModalityChip(modality: $0) } }
                }
                row("Leans toward", cols) { g in
                    chips(doc.bias.column(g.id)) { ModalityChip(modality: $0) }
                }
                row("Easy → hard", same: doc.isSame("intensity"), cols) { g in
                    if g.intensity.isEmpty { Text("Not declared").foregroundStyle(.tertiary) }
                    else { IntensityStrip(split: g.intensity) }
                }
                row("Intensity", same: doc.isSame("intensityModel"), cols) { Text($0.models?.intensity ?? "—") }
                row("Progression", same: doc.isSame("progression"), cols) { Text($0.models?.progression ?? "—") }
            }

            section("Tracks & phases") {
                row("On one scale · \(doc.trackWeeks) wk", same: doc.isSame("tracks"), cols) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(g.tracks) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(t.name).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(t.weeks) wk").monospacedDigit()
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                                PhaseStrip(phases: t.phases.map { ($0.kind, $0.weeks) }, scaleWeeks: doc.trackWeeks)
                            }
                            .opacity(t.id == track(of: g) ? 1 : 0.45)
                        }
                    }
                }
            }

            section("Progress") {
                row("Progress is", same: doc.isSame("headline"), cols) { Text($0.measures?.headline ?? "—") }
                if !doc.standards.shared.isEmpty && !onlyDifferences {
                    sharedLine(cols.count) { ForEach(doc.standards.shared, id: \.name) { StandardChip(standard: $0) } }
                }
                row("Standards", cols) { g in chips(doc.standards.column(g.id)) { StandardChip(standard: $0) } }
            }

            section("Requirements") {
                if !doc.equipment.shared.isEmpty && !onlyDifferences {
                    sharedLine(cols.count) { ForEach(doc.equipment.shared, id: \.id) { PlainChip(text: $0.name) } }
                }
                row("Equipment", cols) { g in
                    if g.equipment.isEmpty { Text("None").foregroundStyle(.tertiary) }
                    else { chips(doc.equipment.column(g.id)) { PlainChip(text: $0.name) } }
                }
                row("You already own", cols) { g in
                    let t = g.tracks.first { $0.id == track(of: g) }
                    let asks = (t?.requires ?? []) + (t?.kettlebellPair == true ? ["a pair of bells"] : [])
                    Text(asks.isEmpty ? "—" : asks.joined(separator: ", ")).foregroundStyle(.secondary)
                }
            }

            forYou(cols)
            likeness(doc)
        }
        .font(.footnote)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .padding(.bottom, 40)
    }

    /// The column heads: name and, for a philosophy with several, its track.
    private func heads(_ cols: [CompareGlance]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(cols) { g in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(g.bias.prefix(2), id: \.self) { m in
                            Image(symbol: ModalityStyle.icon(for: m)).font(.caption)
                                .foregroundStyle(ModalityStyle.color(for: m))
                        }
                    }
                    // The short name: "Uphill Athlete", not its authors.
                    Text(Self.short(g.name)).font(.subheadline).fontWeight(.semibold)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(g.name)
                    if g.tracks.count > 1 {
                        Menu {
                            ForEach(g.tracks) { t in
                                Button(t.name) { tracks[g.id] = t.id; forMe[g.id] = nil; forMeFailed[g.id] = nil }
                            }
                        } label: {
                            Label(g.tracks.first { $0.id == track(of: g) }?.name ?? "Track", systemImage: "chevron.up.chevron.down")
                                .font(.caption).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
            }
        }
    }

    private func track(of g: CompareGlance) -> String { tracks[g.id] ?? g.primaryTrack?.id ?? "" }

    private func section<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            rows()
        }
    }

    /// One row: its label, then a cell per philosophy. A row that reads alike
    /// says so, and hides under "Only differences".
    @ViewBuilder
    private func row<Cell: View>(_ label: String, same: Bool = false, _ cols: [CompareGlance],
                                 @ViewBuilder cell: @escaping (CompareGlance) -> Cell) -> some View {
        if !(onlyDifferences && same) {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                HStack(spacing: 6) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    if same { Text("same for all").font(.caption2).foregroundStyle(.tertiary) }
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(cols) { g in
                        cell(g).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func sharedLine<C: View>(_ n: Int, @ViewBuilder _ chips: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text(n == 2 ? "Both" : "All three").font(.caption).foregroundStyle(.secondary)
            LegendFlow(spacing: 4, lineSpacing: 4) { chips() }
        }
    }

    @ViewBuilder
    private func chips<T, C: View>(_ items: [T], @ViewBuilder _ chip: @escaping (T) -> C) -> some View {
        if items.isEmpty {
            Text("—").foregroundStyle(.tertiary)
        } else {
            LegendFlow(spacing: 4, lineSpacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in chip(item) }
            }
        }
    }

    // MARK: For you

    @ViewBuilder
    private func forYou(_ cols: [CompareGlance]) -> some View {
        section("For you") {
            if !asked {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        asked = true
                        Task { await runForMe(cols) }
                    } label: {
                        Label("See what each gives you", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Builds each track on your profile — days, minutes, equipment, injuries. Nothing is saved.")
                        .foregroundStyle(.secondary)
                }
            } else {
                let assumed = Array(Set(forMe.values.flatMap { $0.assumed.map(\.text) })).sorted()
                if !assumed.isEmpty {
                    Text("Assumed: \(assumed.joined(separator: "; ")).").foregroundStyle(.secondary)
                }
                forMeRow("Runs for you", cols, onlyFeasible: false) { r in
                    if r.feasible {
                        Text("Yes — \(r.trackName), \(r.weeks) wk")
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Not as you are", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange).font(.caption.weight(.semibold))
                            ForEach(Array(r.reasons.enumerated()), id: \.offset) { _, reason in
                                Text(reason.message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                forMeRow("A week", cols) { r in
                    if let w = r.perWeek {
                        Text("\(Self.num(w.days)) days · \(Self.num(w.sessions)) sessions\(w.minutes.map { " · \(Int($0))′" } ?? "")")
                            .monospacedDigit()
                    }
                }
                forMeRow("Mix", cols) { r in MixLegendView(mix: (r.mix ?? []).map { ($0.modality, $0.perWeek) }) }
                forMeRow("Easy → hard", cols) { r in IntensityStrip(split: r.intensity ?? [:]) }
                forMeRow("Phases", cols) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        PhaseStrip(phases: (r.phases ?? []).map { ($0.kind ?? "", $0.weeks ?? 0) }, scaleWeeks: r.weeks)
                        Text((r.phases ?? []).compactMap(\.name).joined(separator: " → "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                forMeRow("Your kit", cols, onlyFeasible: false) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.missingEquipment.isEmpty ? "Has all it asks for"
                             : "Lacks \(r.missingEquipment.map(\.name).joined(separator: ", "))")
                        if let skipped = r.skippedForEquipment, skipped > 0 {
                            Text("Passes over \(skipped)\(r.sessionCount.map { " of \($0)" } ?? "") sessions for it")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                forMeRow("Held back", cols) { r in
                    let held = r.heldBack?.sessions ?? 0
                    let swapped = r.gaps?.substituted.count ?? 0
                    VStack(alignment: .leading, spacing: 2) {
                        if held == 0 && swapped == 0 && (r.warnings ?? []).isEmpty {
                            Text("Nothing").foregroundStyle(.secondary)
                        }
                        if held > 0 { Text("\(held) session\(held == 1 ? "" : "s") with gaps") }
                        if swapped > 0 { Text("\(swapped) swapped for another kind") }
                        ForEach(Array((r.warnings ?? []).enumerated()), id: \.offset) { _, w in
                            Text(w.message).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                forMeRow("Tests", cols) { r in
                    let t = r.tests
                    VStack(alignment: .leading, spacing: 2) {
                        if (t?.placed ?? 0) == 0 && (t?.skipped ?? []).isEmpty { Text("—").foregroundStyle(.tertiary) }
                        if let placed = t?.placed, placed > 0 { Text("\(placed) placed") }
                        ForEach(Array((t?.skipped ?? []).enumerated()), id: \.offset) { _, s in
                            Text("Week \(s.week.map(String.init) ?? "?") skipped: \(s.why)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func forMeRow<C: View>(_ label: String, _ cols: [CompareGlance], onlyFeasible: Bool = true,
                                   @ViewBuilder cell: @escaping (PhilosophyForMe) -> C) -> some View {
        row(label, cols) { g in
            if let r = forMe[g.id] {
                if onlyFeasible && !r.feasible { Text("—").foregroundStyle(.tertiary) } else { cell(r) }
            } else if let message = forMeFailed[g.id] {
                Text(message).foregroundStyle(.red).font(.caption)
            } else if running == g.id {
                HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Generating…") }
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting…").foregroundStyle(.tertiary)
            }
        }
    }

    /// One column after another: each is a whole program on the server, which
    /// answers 429 while the athlete's previous run is still going.
    private func runForMe(_ cols: [CompareGlance]) async {
        guard let api = appState.api else { return }
        for g in cols where forMe[g.id] == nil {
            running = g.id
            for attempt in 0..<6 {
                do {
                    forMe[g.id] = try await api.philosophyForMe(id: g.id, trackId: track(of: g))
                    break
                } catch is APIClient.Busy {
                    if attempt == 5 { forMeFailed[g.id] = "The server is busy." }
                    try? await Task.sleep(for: .seconds(1.5))
                } catch {
                    forMeFailed[g.id] = error.localizedDescription
                    break
                }
            }
        }
        running = nil
    }

    // MARK: Likeness

    private func likeness(_ doc: PhilosophyCompare) -> some View {
        let names = Dictionary(uniqueKeysWithValues: doc.philosophies.map { ($0.id, Self.short($0.name)) })
        return section("How alike") {
            ForEach(Array(doc.pairs.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("\(names[p.a] ?? p.a) · \(names[p.b] ?? p.b)").lineLimit(1)
                        Spacer()
                        Text("\(Int((p.score * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                    ProgressView(value: p.score).tint(.secondary)
                    Text("\(p.primary.detail); \(p.secondary.detail)").font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func num(_ n: Double) -> String { n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n) }

    /// "Uphill Athlete — Steve House & Scott Johnston" → "Uphill Athlete".
    static func short(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "—/(")).first?
            .trimmingCharacters(in: .whitespaces) ?? name
    }
}

// MARK: - Marks

/// Four pips, novice → elite, filled where the method is written for it.
private struct LevelPipsView: View {
    let levels: [String]
    private static let all = [("novice", "N"), ("intermediate", "I"), ("advanced", "A"), ("elite", "E")]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.all, id: \.0) { level, letter in
                let on = levels.contains(level)
                Text(letter).font(.system(size: 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(on ? Color(.systemBackground) : Color.secondary.opacity(0.5))
                    .background(on ? Color.primary.opacity(0.8) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(on ? .clear : Color.secondary.opacity(0.4)))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .accessibilityLabel("Levels: \(levels.joined(separator: ", "))")
    }
}

/// The week's sessions as one strip of modality colours, each as wide as its share.
private struct MixStrip: View {
    let mix: [CompareMix]
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(mix, id: \.modality) { m in
                    ModalityStyle.color(for: m.modality).frame(width: max(0, geo.size.width * (m.share ?? 0) - 1))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

private struct MixLegendView: View {
    let mix: [(String, Double)]
    var body: some View {
        LegendFlow(spacing: 8, lineSpacing: 2) {
            ForEach(Array(mix.prefix(6).enumerated()), id: \.offset) { _, m in
                HStack(spacing: 2) {
                    Image(symbol: ModalityStyle.icon(for: m.0)).foregroundStyle(ModalityStyle.color(for: m.0))
                    Text(PhilosophyCompareView.num(m.1)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption2)
                .accessibilityLabel("\(ModalityStyle.label(for: m.0)) \(PhilosophyCompareView.num(m.1)) a week")
            }
        }
    }
}

/// Easy to hard in the heart-rate zone colours (the glance's bands).
private struct IntensityStrip: View {
    let split: [String: Double]
    private static let bands: [(String, String, Color)] = [
        ("zone1_2_pct", "Z1–2", HRZoneStyle.color(2)), ("zone3_pct", "Z3", HRZoneStyle.color(3)),
        ("zone4_5_pct", "Z4–5", HRZoneStyle.color(4)), ("max_effort_pct", "Max effort", ModalityStyle.color(for: "max_strength"))]
    var body: some View {
        let rows = Self.bands.compactMap { key, label, color in (split[key] ?? 0) > 0 ? (label, color, split[key]!) : nil }
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(rows, id: \.0) { _, color, share in color.frame(width: max(0, geo.size.width * share - 1)) }
            }
        }
        .frame(height: 4)
        .background(Color.secondary.opacity(0.2))
        .clipShape(Capsule())
        .accessibilityLabel(rows.map { "\($0.0) \(Int(($0.2 * 100).rounded()))%" }.joined(separator: ", "))
    }
}

/// A track's phases in their kinds' colours, as long as the track on a shared scale.
private struct PhaseStrip: View {
    let phases: [(String, Int)]
    let scaleWeeks: Int
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(phases.enumerated()), id: \.offset) { _, p in
                    PhaseStyle.color(for: p.0)
                        .frame(width: max(0, geo.size.width * CGFloat(p.1) / CGFloat(max(scaleWeeks, 1)) - 1))
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct ModalityChip: View {
    let modality: String
    var body: some View {
        Label { Text(ModalityStyle.label(for: modality)) } icon: {
            Image(symbol: ModalityStyle.icon(for: modality)).foregroundStyle(ModalityStyle.color(for: modality))
        }
            .labelStyle(.inline)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(ModalityStyle.color(for: modality).opacity(0.18))
            .clipShape(Capsule())
    }
}

private struct StandardChip: View {
    let standard: CompareStandard
    var body: some View {
        HStack(spacing: 3) {
            if let domain = standard.domain {
                Image(symbol: ModalityStyle.icon(for: domain)).foregroundStyle(ModalityStyle.color(for: domain))
            }
            Text(standard.name.replacingOccurrences(of: #" \(.*\)$"#, with: "", options: .regularExpression))
                .lineLimit(1)
            if standard.isTested { Image(systemName: "flask").accessibilityLabel("tested") }
        }
        .font(.caption2)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.background.secondary)
        .clipShape(Capsule())
    }
}

private struct PlainChip: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.background.secondary)
            .clipShape(Capsule())
    }
}
