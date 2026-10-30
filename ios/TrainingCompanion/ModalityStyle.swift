import SwiftUI

// A modality's colour, label and icon, the same on every client: its file in
// data/commons/modalities (`display`), through tools/gen_client_vocab.py into
// ClientVocab.swift — the web, the widgets and the watch read the same data.

struct ModalityStyle {
    static func color(for modalityId: String) -> Color {
        ClientVocab.modalities[modalityId].map { ClientVocab.color($0.hex) } ?? .secondary
    }

    static func label(for modalityId: String) -> String {
        ClientVocab.modalities[modalityId]?.label
            ?? modalityId.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func icon(for modalityId: String) -> String {
        ClientVocab.modalities[modalityId]?.icon ?? "figure.strengthtraining.traditional"
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

/// What a planned session leads with (design-system §6.40): its workout icon
/// — what its main exercise is, from the server's `icon` — tinted with its
/// modality's colour; a session without one keeps its modality icon.
enum SessionIcon {
    static func symbol(icon: String?, modality: String) -> String {
        if let icon, AppSymbol.custom.contains(icon) { return icon }
        return ModalityStyle.icon(for: modality)
    }
}
