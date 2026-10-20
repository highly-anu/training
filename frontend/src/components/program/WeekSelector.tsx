import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import type { TrainingPhase } from '@/api/types'

interface WeekSelectorProps {
  week: number
  totalWeeks: number
  phase: TrainingPhase
  isDeload: boolean
  onPrev: () => void
  onNext: () => void
  /** Override prev disabled state (default: week <= 1) */
  prevDisabled?: boolean
  /** Override next disabled state (default: week >= totalWeeks) */
  nextDisabled?: boolean
  /** The philosophy's own phase name; the badge falls back to the kind. */
  phaseLabel?: string
}

/**
 * The arrows hold only the week number, so they stay put while the phase pill
 * beside them changes width from one phase name to the next.
 */
export function WeekSelector({ week, totalWeeks, phase, phaseLabel, isDeload, onPrev, onNext, prevDisabled, nextDisabled }: WeekSelectorProps) {
  return (
    <div className="flex items-center gap-3">
      <div className="flex items-center gap-1.5">
        <Button variant="outline" size="icon" onClick={onPrev} disabled={prevDisabled ?? week <= 1} className="size-8" aria-label="Previous week">
          <ChevronLeft className="size-4" />
        </Button>
        <span className="min-w-24 text-center text-sm font-semibold text-foreground tabular-nums">
          Week {week} <span className="text-muted-foreground font-normal">/ {totalWeeks}</span>
        </span>
        <Button variant="outline" size="icon" onClick={onNext} disabled={nextDisabled ?? week >= totalWeeks} className="size-8" aria-label="Next week">
          <ChevronRight className="size-4" />
        </Button>
      </div>
      <div className="flex items-center gap-1.5">
        <PhaseBadge phase={phase} label={phaseLabel} />
        {isDeload && (
          <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-500/15 text-slate-700 dark:text-slate-300 border border-slate-500/30">
            Deload
          </span>
        )}
      </div>
    </div>
  )
}
