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
}

export function WeekSelector({ week, totalWeeks, phase, isDeload, onPrev, onNext }: WeekSelectorProps) {
  return (
    <div className="flex items-center gap-3">
      <Button variant="outline" size="icon" onClick={onPrev} disabled={week <= 1} className="size-8">
        <ChevronLeft className="size-4" />
      </Button>
      <div className="flex items-center gap-2 min-w-32 justify-center">
        <span className="text-sm font-semibold text-foreground">
          Week {week} <span className="text-muted-foreground font-normal">/ {totalWeeks}</span>
        </span>
        <PhaseBadge phase={phase} />
        {isDeload && (
          <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-slate-500/15 text-slate-400 border border-slate-500/30">
            Deload
          </span>
        )}
      </div>
      <Button variant="outline" size="icon" onClick={onNext} disabled={week >= totalWeeks} className="size-8">
        <ChevronRight className="size-4" />
      </Button>
    </div>
  )
}
