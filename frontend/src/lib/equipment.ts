import type { EquipmentId } from '@/api/types'
import { EQUIPMENT_GROUPS as GROUPS, EQUIPMENT_LABELS, EQUIPMENT_SECTIONS } from '@/lib/gen/clientVocab'

// The equipment an athlete can declare: the one list in
// data/commons/constraints/equipment.yaml, through tools/gen_client_vocab.py,
// which writes the phone's and the four schemas' copies from the same data.
// Open space is always assumed, so no picker offers it.

export interface EquipmentGroup {
  name: string
  items: { id: EquipmentId; label: string }[]
}

/** The pickers' groups: the builder's EquipmentPicker and Explore ▸ Equipment. */
export const EQUIPMENT_GROUPS: EquipmentGroup[] = GROUPS.map((g) => ({
  name: g.name,
  items: g.items.map((id) => ({ id, label: EQUIPMENT_LABELS[id] })),
}))

export function equipmentLabel(id: string): string {
  return EQUIPMENT_LABELS[id as EquipmentId] ?? id.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase())
}

// Equipment by section, each in the colour of the training it serves: Profile ▸
// Equipment's sections and the builder's constraints form, and the colour of
// an item wherever else it appears (Explore ▸ Philosophies' Requirements).
export const EQUIPMENT_CATEGORIES: { name: string; color: string; items: EquipmentId[] }[] =
  EQUIPMENT_SECTIONS.map((s) => ({ name: s.name, color: s.hex, items: s.items }))

const CATEGORY_HEX: Record<string, string> = Object.fromEntries(
  EQUIPMENT_CATEGORIES.flatMap((c) => c.items.map((id) => [id, c.color])),
)

/** The colour of the section Profile ▸ Equipment files an item under; undefined
 *  for an id it does not list. */
export function equipmentHex(id: string): string | undefined {
  return CATEGORY_HEX[id]
}
