/**
 * What a slot logs. A test's scored slot asks first for the number its
 * standard needs; a for-time slot logs a clock. The phone's copy is
 * `SessionLogging.outcomeFields` — the same cases are in SessionLoggingTests.
 */
import { describe, it, expect } from 'vitest'
import { formatClock, outcomeFieldsFor, parseClock } from './outcomeFields'

describe('outcomeFieldsFor', () => {
  it('keeps the slot-type defaults without a standard', () => {
    expect(outcomeFieldsFor('time_domain')).toEqual(['minutes', 'km'])
    expect(outcomeFieldsFor('amrap')).toEqual(['rounds', 'reps'])
    expect(outcomeFieldsFor('time_domain', { category: 'kettlebell' })).toEqual(['minutes', 'reps'])
  })

  it('logs a for-time slot as a clock', () => {
    expect(outcomeFieldsFor('for_time')).toEqual(['time'])
    expect(outcomeFieldsFor('rounds_for_time')).toEqual(['time', 'rounds'])
  })

  it("asks first for the standard's number", () => {
    // Push-ups in three minutes: reps, not km.
    expect(outcomeFieldsFor('time_domain', { category: 'bodyweight' }, { result: 'reps' })).toEqual(['reps', 'minutes'])
    expect(outcomeFieldsFor('for_time', null, { result: 'duration' })).toEqual(['time'])
    expect(outcomeFieldsFor('amrap', null, { result: 'rounds' })).toEqual(['rounds', 'reps'])
    expect(outcomeFieldsFor('time_domain', { category: 'kettlebell' }, { result: 'reps' })).toEqual(['reps', 'minutes'])
  })
})

describe('clocks', () => {
  it('reads what is typed', () => {
    expect(parseClock('7:32')).toBe(452)
    expect(parseClock('1:02:30')).toBe(3750)
    expect(parseClock('7.5')).toBe(450)
    expect(parseClock('7')).toBe(420)
    expect(parseClock('7:75')).toBeUndefined()
    expect(parseClock('')).toBeUndefined()
    expect(parseClock('abc')).toBeUndefined()
  })

  it('prints them back', () => {
    expect(formatClock(452)).toBe('7:32')
    expect(formatClock(3750)).toBe('1:02:30')
    expect(formatClock(parseClock('4:58')!)).toBe('4:58')
  })
})
