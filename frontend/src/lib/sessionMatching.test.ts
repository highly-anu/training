import { describe, it, expect } from 'vitest'
import {
  findSessionMatch,
  hasSessionMatch,
  isFromAnotherProgram,
  sessionKeyVariants,
} from './sessionMatching'
import type { WorkoutMatch } from '@/api/types'

const CURRENT = 'vCURRENT'
const OLD = 'vOLD'

function match(partial: Partial<WorkoutMatch> & { sessionKey: string }): WorkoutMatch {
  return {
    importedWorkoutId: 'w-' + partial.sessionKey,
    matchConfidence: 'auto',
    matchedAt: '2026-01-01T00:00:00Z',
    ...partial,
  }
}

describe('sessionKeyVariants', () => {
  it('puts the indexed key before the day-level one', () => {
    expect(sessionKeyVariants('3-Monday', 0)).toEqual(['3-Monday-0', '3-Monday'])
  })

  it('is just the day key when there is no index', () => {
    expect(sessionKeyVariants('3-Monday')).toEqual(['3-Monday'])
  })
})

describe('findSessionMatch', () => {
  it('finds an exact indexed key', () => {
    const m = match({ sessionKey: '3-Monday-0', sessionUid: `${CURRENT}:w2-Monday-0` })
    expect(findSessionMatch([m], sessionKeyVariants('3-Monday', 0), CURRENT)).toBe(m)
  })

  it('prefers the indexed key over the day-level one', () => {
    const day = match({ sessionKey: '3-Monday' })
    const indexed = match({ sessionKey: '3-Monday-1' })
    expect(findSessionMatch([day, indexed], sessionKeyVariants('3-Monday', 1), CURRENT))
      .toBe(indexed)
  })

  it('falls back to a day-level key when there is no indexed match', () => {
    const day = match({ sessionKey: '3-Monday' })
    expect(findSessionMatch([day], sessionKeyVariants('3-Monday', 0), CURRENT)).toBe(day)
  })

  it('ignores rejected matches', () => {
    const rejected = match({ sessionKey: '3-Monday-0', matchConfidence: 'rejected' })
    expect(findSessionMatch([rejected], sessionKeyVariants('3-Monday', 0), CURRENT))
      .toBeUndefined()
  })

  // The bug this helper exists for: a session key is program-relative, so on the
  // key alone a finished block's match rendered as the current block's session.
  it('rejects a match recorded against a replaced program', () => {
    const stale = match({ sessionKey: '3-Monday-0', sessionUid: `${OLD}:w2-Monday-0` })
    expect(findSessionMatch([stale], sessionKeyVariants('3-Monday', 0), CURRENT))
      .toBeUndefined()
    expect(hasSessionMatch([stale], sessionKeyVariants('3-Monday', 0), CURRENT)).toBe(false)
  })

  it('picks this program\'s match when both programs have one for that key', () => {
    const stale = match({ sessionKey: '3-Monday-0', sessionUid: `${OLD}:w2-Monday-0` })
    const mine = match({ sessionKey: '3-Monday-0', sessionUid: `${CURRENT}:w2-Monday-0` })
    expect(findSessionMatch([stale, mine], sessionKeyVariants('3-Monday', 0), CURRENT))
      .toBe(mine)
  })

  // Matches stored before program history, and any the server could not resolve
  // without guessing, have no uid. Hiding them would lose real data.
  it('keeps a match with no uid', () => {
    const legacy = match({ sessionKey: '3-Monday-0' })
    expect(findSessionMatch([legacy], sessionKeyVariants('3-Monday', 0), CURRENT))
      .toBe(legacy)
    expect(findSessionMatch([legacy], sessionKeyVariants('3-Monday', 0), null))
      .toBe(legacy)
  })

  it('keeps a scoped match when the current version is unknown', () => {
    const scoped = match({ sessionKey: '3-Monday-0', sessionUid: `${OLD}:w2-Monday-0` })
    expect(findSessionMatch([scoped], sessionKeyVariants('3-Monday', 0), null)).toBe(scoped)
    expect(findSessionMatch([scoped], sessionKeyVariants('3-Monday', 0), undefined))
      .toBe(scoped)
  })

  it('does not confuse two programs whose week numbers coincide', () => {
    const a = match({ sessionKey: '16-Monday-0', sessionUid: `${OLD}:w0-Monday-0` })
    const b = match({ sessionKey: '16-Monday-0', sessionUid: `${CURRENT}:w15-Monday-0` })
    expect(findSessionMatch([a, b], sessionKeyVariants('16-Monday', 0), CURRENT)).toBe(b)
  })
})

describe('isFromAnotherProgram', () => {
  it('is true only for a scoped match from a different version', () => {
    expect(isFromAnotherProgram(
      match({ sessionKey: 'k', sessionUid: `${OLD}:w0-Monday-0` }), CURRENT)).toBe(true)
    expect(isFromAnotherProgram(
      match({ sessionKey: 'k', sessionUid: `${CURRENT}:w0-Monday-0` }), CURRENT)).toBe(false)
    expect(isFromAnotherProgram(match({ sessionKey: 'k' }), CURRENT)).toBe(false)
    expect(isFromAnotherProgram(
      match({ sessionKey: 'k', sessionUid: `${OLD}:w0-Monday-0` }), null)).toBe(false)
  })
})
