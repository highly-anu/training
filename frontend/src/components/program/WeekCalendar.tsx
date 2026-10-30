import { DayColumn } from './DayColumn'
import { ScrollArea } from '@/components/ui/scroll-area'
import type { WeekData } from '@/api/types'
import { format } from 'date-fns'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

function getTodayName(): string {
  const day = format(new Date(), 'EEEE')
  return DAYS.includes(day) ? day : ''
}

interface WeekCalendarProps {
  weekData: WeekData
  isCurrentWeek: boolean
  /** A draft program (the preview): sessions open through this, logs are not read. */
  onOpenSession?: (day: string, sessionIndex: number) => void
  isHighlighted?: (day: string, sessionIndex: number) => boolean
  /** The days that may take an added session (today and later), and what adds one. */
  canAdd?: (day: string) => boolean
  onAddSession?: (day: string) => void
}

export function WeekCalendar({ weekData, isCurrentWeek, onOpenSession, isHighlighted, canAdd, onAddSession }: WeekCalendarProps) {
  const today = getTodayName()

  return (
    <ScrollArea className="w-full">
      <div className="grid min-w-[700px] grid-cols-7 gap-2 pb-2">
        {DAYS.map((day) => (
          <DayColumn
            key={day}
            day={day}
            sessions={weekData.schedule[day] ?? []}
            weekNumber={weekData.week_number}
            isToday={isCurrentWeek && day === today}
            onOpenSession={onOpenSession ? (i) => onOpenSession(day, i) : undefined}
            isHighlighted={isHighlighted ? (i) => isHighlighted(day, i) : undefined}
            onAdd={onAddSession && canAdd?.(day) ? () => onAddSession(day) : undefined}
          />
        ))}
      </div>
    </ScrollArea>
  )
}
