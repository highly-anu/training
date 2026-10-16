import SwiftUI

/// Program ▸ Overview: what the plan is, as the web's Program ▸ Overview
/// shows it — the methodology it comes from, its phases in the methodology's
/// own words, and the modality weights the schedule was allocated from. The
/// weeks themselves are on Calendar; this section describes the program's
/// shape (information-architecture.md §2).
struct ProgramOverviewTab: View {
    @EnvironmentObject var appState: AppState
    @State private var methodologySheet: PhilosophyCard? = nil
    @State private var expandedPhases: Set<Int> = []
    @State private var matrixByExercise = false

    /// The server's per-phase summary (`phase_summary`); empty for an older server.
    private var summaries: [PhaseSummary] {
        PhaseSummary.list(from: appState.serverProgram?.currentProgram?.extra)
    }

    var body: some View {
        Group {
            if appState.allWeeks.isEmpty {
                ContentUnavailableView(
                    "No program",
                    systemImage: "calendar",
                    description: Text("Generate a program on Calendar to see its phases and priorities.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MethodologyRow(cards: appState.programMethodologies()) { methodologySheet = $0 }
                        phasesSection
                        PhaseMatrixSection(summaries: summaries, byExercise: $matrixByExercise)
                        prioritySection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
        }
        .task { await appState.loadPhilosophiesIfNeeded() }
        .sheet(item: $methodologySheet) { philosophy in
            PhilosophyDetailSheet(philosophy: philosophy)
        }
    }

    // MARK: - Phases

    private var phasesSection: some View {
        let weeks = appState.allWeeks
        let segments = PhaseSegment.segments(of: weeks)
        let current = appState.currentWeekIndex ?? -1
        let summaries = self.summaries
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Training phases", subtitle: summaries.isEmpty
                          ? "The blocks this program runs, in order."
                          : "The blocks this program runs, in order. Tap one to see what changes.")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
                    let summary = PhaseSummary.forSegment(index, of: summaries, segmentCount: segments.count)
                    phaseRow(seg, weeks: weeks, isCurrent: seg.weekIndices.contains(current), summary: summary)
                    if seg.id != segments.last?.id { Divider().padding(.leading, 24) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func phaseRow(_ seg: PhaseSegment, weeks: [ProgramWeek], isCurrent: Bool,
                          summary: PhaseSummary?) -> some View {
        let expanded = expandedPhases.contains(seg.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard summary != nil else { return }
                AppHaptics.light()
                withAnimation(AppAnimation.springSnappy) {
                    if expanded { expandedPhases.remove(seg.id) } else { expandedPhases.insert(seg.id) }
                }
            } label: {
                phaseHeader(seg, weeks: weeks, isCurrent: isCurrent, expandable: summary != nil, expanded: expanded)
            }
            .buttonStyle(.plain)
            if expanded, let summary {
                PhaseChangesView(summary: summary)
                    .padding(.leading, 30)
                    .padding([.trailing, .bottom], 12)
                    .transition(.opacity)
            }
        }
    }

    private func phaseHeader(_ seg: PhaseSegment, weeks: [ProgramWeek], isCurrent: Bool,
                             expandable: Bool, expanded: Bool) -> some View {
        let first = seg.weekIndices.first.map { weeks[$0].weekNumber } ?? 0
        let last = seg.weekIndices.last.map { weeks[$0].weekNumber } ?? first
        let range = first == last ? "Week \(first)" : "Weeks \(first)–\(last)"
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(PhaseStyle.color(for: seg.kind))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(seg.label).font(.subheadline).fontWeight(.medium)
                    if isCurrent {
                        Text("Now")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(PhaseStyle.color(for: seg.kind).opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Text("\(range) · \(seg.weekIndices.count) wk")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                if let focus = phaseFocus(seg, weeks: weeks) {
                    Text(focus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if expandable {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .padding(.top, 5)
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(expandable ? (expanded ? "Hides what changes" : "Shows what changes") : "")
    }

    /// The phase's focus line in its methodology's own words — the program's
    /// track first, then any methodology of the blend that declares the phase.
    private func phaseFocus(_ seg: PhaseSegment, weeks: [ProgramWeek]) -> String? {
        guard let i = seg.weekIndices.first else { return nil }
        let week = weeks[i]
        guard let phaseId = week.phaseId else { return nil }
        for card in appState.programMethodologies() {
            let track = card.track(week.trackId)
            let phases = (track?.phases ?? []) + (card.tracks ?? []).flatMap(\.phases)
            if let focus = phases.first(where: { $0.id == phaseId })?.focus, !focus.isEmpty {
                return focus
            }
        }
        return nil
    }

    // MARK: - Priority mix

    /// `goal.priorities`, the modality weights the scheduler allocated sessions
    /// from — the web's Priority Mix.
    private var priorities: [(id: String, weight: Double)] {
        guard case .object(let goal)? = appState.serverProgram?.currentProgram?.extra["goal"],
              case .object(let raw)? = goal["priorities"] else { return [] }
        let pairs: [(id: String, weight: Double)] = raw.compactMap { key, value in
            switch value {
            case .double(let d): return (key, d)
            case .int(let i): return (key, Double(i))
            default: return nil
            }
        }
        return pairs.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }
    }

    @ViewBuilder
    private var prioritySection: some View {
        let rows = priorities
        if !rows.isEmpty {
            let total = max(rows.reduce(0) { $0 + $1.weight }, 0.0001)
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Priority mix", subtitle: "The modality weights the schedule was allocated from.")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.id) { row in
                        let share = row.weight / total
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(ModalityStyle.label(for: row.id)).font(.caption)
                                Spacer()
                                Text("\(Int((share * 100).rounded()))%")
                                    .font(.caption).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(ModalityStyle.color(for: row.id))
                                    .frame(width: max(geo.size.width * share, 3))
                            }
                            .frame(height: 6)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// "About this methodology" — the program explains itself (§6.18). A blend
/// offers one entry per source.
struct MethodologyRow: View {
    let cards: [PhilosophyCard]
    let onSelect: (PhilosophyCard) -> Void

    var body: some View {
        if cards.count == 1, let card = cards.first {
            Button {
                AppHaptics.light()
                onSelect(card)
            } label: {
                label(card.name)
            }
            .buttonStyle(.plain)
        } else if cards.count > 1 {
            Menu {
                ForEach(cards) { card in
                    Button(card.name) { onSelect(card) }
                }
            } label: {
                label(cards.map(\.name).joined(separator: " + "))
            }
        }
    }

    private func label(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "book")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("About this methodology")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

/// One phase's changes from the server's summary: its weekly shape, what is
/// different from the phase before, new and gone sessions, and the loaded
/// lifts' first and last weight. The web shows the same lines in each phase's
/// "Your program" card.
struct PhaseChangesView: View {
    let summary: PhaseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            block("Weekly shape") {
                ForEach(summary.shape, id: \.modality) { row in
                    HStack(spacing: 6) {
                        Text(ModalityStyle.label(for: row.modality))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)
                        HStack(spacing: 2) {
                            ForEach(0..<max(Int(row.perWeek.rounded()), 1), id: \.self) { _ in
                                Circle().fill(ModalityStyle.color(for: row.modality).opacity(0.75))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        Text(Self.times(row.perWeek))
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !summary.changes.isEmpty {
                block("What changes") {
                    ForEach(summary.changes, id: \.self) { line in
                        Label {
                            Text(line).font(.caption).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
            if !summary.newArchetypes.isEmpty || !summary.dropped.archetypes.isEmpty {
                block("Sessions") {
                    ForEach(summary.newArchetypes) { item in
                        Text("+ \(item.name)")
                            .font(.caption)
                            .foregroundStyle(ModalityStyle.color(for: item.modality))
                    }
                    ForEach(summary.dropped.archetypes) { item in
                        Text(item.name)
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(item.name), gone")
                    }
                }
            }
            if !summary.lifts.isEmpty {
                block("Lifts") {
                    ForEach(summary.lifts.prefix(5)) { lift in
                        HStack {
                            Text(lift.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text(lift.firstKg == lift.lastKg
                                 ? Self.kg(lift.lastKg)
                                 : "\(Self.kg(lift.firstKg)) → \(Self.kg(lift.lastKg))")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    static func times(_ n: Double) -> String {
        n == n.rounded() ? "\(Int(n))×/wk" : String(format: "%.1f×/wk", n)
    }

    static func kg(_ n: Double) -> String {
        n == n.rounded() ? "\(Int(n)) kg" : String(format: "%.1f kg", n)
    }
}

/// Every session (or exercise) against every phase: how often it appears per
/// week. The web's "How the phases change" table; it scrolls sideways when a
/// track has more phases than the screen is wide.
struct PhaseMatrixSection: View {
    let summaries: [PhaseSummary]
    @Binding var byExercise: Bool

    private struct Row: Identifiable {
        let id: String
        let name: String
        let modality: String
    }

    private var rows: [Row] {
        var seen: [String: Row] = [:]
        var order: [String] = []
        for summary in summaries {
            for item in byExercise ? summary.exercises : summary.archetypes where seen[item.id] == nil {
                seen[item.id] = Row(id: item.id, name: item.name, modality: item.modality)
                order.append(item.id)
            }
        }
        let modalities = order.compactMap { seen[$0]?.modality }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        return order.compactMap { seen[$0] }.sorted {
            (modalities.firstIndex(of: $0.modality) ?? 0) < (modalities.firstIndex(of: $1.modality) ?? 0)
        }
    }

    var body: some View {
        if summaries.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How the phases change").font(.headline)
                    Text("Times per week each \(byExercise ? "exercise" : "session") appears in each phase.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Show", selection: $byExercise) {
                    Text("Sessions").tag(false)
                    Text("Exercises").tag(true)
                }
                .pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("")
                            ForEach(summaries) { s in
                                Text(s.name)
                                    .font(.caption2).fontWeight(.semibold)
                                    .foregroundStyle(PhaseStyle.color(for: s.kind))
                                    .lineLimit(1)
                                    .gridColumnAlignment(.center)
                            }
                        }
                        ForEach(rows) { row in
                            GridRow {
                                HStack(spacing: 5) {
                                    Circle().fill(ModalityStyle.color(for: row.modality)).frame(width: 6, height: 6)
                                    Text(row.name).font(.caption).lineLimit(1)
                                }
                                .frame(maxWidth: 190, alignment: .leading)
                                ForEach(summaries) { s in
                                    if let n = s.perWeek(row.id, exercises: byExercise) {
                                        Text(n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n))
                                            .font(.caption2).monospacedDigit().fontWeight(.medium)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(ModalityStyle.color(for: row.modality).opacity(0.25))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Text("·").font(.caption2).foregroundStyle(.quaternary)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(12)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
