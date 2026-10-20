import { describe, it, expect } from 'vitest'
import { buildLogSessionRows, mergeLogEntries, performanceSummary, type LogSessionRow, type RecentSessionLog } from './logSessions'
import type { GeneratedProgram } from '@/api/types'

const squat = { id: 'back_squat', name: 'Back Squat' }

const program = {
  weeks: [
    {
      week_number: 3,
      schedule: {
        Friday: [{
          modality: 'max_strength',
          archetype: { name: 'Heavy Day' },
          exercises: [{ exercise: squat, load: {}, slot_type: 'sets_reps' }],
        }],
      },
    },
  ],
} as unknown as GeneratedProgram

const sets = (n: number, reps: number, weightKg: number) =>
  Array.from({ length: n }, (_, i) => ({ setIndex: i, repsActual: reps, weightKg, completed: true }))

describe('performanceSummary', () => {
  it('reads like the phone', () => {
    expect(performanceSummary({ sets: sets(3, 5, 80) }, 'sets_reps')).toBe('3 sets · 3×5 @ 80 kg')
    expect(performanceSummary({ sets: [...sets(1, 5, 80), ...sets(1, 4, 82.5)] }, 'sets_reps'))
      .toBe('2 sets · 5×80, 4×82.5 kg')
    expect(performanceSummary({ sets: [], durationSec: 1920, distanceKm: 8.4 }, 'time_domain')).toBe('32 min · 8.4 km')
    expect(performanceSummary({ sets: [{ setIndex: 0, repsActual: 48, completed: true }], rounds: 7 }, 'amrap'))
      .toBe('7 rounds · 48 reps')
    expect(performanceSummary({ sets: [] }, 'sets_reps')).toBeNull()
  })
})

describe('buildLogSessionRows', () => {
  it('names a log by the current program when its key resolves there', () => {
    const logs: RecentSessionLog[] = [{
      session_key: '3-Friday-0', completed_at: '2026-10-10 18:00:00+02:00', source: 'web',
      exercises: { back_squat: { sets: sets(3, 5, 80) } },
    }]
    const [row] = buildLogSessionRows(logs, program, '2026-09-22')
    expect(row.title).toBe('Heavy Day')
    expect(row.subtitle).toContain('week 1 · Friday')
    expect(row.lines).toEqual(['Back Squat — 3 sets · 3×5 @ 80 kg'])
    expect(row.href).toBe('/program/3/Friday')
  })

  it('names an earlier program\'s log by the server, even when its key resolves now', () => {
    const logs: RecentSessionLog[] = [{
      session_key: '3-Friday-0', completed_at: '2026-04-25 18:00:00+02:00', source: 'apple_watch_live',
      planned_name: 'Heavy/Light/Medium', planned_date: '2026-04-25', program_version_id: 'v1',
      week_index: 2, day_name: 'Friday', exercises: {},
    }]
    const [row] = buildLogSessionRows(logs, program, '2026-09-22')
    expect(row.title).toBe('Heavy/Light/Medium')
    expect(row.subtitle).toContain('apple watch live')
    expect(row.subtitle).toContain('earlier program · week 3 · Friday')
    expect(row.href).toBe('/program/history/v1')
  })

  it('drops logs with nothing in them and sorts completions newest first', () => {
    const logs: RecentSessionLog[] = [
      { session_key: '1-Monday-0', completed_at: null, exercises: {} },
      { session_key: '1-Tuesday-0', completed_at: '2026-10-01T10:00:00Z' },
      { session_key: '1-Wednesday-0', completed_at: '2026-10-03T10:00:00Z' },
      { session_key: '1-Thursday-0', completed_at: null, exercises: { x: { sets: sets(1, 5, 50) } } },
    ]
    const rows = buildLogSessionRows(logs, null, null)
    expect(rows.map((r) => r.key)).toEqual(['1-Wednesday-0', '1-Tuesday-0', '1-Thursday-0'])
    expect(rows[2].subtitle).toBe('not completed')
  })
})

describe('mergeLogEntries', () => {
  const row = (key: string, completedAt: string | null): LogSessionRow => ({
    key, title: key, subtitle: '', lines: [], isComplete: completedAt != null,
    completedAt: completedAt ? new Date(completedAt) : null, href: null,
  })
  const workouts = [
    { id: 'run', date: '2026-10-19', startTime: '2026-10-19T06:00:00Z' },
    { id: 'ride', date: '2026-10-17' },
  ]
  const rows = [row('squat', '2026-10-19T18:00:00Z'), row('open', null), row('swing', '2026-10-18T07:00:00Z')]

  it('puts workouts and logged sessions in one list, newest first, the undated last', () => {
    const ids = mergeLogEntries(workouts, rows).map((e) => (e.kind === 'workout' ? e.workout.id : e.row.key))
    expect(ids).toEqual(['squat', 'run', 'swing', 'ride', 'open'])
  })

  it('keeps one type when asked', () => {
    expect(mergeLogEntries(workouts, rows, 'workouts').map((e) => e.kind)).toEqual(['workout', 'workout'])
    expect(mergeLogEntries(workouts, rows, 'sessions').map((e) => e.kind)).toEqual(['session', 'session', 'session'])
  })
})
