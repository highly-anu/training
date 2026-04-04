import SwiftUI

struct ModalityStyle {
    static func color(for modalityId: String) -> Color {
        switch modalityId {
        case "max_strength", "relative_strength", "combat_sport": return .red
        case "strength_endurance":  return .orange
        case "power":               return .yellow
        case "aerobic_base":        return .green
        case "anaerobic_intervals": return .mint
        case "mixed_modal_conditioning": return .cyan
        case "kettlebell":          return .indigo
        case "movement_skill":      return .purple
        case "mobility":            return .teal
        case "durability":          return .brown
        default:                    return .secondary
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
