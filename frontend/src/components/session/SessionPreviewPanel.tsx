import { ChevronLeft, Clock, ListChecks, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { formatLoad } from '@/lib/formatLoad'
import type { Session } from '@/api/types'

/**
 * The session a search found (or one picked from Browse), in full, before
 * anything is saved: its kind, name, minutes and source, every exercise with
 * its prescription, then Add / Replace — and Search again for another of the
 * kind (frontend-design §7.6.1).
 */
export function SessionPreviewPanel({ session, confirmLabel, note, onConfirm, onBack, onSearchAgain, searching, error }: {
  session: Session
  confirmLabel: string
  /** What it is when added; none when replacing. */
  note?: string
  onConfirm: () => void
  onBack: () => void
  /** Another of the kind; absent when the session was picked by hand. */
  onSearchAgain?: () => void
  searching?: boolean
  error?: string | null
}) {
  const exercises = session.exercises.filter((e) => e.exercise && !e.meta && !e.injury_skip)
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4">
        <button type="button" onClick={onBack}
          className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground">
          <ChevronLeft className="size-3" /> Back
        </button>

        <div className="space-y-1.5">
          <ModalityBadge modality={session.modality} size="sm" />
          <h3 className="text-base font-semibold leading-snug">{session.archetype?.name}</h3>
          <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
            {session.archetype?.duration_estimate_minutes && (
              <span className="flex items-center gap-1"><Clock className="size-3.5" /> {session.archetype.duration_estimate_minutes} min</span>
            )}
            <span className="flex items-center gap-1">
              <ListChecks className="size-3.5" /> {exercises.length ? `${exercises.length} exercises` : 'Coach-led'}
            </span>
            {session.provenance?.borrowed && (
              <span>via {session.provenance.label ?? session.provenance.package.replace(/_/g, ' ')}</span>
            )}
          </div>
          {note && <p className="text-[11px] text-muted-foreground">{note}</p>}
        </div>

        <ol className="divide-y divide-border/60 rounded-lg border border-border/60">
          {exercises.map((ea, i) => (
            <li key={i} className="px-3 py-2.5 space-y-0.5">
              <p className="text-sm font-medium">{ea.exercise?.name}</p>
              <p className="text-xs text-muted-foreground tabular-nums">{formatLoad(ea.load)}</p>
              {ea.load_note && <p className="text-[11px] italic text-muted-foreground">{ea.load_note}</p>}
            </li>
          ))}
          {exercises.length === 0 && (
            <li className="px-3 py-3 text-xs text-muted-foreground">No exercises listed — the session is coach-led.</li>
          )}
        </ol>
      </div>

      <div className="border-t px-5 py-4 space-y-2 shrink-0">
        {error && <p className="text-xs text-destructive">{error}</p>}
        <Button className="w-full" onClick={onConfirm} disabled={searching}>{confirmLabel}</Button>
        {onSearchAgain && (
          <Button variant="outline" className="w-full" onClick={onSearchAgain} disabled={searching}>
            {searching ? <><Loader2 className="size-4 mr-2 animate-spin" /> Searching…</> : 'Search again'}
          </Button>
        )}
      </div>
    </div>
  )
}
