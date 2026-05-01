import { cn } from '@/lib/utils'
import { PHASE_COLORS } from '@/lib/phaseColors'
import type { PhaseSegment } from '@/hooks/usePhaseCalendar'

interface PhaseBarProps {
  segments: PhaseSegment[]
  totalWeeks: number
  currentWeek: number
}

export function PhaseBar({ segments, totalWeeks, currentWeek }: PhaseBarProps) {
  if (!segments.length) return null

  return (
    <div className="space-y-1.5">
      <div className="flex h-3 w-full overflow-hidden rounded-full bg-muted">
        {segments.map((seg) => {
          const pct = (seg.weeks / totalWeeks) * 100
          const colors = PHASE_COLORS[seg.phase] ?? { bg: 'bg-muted', text: 'text-muted-foreground', label: seg.phase, hex: '#888' }
          return (
            <div
              key={seg.phase + seg.startWeek}
              className={cn('transition-all', colors.bg)}
              style={{ width: `${pct}%` }}
              title={`${colors.label}: weeks ${seg.startWeek}–${seg.endWeek}`}
            />
          )
        })}
      </div>

      {/* Phase labels */}
      <div className="flex w-full">
        {segments.map((seg) => {
          const pct = (seg.weeks / totalWeeks) * 100
          const colors = PHASE_COLORS[seg.phase] ?? { bg: 'bg-muted', text: 'text-muted-foreground', label: seg.phase, hex: '#888' }
          const isCurrent = currentWeek >= seg.startWeek && currentWeek <= seg.endWeek
          return (
            <div
              key={seg.phase + seg.startWeek}
              className={cn('text-center overflow-hidden', isCurrent && 'font-bold')}
              style={{ width: `${pct}%` }}
            >
              <span className={cn('text-[9px] sm:text-[10px] truncate', colors.text)}>
                {colors.label}
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
