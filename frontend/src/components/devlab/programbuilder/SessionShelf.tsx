import { useDraggable } from '@dnd-kit/core'
import { GripVertical } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { DescribedSession } from '@/api/manual'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import { BlockStrip } from '@/components/blocks/WorkoutBlocks'
import { ModalityMark } from '@/components/shared/ModalityMark'
import { cn } from '@/lib/utils'

function ShelfChip({ session, placed }: { session: DescribedSession; placed: boolean }) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `s|${session.id}`, data: { type: 'session', sessionId: session.id, title: session.name },
  })
  return (
    <li>
      <button type="button" ref={setNodeRef} {...attributes} {...listeners}
        aria-label={`Drag ${session.name} onto a day`}
        className={cn('flex w-full cursor-grab touch-none items-center gap-2 rounded-md border bg-card px-2 py-1.5 text-left hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:cursor-grabbing',
          isDragging && 'opacity-40')}>
        <GripVertical className="size-3.5 shrink-0 text-muted-foreground" />
        <ModalityMark modality={session.modality} size="sm" />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-medium">{session.name}</span>
          <span className="block truncate text-xs text-muted-foreground">
            {modalityLabel(session.modality)} · {session.minutes} min{placed ? ' · placed' : ''}
          </span>
          <BlockStrip blocks={session.preview} accent={modalityHex(session.modality)} className="mt-1" />
        </span>
      </button>
    </li>
  )
}

/** The saved sessions, to drag onto the days of a week. */
export function SessionShelf({ sessions, placed }: { sessions: DescribedSession[]; placed: Set<string> }) {
  return (
    <section aria-label="Your sessions" className="flex min-h-0 flex-col gap-2">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Your sessions</h3>
      {sessions.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          A program is made of sessions you have saved.{' '}
          <Link to="/dev?tab=session" className="underline underline-offset-2">Build one first</Link>.
        </p>
      ) : (
        <>
          <ul className="flex min-h-0 flex-col gap-1 overflow-y-auto pr-1">
            {sessions.map((s) => <ShelfChip key={s.id} session={s} placed={placed.has(s.id)} />)}
          </ul>
          <Link to="/dev?tab=session" className="text-xs text-muted-foreground underline underline-offset-2">Build another session</Link>
        </>
      )}
    </section>
  )
}
