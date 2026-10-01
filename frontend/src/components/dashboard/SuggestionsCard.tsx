import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Link2 } from 'lucide-react'
import { useBioStore } from '@/store/bioStore'
import { MatchConfirmDialog } from '@/components/bio/MatchConfirmDialog'
import { SuggestionRow } from '@/components/bio/SuggestionRow'
import type { PendingMatch } from '@/api/types'

const PREVIEW = 3

/**
 * "N workouts look like planned sessions" — the match decisions waiting for
 * the athlete, surfaced where they start the day. Renders nothing when the
 * queue is empty, so the page does not change shape for the common case.
 */
export function SuggestionsCard() {
  const pending = useBioStore((s) => s.pendingMatches)
  const dismissSuggestion = useBioStore((s) => s.dismissSuggestion)
  const [active, setActive] = useState<PendingMatch | null>(null)

  if (pending.length === 0) return null
  const n = pending.length

  return (
    <section
      aria-label="Workout match suggestions"
      className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-4"
    >
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Link2 className="size-4 text-amber-700 dark:text-amber-300" />
          <p className="text-sm font-medium">
            {n} workout{n === 1 ? ' looks' : 's look'} like {n === 1 ? 'a planned session' : 'planned sessions'}
          </p>
        </div>
        <Link to="/log?tab=suggestions" className="text-xs text-primary hover:underline">
          {n > PREVIEW ? `All ${n} →` : 'Open →'}
        </Link>
      </div>
      <ul className="mt-3 space-y-2">
        {pending.slice(0, PREVIEW).map((p) => (
          <SuggestionRow
            key={p.importedWorkout.id}
            match={p}
            onReview={() => setActive(p)}
            onDismiss={() => dismissSuggestion(p.importedWorkout.id)}
          />
        ))}
      </ul>
      <MatchConfirmDialog match={active} onClose={() => setActive(null)} />
    </section>
  )
}
