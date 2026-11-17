import type { EquipmentId } from '@/api/types'
import { EQUIPMENT_GROUPS as GROUPS, EQUIPMENT_LABELS, EQUIPMENT_SECTIONS } from '@/lib/gen/clientVocab'
import { NEUTRAL_HEX } from '@/lib/dataColors'

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

function words(id: string): string {
  return id.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase())
}

export function equipmentLabel(id: string): string {
  return EQUIPMENT_LABELS[id as EquipmentId] ?? served[id] ?? words(id)
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

// A package may bring implements of its own (its vocabulary.yaml; roadmap
// 20.7), which no build knows: the server lists them with the commons'
// (GET /api/equipment, each with its `package`), and they are kept here so a
// label is the package's word, not the id's.
const served: Record<string, string> = {}

/** The section and group the pickers file a package's implements under. */
export const PACKAGE_EQUIPMENT = 'From your packages'
const PACKAGE_EQUIPMENT_HEX = NEUTRAL_HEX

export interface ServedEquipment {
  id: string
  label?: string
  package?: string
}

/** The implements of the served list that a package brings, labelled and
 *  remembered for `equipmentLabel`. */
export function packageEquipment(list: ServedEquipment[] | undefined): { id: EquipmentId; label: string }[] {
  const own = (list ?? []).filter((e) => e.package && !(e.id in EQUIPMENT_LABELS))
  for (const e of own) served[e.id] = e.label ?? words(e.id)
  return own.map((e) => ({ id: e.id as EquipmentId, label: served[e.id] }))
}

/** The pickers' groups with the athlete's packages' implements last. */
export function equipmentGroups(list: ServedEquipment[] | undefined): EquipmentGroup[] {
  const own = packageEquipment(list)
  return own.length ? [...EQUIPMENT_GROUPS, { name: PACKAGE_EQUIPMENT, items: own }] : EQUIPMENT_GROUPS
}

/** The Profile's sections with the athlete's packages' implements last. */
export function equipmentCategories(list: ServedEquipment[] | undefined): typeof EQUIPMENT_CATEGORIES {
  const own = packageEquipment(list)
  return own.length
    ? [...EQUIPMENT_CATEGORIES, { name: PACKAGE_EQUIPMENT, color: PACKAGE_EQUIPMENT_HEX, items: own.map((e) => e.id) }]
    : EQUIPMENT_CATEGORIES
}
