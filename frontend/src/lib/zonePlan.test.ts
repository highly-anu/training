/**
 * A workout against its session's programming: the plan-against-recorded
 * rows, each exercise's line and the sentence for each way of counting —
 * the same cases as the phone's (ZonePlanTests.swift).
 */
import { describe, it, expect } from 'vitest'
import { exerciseRow, planNote, prescriptionText, untrackedText, zonePlanRows } from './zonePlan'
import type { WorkoutPlanned, WorkoutPlannedSlot } from '@/api/types'

const slot = (over: Partial<WorkoutPlannedSlot>): WorkoutPlannedSlot => ({
  role: 'warm_up', intensity: 'zone2', zones: [2], prescribes: 'zones', exercises: ['Row'],
  plannedMinutes: 15, recordedMinutes: null, counted: false, ...over })
const plan = (over: Partial<WorkoutPlanned>): WorkoutPlanned => ({
  track: false, mode: 'none', source: 'slots', timing: 'none', plannedMinutes: [0, 0, 0, 0, 0],
  zoneMinutes: [0, 0, 0, 0, 0], countedMinutes: 0, notZoned: ['main: heavy'], slots: [],
  sessionName: 'Workout A', modality: 'max_strength', ...over })

describe('zonePlanRows', () => {
  it('keeps only the zones with either side', () => {
    // KB Ballistic Power on 2026-10-17: planned Z1–4, recorded Z1–2.
    expect(zonePlanRows([7.5, 12.5, 15, 10, 0], [22.88, 15.98, 0.13, 0, 0]).map((r) => r.label))
      .toEqual(['Z1', 'Z2', 'Z3', 'Z4'])
    expect(zonePlanRows([0, 0, 0, 0, 0], [0, 0, 0, 0, 0])).toEqual([])
  })
})

describe('exerciseRow', () => {
  it('a timed zoned exercise: recorded of planned', () => {
    const row = exerciseRow(slot({ recordedMinutes: [3, 9.4, 0, 0, 0], counted: true }), 'timeline')
    expect(row).toEqual({ title: 'Row', prescription: 'Zone 2', detail: '12 of 15 min', counted: true })
  })
  it('a load exercise never counts, timed or not', () => {
    const heavy = slot({ role: 'fran', intensity: 'max_effort', zones: [], prescribes: 'load',
                         exercises: ['Thruster', 'Pull-up'], plannedMinutes: 0 })
    expect(exerciseRow(heavy, 'timeline').detail).toBe('not counted')
    expect(exerciseRow({ ...heavy, recordedMinutes: [0, 1, 3, 2, 0] }, 'timeline').detail).toBe('6 min · not counted')
    expect(exerciseRow(heavy, 'timeline').prescription).toBe('max effort')
  })
  it('untimed and whole sessions say so', () => {
    expect(exerciseRow(slot({}), 'untimed').detail).toBe('not timed')
    expect(exerciseRow(slot({ counted: true }), 'whole').detail).toBe('15 min planned')
    expect(exerciseRow(slot({ exercises: [] }), 'whole').title).toBe('Warm up')
  })
  it('names a band of zones', () => {
    expect(prescriptionText(slot({ zones: [1, 2] }))).toBe('Zones 1–2')
  })
})

describe('planNote', () => {
  it('says what counted, or why nothing did', () => {
    expect(planNote(plan({ timing: 'whole' }))).toBeNull()
    expect(planNote(plan({ timing: 'timeline' }))).toContain('inside the times the watch logged')
    expect(planNote(plan({ timing: 'untimed' }))).toContain("didn't time them")
    expect(planNote(plan({ timing: 'unrecorded' }))).toBe('No heart rate was recorded to compare.')
    expect(planNote(plan({}))).toContain('(main: heavy)')
    expect(untrackedText(plan({ source: 'declared', notZoned: [] }))).toContain("doesn't track heart rate")
  })
})
