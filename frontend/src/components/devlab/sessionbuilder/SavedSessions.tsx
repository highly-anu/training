import { useState } from 'react'
import { format } from 'date-fns'
import { CalendarPlus, Copy, Pencil, Trash2 } from 'lucide-react'
import { useGenerateSession } from '@/api/programs'
import { manualRefusal, useDeleteManualSession, type DescribedSession } from '@/api/manual'
import { useProgramStore } from '@/store/programStore'
import { programSlot } from '@/lib/sessionBuilder'
import { modalityHex, modalityLabel } from '@/lib/modalityColors'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { ConfirmDialog } from '@/components/shared/ConfirmDialog'
import { Tip } from '@/components/shared/Tip'
import { toast } from '@/lib/toast'
import { announce } from '@/lib/announce'

const iconButton = 'rounded p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40'

function AddToDayDialog({ session, onClose }: { session: DescribedSession; onClose: () => void }) {
  const program = useProgramStore((s) => s.currentProgram)
  const startDate = useProgramStore((s) => s.programStartDate)
  const addSession = useProgramStore((s) => s.addSession)
  const generate = useGenerateSession()
  const today = format(new Date(), 'yyyy-MM-dd')
  const [date, setDate] = useState(today)
  const [failed, setFailed] = useState<string | null>(null)
  const slot = programSlot(startDate, program?.weeks.length ?? 0, date, today)
  const week = 'weekIndex' in slot ? program?.weeks[slot.weekIndex] : undefined

  function add() {
    if (!('weekIndex' in slot) || !program || !week) return
    setFailed(null)
    generate.mutate({
      modality: session.modality as never, phase: week.phase, weekInPhase: week.week_in_phase, isDeload: week.is_deload,
      archetypeId: session.id, add: true,
      constraints: {
        session_time_minutes: Math.max(session.minutes, program.constraints?.session_time_minutes ?? 60),
        equipment: program.constraints?.equipment ?? [], injury_flags: program.constraints?.injury_flags ?? [],
        training_level: program.constraints?.training_level ?? 'intermediate',
        fatigue_state: program.constraints?.fatigue_state ?? 'normal',
      },
    } as never, {
      onSuccess: (made) => {
        addSession(slot.weekIndex, slot.day, made)
        announce(`${session.name} added to ${slot.day}.`)
        onClose()
      },
      onError: (e) => setFailed((e as Error).message || 'The session could not be added. Try again.'),
    })
  }

  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose() }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add “{session.name}” to a day</DialogTitle>
          <DialogDescription>It joins that day of your program as an extra session, to do and log like any other.</DialogDescription>
        </DialogHeader>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-xs text-muted-foreground">Day</span>
          <input type="date" value={date} min={today} onChange={(e) => setDate(e.target.value)}
            className="h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" />
        </label>
        <p className="text-sm text-muted-foreground" role="status">
          {'reason' in slot ? slot.reason : `Week ${slot.weekIndex + 1}, ${slot.day}.`}
        </p>
        {failed && <p role="alert" className="text-sm text-bad">{failed}</p>}
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={add} disabled={'reason' in slot} loading={generate.isPending}>Add session</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/** The sessions already saved: open one, copy it, put it on a day, delete it. */
export function SavedSessions({ sessions, currentId, onEdit, onDuplicate, onDeleted }: {
  sessions: DescribedSession[]
  currentId: string | undefined
  onEdit: (session: DescribedSession) => void
  onDuplicate: (session: DescribedSession) => void
  onDeleted: (id: string) => void
}) {
  const [adding, setAdding] = useState<DescribedSession | null>(null)
  const [deleting, setDeleting] = useState<DescribedSession | null>(null)
  const remove = useDeleteManualSession()
  if (!sessions.length) {
    return <p className="text-sm text-muted-foreground">Nothing saved yet. A saved session can be put on any day of your program.</p>
  }
  return (
    <>
      <ul className="flex flex-col gap-1">
        {sessions.map((session) => (
          <li key={session.id} className="flex items-center gap-1 rounded-md border bg-card px-2 py-1.5"
            aria-current={session.id === currentId ? 'true' : undefined}>
            <span className="size-2 shrink-0 rounded-full" style={{ background: modalityHex(session.modality) }} />
            <span className="min-w-0 flex-1">
              <span className="block truncate text-sm font-medium">{session.name}</span>
              <span className="block truncate text-xs text-muted-foreground">
                {modalityLabel(session.modality)} · {session.minutes} min{session.id === currentId ? ' · open' : ''}
              </span>
            </span>
            <Tip label="Edit"><button type="button" aria-label={`Edit ${session.name}`} onClick={() => onEdit(session)} className={iconButton}><Pencil className="size-4" /></button></Tip>
            <Tip label="Duplicate"><button type="button" aria-label={`Duplicate ${session.name}`} onClick={() => onDuplicate(session)} className={iconButton}><Copy className="size-4" /></button></Tip>
            <Tip label="Add to a day"><button type="button" aria-label={`Add ${session.name} to a day`} onClick={() => setAdding(session)} className={iconButton}><CalendarPlus className="size-4" /></button></Tip>
            <Tip label="Delete"><button type="button" aria-label={`Delete ${session.name}`} onClick={() => setDeleting(session)} className={iconButton}><Trash2 className="size-4" /></button></Tip>
          </li>
        ))}
      </ul>
      {adding && <AddToDayDialog session={adding} onClose={() => setAdding(null)} />}
      <ConfirmDialog
        open={deleting !== null}
        onOpenChange={(open) => { if (!open) setDeleting(null) }}
        title={`Delete “${deleting?.name ?? ''}”?`}
        description="It leaves your saved sessions. Days it was already done on keep their logs."
        confirmLabel="Delete"
        destructive
        onConfirm={() => {
          const session = deleting
          setDeleting(null)
          if (!session) return
          remove.mutate(session.id, {
            onSuccess: () => onDeleted(session.id),
            onError: (e) => toast.failed(manualRefusal(e).message),
          })
        }}
      />
    </>
  )
}
