import { motion } from 'framer-motion'
import { Check, BatteryCharging, Plus } from 'lucide-react'
import { SessionCard } from './SessionCard'
import { cn } from '@/lib/utils'
import { useProfileStore } from '@/store/profileStore'
import type { Session } from '@/api/types'
import { COMPLETION } from '@/lib/completionColors'

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
  /** A draft program (SessionCard's onOpen): opens a session, never reads logs. */
  onOpenSession?: (sessionIndex: number) => void
  isHighlighted?: (sessionIndex: number) => boolean
  /** Today or a later day of the active program: a session can be added. */
  onAdd?: () => void
}

export function DayColumn({ day, sessions, weekNumber, isToday, onOpenSession, isHighlighted, onAdd }: DayColumnProps) {
  const dayIndex = DAYS.indexOf(day)
  const isWeekend = dayIndex >= 5
  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const logged = (i: number) => sessionLogs[`${weekNumber}-${day}`]?.[i] === true
  // An extra the athlete added counts once done, never as one still to do.
  const counted = sessions.map((_, i) => i).filter((i) => !sessions[i].added || logged(i))
  const isComplete = !onOpenSession && counted.length > 0 && counted.every(logged)
  const addButton = onAdd && (
    <button type="button" onClick={onAdd} aria-label={`Add a session on ${day}`}
      className="w-full rounded-md border border-dashed border-border/50 py-1 text-[10px] text-muted-foreground hover:border-primary/40 hover:text-foreground transition-colors flex items-center justify-center gap-1">
      <Plus className="size-3" /> Add
    </button>
  )

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
            ? cn('bg-emerald-500/15', COMPLETION.text)
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
            <SessionCard key={i} session={session} weekNumber={weekNumber} day={day} sessionIndex={i}
              onOpen={onOpenSession ? () => onOpenSession(i) : undefined}
              highlight={isHighlighted?.(i)} />
          ))
        ) : (
          <div className="rounded-lg border border-dashed border-border/50 p-3 flex flex-col items-center justify-center gap-1.5">
            <BatteryCharging className="size-[30px] text-muted-foreground/50" />
            <span className="text-[10px] text-muted-foreground">Rest</span>
            {onAdd && addButton}
          </div>
        )}
        {/* Today can take one more after its sessions; other days only when resting. */}
        {onAdd && sessions.length > 0 && isToday && addButton}
      </div>
    </motion.div>
  )
}
