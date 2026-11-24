import { describe, expect, it } from 'vitest'
import {
  addPhase, addWeek, canPlace, clearWeek, dayAt, duplicateOf, duplicateWeek, emptyTrack, fromWire, isBlank, lighterWeeks,
  moveSession, nudgePhase, phaseStarts, placeSession, placedSessions, problemsAt, removePhase, removeSession, removeWeek,
  repeatLine, sessionsInWeek, templateWeekOf, toWire, toggleLight, totalWeeks, updatePhase, type DraftTrack,
} from './programBuilder'

const start = (): [DraftTrack, string] => { const t = emptyTrack(); return [t, t.phases[0].uid] }
const MON = { week: 0, day: 0 }
const WED = { week: 0, day: 2 }

describe('days', () => {
  it('takes two sessions on a day and no third, nor the same twice', () => {
    const [t0, p] = start()
    let t = t0
    t = placeSession(t, p, MON, 'a')
    expect(placeSession(t, p, MON, 'a')).toBe(t)
    t = placeSession(t, p, MON, 'b')
    expect(dayAt(t, p, MON)?.sessions).toEqual(['a', 'b'])
    expect(canPlace(dayAt(t, p, MON), 'c')).toBe(false)
    expect(placeSession(t, p, MON, 'c')).toBe(t)
  })
  it('moves a placed session, and leaves it where the day cannot take it', () => {
    const [t0, p] = start()
    let t = t0
    t = placeSession(placeSession(t, p, MON, 'a'), p, WED, 'a')
    expect(moveSession(t, p, MON, 0, WED)).toBe(t)
    t = moveSession(t, p, MON, 0, { week: 0, day: 4 })
    expect([dayAt(t, p, MON)?.sessions, dayAt(t, p, { week: 0, day: 4 })?.sessions]).toEqual([[], ['a']])
    expect(moveSession(t, p, WED, 0, WED)).toBe(t)
  })
  it('marks a day light, and a day emptied is a plain rest day', () => {
    const [t0, p] = start()
    let t = t0
    t = toggleLight(placeSession(t, p, MON, 'a'), p, MON)
    expect(dayAt(t, p, MON)).toEqual({ sessions: ['a'], light: true })
    t = removeSession(t, p, MON, 0)
    expect(dayAt(t, p, MON)).toEqual({ sessions: [] })
    expect(dayAt(toggleLight(t, p, MON), p, MON)).toEqual({ sessions: [] })
  })
})

describe('weeks and phases', () => {
  it('adds, duplicates, clears and removes template weeks within the limit', () => {
    const [t0, p] = start()
    let t = t0
    t = placeSession(t, p, MON, 'a')
    t = duplicateWeek(t, p, 0)
    expect(t.phases[0].template.map(sessionsInWeek)).toEqual([1, 1])
    t = placeSession(t, p, { week: 1, day: 3 }, 'b')
    expect(dayAt(t, p, { week: 0, day: 3 })?.sessions).toEqual([])     // a copy, not the same week
    t = clearWeek(addWeek(t, p), p, 0)
    expect(t.phases[0].template.map(sessionsInWeek)).toEqual([0, 2, 0])
    t = removeWeek(t, p, 0)
    expect(t.phases[0].template).toHaveLength(2)
    expect(addWeek(t, p, 2)).toEqual(t)
    const [one, q] = start()
    expect(removeWeek(one, q, 0)).toEqual(one)
  })
  it('starts a new phase from the one before it, reorders and removes phases', () => {
    const [t0, p] = start()
    let t = t0
    t = updatePhase(placeSession(t, p, MON, 'a'), p, { name: 'Build', weeks: 6 })
    t = addPhase(t)
    expect(t.phases[1]).toMatchObject({ name: 'Phase 2', kind: 'build', weeks: 6 })
    expect(t.phases[1].template[0][0].sessions).toEqual(['a'])
    expect(nudgePhase(t, p, 1).phases.map((x) => x.name)).toEqual(['Phase 2', 'Build'])
    expect(nudgePhase(t, p, -1)).toBe(t)
    expect(removePhase(t, t.phases[1].uid).phases).toHaveLength(1)
    expect(removePhase(removePhase(t, t.phases[1].uid), p).phases).toHaveLength(1)
    expect(addPhase(t, 2)).toBe(t)
  })
  it('reads the track: its weeks, where phases start, which weeks are lighter, how rows repeat', () => {
    const t = { phases: [{ name: 'A', kind: 'build', weeks: 8, template: [[], []] }, { name: 'B', kind: 'peak', weeks: 3, template: [[]] }] }
    expect(totalWeeks(t)).toBe(11)
    expect(phaseStarts(t)).toEqual([1, 9])
    expect(lighterWeeks(t.phases[0], 4)).toEqual([4, 8])
    expect(lighterWeeks(t.phases[1], 4)).toEqual([])
    expect(lighterWeeks(t.phases[0], null)).toEqual([])
    expect([1, 2, 3].map((w) => templateWeekOf(t.phases[0], w))).toEqual([0, 1, 0])
    expect(repeatLine(t.phases[0])).toBe('These 2 weeks repeat, in order, for the 8 weeks of the phase.')
    expect(repeatLine(t.phases[1])).toBe('This week repeats for the 3 weeks of the phase.')
    expect(repeatLine({ weeks: 2, template: [[], []] })).toBe('One row for each week of the phase.')
    expect(repeatLine({ weeks: 1, template: [[], []] })).toContain('only the first one')
  })
})

describe('the wire', () => {
  it('sends no client keys and reads back the same track', () => {
    const [t0, p] = start()
    let t = t0
    t = toggleLight(placeSession(placeSession(t, p, MON, 'a'), p, WED, 'b'), p, WED)
    t = { ...t, name: ' Block ', deload_every: 4 }
    const wire = toWire(t)
    expect(JSON.stringify(wire)).not.toContain('uid')
    expect(wire.name).toBe('Block')
    expect(wire.phases[0].template[0][2]).toEqual({ sessions: ['b'], light: true })
    expect(wire.phases[0].template[0][1]).toEqual({ sessions: [] })
    expect(toWire(fromWire({ ...wire, id: 'block' }))).toEqual({ ...wire, id: 'block' })
    expect(placedSessions(wire)).toEqual(new Set(['a', 'b']))
    expect(isBlank(emptyTrack())).toBe(true)
    const copy = duplicateOf({ ...wire, id: 'block', phases: wire.phases.map((x) => ({ ...x, id: 'build' })) })
    expect([copy.id, copy.name, copy.phases[0].id]).toEqual([undefined, 'Block copy', undefined])
  })
  it('finds the problems of a phase and of one of its days', () => {
    const problems = [
      { phase: 0, week: 0, day: 2, field: null, message: 'gone' },
      { phase: 0, week: null, day: null, field: 'weeks', message: 'weeks' },
      { phase: null, week: null, day: null, field: 'name', message: 'name' },
    ]
    expect(problemsAt(problems, 0, WED).map((p) => p.message)).toEqual(['gone'])
    expect(problemsAt(problems, 0).map((p) => p.message)).toEqual(['weeks'])
    expect(problemsAt(problems, 1)).toEqual([])
  })
})
