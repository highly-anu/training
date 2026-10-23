import { describe, expect, it } from 'vitest'
import type { AnalyticsProgressEntry, ExerciseSeriesExercise, ExerciseSeriesSection } from '@/api/types'
import { deloadSpans, resolveSelection, seriesFor } from './progressChart'

function exercise(id: string, logged: number, metrics: ExerciseSeriesExercise['metrics'] = ['weight', 'reps']): ExerciseSeriesExercise {
  return {
    exerciseId: id, name: id, modality: 'max_strength', metrics, defaultMetric: metrics[0], scheduled: 3, logged,
    points: [
      { date: '2026-03-02', week: 1, x: 1, isDeload: false, elapsed: true, source: 'log', sessionName: 'A',
        done: { weight: 100, reps: 5 }, prescribed: { weight: 100, reps: 5 }, doneText: '100×5', prescribedText: '3 × 5 @ 100 kg', setsDone: [] },
      { date: '2026-03-09', week: 2, x: 2, isDeload: true, elapsed: true, source: null, sessionName: 'A',
        done: {}, prescribed: { weight: 80, reps: 5 }, doneText: null, prescribedText: '3 × 5 @ 80 kg', setsDone: [] },
      { date: null, week: 3, x: 3, isDeload: false, elapsed: false, source: null, sessionName: 'A',
        done: {}, prescribed: { weight: 105 }, doneText: null, prescribedText: null, setsDone: [] },
    ],
  }
}

const section: ExerciseSeriesSection = {
  metrics: [{ id: 'weight', label: 'Top set', unit: 'kg' }, { id: 'reps', label: 'Reps', unit: 'reps' }],
  exercises: [exercise('press', 0), exercise('back_squat', 2)],
  measures: [{ id: 'rounds', label: 'Rounds', unit: 'rounds', philosophy: 'p', primitive: 'rounds' }],
}

const progress = [{
  id: 'rounds', label: 'Rounds', primitive: 'rounds', philosophy: 'p', unit: 'rounds',
  series: [{ week: 1, x: 1, value: 7, date: '2026-03-06', isDeload: false }],
  expected: [{ week: 1, x: 1, value: 8, date: '2026-03-06' }, { week: 2, x: 2, value: 8, date: '2026-03-13' }],
}, {
  id: 'ladder', label: 'Ladder', primitive: 'benchmark_level', philosophy: 'p', unit: 'level', series: [], expected: [],
}] as unknown as AnalyticsProgressEntry[]

describe('progress chart selection', () => {
  it('opens on the first logged exercise, at its default metric', () => {
    expect(resolveSelection({}, section, progress)).toEqual({ kind: 'exercise', id: 'back_squat', metric: 'weight' })
  })
  it('follows the URL, and keeps only a metric the exercise has', () => {
    expect(resolveSelection({ exercise: 'press', metric: 'reps' }, section, progress))
      .toEqual({ kind: 'exercise', id: 'press', metric: 'reps' })
    expect(resolveSelection({ exercise: 'press', metric: 'distance' }, section, progress))
      .toEqual({ kind: 'exercise', id: 'press', metric: 'weight' })
  })
  it('selects a measure the server names, never one it does not', () => {
    expect(resolveSelection({ measure: 'rounds' }, section, progress)).toEqual({ kind: 'measure', id: 'rounds' })
    expect(resolveSelection({ measure: 'ladder' }, section, progress)).toEqual({ kind: 'exercise', id: 'back_squat', metric: 'weight' })
  })
  it('falls back to a measure, then to nothing', () => {
    expect(resolveSelection({}, { ...section, exercises: [] }, progress)).toEqual({ kind: 'measure', id: 'rounds' })
    expect(resolveSelection({}, undefined, [])).toBeNull()
  })
})

describe('progress chart series', () => {
  it('draws an exercise metric done against prescribed, dated points only', () => {
    const s = seriesFor({ kind: 'exercise', id: 'back_squat', metric: 'weight' }, section, progress)!
    expect(s.unit).toBe('kg')
    expect(s.plannedLabel).toBe('Prescribed')
    expect(s.points.map((p) => [p.done, p.planned])).toEqual([[100, 100], [null, 80]])
  })
  it('draws a measure against its expectation, joined by session', () => {
    const s = seriesFor({ kind: 'measure', id: 'rounds' }, section, progress)!
    expect(s.plannedLabel).toBe('Expected')
    expect(s.points.map((p) => [p.date, p.done, p.planned])).toEqual([['2026-03-06', 7, 8], ['2026-03-13', null, 8]])
  })
  it('shades contiguous deload points', () => {
    const s = seriesFor({ kind: 'exercise', id: 'back_squat', metric: 'weight' }, section, progress)!
    expect(deloadSpans(s.points)).toEqual([[s.points[1].t, s.points[1].t]])
  })
})
