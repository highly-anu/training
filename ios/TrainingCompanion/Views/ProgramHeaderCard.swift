import SwiftUI

/// The program's header card (design-system §6.28): the methodology with the
/// book that opens its description, the current phase and week, a symbol row
/// per fact about how it trains, and a footer the screen supplies — the plan's
/// settings on Program ▸ Overview, plan fidelity on Analytics ▸ Program.
/// Both screens drew their own copy until 2026-10-16.
enum ProgramHeader {
    struct Phase {
        let label: String
        /// The kind (`base`, `build`…), which colours the pill.
        let kind: String
        let week: Int
        let totalWeeks: Int
        let isDeload: Bool
    }

    struct Tag: Identifiable {
        let icon: String
        let text: String
        var id: String { icon }
    }

    /// "rpm_based" → "Rpm based".
    static func words(_ id: String) -> String {
        let s = id.replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

struct ProgramHeaderCard<Footer: View>: View {
    typealias Phase = ProgramHeader.Phase
    typealias Tag = ProgramHeader.Tag

    let name: String
    /// The program's methodologies, for the book; a blend gets a menu.
    let methodologies: [PhilosophyCard]
    let phase: Phase?
    let tags: [Tag]
    @ViewBuilder let footer: () -> Footer

    @State private var sheet: PhilosophyCard?

    var body: some View {
        AnalyticsCard(header: "Program") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    book
                }
                if let phase { phaseRow(phase) }
                if !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tags) { tag in
                            Label(tag.text, systemImage: tag.icon)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                footer()
            }
        }
        .sheet(item: $sheet) { PhilosophyDetailSheet(philosophy: $0) }
    }

    private func phaseRow(_ phase: Phase) -> some View {
        HStack(spacing: 6) {
            TintCapsule(text: phase.label, color: PhaseStyle.color(for: phase.kind))
            Label("\(phase.week)/\(phase.totalWeeks)", systemImage: "calendar")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel("Week \(phase.week) of \(phase.totalWeeks)")
            if phase.isDeload {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption).foregroundStyle(.blue)
                    .accessibilityLabel("Deload")
            }
        }
    }

    /// The methodology's description (§6.18); one entry per source in a blend.
    @ViewBuilder
    private var book: some View {
        let icon = Image(systemName: "book")
            .font(.subheadline)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("About this methodology")
            .accessibilityHint("Opens the methodology")
        if methodologies.count == 1, let card = methodologies.first {
            Button { AppHaptics.light(); sheet = card } label: { icon }
                .padding(.vertical, -12)
        } else if methodologies.count > 1 {
            Menu {
                ForEach(methodologies) { card in Button(card.name) { sheet = card } }
            } label: { icon }
                .padding(.vertical, -12)
        }
    }
}

/// A footer cell: a symbol, a value, and its unit under it — the plan's
/// settings and plan fidelity read the same.
struct ProgramHeaderStat<Mark: View>: View {
    let icon: String
    let value: String
    let unit: String
    let accessibility: String
    @ViewBuilder let mark: () -> Mark

    init(icon: String, value: String, unit: String, accessibility: String,
         @ViewBuilder mark: @escaping () -> Mark) {
        self.icon = icon; self.value = value; self.unit = unit
        self.accessibility = accessibility; self.mark = mark
    }

    var body: some View {
        // The value is the cell's subject; its unit qualifies it (§4.1).
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.footnote).foregroundStyle(.secondary)
                Text(value).font(.subheadline).fontWeight(.semibold).monospacedDigit()
                mark().font(.footnote)
            }
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }
}

extension ProgramHeaderStat where Mark == EmptyView {
    init(icon: String, value: String, unit: String, accessibility: String) {
        self.init(icon: icon, value: value, unit: unit, accessibility: accessibility) { EmptyView() }
    }
}
