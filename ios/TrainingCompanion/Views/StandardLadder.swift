import SwiftUI

/// Where a result sits on a standard — the one ladder every screen draws
/// (design-system §6.31; the web's `StandardLadder`).
///
/// The rungs fill, up to the level the server reached, in the colour of the
/// modality the standard measures; the level is read from position and its
/// word, never from a colour of its own, so a level cannot be mistaken for a
/// pass/fail status. Profile used to colour levels purple/blue/green, Blocks a
/// status green, and Progress the modality — three meanings for one thing.
struct StandardLadder: View {
    /// The thresholds as the server prints them, keyed by level.
    let thresholds: [String: String]
    /// 0 = below entry … 4 = elite; nil = no result yet.
    let levelIndex: Int?
    /// The modality the standard measures.
    let domain: String?

    private var fill: Color { domain.map { ModalityStyle.color(for: $0) } ?? Color.accentColor }

    var body: some View {
        let reached = levelIndex ?? 0
        HStack(alignment: .top, spacing: 3) {
            ForEach(Array(StandardLevel.all.enumerated()), id: \.offset) { i, level in
                VStack(alignment: alignment(i), spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < reached ? fill : Color(.systemFill))
                        .frame(height: 5)
                    // caption2, Apple's 11 pt minimum, not a fixed 9 pt (§4.1).
                    Text(level)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(thresholds[level] ?? "—")
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(i < reached ? .primary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment(i))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(levelIndex == nil
                            ? "No result yet"
                            : "\(StandardLevel.name(reached > 0 ? StandardLevel.all[reached - 1] : nil)) of four levels")
    }

    private func alignment(_ i: Int) -> HorizontalAlignment { i == 0 ? .leading : i == 3 ? .trailing : .center }
    private func frameAlignment(_ i: Int) -> Alignment { i == 0 ? .leading : i == 3 ? .trailing : .center }
}

/// The level reached, as a small capsule in the standard's modality colour —
/// the app's one capsule (`TintCapsule`, §3.1).
struct StandardLevelBadge: View {
    let level: String?
    let domain: String?

    var body: some View {
        let tint = level == nil ? Color.secondary : (domain.map { ModalityStyle.color(for: $0) } ?? Color.accentColor)
        TintCapsule(text: StandardLevel.name(level), color: tint)
    }
}
