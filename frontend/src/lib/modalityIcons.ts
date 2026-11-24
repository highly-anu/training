import { Dumbbell, type LucideIcon } from 'lucide-react'
import { MODALITY_DISPLAY } from '@/lib/gen/clientVocab'
import { servedIconName } from '@/lib/modalityColors'

/** A modality's icon on the web: the lucide counterpart of the phone's
 *  `ModalityStyle.icon(for:)` SF Symbol, both from the modality's file
 *  (data/commons/modalities, `display.icon`; tools/gen_client_vocab.py), so
 *  both clients draw a modality alike. Tint it with the modality's colour
 *  (frontend-design §8.1). */
export const MODALITY_ICONS: Record<string, LucideIcon> = Object.fromEntries(
  Object.entries(MODALITY_DISPLAY).map(([id, d]) => [id, d.icon]),
)

/** The icons the build carries, by the name a modality file writes
 *  (`display.icon.web`): a method's own modality takes one of these — as its
 *  tint is one of the commons' — and the dumbbell for a name the build lacks. */
const BY_NAME: Record<string, LucideIcon> = Object.fromEntries(
  Object.values(MODALITY_DISPLAY).map((d) => [d.icon.displayName ?? '', d.icon]),
)

export function modalityIcon(id: string | null | undefined): LucideIcon {
  if (!id) return Dumbbell
  return MODALITY_ICONS[id] ?? BY_NAME[servedIconName(id) ?? ''] ?? Dumbbell
}
