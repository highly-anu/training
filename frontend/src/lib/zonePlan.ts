import type { WorkoutPlanned, WorkoutPlannedSlot } from '@/api/types'

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

const words = (s: string) => s.replace(/_/g, ' ')
const capitalised = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

/** "Zone 2", "Zones 1–2", or the load word ("heavy", "max effort"). */
export function prescriptionText(slot: WorkoutPlannedSlot): string {
  if (slot.zones.length === 1) return `Zone ${slot.zones[0]}`
  if (slot.zones.length > 1) return `Zones ${slot.zones[0]}–${slot.zones[slot.zones.length - 1]}`
  return words(slot.intensity ?? 'load')
}

/** One exercise row of a workout against its plan: what was done, what the
 *  program prescribed, and what of it counts in the zones. */
export function exerciseRow(slot: WorkoutPlannedSlot, timing: WorkoutPlanned['timing']) {
  const title = slot.exercises.length ? slot.exercises.join(', ') : capitalised(words(slot.role))
  const recorded = slot.recordedMinutes ? Math.round(slot.recordedMinutes.reduce((a, b) => a + b, 0)) : null
  const planned = Math.round(slot.plannedMinutes)
  let detail: string
  if (slot.prescribes === 'load') {
    detail = recorded !== null ? `${recorded} min · not counted` : 'not counted'
  } else if (recorded !== null && slot.counted) {
    detail = planned ? `${recorded} of ${planned} min` : `${recorded} min`
  } else if (timing === 'whole') {
    detail = planned ? `${planned} min planned` : 'counted'
  } else if (timing === 'untimed') {
    detail = 'not timed'
  } else {
    detail = planned ? `${planned} min planned` : ''
  }
  return { title, prescription: prescriptionText(slot), detail, counted: slot.counted }
}

/** The sentence under the comparison: what counted and why, or why nothing did. */
export function planNote(plan: WorkoutPlanned): string | null {
  switch (plan.timing) {
    case 'whole':
      return null
    case 'timeline':
      return 'Only the exercises that prescribe heart-rate zones count, inside the times the watch logged for them; the rest of the session is max effort.'
    case 'untimed':
      return "Some exercises prescribe heart-rate zones, but the watch didn't time them, so none of this workout counts in zones. Record the session on the watch to split it by exercise."
    case 'unrecorded':
      return 'No heart rate was recorded to compare.'
    case 'none':
      return untrackedText(plan)
  }
}

/** "Its programming prescribes load or effort (main: heavy), not heart-rate zones — …" */
export function untrackedText(plan: WorkoutPlanned): string {
  if (plan.source === 'declared') {
    return "This session's programming doesn't track heart rate — the zones are for reference and not counted in the intensity split."
  }
  const what = plan.notZoned.length ? ` (${plan.notZoned.join(', ')})` : ''
  return `Its programming prescribes load or effort${what}, not heart-rate zones — the zones are for reference and not counted in the intensity split.`
}
