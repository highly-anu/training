import { MODALITY_COLORS } from '@/lib/modalityColors'
import { sortPriorities } from '@/lib/prioritySort'
import type { GoalPriorities } from '@/api/types'

interface PriorityBarsProps {
  priorities: GoalPriorities
  maxItems?: number
}

export function PriorityBars({ priorities, maxItems = 5 }: PriorityBarsProps) {
  const sorted = sortPriorities(priorities).slice(0, maxItems)

  return (
    <div className="space-y-1.5">
      {sorted.map(({ modality, weight }) => {
        const colors = MODALITY_COLORS[modality]
        return (
          <div key={modality} className="flex items-center gap-2">
            <span className="w-24 shrink-0 text-[10px] text-muted-foreground leading-none truncate">
              {colors.label}
            </span>
            <div className="flex-1 h-1.5 rounded-full bg-border overflow-hidden">
              <div
                className="h-full rounded-full transition-all duration-500"
                style={{ width: `${weight * 100}%`, backgroundColor: colors.hex }}
              />
            </div>
            <span className="w-7 shrink-0 text-right text-[10px] text-muted-foreground">
              {Math.round(weight * 100)}%
            </span>
          </div>
        )
      })}
    </div>
  )
}
