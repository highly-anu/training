import SwiftUI

/// Every session (or exercise) against every phase: how often it appears per
/// week (design-system §6.26). The web's "How the phases change" table,
/// pushed from Program ▸ Overview's Phases card when a track has more than one
/// phase; it scrolls sideways when the phases are wider than the screen. It
/// sat inline on Overview until 2026-10-17.
struct PhaseMatrixView: View {
    let summaries: [PhaseSummary]
    @State private var byExercise = false

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // A display mode, not a section of the screen (§6.8).
                Picker("Show", selection: $byExercise) {
                    Text("Sessions").tag(false)
                    Text("Exercises").tag(true)
                }
                .pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    grid.padding(AppMetrics.cardPadding)
                }
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("Compare phases")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                // The cells are times per week.
                Text("×/wk").font(.caption).foregroundStyle(.secondary)
                ForEach(summaries) { s in
                    Text(s.name)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(PhaseStyle.color(for: s.kind))
                        .lineLimit(1)
                        .gridColumnAlignment(.center)
                }
            }
            ForEach(rows) { row in
                GridRow {
                    HStack(spacing: 6) {
                        Circle().fill(ModalityStyle.color(for: row.modality)).frame(width: 8, height: 8)
                        Text(row.name).font(.subheadline).lineLimit(1)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                    ForEach(summaries) { s in
                        if let n = s.perWeek(row.id, exercises: byExercise) {
                            Text(n == n.rounded() ? "\(Int(n))" : String(format: "%.1f", n))
                                .font(.footnote).monospacedDigit().fontWeight(.medium)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(ModalityStyle.color(for: row.modality).opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Text("·").font(.footnote).foregroundStyle(.quaternary)
                                .accessibilityLabel("not in this phase")
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
