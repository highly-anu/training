import familiesData from '@shared/commons/modality_families.json'
import type { ModalityId } from '@/api/types'

/**
 * The canonical modality → family grouping, shared with the server.
 *
 * `data/commons/modality_families.json` replaced five divergent copies of this
 * grouping across Python and TypeScript, two of which named modalities that do
 * not exist and all of which dropped combat_sport and rehab. Read it; never
 * re-declare a family list in a component.
 */
export type ModalityFamily = 'strength' | 'aerobic' | 'intervals' | 'durability' | 'skill' | 'combat' | 'other'

const FAMILIES = familiesData.families as Record<Exclude<ModalityFamily, 'other'>, string[]>
const LABELS = familiesData.labels as Record<string, string>

const INDEX: Record<string, ModalityFamily> = {}
for (const [family, ids] of Object.entries(FAMILIES)) {
  for (const id of ids) INDEX[id] = family as ModalityFamily
}

export function familyOf(modality: ModalityId | string | null | undefined): ModalityFamily {
  return INDEX[modality ?? ''] ?? 'other'
}

export function familyLabel(family: ModalityFamily): string {
  return LABELS[family] ?? family
}

export function isStrength(modality: ModalityId | string | null | undefined): boolean {
  return familyOf(modality) === 'strength'
}
