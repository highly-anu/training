import SwiftUI

/// The program's weeks as one bar, a segment per phase in its kind's colour
/// (§3.2): past phases dimmed, the current one filled up to this week with a
/// marker, later ones faint (design-system §6.36). Program ▸ Calendar shows it
/// with each phase's name under its segment; Program ▸ Overview without, since
/// the header's pill names the current phase and the Phases card lists them.
/// Calendar drew it privately until Overview became the second user.
struct PhaseProgressBar: View {
    let weeks: [ProgramWeek]
    /// The array index of this week; nil before the start or after the end.
    let currentIndex: Int?
    var showsLabels = true

    var body: some View {
        let total = weeks.count
        let currentIdx = currentIndex ?? -1
        let segments = PhaseSegment.segments(of: weeks)

        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                let barWidth = geo.size.width
                HStack(spacing: 0) {
                    ForEach(segments) { seg in
                        let segFrac = CGFloat(seg.weekIndices.count) / CGFloat(max(total, 1))
                        let segWidth = barWidth * segFrac
                        let isCurrent = seg.weekIndices.contains(currentIdx)
                        let isPast = (seg.weekIndices.last ?? -1) < currentIdx
                        let color = PhaseStyle.color(for: seg.kind)

                        ZStack(alignment: .leading) {
                            if isPast {
                                Rectangle().fill(color.opacity(0.45))
                            } else if isCurrent, let firstIdx = seg.weekIndices.first {
                                let progress = CGFloat(currentIdx - firstIdx + 1)
                                    / CGFloat(seg.weekIndices.count)
                                let doneWidth = segWidth * progress
                                // Dim fill for whole segment
                                Rectangle().fill(color.opacity(0.18))
                                // Bright fill for completed portion
                                Rectangle().fill(color.opacity(0.65))
                                    .frame(width: doneWidth)
                                // Bright vertical marker at current week
                                Rectangle().fill(color)
                                    .frame(width: 3)
                                    .offset(x: max(0, doneWidth - 1.5))
                            } else {
                                Rectangle().fill(color.opacity(0.15))
                            }
                        }
                        .frame(width: segWidth, height: 10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                // Subtle track behind
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemFill))
                )
            }
            .frame(height: 10)

            if showsLabels {
                // Never scaled below caption2 (11 pt, the HIG's minimum): a
                // name too long for its segment truncates instead.
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(segments) { seg in
                            let segFrac = CGFloat(seg.weekIndices.count) / CGFloat(max(total, 1))
                            let isCurrent = seg.weekIndices.contains(currentIdx)
                            let color = PhaseStyle.color(for: seg.kind)
                            Text(seg.label)
                                .font(.caption2)
                                .fontWeight(isCurrent ? .semibold : .regular)
                                .foregroundStyle(isCurrent ? color : .secondary)
                                .lineLimit(1)
                                .frame(width: geo.size.width * segFrac, alignment: .center)
                        }
                    }
                }
                .frame(height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(segments: segments, current: currentIdx))
    }

    /// "Week 3 of 12, Base" — or the phases in order when no week is current.
    private func accessibilityText(segments: [PhaseSegment], current: Int) -> String {
        if let seg = segments.first(where: { $0.weekIndices.contains(current) }) {
            return "Week \(current + 1) of \(weeks.count), \(seg.label)"
        }
        return segments.map(\.label).joined(separator: ", ")
    }
}
