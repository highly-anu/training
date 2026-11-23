/**
 * The session browser's list: what a search, a group and a level leave, in the
 * server's order. The document is the server's
 * (mocks/fixtures/philosophy-describe.json, written by test_explore_philosophy.py).
 */
import { describe, it, expect } from 'vitest'
import fixture from '@/mocks/fixtures/philosophy-describe.json'
import type { PhilosophyDescription } from '@/api/types'
import { TRAINING_LEVELS } from '@/lib/gen/clientVocab'
import { browse, groupKey, groupLabel, groupOf, levelChoices, neighbour } from './sessionBrowser'

const doc = fixture as unknown as PhilosophyDescription
const ids = (rows: ReturnType<typeof browse>) => rows.map((g) => [g.label, g.sessions.map((s) => s.id)])

describe('browse', () => {
  it('lists every session once, grouped and ordered as the server sends them', () => {
    expect(ids(browse(doc.groups, doc.sessions))).toEqual([
      ['Warm-up', ['w1']], ['Heavy', ['h1', 'h2']], ['Easy', ['e1']], ['Swings', ['c1']],
      ['Power', ['loose']], ['Tests', ['t1']],
    ])
  })

  it('names a group by its modality when the method gives it no name', () => {
    expect(doc.groups.map(groupLabel)).toContain('Power')
  })

  it('finds a session by its name, its group or a movement in it', () => {
    expect(ids(browse(doc.groups, doc.sessions, { query: 'h2' }))).toEqual([['Heavy', ['h2']]])
    expect(ids(browse(doc.groups, doc.sessions, { query: 'heavy' }))).toEqual([['Heavy', ['h1', 'h2']]])
    expect(browse(doc.groups, doc.sessions, { query: 'swing' }).flatMap((g) => g.sessions.map((s) => s.id)))
      .toEqual(['h2', 'c1', 'loose'])
    // Every word must be found.
    expect(ids(browse(doc.groups, doc.sessions, { query: 'heavy swing' }))).toEqual([['Heavy', ['h2']]])
    expect(browse(doc.groups, doc.sessions, { query: 'nothing like it' })).toEqual([])
  })

  it('narrows to one group', () => {
    const heavy = doc.groups.find((g) => g.id === 'heavy')!
    expect(ids(browse(doc.groups, doc.sessions, { group: groupKey(heavy) }))).toEqual([['Heavy', ['h1', 'h2']]])
  })

  it('narrows to a level, keeping what is written for no level in particular', () => {
    const novice = browse(doc.groups, doc.sessions, { level: 'novice' }).flatMap((g) => g.sessions.map((s) => s.id))
    expect(novice).toContain('h1')
    expect(novice).not.toContain('h2')
    expect(novice).toContain('e1')
  })

  it('offers only the levels that tell sessions apart', () => {
    expect(levelChoices(doc.sessions, TRAINING_LEVELS)).toEqual(['novice', 'intermediate', 'advanced'])
    const same = Object.fromEntries(Object.entries(doc.sessions).map(([k, s]) => [k, { ...s, levels: ['novice' as const] }]))
    expect(levelChoices(same, TRAINING_LEVELS)).toEqual([])
  })
})

describe('neighbour', () => {
  const all = browse(doc.groups, doc.sessions)
  it('steps along the list across groups and stops at its ends', () => {
    expect(neighbour(all, 'w1', 1)).toBe('h1')
    expect(neighbour(all, 'h2', 1)).toBe('e1')
    expect(neighbour(all, 'h1', -1)).toBe('w1')
    expect(neighbour(all, 'w1', -1)).toBeNull()
    expect(neighbour(all, 't1', 1)).toBeNull()
  })
  it('starts at the top when nothing listed is open', () => {
    expect(neighbour(all, null, 1)).toBe('w1')
    expect(neighbour(all, 'gone', -1)).toBe('w1')
    expect(neighbour([], null, 1)).toBeNull()
  })
})

describe('groupOf', () => {
  it('is the group a session is filed under', () => {
    expect(groupOf(doc.groups, 'c1')?.id).toBe('swings')
    expect(groupOf(doc.groups, 'nope')).toBeUndefined()
  })
})
