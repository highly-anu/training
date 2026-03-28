import { cn } from '@/lib/utils'
import { PHASE_COLORS } from '@/lib/phaseColors'
import type { TrainingPhase } from '@/api/types'

interface PhaseBadgeProps {
  phase: TrainingPhase
  className?: string
}

export function PhaseBadge({ phase, className }: PhaseBadgeProps) {
  const colors = PHASE_COLORS[phase]
  if (!colors) return null

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium',
        colors.bg,
        colors.text,
        className
      )}
    >
      {colors.label}
    </span>
  )
}
