import type { DevelopmentBlock, DevelopmentLift, DevelopmentCurrency } from '@/api/types'

/**
 * Pure shaping for the Development tab's charts: block bands on a time axis,
 * a lift's series as timestamps, and a block's colour — so the components
 * only lay out and a test can pin the arithmetic.
 */

/** Five muted hues, cycled; a block keeps its colour across every chart. */
export const BLOCK_PALETTE = ['#6366f1', '#10b981', '#f59e0b', '#ec4899', '#0ea5e9'] as const

export function blockColor(blocks: DevelopmentBlock[], blockId: number | null | undefined): string {
  const idx = blocks.findIndex((b) => b.id === blockId)
  return idx < 0 ? '#9ca3af' : BLOCK_PALETTE[idx % BLOCK_PALETTE.length]
}

export function dayStamp(iso: string): number {
  return new Date(`${iso.slice(0, 10)}T00:00:00`).getTime()
}

export interface BlockBand {
  id: number
  label: string
  x1: number
  x2: number
  color: string
  isActive: boolean
}

/** One band per block on a numeric time axis; an active block runs to today. */
export function blockBands(blocks: DevelopmentBlock[], today: string): BlockBand[] {
  return blocks.map((b) => ({
    id: b.id,
    label: b.methodologies.map((m) => m.name).join(' + ') || b.label,
    x1: dayStamp(b.from),
    x2: dayStamp(b.to ?? today),
    color: blockColor(blocks, b.id),
    isActive: b.isActive,
  }))
}

export interface SeriesPoint {
  x: number
  date: string
  value: number
  blockId: number | null
  isDeload: boolean
  reps?: number | null
  weight?: number
}

/** A lift's series on the time axis: est-1RM where there is one, else the weight. */
export function liftSeries(lift: DevelopmentLift): SeriesPoint[] {
  return lift.points
    .map((p) => ({
      x: dayStamp(p.date), date: p.date, value: p.est1rm ?? p.weight, blockId: p.blockId,
      isDeload: p.isDeload, reps: p.reps, weight: p.weight,
    }))
    .filter((p) => Number.isFinite(p.value))
}

export function currencySeries(currency: DevelopmentCurrency): SeriesPoint[] {
  return currency.points.map((p) => ({
    x: dayStamp(p.date), date: p.date, value: p.value, blockId: p.blockId, isDeload: p.isDeload,
  }))
}

/** "+12.5" / "−3" / "0" for a delta, in the series' unit. */
export function formatDelta(delta: number): string {
  if (delta > 0) return `+${trim(delta)}`
  if (delta < 0) return `−${trim(Math.abs(delta))}`
  return '0'
}

function trim(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

export const METRIC_UNIT: Record<DevelopmentCurrency['metric'], string> = {
  rounds: 'rounds', minutes: 'min', km: 'km',
}
