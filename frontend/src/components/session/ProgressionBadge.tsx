import { TrendingUp } from 'lucide-react'

interface ProgressionBadgeProps {
  weekInPhase: number
  progressionNote?: string
}

export function ProgressionBadge({ weekInPhase, progressionNote }: ProgressionBadgeProps) {
  if (!progressionNote) return null

  return (
    <div className="flex items-center gap-1.5 rounded-md bg-primary/10 px-2.5 py-1.5 text-xs text-primary">
      <TrendingUp className="size-3.5 shrink-0" />
      <span>
        Week {weekInPhase} — {progressionNote}
      </span>
    </div>
  )
}
