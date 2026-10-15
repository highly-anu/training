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

/// A whole sectioned screen: the selected section, with the selector pinned
/// under the navigation bar, so the large title collapses as it does on Today
/// and the selector rides up under the inline title (§6.8).
struct AppSubTabScreen<Tab: AppSubTab, Content: View>: View {
    @Binding var selection: Tab
    @ViewBuilder var content: (Tab) -> Content
    /// How far a pull-to-refresh has dragged the section past its top.
    @State private var pull: CGFloat = 0

    var body: some View {
        // The selected section only, not a paged TabView: the navigation
        // bar collapses its large title by watching the screen's scroll
        // view, and a paging container hides it.
        content(selection)
            .id(selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Read from the section's scroll view, whichever kind it is.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, overscroll in
                pull = overscroll
            }
            // An inset, moved down by the pull so it follows the large title
            // the way Today's header does. Not the bar's `largeSubtitle`
            // slot: over a List or Form section that slot takes no touches
            // at all (Log, Profile; 1.1.1). Not a `safeAreaBar`: it left
            // List sections' titles blurred with nothing scrolled.
            .safeAreaInset(edge: .top, spacing: 0) {
                AppSubTabPicker(selection: $selection)
                    .offset(y: pull)
            }
    }
}
