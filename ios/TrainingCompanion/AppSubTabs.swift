import SwiftUI

/// The one way a screen splits itself into sub-sections.
///
/// Analytics and Profile had each grown their own: Analytics used a native
/// segmented `Picker` with haptics and a swipeable paged `TabView`, Profile a
/// hand-rolled scrolling row of bordered pills with no haptics and no swipe.
/// Same job, two different languages, and nothing to stop the next screen
/// inventing a third. See §6.8 of `ios/docs/design-system.md` for the rules.
///
/// Conform a sub-section enum to `AppSubTab` and the screen gets the selector
/// pinned under the navigation bar and the selected section beneath it:
///
///     private enum ProfileTab: Int, AppSubTab {
///         case equipment, injuries
///         var label: String { … }
///     }
///
///     AppSubTabScreen(selection: $tab) { tab in
///         switch tab { … }
///     }
protocol AppSubTab: CaseIterable, Hashable, Identifiable {
    /// Shown in the segmented control. Keep it to one word where possible —
    /// a segmented control divides the width evenly and truncates the rest.
    var label: String { get }
}

extension AppSubTab where Self: Hashable {
    var id: Self { self }
}

/// The selector. Native segmented control, so it inherits system styling,
/// Dynamic Type and VoiceOver rather than reimplementing them.
struct AppSubTabPicker<Tab: AppSubTab>: View {
    @Binding var selection: Tab

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(Tab.allCases)) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: selection) { AppHaptics.selection() }
    }
}

/// A whole sectioned screen: the paged content, with the selector pinned
/// under the navigation bar in a `safeAreaBar`, so the content scrolls
/// beneath it, the large title collapses as it does on Today, and the
/// selector gets the system's scroll-edge effect (§6.8).
struct AppSubTabScreen<Tab: AppSubTab, Content: View>: View {
    @Binding var selection: Tab
    @ViewBuilder var content: (Tab) -> Content

    /// False for the screen's first moment. A deep link picks its section
    /// in `onAppear`; a section swapped in while the screen is still
    /// appearing left the bar tracking the discarded one, with the large
    /// title stuck under the scroll-edge blur. Holding the content back
    /// until then means the first section the bar sees is the right one.
    @State private var hasAppeared = false

    var body: some View {
        // The selected section only, not a paged TabView: the navigation
        // bar collapses its large title by watching the screen's scroll
        // view, and a paging container hides it.
        Group {
            if hasAppeared {
                content(selection).id(selection)
            } else {
                Color.clear
            }
        }
        .task { hasAppeared = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaBar(edge: .top) {
            AppSubTabPicker(selection: $selection)
        }
    }
}
