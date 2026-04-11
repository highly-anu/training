import SwiftUI

enum AppAnimation {
    static let springStandard  = Animation.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    static let springSnappy    = Animation.spring(response: 0.35, dampingFraction: 0.86, blendDuration: 0)
    static let springBouncy    = Animation.spring(response: 0.55, dampingFraction: 0.72, blendDuration: 0)
    static let springGentle    = Animation.spring(response: 0.6,  dampingFraction: 0.9,  blendDuration: 0)
    static let layoutChange    = Animation.spring(response: 0.5,  dampingFraction: 0.88)
    static let interactiveDrag = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86, blendDuration: 0.25)
}

enum AppHaptics {
    static func light()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()    { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func rigid()     { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func soft()      { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

enum AppMetrics {
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let swipeThreshold: CGFloat = 80
    static let swipeVelocityThreshold: CGFloat = 400
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
