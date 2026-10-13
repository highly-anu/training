import SwiftUI

/// Program ▸ Overview: what the plan is, as the web's Program ▸ Overview
/// shows it — the methodology it comes from, its phases in the methodology's
/// own words, and the modality weights the schedule was allocated from. The
/// weeks themselves are on Calendar; this section describes the program's
/// shape (information-architecture.md §2).
struct ProgramOverviewTab: View {
    @EnvironmentObject var appState: AppState
    @State private var methodologySheet: PhilosophyCard? = nil

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
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Training phases", subtitle: "The blocks this program runs, in order.")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(segments) { seg in
                    phaseRow(seg, weeks: weeks, isCurrent: seg.weekIndices.contains(current))
                    if seg.id != segments.last?.id { Divider().padding(.leading, 24) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func phaseRow(_ seg: PhaseSegment, weeks: [ProgramWeek], isCurrent: Bool) -> some View {
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
        }
        .padding(12)
        .accessibilityElement(children: .combine)
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
