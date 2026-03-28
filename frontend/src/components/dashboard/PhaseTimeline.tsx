import { cn } from '@/lib/utils'
import { PHASE_COLORS } from '@/lib/phaseColors'
import { usePhaseCalendar } from '@/hooks/usePhaseCalendar'
import type { GoalProfile } from '@/api/types'

interface PhaseTimelineProps {
  goal: GoalProfile
  currentWeek?: number
}

export function PhaseTimeline({ goal, currentWeek = 1 }: PhaseTimelineProps) {
  const { segments, totalWeeks, weeksToEvent } = usePhaseCalendar(goal, currentWeek)

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Phase Timeline</h3>
        {weeksToEvent !== null && weeksToEvent > 0 && (
          <span className="text-xs text-muted-foreground">{weeksToEvent} weeks to event</span>
        )}
      </div>

      {/* Proportional bar */}
      <div className="relative flex h-5 w-full overflow-hidden rounded-lg">
        {segments.map((seg) => {
          const pct = (seg.weeks / totalWeeks) * 100
          const colors = PHASE_COLORS[seg.phase]
          const isCurrent = currentWeek >= seg.startWeek && currentWeek <= seg.endWeek
          return (
            <div
              key={seg.phase + seg.startWeek}
              className={cn('relative flex items-center justify-center transition-all', colors.bg, isCurrent && 'ring-1 ring-inset ring-white/20')}
              style={{ width: `${pct}%` }}
              title={`${colors.label}: weeks ${seg.startWeek}–${seg.endWeek}`}
            >
              <span className={cn('text-[9px] font-medium truncate px-1', colors.text)}>
                {pct > 12 ? colors.label : ''}
              </span>
              {/* Current week marker */}
              {isCurrent && (
                <div className="absolute right-0 top-0 h-full w-0.5 bg-primary" />
              )}
            </div>
          )
        })}
      </div>

      {/* Week labels */}
      <div className="flex justify-between text-[10px] text-muted-foreground">
        <span className={currentWeek === 1 ? 'text-primary font-medium' : ''}>Week 1</span>
        {currentWeek > 1 && currentWeek < totalWeeks && (
          <span className="text-primary font-medium">Week {currentWeek}</span>
        )}
        <span className={currentWeek === totalWeeks ? 'text-primary font-medium' : ''}>Week {totalWeeks}</span>
      </div>
    </div>
  )
}
