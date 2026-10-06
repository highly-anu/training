import { format, parseISO } from 'date-fns'
import type { WellnessReading } from '@/api/types'

/** "6 Oct, 07:31 · resting HR 46 · Body Battery 95 · recovery 58 h" — only
 *  what the watch actually read. */
export function wellnessSummary(r: WellnessReading): string {
  let at = r.date
  try { at = format(parseISO(r.read_at ?? r.date), r.read_at ? 'd MMM, HH:mm' : 'd MMM') } catch { /* keep the date */ }
  const parts = [at]
  if (r.resting_hr != null) parts.push(`resting HR\u00a0${r.resting_hr}`)
  if (r.body_battery_max != null) parts.push(`Body Battery\u00a0${r.body_battery_max}`)
  if (r.recovery_time_h != null) parts.push(`recovery\u00a0${r.recovery_time_h}\u00a0h`)
  return parts.join(' · ')
}
