import type { PhaseSummary } from '@/api/types'

/** The summary for the i-th phase segment. Both are the program's phases in
 *  order; week numbers cannot be compared, because the calendar counts weeks
 *  from 1 while `week_number` may start later (an event-date program, or a
 *  regenerate that kept its head). */
export function findPhaseSummary(
  summaries: PhaseSummary[] | undefined, index: number, segmentCount: number,
): PhaseSummary | undefined {
  if (!summaries || summaries.length !== segmentCount) return undefined
  return summaries[index]
}
