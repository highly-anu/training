import {
  Accessibility, Activity, Backpack, Cross, Dumbbell, Footprints, HeartPulse, PersonStanding, Swords,
  Weight, Zap, type LucideIcon,
} from 'lucide-react'

/** A modality's icon on the web: the lucide counterpart of the phone's
 *  `ModalityStyle.icon(for:)` SF Symbol, so both clients draw a modality
 *  alike. Tint it with the modality's colour (frontend-design §8.1). */
export const MODALITY_ICONS: Record<string, LucideIcon> = {
  max_strength: Dumbbell,             // figure.strengthtraining.traditional
  relative_strength: Dumbbell,
  strength_endurance: Weight,         // dumbbell.fill
  aerobic_base: Footprints,           // figure.run
  anaerobic_intervals: HeartPulse,    // heart.circle.fill
  mixed_modal_conditioning: Activity, // bolt.heart.fill
  power: Zap,                         // bolt.fill
  movement_skill: PersonStanding,     // figure.flexibility
  mobility: Accessibility,            // figure.cooldown
  durability: Backpack,               // backpack.fill
  combat_sport: Swords,               // figure.boxing
  rehab: Cross,                       // cross.case.fill
}

export function modalityIcon(id: string | null | undefined): LucideIcon {
  return (id && MODALITY_ICONS[id]) || Dumbbell
}
