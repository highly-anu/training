import { describe, it, expect } from 'vitest'
import { buildLinkingDays, dismissKey, programSessions, suggestForDay } from './linking'
import type { GeneratedProgram, ImportedWorkout, WorkoutMatch } from '@/api/types'

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
