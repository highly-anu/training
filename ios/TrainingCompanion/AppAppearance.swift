import SwiftUI

/// App appearance preference.
///
/// The app previously had no appearance handling at all, so it simply followed
/// the system and rendered light. `dark` is the default here: the training
/// surfaces are dense, chart-heavy and dark-first (matching the watch app and
/// the web app's dark theme), and a light background washes out the modality
/// accent colours those views rely on to be readable at a glance.
enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark:   return "Dark"
        case .light:  return "Light"
        case .system: return "System"
        }
    }

    var symbol: String {
        switch self {
        case .dark:   return "moon.fill"
        case .light:  return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// nil means "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }

    /// Storage key, shared by the root view and the settings picker.
    static let storageKey = "appAppearance"

    /// Default for anyone who has never chosen.
    static let fallback: AppAppearance = .dark
}
