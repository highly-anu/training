import { ArrowRight, Pencil } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { PhilosophyDescription } from '@/api/types'
import { useExploreNavigate } from '@/components/explore/topics'
import { EditableText, useMethodEditing } from '@/components/methods/MethodEdit'
import { SessionBrowser } from '@/components/sessions/SessionBrowser'
import { useMethods } from '@/api/methods'
import { useDevLabEnabled } from '@/lib/featureFlags'

/**
 * Every session the package writes, in the session browser: grouped as the
 * method groups them — a template's day categories in the source's order, a
 * contract's modules, the rest by modality, tests last — with each slot's
 * exercises as the generator can give them (the server applies the selector's
 * rule). The page owns which is open (`?session=`); an own method's words are
 * edited in the open session.
 */
export function PhilosophySessions({ doc, sessionId, onSession }: {
  doc: PhilosophyDescription; sessionId: string | null; onSession: (id: string | null) => void
}) {
  const go = useExploreNavigate()
  const editing = useMethodEditing()
  // Sessions the athlete composed by hand open in the session builder.
  const builder = useDevLabEnabled()
  const methods = useMethods()
  const composed = builder && !!methods.data?.methods?.find((m) => m.id === doc.id)?.composed
  return (
    <SessionBrowser
      groups={doc.groups}
      sessions={doc.sessions}
      selectedId={sessionId && doc.sessions[sessionId] ? sessionId : null}
      onSelect={onSession}
      onExercise={(id) => go('exercises', id)}
      detailFooter={(s) => (
        <span className="flex flex-wrap items-center gap-x-4 gap-y-1">
          {composed && (
            <Link to={`/dev?tab=session&edit=${encodeURIComponent(s.id)}`}
              className="inline-flex items-center gap-1 font-medium text-foreground hover:underline">
              <Pencil className="size-3" /> Edit session
            </Link>
          )}
          <button type="button" onClick={() => go('archetypes', s.id)} className="inline-flex items-center gap-1 hover:text-foreground">
            Open as an archetype <ArrowRight className="size-3" />
          </button>
        </span>
      )}
      editing={editing ? {
        name: (s) => (
          <EditableText value={s.name} label="Session name" edits={(name) => ({ sessions: { [s.id]: { name } } })} />
        ),
        note: (s) => (
          <EditableText value={s.note} label="Session notes" multiline placeholder="Add a note for this session"
            edits={(notes) => ({ sessions: { [s.id]: { notes } } })} />
        ),
        slotNote: (s, role, note) => (
          <EditableText value={note} label="Note" multiline
            edits={(notes) => ({ sessions: { [s.id]: { slots: { [role]: { notes } } } } })} />
        ),
      } : undefined}
    />
  )
}
