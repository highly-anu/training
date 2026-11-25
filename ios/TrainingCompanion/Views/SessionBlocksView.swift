import SwiftUI

/// A session as its blocks (design-system §6.62): what opens it, what repeats
/// in rounds or every minute, the rests, what closes it — as the server reads
/// it (src/session_blocks.py; the web's components/blocks/WorkoutBlocks.tsx).
/// A stage is named only when the session has more than one; a round's
/// movements sit on a rail in the session's colour with what ends the round
/// at its foot. Every word is the server's. The caller draws a movement's row
/// (`row`), so a shared session shows the numbers planned and a method's
/// session the written count.
struct SessionBlocksView<Row: View>: View {
    let blocks: [SessionBlock]
    var accent: Color = .secondary
    /// The block's own load line; off where the caller's rows already carry
    /// each movement's note (a planned session's), which is the same sentence.
    var showsLoad = true
    @ViewBuilder let row: (SessionBlock.Movement, SessionBlock) -> Row

    var body: some View {
        let stages = SessionBlock.stages(blocks)
        VStack(alignment: .leading, spacing: AppMetrics.gapLarge) {
            ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                    if stages.count > 1, !stage.label.isEmpty { SectionLabel(stage.label) }
                    ForEach(stage.blocks) { block in card(block) }
                }
            }
        }
    }

    private func card(_ block: SessionBlock) -> some View {
        VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
            HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                Image(systemName: Self.symbol(block.shape))
                    .foregroundStyle(block.stage == "main" ? accent : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let headline = block.headline, !headline.isEmpty {
                        Text(headline).font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    if let title = block.title, !title.isEmpty, block.movements.count != 1 {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if block.isLoop {
                HStack(alignment: .top, spacing: AppMetrics.gapSmall) {
                    Capsule().fill(accent).frame(width: 2)
                    VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
                        movements(block)
                        if let foot = block.foot {
                            Label(foot, systemImage: "arrow.turn.left.up")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                movements(block)
                if let rest = block.rest?.text, !rest.isEmpty {
                    Label(rest, systemImage: "pause").font(.caption).foregroundStyle(.secondary)
                }
            }
            if showsLoad, let load = block.load, !load.isEmpty {
                Text(load).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(compact: true)
    }

    private func movements(_ block: SessionBlock) -> some View {
        VStack(alignment: .leading, spacing: AppMetrics.gapSmall) {
            ForEach(block.movements, id: \.role) { movement in row(movement, block) }
        }
    }

    /// The mark of a block's shape (the web's SHAPE_ICON).
    static func symbol(_ shape: String) -> String {
        switch shape {
        case "rounds": return "repeat"
        case "for_time": return "flag.checkered"
        case "amrap": return "hourglass"
        case "emom": return "timer"
        case "interval": return "bolt"
        case "timed": return "clock"
        case "distance": return "point.topleft.down.to.point.bottomright.curvepath"
        case "hold": return "pause.circle"
        case "practice": return "sparkles"
        case "note": return "note.text"
        default: return "list.bullet"
        }
    }
}

/// A movement as the block writes it: its count and its name, the note under it.
struct BlockMovementRow: View {
    let movement: SessionBlock.Movement

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: AppMetrics.gapSmall) {
                if let count = movement.count, !count.isEmpty {
                    Text(count).font(.subheadline.monospacedDigit()).foregroundStyle(.tint)
                }
                Text(movement.eachSide ? "\(movement.name) · each side" : movement.name).font(.subheadline)
            }
            if let note = movement.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
