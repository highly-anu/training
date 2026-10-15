import SwiftUI

// iPhone copy — colours match web app MODALITY_COLORS and the Watch app's ModalityStyle.swift

struct ModalityStyle {
    static func color(for modalityId: String) -> Color {
        switch modalityId {
        case "max_strength":             return Color(red: 0.937, green: 0.267, blue: 0.267) // #ef4444
        case "relative_strength":        return Color(red: 0.957, green: 0.247, blue: 0.369) // #f43f5e
        case "strength_endurance":       return Color(red: 0.976, green: 0.451, blue: 0.086) // #f97316
        case "power":                    return Color(red: 0.918, green: 0.702, blue: 0.031) // #eab308
        case "aerobic_base":             return Color(red: 0.055, green: 0.647, blue: 0.914) // #0ea5e9
        case "anaerobic_intervals":      return Color(red: 0.024, green: 0.714, blue: 0.831) // #06b6d4
        case "mixed_modal_conditioning": return Color(red: 0.545, green: 0.361, blue: 0.965) // #8b5cf6
        case "movement_skill":           return Color(red: 0.078, green: 0.722, blue: 0.651) // #14b8a6
        case "mobility":                 return Color(red: 0.063, green: 0.725, blue: 0.506) // #10b981
        case "durability":               return Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
        case "combat_sport":             return Color(red: 0.925, green: 0.282, blue: 0.600) // #ec4899
        case "rehab":                    return Color(red: 0.518, green: 0.800, blue: 0.086) // #84cc16
        default:                         return .secondary
        }
    }

    static func label(for modalityId: String) -> String {
        switch modalityId {
        case "max_strength":             return "Max Strength"
        case "relative_strength":        return "Relative Strength"
        case "strength_endurance":       return "Strength Endurance"
        case "power":                    return "Power"
        case "aerobic_base":             return "Aerobic Base"
        case "anaerobic_intervals":      return "Anaerobic Intervals"
        case "mixed_modal_conditioning": return "Mixed Modal"
        case "movement_skill":           return "Movement Skill"
        case "mobility":                 return "Mobility"
        case "durability":               return "Durability"
        case "combat_sport":             return "Combat Sport"
        case "rehab":                    return "Rehab"
        default:                         return modalityId.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func icon(for modalityId: String) -> String {
        switch modalityId {
        case "max_strength", "relative_strength": return "figure.strengthtraining.traditional"
        case "strength_endurance":       return "dumbbell.fill"
        case "aerobic_base":             return "figure.run"
        case "anaerobic_intervals":      return "heart.circle.fill"
        case "mixed_modal_conditioning": return "bolt.heart.fill"
        case "power":                    return "bolt.fill"
        case "movement_skill":           return "figure.flexibility"
        case "mobility":                 return "figure.cooldown"
        case "durability":               return "backpack.fill"
        case "combat_sport":             return "figure.boxing"
        case "rehab":                    return "cross.case.fill"
        default:                         return "figure.strengthtraining.traditional"
        }
    }
}

/// The icon for a *recorded* activity, as opposed to a planned modality.
///
/// These are different questions with different answers, and conflating them is
/// what put a runner on every cycling row: a ride infers the `aerobic_base`
/// modality, whose icon is `figure.run`, so the list showed a runner while the
/// detail page — which keyed off the activity type — showed a bike.
///
/// Four screens had each written their own version of this mapping (§6.12 of
/// `ios/docs/design-system.md`), and they disagreed: only two of them knew that
/// "bike" means cycling.
enum ActivityIcon {
    /// The icon for an activity type, or nil when the string names no
    /// particular activity ("workout", "watch_16-Saturday-0", …) and the
    /// caller should fall back to the modality.
    ///
    /// Matches whole words, never substrings. The watch records a session's
    /// archetype name as its activity type ("KB Movement Skill Session
    /// (Wildman)"), and substring matching read "skill" as skiing and
    /// "Weighted Box Step-Ups" as boxing.
    static func forActivityType(_ activityType: String) -> String? {
        let words = activityType.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        func word(_ exact: Set<String>) -> Bool { words.contains { exact.contains($0) } }
        func stem(_ prefixes: String...) -> Bool {
            words.contains { w in prefixes.contains { w.hasPrefix($0) } }
        }

        if word(["kb", "kettlebell", "kettlebells"]) { return AppSymbol.kettlebell }
        if stem("run")                               { return "figure.run" }
        if stem("cycl", "bike", "biking")            { return "figure.outdoor.cycle" }
        if stem("swim")                              { return "figure.pool.swim" }
        if stem("hik")                               { return "figure.hiking" }
        if stem("walk")                              { return "figure.walk" }
        if word(["row", "rowing", "rower", "erg"])   { return "figure.rowing" }
        if word(["ruck", "rucking"])                 { return "figure.hiking" }
        if stem("elliptical")                        { return "figure.elliptical" }
        if stem("yoga")                              { return "figure.yoga" }
        if stem("flexib", "mobility")                { return "figure.flexibility" }
        if stem("strength", "weight", "bodyweight")  { return "figure.strengthtraining.traditional" }
        if word(["core"])                            { return "figure.core.training" }
        if word(["boxing", "kickboxing"])            { return "figure.boxing" }
        if stem("climb")                             { return "figure.climbing" }
        if word(["ski", "skiing", "skier", "skierg"]) { return "figure.skiing.crosscountry" }
        if word(["hiit"]) || stem("interval")        { return "figure.highintensity.intervaltraining" }
        if word(["watch"])                           { return "applewatch.watchface" }
        return nil
    }

    /// What a row or header should show for an imported workout: what the
    /// device recorded, falling back to the modality it was filed under.
    static func forWorkout(activityType: String, modalityId: String?) -> String {
        if let icon = forActivityType(activityType) { return icon }
        if let modalityId { return ModalityStyle.icon(for: modalityId) }
        return "figure.mixed.cardio"
    }
}

/// Symbols the app draws itself, from the asset catalog, for what SF Symbols
/// has no glyph for (design-system §6.12). `kettlebell.symbolset` is written by
/// `ios/tools/make_kettlebell_symbol.py`.
enum AppSymbol {
    static let kettlebell = "kettlebell"
    static let custom: Set<String> = [kettlebell]
}

extension Image {
    /// An icon name from `ActivityIcon` or `ModalityStyle`: one of the app's
    /// own symbols from the asset catalog, any other from SF Symbols.
    /// `Image(systemName:)` draws nothing for a custom name.
    init(symbol name: String) {
        if AppSymbol.custom.contains(name) {
            self.init(name)
        } else {
            self.init(systemName: name)
        }
    }
}
