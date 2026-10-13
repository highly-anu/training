import { cn } from '@/lib/utils'
import { PHASE_COLORS } from '@/lib/phaseColors'
import type { PhaseKind } from '@/api/types'

interface PhaseBadgeProps {
  /** The phase kind: sets the colour. */
  phase: PhaseKind
  /** The philosophy's own phase name; falls back to the kind's label. */
  label?: string
  className?: string
}

export function PhaseBadge({ phase, label, className }: PhaseBadgeProps) {
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
      {label ?? colors.label}
    </span>
  )
}
