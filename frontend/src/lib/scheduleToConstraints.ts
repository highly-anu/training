/**
 * Converts a saved weekly schedule into the constraint fields that the
 * program generator expects (days_per_week, day_configs, preferred_days, etc.).
 *
 * Used by GuidedScheduler (live sync on step 3) and ReviewGenerate (override
 * at generation time) so both always use the same derivation logic.
 */
import type { Day, DaySchedule, SessionType } from '@/api/types'

const DAYS: Day[] = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

const SESSION_MINUTES: Record<SessionType, number> = {
  rest:     0,
  short:    40,
  long:     75,
  mobility: 20,
}

export interface ScheduleConstraints {
  days_per_week: number
  preferred_days: number[]
  forced_rest_days: number[]
  day_configs: Record<number, { minutes: number; has_secondary: boolean; session_types: SessionType[] }>
  allow_split_sessions: boolean
}

export function scheduleToConstraints(sched: Record<Day, DaySchedule>): ScheduleConstraints {
  const dayConfigs: ScheduleConstraints['day_configs'] = {}
  const preferredDays: number[] = []
  const forcedRestDays: number[] = []

  DAYS.forEach((dayName, idx) => {
    const dayIdx = idx + 1
    const daySchedule = sched[dayName]
    const sessions = [daySchedule.session1, daySchedule.session2, daySchedule.session3, daySchedule.session4]
    const nonRest = sessions.filter((s): s is SessionType => s !== 'rest')

    if (nonRest.length > 0) {
      preferredDays.push(dayIdx)
      const totalMinutes = nonRest.reduce((sum, s) => sum + (SESSION_MINUTES[s] ?? 0), 0)
      dayConfigs[dayIdx] = {
        minutes: totalMinutes,
        has_secondary: nonRest.length > 1,
        session_types: nonRest,
      }
    } else {
      forcedRestDays.push(dayIdx)
    }
  })

  return {
    days_per_week: preferredDays.length,
    preferred_days: preferredDays,
    forced_rest_days: forcedRestDays,
    day_configs: dayConfigs,
    allow_split_sessions: Object.values(dayConfigs).some((cfg) => cfg.has_secondary),
  }
}
