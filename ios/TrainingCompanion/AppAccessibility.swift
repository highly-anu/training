import SwiftUI

// Accessibility's shared pieces (design-system §6.57). A view writes none of
// these by hand: a small control takes `.appTapTarget()`, a tile of several
// texts that is one fact takes `.appStat(_:)`, a row that acts on a tap takes
// `.appTapRow()`, a status told by colour alone takes a `ColorTwin`, a row of
// tiles that cannot fit at the accessibility sizes is an `AppAdaptiveStack`,
// and a chart says its numbers through `ChartSummary`.

extension View {
    /// The 44 pt minimum, around a glyph that is drawn smaller. The whole
    /// frame takes the tap.
    func appTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    /// A text button in running content, where a 44 pt frame would open a gap:
    /// the tap area grows above and below and nothing moves.
    func appTapSlop(_ slop: CGFloat = 12) -> some View {
        padding(.vertical, slop).contentShape(Rectangle()).padding(.vertical, -slop)
    }

    /// Several texts that are one fact (a value, its unit, its caption) read
    /// as one element in the words given.
    func appStat(_ label: String) -> some View {
        accessibilityElement(children: .ignore).accessibilityLabel(label)
    }

    /// A row that acts on a tap gesture: one element, announced as a button,
    /// and as selected when it is the chosen one of several.
    func appTapRow(selected: Bool = false) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// A chart's numbers for VoiceOver: what it draws as the label, the
    /// summary as its value. Without a summary the label stands alone.
    func appChartSummary(_ label: String, _ summary: String?) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(summary ?? "")
    }
}

/// The symbol that says what a colour says, drawn only when the athlete asked
/// to differentiate without colour (Settings ▸ Accessibility ▸ Display). Sits
/// beside the coloured text or mark; VoiceOver hears the words instead.
struct ColorTwin: View {
    let symbol: String
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        if differentiate {
            Image(systemName: symbol)
                .imageScale(.small)
                .accessibilityHidden(true)
        }
    }
}

/// A row of tiles at the standard sizes, a column at the accessibility sizes,
/// where three numbers side by side would each truncate.
struct AppAdaptiveStack<Content: View>: View {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let layout = size.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}

/// A grid of tiles: the columns asked for at the standard sizes, two (or one,
/// when fewer than three were asked for) at the accessibility sizes.
struct AppAdaptiveGrid<Content: View>: View {
    let columns: Int
    var spacing: CGFloat? = nil
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: Self.count(columns, accessibility: size.isAccessibilitySize)),
                  spacing: spacing) { content }
    }

    nonisolated static func count(_ columns: Int, accessibility: Bool) -> Int {
        guard accessibility else { return max(columns, 1) }
        return columns >= 3 ? 2 : 1
    }
}

/// A unit as VoiceOver should say it: "min" is read as the word, "bpm" letter
/// by letter. Anything not listed is said as written.
enum SpokenUnit {
    nonisolated static func text(_ unit: String) -> String {
        switch unit.lowercased() {
        case "min": return "minutes"
        case "h", "hr", "hrs": return "hours"
        case "s", "sec": return "seconds"
        case "kcal": return "kilocalories"
        case "bpm": return "beats per minute"
        case "km": return "kilometres"
        case "m": return "metres"
        case "/km": return "per kilometre"
        case "kg": return "kilograms"
        default: return unit
        }
    }
}

/// A chart in one sentence. Pure, so the words are tested; the numbers are the
/// ones the chart was given, never recomputed from anything else.
enum ChartSummary {
    /// "Average 142 bpm, from 98 to 171": a recording, where no point is the latest.
    static func range(_ values: [Double], unit: String = "", format: (Double) -> String = whole) -> String? {
        guard let low = values.min(), let high = values.max() else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        if low == high { return "\(format(mean))\(suffix(unit)) throughout" }
        return "Average \(format(mean))\(suffix(unit)), from \(format(low)) to \(format(high))"
    }

    /// "Latest 4 sessions, average 3, from 1 to 5": a series over time.
    static func series(_ values: [Double], unit: String = "", format: (Double) -> String = whole) -> String? {
        guard let last = values.last, let rest = range(values, format: format) else { return nil }
        if values.count == 1 { return "\(format(last))\(suffix(unit))" }
        return "Latest \(format(last))\(suffix(unit)), \(rest.prefix(1).lowercased())\(rest.dropFirst())"
    }

    /// "Zone 2 62 percent, Zone 3 20 percent": shares, largest first, zeros left out.
    static func shares(_ parts: [(name: String, percent: Double)]) -> String? {
        let shown = parts.filter { $0.percent >= 0.5 }.sorted { $0.percent > $1.percent }
        guard !shown.isEmpty else { return nil }
        return shown.map { "\($0.name) \(whole($0.percent)) percent" }.joined(separator: ", ")
    }

    static func whole(_ value: Double) -> String { String(Int(value.rounded())) }
    static func oneDecimal(_ value: Double) -> String { String(format: "%.1f", value) }

    private static func suffix(_ unit: String) -> String { unit.isEmpty ? "" : " \(unit)" }
}
