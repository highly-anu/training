import SwiftUI

/// Where a result sits on a standard — the one ladder every screen draws
/// (design-system §6.24; the web's `StandardLadder`).
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
                    Text(level)
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(thresholds[level] ?? "—")
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(i < reached ? .primary : .secondary)
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

/// The level reached, as a small capsule in the standard's modality colour.
struct StandardLevelBadge: View {
    let level: String?
    let domain: String?

    var body: some View {
        let tint = level == nil ? Color.secondary : (domain.map { ModalityStyle.color(for: $0) } ?? Color.accentColor)
        Text(StandardLevel.name(level))
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

/// A block's results as a small line in the standard's modality colour, from
/// where the block started to where it stands. No axis: the words beside it
/// ("+1 level this block") carry the reading.
struct StandardSparkline: View {
    let values: [Double]
    let domain: String?

    var body: some View {
        let color = domain.map { ModalityStyle.color(for: $0) } ?? Color.accentColor
        GeometryReader { geo in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = hi - lo == 0 ? 1 : hi - lo
            let pts = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: geo.size.height * (1 - CGFloat((v - lo) / span)))
            }
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                pts.dropFirst().forEach { p.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let last = pts.last {
                Circle().fill(color).frame(width: 5, height: 5).position(last)
            }
        }
        .frame(width: 56, height: 16)
        .padding(.vertical, 2)
    }
}
