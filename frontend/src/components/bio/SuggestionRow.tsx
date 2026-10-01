import { X } from 'lucide-react'
import { format, parseISO } from 'date-fns'
import { Button } from '@/components/ui/button'
import { formatActivityType } from '@/lib/activityType'
import { sessionLabel } from '@/lib/sessionKeys'
import type { PendingMatch } from '@/api/types'

interface SuggestionRowProps {
  match: PendingMatch
  onReview: () => void
  onDismiss: () => void
}

/**
 * One workout waiting for a match decision: what was recorded, which planned
 * session it looks like, and the two things the athlete can do about it.
 * Reviewing opens MatchConfirmDialog; dismissing forgets the suggestion
 * without deciding the workout.
 */
export function SuggestionRow({ match, onReview, onDismiss }: SuggestionRowProps) {
  const w = match.importedWorkout
  const candidate = match.candidateSessionKeys[0]
  const activity = formatActivityType(w.activityType)
  const when = (() => {
    try { return format(parseISO(w.startTime), 'EEE, MMM d') } catch { return w.date }
  })()

  return (
    <li className="flex items-center gap-3 rounded-lg border border-border/40 bg-card/60 px-3 py-2">
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">
          {activity}
          <span className="ml-1.5 font-normal text-muted-foreground">· {w.durationMinutes} min</span>
        </p>
        <p className="text-xs text-muted-foreground truncate">
          {when} → {candidate ? sessionLabel(candidate) : 'no session suggested'}
        </p>
      </div>
      <Button size="sm" variant="outline" onClick={onReview}>
        Review
      </Button>
      <Button
        size="sm"
        variant="ghost"
        onClick={onDismiss}
        className="px-2 text-muted-foreground"
        aria-label={`Dismiss suggestion for ${activity}`}
      >
        <X className="size-3.5" />
      </Button>
    </li>
  )
}
