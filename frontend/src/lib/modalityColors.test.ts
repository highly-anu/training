import { describe, it, expect } from 'vitest'
import { MODALITY_COLORS, modalityHex, modalityLabel, registerModalities } from './modalityColors'
import { MODALITY_DISPLAY } from '@/lib/gen/clientVocab'
import type { ModalityId } from '@/api/types'

// A package may bring a modality no build knows (vocabulary.yaml; roadmap 20.6).
const lookup = (id: string) => MODALITY_COLORS[id as ModalityId]

describe('modality styles for an id the build does not carry', () => {
  it('answers a neutral style and the id in words, never undefined', () => {
    const style = lookup('zz_unknown_work')
    expect(style.label).toBe('zz unknown work')
    expect(style.bg).toBe('bg-slate-500/15')
    expect(modalityHex('zz_unknown_work')).toBe('#94a3b8')
    expect(modalityLabel('zz_unknown_work')).toBe('zz unknown work')
  })

  it("keeps the commons' as generated, and lists only those", () => {
    expect(lookup('max_strength').label).toBe(MODALITY_DISPLAY.max_strength.label)
    expect(Object.keys(MODALITY_COLORS)).toEqual(Object.keys(MODALITY_DISPLAY))
  })

  it("takes a served modality's label and colour, and the tint classes of its colour family", () => {
    const learned = registerModalities([
      { id: 'u1a2b3c4d_sled_work', name: 'Sled work', display: { label: 'Sled', color: '#b91c1c', tint: 'red' } },
      { id: 'max_strength', display: { label: 'Not this', color: '#000000', tint: 'red' } },
    ])
    expect(learned).toBe(true)
    const style = lookup('u1a2b3c4d_sled_work')
    expect(style.label).toBe('Sled')
    expect(style.hex).toBe('#b91c1c')
    expect(style.bg).toBe(MODALITY_DISPLAY.max_strength.bg)
    expect(style.text).toBe(MODALITY_DISPLAY.max_strength.text)
    expect(lookup('max_strength').label).toBe(MODALITY_DISPLAY.max_strength.label)
  })

  it('says nothing was learned the second time', () => {
    const again = [{ id: 'u1a2b3c4d_sled_work', display: { label: 'Sled', color: '#b91c1c', tint: 'red' } }]
    expect(registerModalities(again)).toBe(false)
    expect(registerModalities(undefined)).toBe(false)
  })

  it('falls back to the name, and to neutral classes for a tint the stylesheet lacks', () => {
    registerModalities([{ id: 'zz_plain', name: 'Plain work', display: { tint: 'fuchsia' } }])
    expect(lookup('zz_plain').label).toBe('Plain work')
    expect(lookup('zz_plain').bg).toBe('bg-slate-500/15')
  })
})
