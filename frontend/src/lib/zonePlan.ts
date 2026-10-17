import type { WorkoutPlanned } from '@/api/types'

/** Planned against recorded minutes per heart-rate zone, for
 *  components/bio/ZonePlanComparison.tsx (the phone's ZonePlanComparison.swift). */
export interface ZonePlanRow { zone: string; label: string; planned: number; recorded: number }

/** Rows from the five-zone arrays the server sends, only zones with either side. */
export function zonePlanRows(planned: number[], recorded: number[]): ZonePlanRow[] {
  return [0, 1, 2, 3, 4].flatMap((i) => {
    const p = planned[i] ?? 0
    const r = recorded[i] ?? 0
    return Math.round(p) || Math.round(r) ? [{ zone: `z${i + 1}`, label: `Z${i + 1}`, planned: p, recorded: r }] : []
  })
}

/** "Its programming prescribes load or effort (main: heavy), not heart-rate zones — …" */
export function untrackedText(plan: WorkoutPlanned): string {
  if (plan.source === 'declared') {
    return "This session's programming doesn't track heart rate — the zones are for reference and not counted in the intensity split."
  }
  const what = plan.notZoned.length ? ` (${plan.notZoned.join(', ')})` : ''
  return `Its programming prescribes load or effort${what}, not heart-rate zones — the zones are for reference and not counted in the intensity split.`
}
