import type {
  AnalyticsProgressEntry,
  ExerciseSeriesExercise,
  ExerciseSeriesMetricId,
  ExerciseSeriesPoint,
  ExerciseSeriesSection,
} from '@/api/types'

/**
 * The Progress tab's one chart: which series is selected, and its points on
 * one date axis. Every number is the server's (`exerciseSeries`, `progress`);
 * this only picks and lines them up.
 */

export type ChartSelection =
  | { kind: 'exercise'; id: string; metric: ExerciseSeriesMetricId }
  /** `id` is `measureKey`: a blend repeats entry ids (Uphill's and Horsemen's aerobic_volume). */
  | { kind: 'measure'; id: string }

/** "philosophy:id", one measure's key. */
export function measureKey(entry: { philosophy: string; id: string }): string {
  return `${entry.philosophy}:${entry.id}`
}

/** A link's `measure`: the key, or a bare entry id (the first methodology's). */
function findMeasure<T extends { philosophy: string; id: string }>(measures: T[], wanted: string): T | undefined {
  return measures.find((m) => measureKey(m) === wanted) ?? measures.find((m) => m.id === wanted)
}

export interface ChartPoint {
  /** Milliseconds, for a numeric time axis. */
  t: number
  date: string
  done: number | null
  planned: number | null
  isDeload: boolean
  elapsed: boolean
  sessionName?: string | null
  doneText?: string | null
  prescribedText?: string | null
}

export interface ChartSeries {
  label: string
  unit: string
  /** What the dashed line is: the program's prescription, or the measure's expectation. */
  plannedLabel: 'Prescribed' | 'Expected'
  points: ChartPoint[]
}

/** The measures the chart can draw: those the server names in `exerciseSeries.measures`. */
export function chartableMeasures(section: ExerciseSeriesSection | undefined, progress: AnalyticsProgressEntry[]) {
  const named = new Set((section?.measures ?? []).map(measureKey))
  return progress.filter((p) => named.has(measureKey(p)))
}

/**
 * The URL's `exercise` / `measure` / `metric`, read against what the document
 * has; else the first logged exercise, else the first measure, else the first
 * exercise. Null when there is nothing to draw.
 */
export function resolveSelection(
  params: { exercise?: string | null; measure?: string | null; metric?: string | null },
  section: ExerciseSeriesSection | undefined,
  progress: AnalyticsProgressEntry[],
): ChartSelection | null {
  const exercises = section?.exercises ?? []
  const measures = chartableMeasures(section, progress)
  const metricFor = (ex: ExerciseSeriesExercise): ExerciseSeriesMetricId =>
    params.metric && ex.metrics.includes(params.metric as ExerciseSeriesMetricId)
      ? (params.metric as ExerciseSeriesMetricId)
      : ex.defaultMetric
  if (params.exercise) {
    const ex = exercises.find((e) => e.exerciseId === params.exercise)
    if (ex) return { kind: 'exercise', id: ex.exerciseId, metric: metricFor(ex) }
  }
  if (params.measure) {
    const m = findMeasure(measures, params.measure)
    if (m) return { kind: 'measure', id: measureKey(m) }
  }
  const logged = exercises.find((e) => e.logged > 0)
  if (logged) return { kind: 'exercise', id: logged.exerciseId, metric: metricFor(logged) }
  if (measures.length) return { kind: 'measure', id: measureKey(measures[0]) }
  if (exercises.length) return { kind: 'exercise', id: exercises[0].exerciseId, metric: metricFor(exercises[0]) }
  return null
}

function toMs(date: string): number {
  return new Date(`${date.slice(0, 10)}T12:00:00`).getTime()
}

function exercisePoint(p: ExerciseSeriesPoint, metric: ExerciseSeriesMetricId): ChartPoint | null {
  if (!p.date) return null
  return {
    t: toMs(p.date), date: p.date, done: p.done[metric] ?? null, planned: p.prescribed[metric] ?? null,
    isDeload: p.isDeload, elapsed: p.elapsed, sessionName: p.sessionName,
    doneText: p.doneText, prescribedText: p.prescribedText,
  }
}

/** A measure's own line, or its lead exercise's for a load measure. */
function measurePoints(entry: AnalyticsProgressEntry): ChartPoint[] {
  const lead = (entry.exercises ?? []).find((e) => e.exerciseId === entry.leadExerciseId) ?? entry.exercises?.[0]
  const series = lead ? lead.series : entry.series
  const expected = lead ? lead.expected : entry.expected
  const byKey = new Map<string, ChartPoint>()
  for (const p of series) {
    if (!p.date) continue
    byKey.set(`${p.x}`, { t: toMs(p.date), date: p.date, done: p.value, planned: null, isDeload: p.isDeload, elapsed: true })
  }
  for (const e of expected) {
    if (!e.date) continue
    const had = byKey.get(`${e.x}`)
    byKey.set(`${e.x}`, had ? { ...had, planned: e.value }
      : { t: toMs(e.date), date: e.date, done: null, planned: e.value, isDeload: false, elapsed: true })
  }
  return [...byKey.values()].sort((a, b) => a.t - b.t)
}

export function seriesFor(
  selection: ChartSelection,
  section: ExerciseSeriesSection | undefined,
  progress: AnalyticsProgressEntry[],
): ChartSeries | null {
  if (selection.kind === 'exercise') {
    const ex = section?.exercises.find((e) => e.exerciseId === selection.id)
    if (!ex) return null
    const metric = section?.metrics.find((m) => m.id === selection.metric)
    return {
      label: ex.name, unit: metric?.unit ?? '', plannedLabel: 'Prescribed',
      points: ex.points.map((p) => exercisePoint(p, selection.metric)).filter((p): p is ChartPoint => p != null),
    }
  }
  const entry = findMeasure(progress, selection.id)
  if (!entry) return null
  const lead = (entry.exercises ?? []).find((e) => e.exerciseId === entry.leadExerciseId)
  return {
    label: lead ? `${entry.label} · ${lead.name}` : entry.label,
    unit: lead?.unit ?? entry.unit, plannedLabel: 'Expected', points: measurePoints(entry),
  }
}

/** Deload spans to shade: contiguous deload points, first to last date. */
export function deloadSpans(points: ChartPoint[]): Array<[number, number]> {
  const spans: Array<[number, number]> = []
  let start: number | null = null
  let last: number | null = null
  for (const p of points) {
    if (p.isDeload) {
      if (start == null) start = p.t
      last = p.t
    } else if (start != null && last != null) {
      spans.push([start, last])
      start = last = null
    }
  }
  if (start != null && last != null) spans.push([start, last])
  return spans
}
