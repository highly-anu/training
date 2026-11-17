import { describe, it, expect } from 'vitest'
import { deriveBlendedPriorities, derivePhilosophyPriorities, samePriorities } from './philosophyPriorities'
import type { Framework, Philosophy } from '@/api/types'

const framework = (id: string, sessions: Record<string, number>) =>
  ({ id, sessions_per_week: sessions }) as unknown as Framework
const philosophy = (id: string, frameworkId: string, bias: string[] = []) => ({
  id, name: id, bias,
  tracks: [{ id: 'standard', name: 'Standard', phases: [{ id: 'p', name: 'P', kind: 'base', weeks: 8, framework_id: frameworkId }] }],
}) as unknown as Philosophy

describe('derivePhilosophyPriorities', () => {
  it('gives a modality the package brings itself its share', () => {
    // A method made of its own modality used to come out as all zeros: the
    // vector covered the compiled list only, and the server took it as an override.
    const own = 'u1234abcd_odd_object_strength'
    const p = derivePhilosophyPriorities(philosophy('mine', 'fw'), [framework('fw', { [own]: 2, aerobic_base: 2 })])
    expect(p[own as keyof typeof p]).toBeCloseTo(0.5)
    expect(p.aerobic_base).toBeCloseTo(0.5)
    expect(Object.values(p).reduce((s, v) => s + v, 0)).toBeCloseTo(1)
  })

  it('still lists every shared modality, at zero when unused', () => {
    const p = derivePhilosophyPriorities(philosophy('ss', 'fw'), [framework('fw', { max_strength: 3 })])
    expect(p.max_strength).toBe(1)
    expect(p.mobility).toBe(0)
  })

  it('falls back to the bias, the package\'s own modalities included', () => {
    const p = derivePhilosophyPriorities(philosophy('mine', 'none', ['u1_carry', 'power']), [])
    expect(p['u1_carry' as keyof typeof p]).toBe(0.5)
    expect(p.power).toBe(0.5)
  })
})

describe('deriveBlendedPriorities', () => {
  it('keeps a package modality through a blend', () => {
    const frameworks = [framework('a', { u1_carry: 2 }), framework('b', { max_strength: 2 })]
    const p = deriveBlendedPriorities(['mine', 'ss'], { mine: 50, ss: 50 },
      [philosophy('mine', 'a'), philosophy('ss', 'b')], frameworks)
    expect(p['u1_carry' as keyof typeof p]).toBeCloseTo(0.5)
    expect(p.max_strength).toBeCloseTo(0.5)
  })
})

describe('samePriorities', () => {
  it('reads a missing modality as zero and nothing as different', () => {
    expect(samePriorities({ power: 1, mobility: 0 }, { power: 1 })).toBe(true)
    expect(samePriorities({ power: 0.6, mobility: 0.4 }, { power: 1 })).toBe(false)
    expect(samePriorities({ power: 1 }, null)).toBe(false)
  })
})
