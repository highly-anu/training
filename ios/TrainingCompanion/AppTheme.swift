import SwiftUI
import UIKit

// The app's colour and type tokens (design-system §2, §4). A view names what a
// colour means — complete, warning, a card's surface — and never a literal:
// `Color(red:` belongs to this file and to the generated ClientVocab alone,
// and `.font(.system(size:` to AppFont (DesignTokenTests holds both).
//
// What is *not* here, because the colour is the information and has its own
// owner: modality and phase-kind colours (ClientVocab, generated from the
// commons), heart-rate zones (HRZoneStyle) and an analytics status
// (AnalyticsStatusStyle).

// MARK: - Colour

enum AppColor {

    // MARK: Brand

    /// Amber, from the AccentColor asset: #C97D15 on dark, #A8650F on light,
    /// where the brand amber reads 3.3:1 on white and the darker one 4.6:1.
    static let accent = Color.accentColor

    // MARK: Surfaces

    /// A card on the page.
    static let surface = Color(uiColor: .secondarySystemBackground)
    /// A row or card inside a grouped list or form.
    static let surfaceGrouped = Color(uiColor: .secondarySystemGroupedBackground)
    /// A control or chip inside a card: one step up from the card.
    static let surfaceRaised = Color(uiColor: .tertiarySystemBackground)
    /// A hairline between or around surfaces.
    static let separator = Color(uiColor: .separator)

    // MARK: Status

    /// Done, saved, linked, on track. Emerald (#10B981), the web's completion
    /// colour; never the tint, so "done" reads apart from "tap me".
    static let complete = Color(red: 0.063, green: 0.725, blue: 0.506)
    /// Needs attention but nothing failed: behind, partial, a compromise.
    static let warning = Color.orange
    /// Weaker than a warning: a mild flag, a middling reading.
    static let caution = Color.yellow
    /// A failure, or an action that removes something.
    static let destructive = Color.red
    /// Neutral information that still wants a colour of its own.
    static let info = Color.blue

    // MARK: Opacity scale (§2.2)

    /// How strongly a colour is laid over a surface. A tint behind content, a
    /// fill for a badge, a border — each one step, so two cards tinted with
    /// different colours weigh the same.
    enum Opacity {
        /// A card washed with its colour.
        static let tint = 0.08
        /// A badge or chip's fill.
        static let fill = 0.12
        /// A stronger fill: a selected chip, a bar's track.
        static let fillStrong = 0.2
        /// A coloured border.
        static let border = 0.35
        /// A ghost: disabled, not yet reached, behind the data.
        static let ghost = 0.5
        /// De-emphasised but still read.
        static let muted = 0.75
    }

    // MARK: Palettes

    /// Training effect, mild to hard (the workout screens' label).
    enum Effect {
        static let maintenance = Color(red: 0.078, green: 0.722, blue: 0.651)   // teal
        static let base = Color(red: 0.055, green: 0.647, blue: 0.914)          // sky
        static let aerobic = Color(red: 0.063, green: 0.725, blue: 0.506)       // emerald
        static let threshold = Color(red: 0.976, green: 0.451, blue: 0.086)     // orange
        static let hard = Color(red: 0.937, green: 0.267, blue: 0.267)          // red
    }

    /// Five hues cycled in block order, the web's `lib/developmentShaping.ts`.
    static let blocks: [Color] = [
        Color(red: 0.39, green: 0.40, blue: 0.95),   // indigo
        Color(red: 0.06, green: 0.73, blue: 0.51),   // emerald
        Color(red: 0.96, green: 0.62, blue: 0.04),   // amber
        Color(red: 0.93, green: 0.28, blue: 0.60),   // pink
        Color(red: 0.05, green: 0.65, blue: 0.91),   // sky
    ]

    /// Sleep stages, for the chart and Last Night's row.
    enum Sleep {
        static let deep = Color(red: 0.2, green: 0.2, blue: 0.7)
        static let rem = Color(red: 0.4, green: 0.3, blue: 0.8)
        static let light = Color(red: 0.45, green: 0.65, blue: 0.9)
        static let awake = Color(red: 0.8, green: 0.7, blue: 0.4)
    }

    /// The weekly schedule's session lengths (Profile ▸ Schedule).
    enum Schedule {
        static let rest = Color(uiColor: .systemGray3)
        static let short = Color.yellow
        static let long = Color(red: 0.36, green: 0.77, blue: 0.96)
        static let mobility = Color(red: 0.67, green: 0.44, blue: 0.96)
    }
}

// MARK: - Type

/// The sizes the text styles do not have. Everything else is a text style
/// (`.headline`, `.subheadline`, `.caption`…), which scales with Dynamic Type
/// by itself. `hero` and `symbol` are fixed: a 160 pt clock is already as
/// large as the screen allows.
enum AppFont {

    /// The one number a screen is about: the player's clock, a rest countdown.
    /// `size` is its size at the default text size.
    static func hero(_ size: CGFloat = 72) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// A card's lead number (readiness, a score).
    static let metric = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()

    /// The same in a tile a third of the screen wide (Today's summary row).
    static let metricCompact = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()

    /// A symbol standing alone as an illustration: an empty state, a result.
    static func symbol(_ size: CGFloat = 48) -> Font { .system(size: size) }

    /// The smallest text the app sets: a chart's tick, a chip's label. 11 pt
    /// at the default size — nothing is set smaller.
    static let micro = Font.caption2
    static let microStrong = Font.caption2.weight(.semibold)

    /// Fixed-pitch text for a log or an identifier.
    static let mono = Font.system(.caption2, design: .monospaced)
}
