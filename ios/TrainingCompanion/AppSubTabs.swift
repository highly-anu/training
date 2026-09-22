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
/// and the paged content for free:
///
///     private enum ProfileTab: Int, AppSubTab {
///         case equipment, injuries
///         var label: String { … }
///     }
///
///     AppSubTabPicker(selection: $tab)
///     AppSubTabContent(selection: $tab) { tab in
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
        .onChange(of: selection) { _ in AppHaptics.selection() }
    }
}

/// The content pane beneath it. A paged `TabView` so the sections can also be
/// swiped between — the selector is not the only way to move.
struct AppSubTabContent<Tab: AppSubTab, Content: View>: View {
    @Binding var selection: Tab
    @ViewBuilder var content: (Tab) -> Content

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(Tab.allCases)) { tab in
                content(tab).tag(tab)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(AppAnimation.springStandard, value: selection)
    }
}
