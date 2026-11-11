import SwiftUI

// How a screen arrives (design-system §6.48): a sheet's height by what it
// holds, a step inside a sheet as a push, and a detail screen growing out of
// the row or card that opened it.

// MARK: - Sheet heights

/// How tall a sheet opens. A sheet without one is full height: a flow (the
/// builder, a preview) or a screen in its own right (a session, a workout).
enum AppSheetSize {
    /// A short choice with nothing to type: half height, and no taller.
    case compact
    /// Reference, a short list or a small form: half height, and the athlete
    /// may pull it up — the keyboard does when a field takes focus.
    case flexible
}

extension View {
    /// The sheet's height and its grabber. On the sheet's own content, never
    /// on a screen that is pushed.
    func appSheet(_ size: AppSheetSize) -> some View {
        presentationDetents(size == .compact ? [.medium] : [.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

// MARK: - A step inside a sheet

private struct AppPush<Item, Destination: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder let destination: (Item) -> Destination
    /// The screen keeps its content while it slides away, after `item` is nil.
    @State private var shown: Item?

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            )) {
                if let value = item ?? shown { destination(value) }
            }
            .onChange(of: item != nil) { if let item { shown = item } }
    }
}

extension View {
    /// Pushes a screen while `item` is set. Inside a sheet that owns a
    /// `NavigationStack`, a further step (an exercise's reference, a swap) is
    /// a push with a Back button, never a sheet on the sheet.
    func appPush<Item, Destination: View>(
        item: Binding<Item?>, @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        modifier(AppPush(item: item, destination: destination))
    }
}

// MARK: - Zoom

private struct AppZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace a screen's rows and the screens they open share.
    var appZoomNamespace: Namespace.ID? {
        get { self[AppZoomNamespaceKey.self] }
        set { self[AppZoomNamespaceKey.self] = newValue }
    }
}

private struct AppZoomSource<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.appZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct AppZoomDestination<ID: Hashable>: ViewModifier {
    let id: ID?
    let namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Under Reduce Motion the system's own slide or cover, which it
        // already crossfades.
        if let id, let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

extension View {
    /// The screen that owns the rows: one namespace for them and what they open.
    func appZoomScope(_ namespace: Namespace.ID) -> some View {
        environment(\.appZoomNamespace, namespace)
    }

    /// The row or card a detail screen grows out of.
    func appZoomSource<ID: Hashable>(_ id: ID) -> some View {
        modifier(AppZoomSource(id: id))
    }

    /// The screen that grows out of the source with the same id: on the
    /// content of a sheet, a cover or a pushed destination.
    func appZoom<ID: Hashable>(from id: ID?, in namespace: Namespace.ID?) -> some View {
        modifier(AppZoomDestination(id: id, namespace: namespace))
    }
}
