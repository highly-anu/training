import { FileText, ChevronRight, X } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { formatActivityType } from '@/lib/activityType'
import { sourceShortLabel } from '@/lib/workoutSource'
import type { ImportedWorkout } from '@/api/types'

export type WorkoutMatchStatus = 'matched' | 'pending' | 'unmatched'

interface WorkoutRowProps {
  workout: ImportedWorkout
  status: WorkoutMatchStatus
  /** "Wk 3 Monday — KB Ballistic Power" when matched to a known session. */
  sessionLabel?: string | null
  onOpen: () => void
  onMatch?: () => void
  onRemove?: () => void
}

const STATUS_CLASS: Record<WorkoutMatchStatus, string> = {
  matched:   'border-emerald-500/40 text-emerald-700 dark:text-emerald-300',
  pending:   'border-amber-500/40 text-amber-700 dark:text-amber-300',
  unmatched: 'border-border text-muted-foreground',
}

function workoutDateLabel(w: ImportedWorkout): string {
  try { return format(parseISO(w.startTime), 'EEE, MMM d') } catch { return w.date }
}

/**
 * One recorded workout in a list. This row used to exist three times
 * (Import ▸ History, Import ▸ Matched, Analytics ▸ Activity), each with its
 * own badge colours and date formatting.
 */
export function WorkoutRow({ workout, status, sessionLabel, onOpen, onMatch, onRemove }: WorkoutRowProps) {
  const activity = formatActivityType(workout.activityType)
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={onOpen}
      onKeyDown={(e) => e.key === 'Enter' && onOpen()}
      className="flex items-center gap-3 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 cursor-pointer hover:bg-card/60 transition-colors"
    >
      <FileText className="size-4 shrink-0 text-muted-foreground" />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium truncate">{activity}</p>
          <Badge variant="outline" className={cn('text-[10px] shrink-0', STATUS_CLASS[status])}>
            {status}
          </Badge>
          <span className="text-[9px] text-muted-foreground/60 border border-border/40 rounded px-1 py-px shrink-0">
            {sourceShortLabel(workout.source)}
          </span>
        </div>
        <p className="text-xs text-muted-foreground truncate">
          {workoutDateLabel(workout)} · {workout.durationMinutes} min
          {workout.heartRate.avg != null && ` · ${Math.round(workout.heartRate.avg)} bpm`}
          {sessionLabel && <span className="text-muted-foreground/70"> · {sessionLabel}</span>}
        </p>
      </div>
      {status === 'pending' && onMatch && (
        <Button
          size="sm"
          variant="ghost"
          onClick={(e) => { e.stopPropagation(); onMatch() }}
          className="text-xs text-amber-700 dark:text-amber-300"
        >
          Match
        </Button>
      )}
      {onRemove && (
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onRemove() }}
          className="p-1 text-muted-foreground hover:text-foreground transition-colors rounded"
          aria-label={`Remove ${activity}`}
        >
          <X className="size-3.5" />
        </button>
      )}
      <ChevronRight className="size-4 shrink-0 text-muted-foreground/50" />
    </div>
  )
}
