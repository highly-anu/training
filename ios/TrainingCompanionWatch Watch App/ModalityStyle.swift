import SwiftUI

struct ModalityStyle {
    // Colours and icons from the modality's file (data/commons/modalities,
    // `display`) through tools/gen_client_vocab.py — the watch's own icon, the
    // phone's colour. `kettlebell` is no modality: a session the watch tints by
    // its implement.
    static func color(for modalityId: String) -> Color {
        if modalityId == "kettlebell" { return color(for: "mixed_modal_conditioning") }
        return ClientVocab.modalities[modalityId].map { ClientVocab.color($0.hex) } ?? .secondary
    }

    static func icon(for modalityId: String) -> String {
        if modalityId == "kettlebell" { return "dumbbell" }
        return ClientVocab.modalities[modalityId]?.watchIcon ?? "figure.strengthtraining.traditional"
    }

    static func slotTypeIcon(for slotType: String) -> String {
        switch slotType {
        case "sets_reps":       return "dumbbell.fill"
        case "time_domain":     return "clock.fill"
        case "emom":            return "timer"
        case "amrap":           return "arrow.clockwise"
        case "for_time":        return "flag.checkered"
        case "distance":        return "map.fill"
        case "static_hold":     return "pause.circle.fill"
        case "skill_practice":  return "sparkles"
        case "amrap_movement":  return "repeat"
        default:                return "dumbbell.fill"
        }
    }
}

/// What a session leads with: its workout icon (the server's `icon`, the same
/// the phone and the Garmin draw), else its modality icon; tinted with the
/// modality colour either way.
enum SessionIcon {
    static func symbol(icon: String?, modality: String) -> String {
        if let icon, AppSymbol.custom.contains(icon) { return icon }
        return ModalityStyle.icon(for: modality)
    }
}
