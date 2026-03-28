import { format } from 'date-fns'
import { Check } from 'lucide-react'
import { cn } from '@/lib/utils'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { useProfileStore } from '@/store/profileStore'
import type { WeekData } from '@/api/types'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const DAY_SHORT = ['M', 'T', 'W', 'T', 'F', 'S', 'S']

interface WeekOverviewProps {
  weekData: WeekData | undefined
}

function getTodayName() {
  return format(new Date(), 'EEEE')
}

export function WeekOverview({ weekData }: WeekOverviewProps) {
  const today = getTodayName()
  const sessionLogs = useProfileStore((s) => s.sessionLogs)

  return (
    <div className="flex gap-1.5 sm:gap-2">
      {DAYS.map((day, i) => {
        const sessions = weekData?.schedule[day] ?? []
        const isToday = day === today
        const hasSession = sessions.length > 0
        const firstModality = sessions[0]?.modality
        const colors = firstModality ? MODALITY_COLORS[firstModality] : null
        const isComplete = hasSession && sessionLogs[`${weekData?.week_number}-${day}`]?.[0] === true

        return (
          <div key={day} className="flex flex-col items-center gap-1 flex-1">
            <div
              className={cn(
                'flex size-8 items-center justify-center rounded-full text-[10px] font-semibold transition-colors border',
                isComplete
                  ? 'border-emerald-500/40 bg-emerald-500/15 text-emerald-500'
                  : isToday && hasSession
                    ? 'border-primary bg-primary text-primary-foreground shadow-md shadow-primary/20'
                    : isToday
                      ? 'border-primary bg-primary/10 text-primary'
                      : hasSession && colors
                        ? `${colors.bg} ${colors.text} border-transparent`
                        : 'border-border bg-muted/50 text-muted-foreground'
              )}
              title={day}
            >
              {isComplete ? <Check className="size-3.5" /> : DAY_SHORT[i]}
            </div>
            {hasSession && (
              <div
                className="size-1 rounded-full"
                style={{ backgroundColor: isComplete ? '#22c55e' : (colors?.hex ?? 'var(--muted-foreground)') }}
              />
            )}
          </div>
        )
      })}
    </div>
  )
}
