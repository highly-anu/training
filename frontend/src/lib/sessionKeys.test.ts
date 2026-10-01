import { describe, it, expect } from 'vitest'
import { parseSessionKey, sessionLabel } from './sessionKeys'

describe('parseSessionKey', () => {
  it('reads a day key', () => {
    expect(parseSessionKey('3-Monday')).toEqual({
      weekNumber: 3, dayName: 'Monday', sessionIndex: null, dayKey: '3-Monday',
    })
  })
  it('reads a per-session key', () => {
    expect(parseSessionKey('12-Saturday-1')).toEqual({
      weekNumber: 12, dayName: 'Saturday', sessionIndex: 1, dayKey: '12-Saturday',
    })
  })
  it('rejects keys without a week number', () => {
    expect(parseSessionKey('Monday')).toBeNull()
    expect(parseSessionKey('x-Monday')).toBeNull()
    expect(parseSessionKey('')).toBeNull()
  })
})

describe('sessionLabel', () => {
  it('names the week and day', () => {
    expect(sessionLabel('3-Monday')).toBe('Week 3 — Monday')
    expect(sessionLabel('3-Monday-0')).toBe('Week 3 — Monday')
  })
  it('names a second session on the day', () => {
    expect(sessionLabel('3-Monday-1')).toBe('Week 3 — Monday · session 2')
  })
  it('passes an unparseable key through', () => {
    expect(sessionLabel('garbage')).toBe('garbage')
  })
})
