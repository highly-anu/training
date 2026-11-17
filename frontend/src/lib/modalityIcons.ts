import { Dumbbell, type LucideIcon } from 'lucide-react'
import { MODALITY_DISPLAY } from '@/lib/gen/clientVocab'

/** A modality's icon on the web: the lucide counterpart of the phone's
 *  `ModalityStyle.icon(for:)` SF Symbol, both from the modality's file
 *  (data/commons/modalities, `display.icon`; tools/gen_client_vocab.py), so
 *  both clients draw a modality alike. Tint it with the modality's colour
 *  (frontend-design §8.1). */
export const MODALITY_ICONS: Record<string, LucideIcon> = Object.fromEntries(
  Object.entries(MODALITY_DISPLAY).map(([id, d]) => [id, d.icon]),
)

export function modalityIcon(id: string | null | undefined): LucideIcon {
  return (id && MODALITY_ICONS[id]) || Dumbbell
}
