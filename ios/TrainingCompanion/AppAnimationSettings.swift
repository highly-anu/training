import SwiftUI

/// The app's motion (design-system §7). Three springs, and nothing else:
/// a view never writes `withAnimation {` or a curve of its own
/// (DesignTokenTests). With Reduce Motion on every preset is a short
/// crossfade — decided here, so no caller has to ask.
enum AppAnimation {
    /// State changing in place: a card expanding, a selection moving.
    static var springStandard: Animation {
        reduced ?? .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    }
    /// A small, quick answer to a tap: a toggle, a chip, a tab.
    static var springSnappy: Animation {
        reduced ?? .spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0)
    }
    /// Content arriving, leaving or moving in a list.
    static var layoutChange: Animation {
        reduced ?? .spring(response: 0.5, dampingFraction: 0.88)
    }

    /// The crossfade that stands in for every spring under Reduce Motion,
    /// and the app's one non-spring: content fading in once it has loaded.
    static let crossfade = Animation.easeInOut(duration: 0.2)

    /// A clock's hand between two seconds: a countdown ring. Linear because
    /// time is.
    static let tick = Animation.linear(duration: 1)

    /// A chart drawing itself the first time it appears (`appChartEntry`):
    /// slower than a state change and without overshoot — a line that bounced
    /// past its last point would show a value that is not there.
    static var chartEntry: Animation {
        reduced ?? .spring(response: 0.7, dampingFraction: 1)
    }

    /// A placeholder's pulse while its screen loads (§7.3); never run under
    /// Reduce Motion.
    static let shimmer = Animation.easeInOut(duration: 0.9)

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private static var reduced: Animation? { reduceMotion ? crossfade : nil }
}

enum AppHaptics {
    static func light()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()    { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func rigid()     { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func soft()      { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning()   { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()     { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

/// Pull-to-refresh with one contract (design system §7): a light haptic when
/// the gesture triggers, the spinner shown for at least 600 ms so a fast reply
/// never flashes it, and a success haptic when the work is done. Every
/// `.refreshable` goes through here so no screen has to remember the recipe.
enum AppRefresh {
    static let minimumDisplayNanoseconds: UInt64 = 600_000_000

    static func perform(_ work: () async -> Void) async {
        AppHaptics.light()
        async let delay: () = Task.sleep(nanoseconds: minimumDisplayNanoseconds)
        await work()
        _ = try? await delay
        AppHaptics.success()
    }
}

/// Spacing and radii (design-system §5). A view takes a step of the scale,
/// never a number of its own.
enum AppMetrics {
    // Gaps: between and inside elements.
    /// 4 — an icon and its label, a title and its caption.
    static let gapTight: CGFloat = 4
    /// 8 — rows inside a card, chips in a row.
    static let gapSmall: CGFloat = 8
    /// 12 — cards in a stack, a compact card's padding.
    static let gapMedium: CGFloat = 12
    /// 16 — the page's margin, a card's padding.
    static let gapLarge: CGFloat = 16
    /// 24 — between a screen's sections.
    static let gapSection: CGFloat = 24

    // Radii.
    /// 6 — a chip, a badge, a bar.
    static let radiusChip: CGFloat = 6
    /// 10 — a control: a field, a small button, a thumbnail.
    static let radiusControl: CGFloat = 10
    /// 12 — a row that stands alone, a card inside a card.
    static let radiusRow: CGFloat = 12
    /// 16 — a card.
    static let radiusCard: CGFloat = 16

    static let cardCornerRadius: CGFloat = radiusCard
    static let cardPadding: CGFloat = gapLarge
    static let cardPaddingCompact: CGFloat = gapMedium
    /// The smallest thing a finger is asked to hit.
    static let minTapTarget: CGFloat = 44
    static let swipeThreshold: CGFloat = 80
    static let swipeVelocityThreshold: CGFloat = 400

    /// Width of the screen the app's window scene is on — `UIScreen.main`
    /// is deprecated in iOS 26.
    static var screenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.width ?? 390
    }
}

struct AppTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(.accentColor)
    }
}

extension View {
    func appTabStyle() -> some View { modifier(AppTabStyle()) }
}
