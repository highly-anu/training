import SwiftUI

// MARK: - Card

/// The app's one card surface (design-system §6.15): the secondary background
/// at the card radius, padded. Every card is this — Today's, Program's and
/// Profile's each drew their own at 10, 12 and 14 pt until 1.35.
///
/// - `compact`: 12 pt of padding, for a card that is one row of a stack.
/// - `border`: a ring in the card's colour, for a card whose colour is its
///   state (readiness, adherence, a pending suggestion).
/// - `tint`: the card washed with a colour (a completed session).
struct AppCardSurface: ViewModifier {
    var compact = false
    var border: Color? = nil
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppMetrics.radiusCard, style: .continuous)
        content
            .padding(compact ? AppMetrics.cardPaddingCompact : AppMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(.background.secondary)
                    if let tint { shape.fill(tint.opacity(AppColor.Opacity.tint)) }
                }
            }
            .clipShape(shape)
            .overlay {
                if let border {
                    shape.strokeBorder(border.opacity(AppColor.Opacity.border), lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Lays the view on the app's card surface. See `AppCardSurface`.
    func appCard(compact: Bool = false, border: Color? = nil, tint: Color? = nil) -> some View {
        modifier(AppCardSurface(compact: compact, border: border, tint: tint))
    }
}

/// A card with an uppercase caption header over its content. The header may
/// carry a trailing view — a status badge — so a card's verdict sits beside
/// its name rather than on a row of its own. A card without a header is the
/// `appCard()` modifier on its content.
struct AppCard<Content: View, Trailing: View>: View {
    let header: String
    var compact = false
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(header: String, compact: Bool = false,
         @ViewBuilder content: @escaping () -> Content) where Trailing == EmptyView {
        self.header = header
        self.compact = compact
        self.trailing = { EmptyView() }
        self.content = content
    }

    init(header: String, compact: Bool = false,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.compact = compact
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: AppMetrics.gapSmall) {
                Text(header)
                    .font(.footnote).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                trailing()
            }
            content()
        }
        .appCard(compact: compact)
    }
}

/// A group's name above its cards, styled as an inset list's section header
/// and aligned with the cards' text — not a card: it says what follows,
/// nothing of its own. The same type as a card's header, so a label above
/// cards and a header inside one read as one voice.
struct SectionLabel: View {
    let text: String
    /// Inset to the cards' text (the default), or flush with their edge.
    var inset = true

    init(_ text: String, inset: Bool = true) {
        self.text = text
        self.inset = inset
    }

    init(text: String) { self.init(text) }

    var body: some View {
        Text(text)
            .font(.footnote).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, inset ? AppMetrics.cardPadding : 0)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons

/// The app's buttons (design-system §6.46). One family, by what the button
/// does — not a style picked per screen:
///
/// - `primary`: the screen's one main action (Start workout, Save).
/// - `secondary`: everything beside it.
/// - `destructive`: removes or discards.
/// - `complete`: confirms something as done — emerald, as completion is.
enum AppButtonKind {
    case primary, secondary, destructive, complete
}

private struct AppButtonModifier: ViewModifier {
    let kind: AppButtonKind
    @Environment(\.appButtonsFloat) private var floats

    func body(content: Content) -> some View {
        if floats {
            // Over content (an action bar, the player's controls): glass, the
            // one place a button is not a solid fill (§6.47).
            switch kind {
            case .primary:
                content.buttonStyle(.glassProminent)
            case .secondary:
                content.buttonStyle(.glass)
            case .destructive:
                content.buttonStyle(.glass).tint(AppColor.destructive)
            case .complete:
                content.buttonStyle(.glassProminent).tint(AppColor.complete)
            }
        } else {
            switch kind {
            case .primary:
                content.buttonStyle(.borderedProminent)
            case .secondary:
                content.buttonStyle(.bordered)
            case .destructive:
                content.buttonStyle(.bordered).tint(AppColor.destructive)
            case .complete:
                content.buttonStyle(.borderedProminent).tint(AppColor.complete)
            }
        }
    }
}

extension View {
    /// Styles a button as one of the app's kinds. See `AppButtonKind`.
    func appButton(_ kind: AppButtonKind) -> some View {
        modifier(AppButtonModifier(kind: kind))
    }
}

// MARK: - Floating controls

extension EnvironmentValues {
    /// Whether `appButton` draws glass: true inside an action bar and the
    /// player's controls, which float over content.
    @Entry var appButtonsFloat = false
}

/// The buttons that float over a screen's content (design-system §6.47): the
/// app's kinds drawn in glass, grouped so neighbouring buttons blend. Content
/// scrolls beneath; the group itself has no background.
struct AppFloatingControls<Content: View>: View {
    var spacing: CGFloat = AppMetrics.gapSmall
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            VStack(spacing: spacing) { content() }
        }
        .environment(\.appButtonsFloat, true)
    }
}

extension View {
    /// A screen's bottom action bar: its buttons in glass over the content,
    /// which fades out beneath them. One per screen, for the screen's main
    /// action and at most one beside it.
    func appActionBar<Bar: View>(@ViewBuilder _ bar: @escaping () -> Bar) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) {
            AppFloatingControls(content: bar)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, AppMetrics.gapSmall)
        }
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
    /// The detail grows out of the card (§6.48).
    @Namespace private var zoom

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
            destination().appZoom(from: "card", in: zoom)
        } label: {
            AppCard(header: header) {
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
            .matchedTransitionSource(id: "card", in: zoom)
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

/// A small capsule in one colour: a 12 % fill, the colour's text and symbol,
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
        .background(color.opacity(AppColor.Opacity.fill))
        .foregroundStyle(color)
        .clipShape(Capsule())
        .overlay {
            if bordered { Capsule().stroke(color.opacity(AppColor.Opacity.border), lineWidth: 1) }
        }
    }
}
