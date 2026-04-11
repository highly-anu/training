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
