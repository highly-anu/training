import type { EquipmentId } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'

// The equipment an athlete can declare, grouped and named for pickers: the
// builder's EquipmentPicker and Explore ▸ Equipment. Ids are the constraints
// schema's (docs/schemas/constraints.schema.json); open space is always
// assumed, so no picker offers it.

export interface EquipmentGroup {
  name: string
  items: { id: EquipmentId; label: string }[]
}

export const EQUIPMENT_GROUPS: EquipmentGroup[] = [
  {
    name: 'Free Weights',
    items: [
      { id: 'barbell',    label: 'Barbell' },
      { id: 'rack',       label: 'Rack' },
      { id: 'plates',     label: 'Plates' },
      { id: 'kettlebell', label: 'Kettlebell' },
      { id: 'dumbbell',   label: 'Dumbbell' },
    ],
  },
  {
    name: 'Gymnastics / Bodyweight',
    items: [
      { id: 'pull_up_bar',  label: 'Pull-up Bar' },
      { id: 'rings',        label: 'Rings' },
      { id: 'parallettes',  label: 'Parallettes' },
      { id: 'hangboard',    label: 'Hangboard' },
      { id: 'rope',         label: 'Rope Climb' },
      { id: 'box',          label: 'Box' },
      { id: 'dip_belt',     label: 'Dip Belt' },
    ],
  },
  {
    name: 'Cardio Machines',
    items: [
      { id: 'rower',   label: 'Rower' },
      { id: 'bike',    label: 'Assault Bike' },
      { id: 'ski_erg', label: 'Ski Erg' },
      { id: 'pool',    label: 'Pool (Swimming)' },
    ],
  },
  {
    name: 'Field / Load',
    items: [
      { id: 'ruck_pack',       label: 'Ruck Pack' },
      { id: 'sandbag',         label: 'Sandbag' },
      { id: 'jump_rope',       label: 'Jump Rope' },
      { id: 'resistance_band', label: 'Resistance Band' },
    ],
  },
  {
    name: 'Specialty',
    items: [
      { id: 'ghd',           label: 'GHD' },
      { id: 'medicine_ball', label: 'Medicine Ball' },
      { id: 'sled',          label: 'Sled' },
      { id: 'tire',          label: 'Tire' },
      { id: 'sledgehammer',  label: 'Sledgehammer' },
      { id: 'cable_machine', label: 'Cable Machine' },
      { id: 'hurdles',       label: 'Hurdles' },
      { id: 'agility_ladder', label: 'Agility Ladder' },
      { id: 'training_partner', label: 'Training Partner' },
    ],
  },
]

const LABELS: Record<string, string> = Object.fromEntries(
  EQUIPMENT_GROUPS.flatMap((g) => g.items.map((i) => [i.id, i.label])),
)

export function equipmentLabel(id: string): string {
  return LABELS[id] ?? id.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase())
}

// Equipment by category, each in the colour of the training it serves: Profile ▸
// Equipment's sections, and the colour of an item wherever else it appears
// (Explore ▸ Philosophies' Requirements).
export const EQUIPMENT_CATEGORIES = [
  {
    name: 'Strength',
    color: MODALITY_COLORS.max_strength.hex,
    items: ['barbell', 'rack', 'plates'] as EquipmentId[],
  },
  {
    name: 'Power & Kettlebell',
    color: MODALITY_COLORS.power.hex,
    items: ['kettlebell', 'dumbbell'] as EquipmentId[],
  },
  {
    name: 'Bodyweight & Gymnastics',
    color: MODALITY_COLORS.relative_strength.hex,
    items: ['pull_up_bar', 'rings', 'parallettes', 'dip_bar', 'hangboard'] as EquipmentId[],
  },
  {
    name: 'Aerobic & Conditioning',
    color: MODALITY_COLORS.aerobic_base.hex,
    items: ['rower', 'assault_bike', 'ski_erg', 'jump_rope', 'pool'] as EquipmentId[],
  },
  {
    name: 'GPP & Durability',
    color: MODALITY_COLORS.durability.hex,
    items: ['ruck_pack', 'sandbag', 'sled', 'tire', 'sledgehammer', 'medicine_ball', 'box'] as EquipmentId[],
  },
  {
    name: 'Mobility & Prehab',
    color: MODALITY_COLORS.rehab.hex,
    items: ['resistance_band', 'foam_roller', 'ghd'] as EquipmentId[],
  },
  {
    name: 'General',
    color: '#6366f1',
    items: ['rope', 'open_space', 'training_partner', 'cable_machine', 'hurdles', 'agility_ladder'] as EquipmentId[],
  },
]

const CATEGORY_HEX: Record<string, string> = Object.fromEntries(
  EQUIPMENT_CATEGORIES.flatMap((c) => c.items.map((id) => [id, c.color])),
)

/** The colour of the category Profile ▸ Equipment files an item under; undefined
 *  for an id it does not list. */
export function equipmentHex(id: string): string | undefined {
  return CATEGORY_HEX[id]
}
