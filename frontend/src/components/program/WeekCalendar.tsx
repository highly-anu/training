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
}

export function WeekCalendar({ weekData }: WeekCalendarProps) {
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
            isToday={day === today}
          />
        ))}
      </div>
    </ScrollArea>
  )
}
