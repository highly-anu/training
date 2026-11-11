import SwiftUI

// The app's small motions (design-system §7.5, §6.56): a number rolling to its
// new value, a symbol answering a change, a card easing in at the scroll's
// edge, a chart drawing itself once. Each is one modifier here, timed by an
// `AppAnimation` preset and still under Reduce Motion — a view never writes
// `.contentTransition(`, `.symbolEffect(` or `.scrollTransition(` of its own
// (DesignTokenTests).

// MARK: - Numbers

private struct NumericRoll<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    let countsDown: Bool

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: countsDown))
            .animation(AppAnimation.springSnappy, value: value)
    }
}

private struct NumericText: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let countsDown: Bool

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : .numericText(countsDown: countsDown))
    }
}

// MARK: - Symbols

private struct SymbolBounce<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        if reduceMotion { content } else { content.symbolEffect(.bounce, value: value) }
    }
}

private struct SymbolReplace<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .animation(AppAnimation.springSnappy, value: value)
    }
}

private struct SymbolSpin: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    func body(content: Content) -> some View {
        content.symbolEffect(.rotate, options: .repeating, isActive: isActive && !reduceMotion)
    }
}

// MARK: - Scroll

private struct ScrollFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Settled once a third of the card shows: a tall card half on
            // screen is at rest, not mid-transition.
            content.scrollTransition(.interactive.threshold(.visible(0.3)), axis: .vertical) { view, phase in
                view
                    .opacity(1 - 0.35 * abs(phase.value))
                    .scaleEffect(1 - 0.03 * abs(phase.value))
            }
        }
    }
}

/// The children of a screen's card stack, each easing in and out at the
/// scroll's edge (`appScrollFade`). Goes inside the stack, around its cards,
/// so a card added later needs nothing:
///
///     LazyVStack(spacing: 16) { AppScrollFade { readinessCard; sleepCard } }
struct AppScrollFade<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ForEach(subviews: content) { $0.appScrollFade() }
    }
}

// MARK: - Charts

private struct ChartEntry: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drawn: the reveal has run. State of the view, so it runs once.
    @State private var drawn = false
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .mask {
                // Wider than the chart, so an annotation over its edge shows;
                // nothing at all once the reveal is over.
                Rectangle()
                    .padding(settled ? -1000 : -24)
                    .scaleEffect(x: drawn || reduceMotion ? 1 : 0, anchor: .leading)
            }
            .onAppear {
                guard !drawn else { return }
                if reduceMotion { drawn = true; settled = true; return }
                withAnimation(AppAnimation.chartEntry) { drawn = true } completion: { settled = true }
            }
    }
}

extension View {
    /// A number that rolls to its new value. Give it the value it shows.
    func appNumeric<Value: Equatable>(value: Value, countsDown: Bool = false) -> some View {
        modifier(NumericRoll(value: value, countsDown: countsDown))
    }

    /// The roll alone, where the change is already animated by its owner (a
    /// clock's tick).
    func appNumeric(countsDown: Bool = false) -> some View {
        modifier(NumericText(countsDown: countsDown))
    }

    /// A symbol that bounces when the value changes: something was earned.
    func appSymbolBounce<Value: Equatable>(value: Value) -> some View {
        modifier(SymbolBounce(value: value))
    }

    /// One image whose symbol changes with a state (pause / play, linked or
    /// not): the old one is replaced, not swapped.
    func appSymbolReplace<Value: Equatable>(value: Value) -> some View {
        modifier(SymbolReplace(value: value))
    }

    /// A symbol that turns while work runs.
    func appSymbolSpin(isActive: Bool) -> some View {
        modifier(SymbolSpin(isActive: isActive))
    }

    /// A card easing in and out at the scroll's top and bottom edge.
    func appScrollFade() -> some View {
        modifier(ScrollFade())
    }

    /// A chart drawn from its leading edge the first time it appears.
    func appChartEntry() -> some View {
        modifier(ChartEntry())
    }
}
