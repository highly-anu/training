import type { BriefingItem, BriefingMetric, BriefingOccurrence, SessionBriefing } from '@/api/briefing'
import { series as seriesSummary } from '@/lib/chartSummary'
import { parseSessionKey } from '@/lib/sessionKeys'

export interface BriefingPoint {
  label: string
  value: number
  planned: boolean
  isDeload: boolean
}

/**
 * The block's unit (frontend-design §13.10): one exercise — its name, today's
 * numbers and every earlier time as one mark each. The dated lines, the chart,
 * the standard and the note are the row's sheet. The phone's is
 * `SessionBriefing.Row`; the two read the document the same way.
 */
export interface BriefingRow {
  id: string
  /** The item's name over its first row, when it has several exercises. */
  header?: string
  headerDetail?: string
  name: string
  todayText: string
  todayValue?: number
  /** Every earlier time, oldest first. */
  run: BriefingOccurrence[]
  metric?: BriefingMetric
  /** "6 sessions", "First time"; an item of one exercise in a cycle, "Step 7 of 32". */
  caption: string
  /** The item's one suggestion, under its last row. */
  suggestion?: { kind: string; text: string }
  item: BriefingItem
}

/** The most marks a strip draws: the newest of a longer run. */
export const STRIP_MAX = 40

/** Whether a briefing has anything beyond the prescription to say. */
export function saysSomething(b: SessionBriefing | undefined): boolean {
  if (!b) return false
  return b.pending.length > 0 || b.items.some((i) => i.times > 0 || !!i.suggestion || !!i.cycle || !!i.standard)
}

const caption = (times: number, text?: string) =>
  text ?? (times === 0 ? 'First time' : times === 1 ? '1 session' : `${times} sessions`)

/**
 * The rows of the block, in the session's order. An item of one exercise is
 * one row under the item's name, its cycle position the short caption ("Step
 * 7 of 32" — the stages are the sheet's); an item of several is headed once.
 * A session to confirm holds up every module of the day: that sentence is
 * said by the first and not again.
 */
export function briefingRows(b: SessionBriefing): BriefingRow[] {
  const said = new Set<string>()
  return b.items.flatMap((item): BriefingRow[] => {
    const exercises = item.exercises ?? []
    const several = exercises.length > 1
    const repeated = item.suggestion?.kind === 'confirm_pending' && said.has(item.suggestion.text)
    const suggestion = repeated ? undefined : item.suggestion
    if (suggestion) said.add(suggestion.text)
    const cycle = item.cycle ? `Step ${item.cycle.step} of ${item.cycle.of}` : undefined
    const valued = (rows: BriefingOccurrence[], key?: string) =>
      rows.map((o) => ({ ...o, value: o.value ?? (key ? o.values?.[key] : undefined) }))
    if (!exercises.length) {
      // A server that sends no exercises: the item is its own row.
      const key = item.metric?.id
      return [{
        id: item.id, name: item.title, todayText: item.today.lines?.[0]?.text ?? item.today.text,
        todayValue: key ? item.today.values?.[key] : undefined, run: valued(item.history, key), metric: item.metric,
        caption: cycle ?? caption(item.times), suggestion, item,
      }]
    }
    return exercises.map((e, index): BriefingRow => {
      const metric = e.metric ?? (several ? undefined : item.metric)
      const run = e.run ?? valued(e.history, metric?.id)
      return {
        id: `${item.id}/${e.exerciseId}`,
        header: several && index === 0 ? item.title : undefined,
        headerDetail: several && index === 0 ? item.cycle?.text : undefined,
        name: several ? e.name : item.title,
        todayText: e.today.text || item.today.text,
        todayValue: e.today.value ?? (e.run || !metric ? undefined : item.today.values?.[metric.id]),
        run, metric,
        caption: (several ? undefined : cycle) ?? caption(e.times ?? (several ? run.length : item.times), e.timesText),
        suggestion: index === exercises.length - 1 ? suggestion : undefined,
        item,
      }
    })
  })
}

/** The marks a strip draws: the newest `max` of the run. */
export function stripMarks(row: BriefingRow, max = STRIP_MAX): BriefingOccurrence[] {
  return max > 0 ? row.run.slice(-max) : []
}

/**
 * How tall a strip's mark is, as a share of the strip: the run's lowest number
 * a third, its highest the whole, so a small step still shows; a mark without
 * a number, or a run that never moves, sits in between.
 */
export function markHeight(value: number | undefined, values: number[]): number {
  if (value === undefined || !values.length) return 0.6
  const lo = Math.min(...values), hi = Math.max(...values)
  return hi > lo ? 1 / 3 + ((2 / 3) * (value - lo)) / (hi - lo) : 0.6
}

/**
 * The sheet's chart: every earlier time's number, then today's as planned.
 * Fewer than three points is a list, not a chart, and so is a run that never
 * changes (a get-up a minute, every time).
 */
export function rowSeries(row: BriefingRow): BriefingPoint[] {
  const out: BriefingPoint[] = row.run
    .filter((o) => typeof o.value === 'number')
    .map((o) => ({ label: o.dayText, value: o.value as number, planned: false, isDeload: o.isDeload }))
  if (typeof row.todayValue === 'number') out.push({ label: 'Today', value: row.todayValue, planned: true, isDeload: false })
  return out.length >= 3 && new Set(out.map((p) => p.value)).size > 1 ? out : []
}

/** The series in words, for the chart's label. */
export function rowSeriesSummary(row: BriefingRow): string | null {
  const points = rowSeries(row)
  if (!points.length) return null
  return seriesSummary(points.map((p) => p.value), row.metric?.unit ?? '')
}

const STATUS_WORD: Record<string, string> = {
  clean: 'clean', made: 'made', missed: 'missed', logged: 'logged', unconfirmed: 'not confirmed',
}

/** The row read aloud as one element. */
export function rowLabel(row: BriefingRow): string {
  const parts = [`${row.name}. Today: ${row.todayText}`, row.caption]
  if (row.run.length && !row.caption.includes('session')) {
    parts.push(row.run.length === 1 ? '1 earlier session' : `${row.run.length} earlier sessions`)
  }
  const last = row.run[row.run.length - 1]
  if (last) parts.push(`Last, ${last.dayText}: ${last.text}, ${STATUS_WORD[last.status] ?? 'logged'}`)
  if (row.suggestion) parts.push(row.suggestion.text)
  return parts.join('. ')
}

/** The program page of the session a key names ("3-Thursday-0" → /program/3/Thursday). */
export function sessionPath(sessionKey: string): string | null {
  const parsed = parseSessionKey(sessionKey)
  return parsed ? `/program/${parsed.weekNumber}/${parsed.dayName}` : null
}
