import SwiftUI

/// The analytics card: an uppercase caption header over content, on the
/// secondary background with the app's card radius (design-system §6.15).
/// Overview and Recovery each carried a private copy of this; the Program
/// section is the third user, which is the §1.7 threshold for extracting it.
/// The header may carry a trailing view — a status badge — so a card's
/// verdict sits beside its name rather than on a row of its own.
struct AnalyticsCard<Content: View, Trailing: View>: View {
    let header: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(header: String, @ViewBuilder content: @escaping () -> Content) where Trailing == EmptyView {
        self.header = header
        self.trailing = { EmptyView() }
        self.content = content
    }

    init(header: String, @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(header)
                    .font(.footnote).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .lineLimit(2)
                Spacer(minLength: 0)
                trailing()
            }
            content()
        }
        .padding(AppMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardCornerRadius))
    }
}

/// A summary card that opens its detail screen (design-system §6.37) — the
/// iPhone's form of "more on this": not a flip to the back of the card, a level
/// down. The whole card is the link, a chevron follows the header's badge, and
/// VoiceOver hears where it goes. What the card shows is the summary state;
/// the chart, the rows and the About section are the destination's.
struct AnalyticsDetailCard<Content: View, Trailing: View, Destination: View>: View {
    let header: String
    /// Where the card goes, for VoiceOver: "Opens Load on the bar".
    let hint: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let content: () -> Content

    init(header: String, hint: String,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder destination: @escaping () -> Destination,
         @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.hint = hint
        self.trailing = trailing
        self.destination = destination
        self.content = content
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            AnalyticsCard(header: header) {
                HStack(spacing: 8) {
                    trailing()
                    Image(systemName: "chevron.right")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            } content: {
                content()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}

extension AnalyticsDetailCard where Trailing == EmptyView {
    init(header: String, hint: String,
         @ViewBuilder destination: @escaping () -> Destination,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(header: header, hint: hint, trailing: { EmptyView() },
                  destination: destination, content: content)
    }
}

/// A symbol and its words side by side at the system's small spacing,
/// wherever the label sits. Inside a `List`, a `Label` gets an icon column —
/// the symbol in a fixed-width slot, the words far from it — and
/// `.titleAndIcon` does not undo it ("◎     120kg"). For a label that is
/// part of a row's content: a badge, a target, a trend, a reading.
struct InlineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == InlineLabelStyle {
    static var inline: InlineLabelStyle { InlineLabelStyle() }
}

/// A small capsule in one colour: a 15 % fill, the colour's text and symbol,
/// and — `bordered` — a 35 % ring (design-system §3.1's badge). The modality
/// badge, a linked session's chip, a status and a training effect are all
/// this; each screen used to restyle its own.
struct TintCapsule: View {
    let text: String
    var symbol: String? = nil
    let color: Color
    var bordered: Bool = false

    var body: some View {
        Group {
            if let symbol {
                Label(text, systemImage: symbol).labelStyle(.inline)
            } else {
                Text(text)
            }
        }
        .font(.caption2).fontWeight(.semibold)
        .lineLimit(1)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay {
            if bordered { Capsule().stroke(color.opacity(0.35), lineWidth: 1) }
        }
    }
}
