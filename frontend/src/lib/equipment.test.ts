import { describe, it, expect } from 'vitest'
import { EQUIPMENT_CATEGORIES, equipmentHex } from '@/lib/equipment'
import { MODALITY_COLORS } from '@/lib/modalityColors'

// Explore's Requirements chips take the colour Profile ▸ Equipment files each item under.
describe('equipmentHex', () => {
  it("gives an item its Profile category's colour", () => {
    expect(equipmentHex('barbell')).toBe(MODALITY_COLORS.max_strength.hex)
    expect(equipmentHex('kettlebell')).toBe(MODALITY_COLORS.power.hex)
    expect(equipmentHex('rower')).toBe(MODALITY_COLORS.aerobic_base.hex)
    expect(equipmentHex('sled')).toBe(MODALITY_COLORS.durability.hex)
  })

  it('every listed item has exactly one category', () => {
    const ids = EQUIPMENT_CATEGORIES.flatMap((c) => c.items)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it('an unlisted id has no colour', () => {
    expect(equipmentHex('teleporter')).toBeUndefined()
  })
})
