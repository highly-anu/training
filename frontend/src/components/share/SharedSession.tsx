import { useMemo, useState } from 'react'
import { ChevronDown, Clock } from 'lucide-react'
import type { ExerciseAssignment } from '@/api/types'
import type { SharedSessionDoc } from '@/api/shares'
import { ExerciseFacts } from '@/components/explore/ExerciseFacts'
import { WorkoutIcon } from '@/components/icons/WorkoutIcon'
import { Collapse } from '@/components/motion/Collapse'
import { SessionExercises } from '@/components/session/SessionExercises'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { TestBadge } from '@/components/standards/TestBadge'
import { formatLoad } from '@/lib/formatLoad'
import { modalityHex, registerModalities } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'

const GAP: Record<string, string> = {
  injury: 'Left out for an injury',
  equipment: 'Left out: the equipment was not there',
  coverage: 'Nothing fitted this slot',
}

function gapOf(ea: ExerciseAssignment): string | null {
  if (ea.injury_skip) return GAP.injury
  if (ea.equipment_gap) return GAP.equipment
  if (ea.coverage_gap) return GAP.coverage
  return null
}

/**
 * A shared session, read-only: what it is and where it stood, then its
 * blocks (src/session_blocks.py) with each movement as planned — the sharer's
 * numbers. A movement opens in place to the exercise's own document, which
 * rides in the link: the reader may have no library to look it up in
 * (docs/frontend-design.md §13.14).
 */
export function SharedSession({ doc }: { doc: SharedSessionDoc }) {
  const { session, week, day } = doc
  const [open, setOpen] = useState<number | null>(null)
  // A modality the sharer's own method brought: drawn in its colour, by its name.
  useMemo(() => {
    if (doc.modalityDisplay) registerModalities([{ id: session.modality, display: doc.modalityDisplay as never }])
  }, [doc.modalityDisplay, session.modality])
  const accent = modalityHex(session.modality)
  const minutes = session.archetype?.duration_estimate_minutes ?? 0
  const where = [week.week_number != null ? `Week ${week.week_number}` : null, day].filter(Boolean).join(' · ')

  const row = (ea: ExerciseAssignment, i: number) => {
    const gap = gapOf(ea)
    const name = ea.exercise?.name ?? (ea.slot_role ?? 'Movement').replace(/_/g, ' ')
    const canOpen = !!ea.exercise?.id && !ea.meta && !gap
    const isOpen = open === i
    const line = (
      <>
        <span className="min-w-0 flex-1">
          <span className={cn('block truncate text-sm font-medium', gap && 'text-muted-foreground')}>{name}</span>
          <span className="block text-xs text-muted-foreground tabular-nums">{gap ?? formatLoad(ea.load)}</span>
        </span>
        {canOpen && <ChevronDown className={cn('size-3.5 shrink-0 text-muted-foreground', isOpen && 'rotate-180')} aria-hidden />}
      </>
    )
    return (
      <div key={i} className={cn('rounded-md border border-border/40 bg-card/40', isOpen && 'border-border')}
        style={isOpen ? { borderLeftColor: accent, borderLeftWidth: 2 } : undefined}>
        {canOpen ? (
          <button type="button" aria-expanded={isOpen} onClick={() => setOpen(isOpen ? null : i)}
            className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-muted/30">
            {line}
          </button>
        ) : (
          <div className="flex items-center gap-2 px-3 py-2">{line}</div>
        )}
        {(ea.load_note || ea.notes) && (
          <p className="px-3 pb-2 text-[11px] leading-relaxed text-muted-foreground">{ea.load_note ?? ea.notes}</p>
        )}
        <Collapse open={isOpen}>
          {canOpen && (
            <div className="space-y-4 border-t border-border/40 px-3 py-3">
              <ExerciseFacts exercise={ea.exercise} />
            </div>
          )}
        </Collapse>
      </div>
    )
  }

  return (
    <article className="space-y-5">
      <div className="space-y-2">
        {/* The page's header already names it: here, what kind of session it is. */}
        <div className="flex flex-wrap items-center gap-2">
          <WorkoutIcon icon={session.icon} modality={session.modality} className="size-5" />
          <ModalityBadge modality={session.modality} />
          {week.phase && <PhaseBadge phase={week.phase} label={week.phase_name} />}
          {session.test && <TestBadge test={session.test} size="md" />}
          {week.is_deload && <span className="text-[11px] text-muted-foreground">Deload week</span>}
        </div>
        <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
          {where && <span>{where}</span>}
          {minutes > 0 && <span className="flex items-center gap-1"><Clock className="size-3.5" aria-hidden /> ~{minutes} min</span>}
          {doc.method && <span>From {doc.method.name}</span>}
        </p>
      </div>

      {session.exercises?.length ? (
        <SessionExercises session={session} row={row} />
      ) : (
        <p className="text-sm text-muted-foreground">No exercises are listed: the session is coach-led.</p>
      )}

      <p className="border-t border-border/40 pt-3 text-[11px] text-muted-foreground">
        The numbers are the ones planned for the person who shared it. Tap a movement for what it is and how to do it.
      </p>
    </article>
  )
}
