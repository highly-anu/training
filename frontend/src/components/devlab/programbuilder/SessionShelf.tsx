import { useDeferredValue, useMemo, useState } from 'react'
import { useDraggable } from '@dnd-kit/core'
import { GripVertical, Pencil } from 'lucide-react'
import { Link } from 'react-router-dom'
import { libraryMethods, searchLibrary, type ShelfSession } from '@/lib/programBuilder'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import { BlockStrip } from '@/components/blocks/WorkoutBlocks'
import { ModalityMark } from '@/components/shared/ModalityMark'
import { SearchField } from '@/components/shared/SearchField'
import { LoadingState } from '@/components/shared/states'
import { Tip } from '@/components/shared/Tip'
import { cn } from '@/lib/utils'

/** How many of the library's sessions are drawn at once; a search narrows the rest. */
const SHOWN = 40

const heading = 'text-xs font-semibold uppercase tracking-wide text-muted-foreground'

function ShelfChip({ session, placed }: { session: ShelfSession; placed: boolean }) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `s|${session.id}`, data: { type: 'session', sessionId: session.id, title: session.name },
  })
  const facts = [session.own ? modalityLabel(session.modality) : session.from?.name ?? modalityLabel(session.modality),
    session.minutes ? `${session.minutes} min` : null, placed ? 'placed' : null].filter(Boolean)
  return (
    <li className="flex items-stretch gap-0.5">
      <button type="button" ref={setNodeRef} {...attributes} {...listeners}
        aria-label={`Drag ${session.name} onto a day`}
        className={cn('flex min-w-0 flex-1 cursor-grab touch-none items-center gap-2 rounded-md border bg-card px-2 py-1.5 text-left hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:cursor-grabbing',
          isDragging && 'opacity-40')}>
        <GripVertical className="size-3.5 shrink-0 text-muted-foreground" />
        <ModalityMark modality={session.modality} size="sm" />
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-medium">{session.name}</span>
          <span className="block truncate text-xs text-muted-foreground">{facts.join(' · ')}</span>
          <BlockStrip blocks={session.preview} accent={modalityHex(session.modality)} className="mt-1" />
        </span>
      </button>
      {session.own && (
        <Tip label="Edit session">
          <Link to={`/dev?tab=session&edit=${encodeURIComponent(session.id)}`} aria-label={`Edit ${session.name}`}
            className="flex w-7 shrink-0 items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            <Pencil className="size-3.5" />
          </Link>
        </Tip>
      )}
    </li>
  )
}

/**
 * The sessions to drag onto the days of a week: the athlete's own, then every
 * other session in view — any method's — found by name, method or movement.
 */
export function SessionShelf({ sessions, placed, libraryLoading }: {
  sessions: ShelfSession[]; placed: Set<string>; libraryLoading?: boolean
}) {
  const [query, setQuery] = useState('')
  const [method, setMethod] = useState<string | null>(null)
  const asked = useDeferredValue(query)
  const own = useMemo(() => sessions.filter((s) => s.own), [sessions])
  const methods = useMemo(() => libraryMethods(sessions), [sessions])
  const found = useMemo(() => searchLibrary(sessions, asked, method), [sessions, asked, method])
  const total = sessions.length - own.length
  return (
    <div className="flex min-h-0 flex-col gap-4">
      <section aria-label="Your sessions" className="flex max-h-[40%] min-h-0 shrink-0 flex-col gap-2">
        <h3 className={heading}>Your sessions</h3>
        {own.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            None of your own yet.{' '}
            <Link to="/dev?tab=session" className="underline underline-offset-2">Build one</Link>, or use any session below.
          </p>
        ) : (
          <>
            <ul className="flex min-h-0 flex-col gap-1 overflow-y-auto pr-1">
              {own.map((s) => <ShelfChip key={s.id} session={s} placed={placed.has(s.id)} />)}
            </ul>
            <Link to="/dev?tab=session" className="text-xs text-muted-foreground underline underline-offset-2">Build another session</Link>
          </>
        )}
      </section>

      <section aria-label="All sessions" className="flex min-h-0 flex-1 flex-col gap-2">
        <h3 className={heading}>All sessions</h3>
        <SearchField value={query} onChange={setQuery} placeholder="Name, method or movement" label="Search all sessions" />
        <select aria-label="Method" value={method ?? ''} onChange={(e) => setMethod(e.target.value || null)}
          className="h-8 rounded-md border border-input bg-background px-2 text-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
          <option value="">Every method</option>
          {methods.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
        </select>
        {libraryLoading && total === 0 && <LoadingState shape="list" count={3} label="Loading every session" />}
        {!libraryLoading && found.length === 0 && (
          <p className="text-sm text-muted-foreground">{total === 0 ? 'No other sessions to show.' : 'No session matches. Try fewer words.'}</p>
        )}
        <ul className="flex min-h-0 flex-col gap-1 overflow-y-auto pr-1">
          {found.slice(0, SHOWN).map((s) => <ShelfChip key={s.id} session={s} placed={placed.has(s.id)} />)}
        </ul>
        {found.length > SHOWN && (
          <p className="text-xs text-muted-foreground">Showing {SHOWN} of {found.length}. Search to narrow them.</p>
        )}
      </section>
    </div>
  )
}
