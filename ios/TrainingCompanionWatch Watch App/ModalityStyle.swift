import SwiftUI

struct ModalityStyle {
    // Colours match the web app's MODALITY_COLORS (modalityColors.ts) hex values exactly.
    static func color(for modalityId: String) -> Color {
        switch modalityId {
        case "max_strength":             return Color(red: 0.937, green: 0.267, blue: 0.267) // #ef4444 red-500
        case "relative_strength":        return Color(red: 0.957, green: 0.247, blue: 0.369) // #f43f5e rose-500
        case "strength_endurance":       return Color(red: 0.976, green: 0.451, blue: 0.086) // #f97316 orange-500
        case "power":                    return Color(red: 0.918, green: 0.702, blue: 0.031) // #eab308 yellow-500
        case "aerobic_base":             return Color(red: 0.055, green: 0.647, blue: 0.914) // #0ea5e9 sky-500
        case "anaerobic_intervals":      return Color(red: 0.024, green: 0.714, blue: 0.831) // #06b6d4 cyan-500
        case "mixed_modal_conditioning": return Color(red: 0.545, green: 0.361, blue: 0.965) // #8b5cf6 violet-500
        case "kettlebell":               return Color(red: 0.545, green: 0.361, blue: 0.965) // violet (no web entry — matches mixed_modal)
        case "movement_skill":           return Color(red: 0.078, green: 0.722, blue: 0.651) // #14b8a6 teal-500
        case "mobility":                 return Color(red: 0.063, green: 0.725, blue: 0.506) // #10b981 emerald-500
        case "durability":               return Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b amber-500
        case "combat_sport":             return Color(red: 0.925, green: 0.282, blue: 0.600) // #ec4899 pink-500
        case "rehab":                    return Color(red: 0.518, green: 0.800, blue: 0.086) // #84cc16 lime-500
        default:                         return .secondary
        }
    }

    static func icon(for modalityId: String) -> String {
        switch modalityId {
        case "max_strength", "relative_strength": return "figure.strengthtraining.traditional"
        case "aerobic_base":        return "figure.run"
        case "anaerobic_intervals": return "heart.circle"
        case "kettlebell":          return "dumbbell"
        case "movement_skill":      return "figure.flexibility"
        case "mobility":            return "figure.cooldown"
        case "durability":          return "backpack"
        case "mixed_modal_conditioning": return "bolt.heart"
        case "power":               return "bolt.fill"
        case "combat_sport":        return "figure.boxing"
        default:                    return "figure.strengthtraining.traditional"
        }
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
