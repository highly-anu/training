import type { BriefingItem, SessionBriefing } from '@/api/briefing'
import { series as seriesSummary } from '@/lib/chartSummary'
import { parseSessionKey } from '@/lib/sessionKeys'

export interface BriefingPoint {
  label: string
  value: number
  planned: boolean
  isDeload: boolean
}

/** Whether a briefing has anything beyond the prescription to say. */
export function saysSomething(b: SessionBriefing | undefined): boolean {
  if (!b) return false
  return b.pending.length > 0 || b.items.some((i) => i.times > 0 || !!i.suggestion || !!i.cycle || !!i.standard)
}

/**
 * The item's metric across its earlier occurrences, then today's as planned.
 * Fewer than three points is a list, not a chart, and so is a run that never
 * changes (a get-up a minute, every time).
 */
export function briefingSeries(item: BriefingItem): BriefingPoint[] {
  const key = item.metric?.id
  // Several exercises have several runs: their rows say it, one chart of the first would not.
  if (!key || (item.exercises?.length ?? 0) > 1) return []
  const out: BriefingPoint[] = item.history
    .filter((h) => typeof h.values?.[key] === 'number')
    .map((h) => ({ label: h.dayText, value: h.values[key], planned: false, isDeload: h.isDeload }))
  const today = item.today.values?.[key]
  if (typeof today === 'number') out.push({ label: 'Today', value: today, planned: true, isDeload: false })
  return out.length >= 3 && new Set(out.map((p) => p.value)).size > 1 ? out : []
}

/** The series in words, for the chart's label. */
export function briefingSeriesSummary(item: BriefingItem): string | null {
  const points = briefingSeries(item)
  if (!points.length) return null
  return seriesSummary(points.map((p) => p.value), item.metric?.unit ?? '')
}

/** The program page of the session a key names ("3-Thursday-0" → /program/3/Thursday). */
export function sessionPath(sessionKey: string): string | null {
  const parsed = parseSessionKey(sessionKey)
  return parsed ? `/program/${parsed.weekNumber}/${parsed.dayName}` : null
}
