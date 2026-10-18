import SwiftUI

/// One phase of the program, pushed from Program ▸ Overview's Phases card
/// (design-system §6.26): its weeks and its methodology's words for it, then
/// the server's summary — the weekly shape, what changes from the phase
/// before, new and gone sessions, and the loaded lifts' first and last
/// weight. The web shows the same lines in each phase's "Your program" card.
/// Until 2026-10-17 these opened in place under the phase's row, in caption
/// type, and a four-phase track made Overview a page of them.
struct PhaseDetailView: View {
    let segment: PhaseSegment
    let summary: PhaseSummary
    /// The methodology's own phase, for its focus line and description.
    let phase: PhilosophyPhase?
    let weeks: [ProgramWeek]
    let isCurrent: Bool

    private var color: Color { PhaseStyle.color(for: segment.kind) }

    var body: some View {
        List {
            Section {
                header
            } footer: {
                // The methodology's own account of the phase, under its card
                // as the system puts explanations (Settings' footers).
                if let text = phase?.description, !text.isEmpty {
                    Text(text)
                }
            }
            Section("Each week") {
                ForEach(summary.shape, id: \.modality) { row in
                    shapeRow(row)
                }
                if summary.minutesMean > 0 {
                    LabeledContent {
                        Text("\(summary.minutesMean) min").monospacedDigit()
                    } label: {
                        Label("Training time", systemImage: "clock")
                    }
                }
            }
            if !summary.changes.isEmpty {
                Section("What changes") {
                    ForEach(summary.changes, id: \.self) { line in
                        Text(line)
                    }
                }
            }
            if !summary.newArchetypes.isEmpty || !summary.dropped.archetypes.isEmpty {
                Section("Sessions") {
                    ForEach(summary.newArchetypes) { item in
                        Label {
                            Text(item.name)
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(ModalityStyle.color(for: item.modality))
                        }
                        .accessibilityLabel("\(item.name), new")
                    }
                    ForEach(summary.dropped.archetypes) { item in
                        Label {
                            Text(item.name).strikethrough().foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("\(item.name), gone")
                    }
                }
            }
            if !summary.lifts.isEmpty {
                Section("Lifts") {
                    ForEach(summary.lifts) { lift in
                        LabeledContent(lift.name) {
                            Text(Self.liftText(lift)).monospacedDigit()
                        }
                        .accessibilityLabel(lift.firstKg == lift.lastKg
                            ? "\(lift.name), \(Self.kg(lift.lastKg))"
                            : "\(lift.name), \(Self.kg(lift.firstKg)) to \(Self.kg(lift.lastKg))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(segment.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text("\(segment.range(in: weeks)) · \(segment.weekIndices.count) wk")
                    .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                if isCurrent {
                    TintCapsule(text: "Now", color: color)
                }
            }
            if let focus = phase?.focus, !focus.isEmpty {
                Text(focus).font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// A modality, a dot per session a week, and the average.
    private func shapeRow(_ row: (modality: String, perWeek: Double)) -> some View {
        let modalityColor = ModalityStyle.color(for: row.modality)
        return LabeledContent {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(0..<max(Int(row.perWeek.rounded()), 1), id: \.self) { _ in
                        Circle().fill(modalityColor.opacity(0.75)).frame(width: 8, height: 8)
                    }
                }
                Text(Self.times(row.perWeek)).monospacedDigit()
            }
        } label: {
            Label {
                Text(ModalityStyle.label(for: row.modality)).lineLimit(2)
            } icon: {
                Image(symbol: ModalityStyle.icon(for: row.modality)).foregroundStyle(modalityColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ModalityStyle.label(for: row.modality)), \(Self.times(row.perWeek))")
    }

    static func times(_ n: Double) -> String {
        n == n.rounded() ? "\(Int(n))×/wk" : String(format: "%.1f×/wk", n)
    }

    static func kg(_ n: Double) -> String {
        n == n.rounded() ? "\(Int(n)) kg" : String(format: "%.1f kg", n)
    }

    /// "70 → 145 kg", or one weight when the phase holds it.
    static func liftText(_ lift: PhaseSummary.Lift) -> String {
        lift.firstKg == lift.lastKg ? kg(lift.lastKg) : "\(kg(lift.firstKg)) → \(kg(lift.lastKg))"
    }
}

extension PhaseSegment {
    /// The program's own numbers for the phase's first and last week — a
    /// program regenerated from an event date numbers them absolutely.
    func weekNumbers(in weeks: [ProgramWeek]) -> (first: Int, last: Int) {
        let number = { (i: Int) in weeks.indices.contains(i) ? weeks[i].weekNumber : nil }
        let first = weekIndices.first.flatMap(number) ?? 0
        return (first, weekIndices.last.flatMap(number) ?? first)
    }

    /// "Wk 1–12", "Wk 5": a row on the Phases card.
    func shortRange(in weeks: [ProgramWeek]) -> String {
        let (first, last) = weekNumbers(in: weeks)
        return first == last ? "Wk \(first)" : "Wk \(first)–\(last)"
    }

    /// "Weeks 1–12", "Week 5": the phase's own screen.
    func range(in weeks: [ProgramWeek]) -> String {
        let (first, last) = weekNumbers(in: weeks)
        return first == last ? "Week \(first)" : "Weeks \(first)–\(last)"
    }
}
