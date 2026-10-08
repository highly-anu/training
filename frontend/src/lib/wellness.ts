import { format, parseISO } from 'date-fns'
import type { WellnessReading } from '@/api/types'

/** "8 Oct, 07:20 · HR low 47 · 7-day resting HR 47 · Body Battery 75 · recovery 82 h"
 *  — only what the watch actually read. Not the profile's `resting_hr`: that
 *  is the zone setting, which sat at 46 while the watch showed 45 and 49. */
export function wellnessSummary(r: WellnessReading): string {
  let at = r.date
  try { at = format(parseISO(r.read_at ?? r.date), r.read_at ? 'd MMM, HH:mm' : 'd MMM') } catch { /* keep the date */ }
  const parts = [at]
  if (r.hr_min != null) parts.push(`HR low\u00a0${r.hr_min}`)
  if (r.resting_hr_7d_avg != null) parts.push(`7-day resting HR\u00a0${r.resting_hr_7d_avg}`)
  if (r.body_battery_max != null) parts.push(`Body Battery\u00a0${r.body_battery_max}`)
  if (r.recovery_time_h != null) parts.push(`recovery\u00a0${r.recovery_time_h}\u00a0h`)
  return parts.join(' · ')
}
