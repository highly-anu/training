import { describe, it, expect } from 'vitest'
import { buildLinkingDays, dismissKey, programSessions, suggestForDay } from './linking'
import type { GeneratedProgram, ImportedWorkout, PlannedSession, WorkoutMatch } from '@/api/types'

// Starts Monday 2026-10-05.
const program = {
  weeks: [
    {
      week_number: 1,
      schedule: {
        Monday: [
          { modality: 'max_strength', archetype: { name: 'Heavy Day', duration_estimate_minutes: 60 }, exercises: [] },
          { modality: 'aerobic_base', archetype: { name: 'Zone 2', duration_estimate_minutes: 45 }, exercises: [] },
        ],
        Wednesday: [
          { modality: 'aerobic_base', archetype: { name: 'Long Zone 2', duration_estimate_minutes: 90 }, exercises: [] },
        ],
        Saturday: [
          { modality: 'max_strength', archetype: { name: 'Volume Day', duration_estimate_minutes: 60 }, exercises: [] },
        ],
      },
    },
  ],
} as unknown as GeneratedProgram

const workout = (id: string, date: string, modality: string, minutes: number): ImportedWorkout => ({
  id, source: 'garmin', date, startTime: `${date}T07:00:00Z`, endTime: `${date}T08:00:00Z`,
  durationMinutes: minutes, activityType: modality === 'aerobic_base' ? 'running' : 'strength_training',
  inferredModalityId: modality as ImportedWorkout['inferredModalityId'], heartRate: {}, rawData: {},
})

const match = (workoutId: string, sessionKey: string, extra: Partial<WorkoutMatch> = {}): WorkoutMatch => ({
  importedWorkoutId: workoutId, sessionKey, matchConfidence: 'manual', matchedAt: '2026-10-08T00:00:00Z', ...extra,
})

const base = { pending: [], program, programStartDate: '2026-10-05', today: '2026-10-08' }

describe('programSessions', () => {
  it('puts each session on its calendar day', () => {
    const s = programSessions(program, '2026-10-05')
    expect(s.get('1-Monday-1')?.date).toBe('2026-10-05')
    expect(s.get('1-Wednesday-0')?.date).toBe('2026-10-07')
    expect(s.get('1-Wednesday-0')?.name).toBe('Long Zone 2')
  })
})

describe('suggestForDay', () => {
  it('pairs one-to-one, best score first', () => {
    const sessions = [...programSessions(program, '2026-10-05').values()].filter((s) => s.date === '2026-10-05')
    const run = workout('run', '2026-10-05', 'aerobic_base', 44)
    const lift = workout('lift', '2026-10-05', 'max_strength', 62)
    const out = suggestForDay([run, lift], sessions)
    expect(out.map((p) => [p.workout.id, p.session.key]).sort()).toEqual([['lift', '1-Monday-0'], ['run', '1-Monday-1']])
  })

  it('skips a dismissed pair', () => {
    const sessions = [...programSessions(program, '2026-10-05').values()].filter((s) => s.date === '2026-10-05')
    const run = workout('run', '2026-10-05', 'aerobic_base', 44)
    const out = suggestForDay([run], sessions, new Set([dismissKey('run', '1-Monday-1')]))
    expect(out.find((p) => p.session.key === '1-Monday-1')).toBeUndefined()
  })
})

describe('buildLinkingDays', () => {
  it('makes one card per day up to today, newest first', () => {
    const days = buildLinkingDays({ ...base, workouts: [], matches: [] })
    expect(days.map((d) => d.date)).toEqual(['2026-10-07', '2026-10-05'])   // Saturday is after today
  })

  it('only suggests within the workout’s own day', () => {
    // A Tuesday run looks like Wednesday's long run, but it is not on Wednesday.
    const tue = workout('tue', '2026-10-06', 'aerobic_base', 88)
    const days = buildLinkingDays({ ...base, workouts: [tue], matches: [] })
    const tuesday = days.find((d) => d.date === '2026-10-06')!
    expect(tuesday.suggestions).toEqual([])
    expect(tuesday.workouts.map((w) => w.id)).toEqual(['tue'])
    expect(tuesday.needsAttention).toBe(true)
    expect(days.find((d) => d.date === '2026-10-07')!.suggestions).toEqual([])
  })

  it('drops a pending suggestion that names another day’s session', () => {
    const tue = workout('tue', '2026-10-06', 'aerobic_base', 88)
    const days = buildLinkingDays({
      ...base, workouts: [tue], matches: [],
      pending: [{ importedWorkout: tue, candidateSessionKeys: ['1-Wednesday-0'] }],
    })
    expect(days.flatMap((d) => d.suggestions)).toEqual([])
  })

  it('keeps a same-day pending suggestion', () => {
    const run = workout('run', '2026-10-07', 'aerobic_base', 30)
    const days = buildLinkingDays({
      ...base, workouts: [run], matches: [],
      pending: [{ importedWorkout: run, candidateSessionKeys: ['1-Wednesday-0'] }],
    })
    const wed = days.find((d) => d.date === '2026-10-07')!
    expect(wed.suggestions).toHaveLength(1)
    expect(wed.suggestions[0].fromPending).toBe(true)
    expect(wed.sessions).toEqual([])
  })

  it('shows a cross-date link on both days', () => {
    const tue = workout('tue', '2026-10-06', 'aerobic_base', 88)
    const days = buildLinkingDays({ ...base, workouts: [tue], matches: [match('tue', '1-Wednesday-0')] })
    expect(days.find((d) => d.date === '2026-10-06')!.links).toHaveLength(1)
    const wed = days.find((d) => d.date === '2026-10-07')!
    expect(wed.links).toHaveLength(1)
    expect(wed.sessions).toEqual([])
    expect(wed.needsAttention).toBe(false)
  })

  it('treats another version’s match as linked elsewhere', () => {
    const run = workout('run', '2026-10-07', 'aerobic_base', 90)
    const days = buildLinkingDays({
      ...base, workouts: [run], programVersionId: 'v2',
      matches: [match('run', '1-Wednesday-0', { sessionUid: 'v1:w0-Wednesday-0' })],
    })
    const wed = days.find((d) => d.date === '2026-10-07')!
    expect(wed.links).toEqual([])
    expect(wed.elsewhere.map((e) => e.workout.id)).toEqual(['run'])
    expect(wed.sessions.map((s) => s.key)).toEqual(['1-Wednesday-0'])
  })

  it('does not suggest a declined workout', () => {
    const run = workout('run', '2026-10-07', 'aerobic_base', 90)
    const days = buildLinkingDays({ ...base, workouts: [run], matches: [match('run', '', { matchConfidence: 'rejected' })] })
    const wed = days.find((d) => d.date === '2026-10-07')!
    expect(wed.suggestions).toEqual([])
    expect(wed.declined.map((w) => w.id)).toEqual(['run'])
    expect(wed.needsAttention).toBe(false)
  })

  it('leaves out workouts before the program', () => {
    const old = workout('old', '2026-09-30', 'aerobic_base', 45)
    const days = buildLinkingDays({ ...base, workouts: [old], matches: [] })
    expect(days.some((d) => d.date === '2026-09-30')).toBe(false)
  })
})

// An earlier program, in force the week before: 2026-09-28 → 2026-10-04.
const planned = (vid: string, date: string, dayName: string, modality: string, minutes: number, name: string,
  extra: Partial<PlannedSession> = {}): PlannedSession => ({
  sessionUid: `${vid}:w0-${dayName}-0`, programVersionId: vid, date, weekIndex: 0, weekNumber: 1,
  dayName, sessionIndex: 0, sessionKey: `1-${dayName}-0`, modality: modality as PlannedSession['modality'],
  archetypeId: null, archetypeName: name, durationMinutes: minutes, phase: 'base', isDeload: false, ...extra,
})

const history = [
  planned('old', '2026-09-28', 'Monday', 'aerobic_base', 45, 'Old Zone 2'),
  planned('old', '2026-10-01', 'Thursday', 'max_strength', 60, 'Old Heavy', { completedAt: '2026-10-01T18:00:00Z' }),
  // The current version's own row: the program above already has it.
  planned('cur', '2026-10-05', 'Monday', 'max_strength', 60, 'Heavy Day'),
]

const withHistory = { ...base, programVersionId: 'cur', history }

describe('buildLinkingDays — earlier programs', () => {
  it('adds the earlier program’s days, marked as such', () => {
    const days = buildLinkingDays({ ...withHistory, workouts: [], matches: [] })
    expect(days.map((d) => [d.date, d.historical])).toEqual([
      ['2026-10-07', false], ['2026-10-05', false], ['2026-10-01', true], ['2026-09-28', true],
    ])
    expect(days.find((d) => d.date === '2026-09-28')!.programVersionId).toBe('old')
    // The current version's archived row is not shown twice.
    expect(days.find((d) => d.date === '2026-10-05')!.sessions.map((s) => s.name)).toEqual(['Heavy Day', 'Zone 2'])
  })

  it('gives a day an earlier program ran to that program, keeping links to this one', () => {
    // This program starts Monday the 5th but was activated on the 7th.
    const overlap = [
      planned('old', '2026-10-05', 'Monday', 'mobility', 30, 'Old Mobility', { sessionUid: 'old:w1-Monday-0', weekIndex: 1, weekNumber: 2, sessionKey: '2-Monday-0' }),
    ]
    const lift = workout('lift', '2026-10-05', 'max_strength', 60)
    const days = buildLinkingDays({
      ...withHistory, history: overlap, workouts: [lift], matches: [match('lift', '1-Monday-0', { sessionUid: 'cur:w0-Monday-0' })],
    })
    const mon = days.find((d) => d.date === '2026-10-05')!
    expect(mon.historical).toBe(true)
    expect(mon.sessions.map((s) => s.name)).toEqual(['Old Mobility'])
    expect(mon.links.map((l) => l.session.name)).toEqual(['Heavy Day'])
    expect(days.find((d) => d.date === '2026-10-07')!.historical).toBe(false)
  })

  it('suggests within an earlier program’s day', () => {
    const run = workout('run', '2026-09-28', 'aerobic_base', 44)
    const days = buildLinkingDays({ ...withHistory, workouts: [run], matches: [] })
    const mon = days.find((d) => d.date === '2026-09-28')!
    expect(mon.suggestions.map((p) => [p.workout.id, p.session.uid, p.session.historical]))
      .toEqual([['run', 'old:w0-Monday-0', true]])
  })

  it('gives the current program’s sessions their uid', () => {
    const s = programSessions(program, '2026-10-05', 'cur')
    expect(s.get('1-Wednesday-0')?.uid).toBe('cur:w0-Wednesday-0')
    expect(programSessions(program, '2026-10-05').get('1-Wednesday-0')?.uid).toBeNull()
  })

  it('resolves a match by its uid, across days', () => {
    const tue = workout('tue', '2026-09-29', 'aerobic_base', 45)
    const days = buildLinkingDays({
      ...withHistory, workouts: [tue], matches: [match('tue', '1-Monday-0', { sessionUid: 'old:w0-Monday-0' })],
    })
    expect(days.find((d) => d.date === '2026-09-28')!.links.map((l) => l.session.name)).toEqual(['Old Zone 2'])
    expect(days.find((d) => d.date === '2026-09-29')!.links).toHaveLength(1)
    // The current program's "1-Monday-0" is not the one it names.
    expect(days.find((d) => d.date === '2026-10-05')!.links).toEqual([])
  })

  it('places an old unscoped match by its key on the workout’s date', () => {
    const lift = workout('lift', '2026-10-01', 'max_strength', 60)
    const days = buildLinkingDays({
      ...withHistory, workouts: [lift],
      matches: [match('lift', '1-Thursday-0', { inCurrentProgram: false })],
    })
    const thu = days.find((d) => d.date === '2026-10-01')!
    expect(thu.links.map((l) => l.session.uid)).toEqual(['old:w0-Thursday-0'])
    expect(thu.elsewhere).toEqual([])
  })
})
