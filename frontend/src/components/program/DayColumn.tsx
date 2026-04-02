import { motion } from 'framer-motion'
import { Check, BatteryCharging } from 'lucide-react'
import { SessionCard } from './SessionCard'
import { cn } from '@/lib/utils'
import { useProfileStore } from '@/store/profileStore'
import type { Session } from '@/api/types'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const DAY_SHORT: Record<string, string> = {
  Monday: 'Mon', Tuesday: 'Tue', Wednesday: 'Wed', Thursday: 'Thu',
  Friday: 'Fri', Saturday: 'Sat', Sunday: 'Sun',
}

interface DayColumnProps {
  day: string
  sessions: Session[]
  weekNumber: number
  isToday: boolean
}

export function DayColumn({ day, sessions, weekNumber, isToday }: DayColumnProps) {
  const dayIndex = DAYS.indexOf(day)
  const isWeekend = dayIndex >= 5
  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const isComplete = sessions.length > 0 && sessions.every((_, i) => sessionLogs[`${weekNumber}-${day}`]?.[i] === true)

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0, transition: { delay: dayIndex * 0.04, duration: 0.2 } }}
      className="min-w-[120px] sm:min-w-0"
    >
      {/* Day header */}
      <div
        className={cn(
          'mb-2 rounded-md px-2 py-1 text-center text-xs font-semibold flex items-center justify-center gap-1',
          isComplete
            ? 'bg-emerald-500/15 text-emerald-500'
            : isToday
              ? 'bg-primary text-primary-foreground'
              : isWeekend
                ? 'bg-muted/50 text-muted-foreground'
                : 'bg-muted text-muted-foreground'
        )}
      >
        {isComplete && <Check className="size-2.5 shrink-0" />}
        <span className="hidden sm:block">{day}</span>
        <span className="sm:hidden">{DAY_SHORT[day]}</span>
      </div>

      {/* Sessions or rest */}
      <div className="space-y-2">
        {sessions.length > 0 ? (
          sessions.map((session, i) => (
            <SessionCard key={i} session={session} weekNumber={weekNumber} day={day} sessionIndex={i} />
          ))
        ) : (
          <div className="rounded-lg border border-dashed border-border/50 p-3 flex flex-col items-center justify-center gap-1.5">
            <BatteryCharging className="size-[30px] text-muted-foreground/50" />
            <span className="text-[10px] text-muted-foreground">Rest</span>
          </div>
        )}
      </div>
    </motion.div>
  )
}
