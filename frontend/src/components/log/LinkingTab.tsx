import { Fragment, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import {
  DndContext,
  DragOverlay,
  MouseSensor,
  TouchSensor,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  type DragEndEvent,
  type DragStartEvent,
} from '@dnd-kit/core'
import { Activity, Check, CheckCircle2, ChevronRight, GripVertical, Link2, Unlink, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { EmptyState } from '@/components/shared/EmptyState'
import { WorkoutIcon } from '@/components/icons/WorkoutIcon'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { COMPLETION } from '@/lib/completionColors'
import { formatActivityType } from '@/lib/activityType'
import { sourceShortLabel } from '@/lib/workoutSource'
import { dismissKey, type LinkingDay, type LinkSession, type LinkSuggestion } from '@/lib/linking'
import { useBioStore } from '@/store/bioStore'
import { dismissLink } from '@/hooks/useDismissedLinks'
import type { ImportedWorkout } from '@/api/types'

/**
 * Log ▸ Linking: one card per day, the day's recorded workouts on the left
 * and its planned sessions on the right (`lib/linking.ts` builds the days).
 * Suggestions come from the shared matcher scored inside each day only; to
 * link across days, drag a workout onto any session — or select it and then
 * pick the session, which is the keyboard and touch path.
 */

type Filter = 'open' | 'all'

const dayLabel = (date: string) => format(parseISO(date), 'EEE, MMM d')
const shortDay = (date: string) => format(parseISO(date), 'EEE d')
const timeOf = (w: ImportedWorkout) => {
  try { return format(parseISO(w.startTime), 'HH:mm') } catch { return '' }
}

// ── Workout ────────────────────────────────────────────────────────────────────

interface WorkoutCardProps {
  workout: ImportedWorkout
  /** The card's own date; another date is shown on the chip. */
  onDate: string
  selected?: boolean
  dragging?: boolean
  onSelect?: () => void
  onOpen?: () => void
  note?: string
  /** The session it is linked to: the workout shows that session's icon. */
  linkedTo?: LinkSession
}

/** A workout that can be dragged onto a session. Its id carries the card's date: a cross-day link shows it twice. */
function DraggableWorkout(props: WorkoutCardProps) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `w|${props.onDate}|${props.workout.id}`, data: { workout: props.workout },
  })
  return <WorkoutCard {...props} dragging={props.dragging || isDragging} handle={{ ref: setNodeRef, props: { ...attributes, ...listeners } }} />
}

function WorkoutCard({ workout, onDate, selected, dragging, onSelect, onOpen, note, linkedTo, handle }: WorkoutCardProps & {
  handle?: { ref: (el: HTMLElement | null) => void; props: Record<string, unknown> }
}) {
  return (
    <div
      ref={handle?.ref}
      className={cn(
        'group/card flex items-center gap-1 sm:gap-2 rounded-lg border bg-card/60 px-2 py-2 transition-colors min-w-0',
        selected ? 'border-primary/60 ring-1 ring-primary/30 bg-primary/5' : 'border-border/40',
        dragging && 'opacity-30'
      )}
    >
      <button
        type="button"
        {...handle?.props}
        onClick={onSelect}
        aria-pressed={selected}
        aria-label={`${selected ? 'Deselect' : 'Select'} ${formatActivityType(workout.activityType)} to link`}
        className="flex flex-1 items-center gap-2 min-w-0 text-left cursor-grab active:cursor-grabbing touch-manipulation"
      >
        <GripVertical className="hidden sm:block size-3.5 shrink-0 text-muted-foreground/40 group-hover/card:text-muted-foreground" />
        {linkedTo?.icon
          ? <WorkoutIcon icon={linkedTo.icon} modality={linkedTo.modality} className="hidden sm:block size-3.5" />
          : <Activity className="hidden sm:block size-3.5 shrink-0 text-muted-foreground" />}
        <div className="min-w-0">
          <p className="text-sm font-medium truncate">{formatActivityType(workout.activityType)}</p>
          <p className="text-[11px] text-muted-foreground truncate">
            {workout.date !== onDate && <span className="font-medium text-foreground/70">{shortDay(workout.date)} · </span>}
            {timeOf(workout)} · {workout.durationMinutes} min
            {workout.heartRate.avg != null && ` · ${Math.round(workout.heartRate.avg)} bpm`}
            {' · '}{sourceShortLabel(workout.source)}
          </p>
          {note && <p className="text-[10px] text-muted-foreground/80 truncate">{note}</p>}
        </div>
      </button>
      {onOpen && (
        <button
          type="button"
          onClick={onOpen}
          className="p-0.5 sm:p-1 rounded text-muted-foreground/50 hover:text-foreground transition-colors"
          aria-label="Open workout"
        >
          <ChevronRight className="size-3.5" />
        </button>
      )}
    </div>
  )
}

// ── Session ────────────────────────────────────────────────────────────────────

function SessionCard({ session, onDate, complete, armed, onPick, onOpen }: {
  session: LinkSession
  onDate: string
  complete: boolean
  /** A workout is being dragged or is selected: this session can take it. */
  armed: boolean
  onPick: () => void
  onOpen: () => void
}) {
  const { setNodeRef, isOver } = useDroppable({ id: `s|${onDate}|${session.key}`, data: { session } })
  const colors = MODALITY_COLORS[session.modality]
  return (
    <div
      ref={setNodeRef}
      className={cn(
        'relative flex items-center gap-2 rounded-lg border bg-card/60 pl-2.5 sm:pl-3 pr-2 py-2 transition-all min-w-0 overflow-hidden',
        isOver ? 'border-primary/60 bg-primary/5 ring-1 ring-primary/20'
          : armed ? 'border-dashed border-primary/40' : 'border-border/40'
      )}
    >
      <span className="absolute inset-y-0 left-0 w-0.5" style={{ backgroundColor: colors?.hex ?? 'var(--primary)' }} />
      <button
        type="button"
        onClick={armed ? onPick : onOpen}
        className="flex flex-1 items-center gap-2 min-w-0 text-left"
        aria-label={armed ? `Link to ${session.name}` : `Open ${session.name}`}
      >
        <WorkoutIcon icon={session.icon} modality={session.modality} className="size-4" />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium truncate">{session.name}</p>
          <p className="text-[11px] text-muted-foreground truncate">
            {session.date !== onDate && <span className="font-medium text-foreground/70">{shortDay(session.date)} · </span>}
            Wk {session.weekNumber} · {colors?.label ?? session.modality} · ~{session.durationMinutes} min
          </p>
        </div>
        {complete && <CheckCircle2 className={cn('size-3.5 shrink-0', COMPLETION.text)} aria-label="Logged complete" />}
        {armed && <span className="hidden sm:inline text-[10px] text-primary shrink-0">Link here</span>}
      </button>
    </div>
  )
}

// ── Connector between the two columns ──────────────────────────────────────────

function Connector({ kind, onAction, onDismiss, label }: {
  kind: 'linked' | 'suggested'
  onAction: () => void
  onDismiss?: () => void
  label: string
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-1 px-1">
      {kind === 'linked' ? (
        <button
          type="button"
          onClick={onAction}
          title="Unlink"
          aria-label={`Unlink ${label}`}
          className={cn('group/link flex size-7 items-center justify-center rounded-full border transition-colors',
            COMPLETION.border, COMPLETION.bgStrong, COMPLETION.text, 'hover:border-red-500/40 hover:bg-red-500/10 hover:text-red-700 dark:hover:text-red-300')}
        >
          <Check className="size-3.5 group-hover/link:hidden" />
          <Unlink className="size-3.5 hidden group-hover/link:block" />
        </button>
      ) : (
        <>
          <Button size="sm" variant="outline" onClick={onAction} className="h-7 px-1.5 sm:px-2 text-xs border-amber-500/40 text-amber-700 dark:text-amber-300 hover:bg-amber-500/10" aria-label={`Link ${label}`}>
            <Link2 className="size-3 sm:mr-1" /><span className="hidden sm:inline">Link</span>
          </Button>
          {onDismiss && (
            <button type="button" onClick={onDismiss} className="text-[10px] text-muted-foreground hover:text-foreground" aria-label={`Dismiss suggestion ${label}`}>
              <X className="size-3 inline" /><span className="hidden sm:inline"> not this</span>
            </button>
          )}
        </>
      )}
    </div>
  )
}

// ── Day card ───────────────────────────────────────────────────────────────────

function DayCard({ day, programLabel, armed, selectedId, draggingId, isComplete, onSelect, onPick, onLink, onUnlink, onDismiss, onOpenWorkout, onOpenSession }: {
  day: LinkingDay
  /** The earlier program's name, on a day that belongs to one. */
  programLabel?: string
  armed: boolean
  selectedId: string | null
  draggingId: string | null
  isComplete: (s: LinkSession) => boolean
  onSelect: (w: ImportedWorkout) => void
  onPick: (s: LinkSession) => void
  onLink: (w: ImportedWorkout, s: LinkSession) => void
  onUnlink: (w: ImportedWorkout) => void
  onDismiss: (p: LinkSuggestion) => void
  onOpenWorkout: (w: ImportedWorkout) => void
  onOpenSession: (s: LinkSession) => void
}) {
  const workoutProps = (w: ImportedWorkout) => ({
    workout: w, onDate: day.date,
    selected: selectedId === w.id, dragging: draggingId === w.id,
    onSelect: () => onSelect(w), onOpen: () => onOpenWorkout(w),
  })
  const sessionProps = (s: LinkSession) => ({
    session: s, onDate: day.date, complete: isComplete(s), armed,
    onPick: () => onPick(s), onOpen: () => onOpenSession(s),
  })
  const rest = Math.max(day.workouts.length, day.sessions.length)
  const extras = [
    ...day.elsewhere.map((e) => ({ workout: e.workout, note: 'linked to an earlier program' })),
    ...day.declined.map((w) => ({ workout: w, note: 'marked as no session' })),
  ]
  const empty = day.links.length + day.suggestions.length + rest + extras.length === 0

  return (
    <section
      aria-label={dayLabel(day.date)}
      className={cn('rounded-xl border p-2.5 sm:p-3 space-y-2',
        day.needsAttention ? 'border-amber-500/30 bg-amber-500/[0.03]' : 'border-border bg-card/40')}
    >
      <header className="flex items-center gap-2">
        <h3 className="text-sm font-semibold">{dayLabel(day.date)}</h3>
        {day.historical && (
          <span className="text-[10px] rounded border border-border px-1.5 py-px text-muted-foreground truncate">
            {programLabel ? `Earlier program · ${programLabel}` : 'Earlier program'}
          </span>
        )}
        {day.needsAttention && (
          <span className="text-[10px] rounded border border-amber-500/40 px-1.5 py-px text-amber-700 dark:text-amber-300">to link</span>
        )}
      </header>

      <div className="grid grid-cols-[minmax(0,1fr)_2.25rem_minmax(0,1fr)] sm:grid-cols-[minmax(0,1fr)_4.5rem_minmax(0,1fr)] gap-x-1.5 sm:gap-x-2 gap-y-1.5 items-center">
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">Workouts</p>
        <span />
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">Sessions</p>

        {day.links.map((l) => (
          <Fragment key={`l|${l.workout.id}`}>
            <DraggableWorkout {...workoutProps(l.workout)} linkedTo={l.session} />
            <Connector kind="linked" label={`${formatActivityType(l.workout.activityType)} from ${l.session.name}`} onAction={() => onUnlink(l.workout)} />
            <SessionCard {...sessionProps(l.session)} />
          </Fragment>
        ))}

        {day.suggestions.map((p) => (
          <Fragment key={`p|${p.workout.id}`}>
            <DraggableWorkout {...workoutProps(p.workout)} />
            <Connector kind="suggested" label={`${formatActivityType(p.workout.activityType)} to ${p.session.name}`}
              onAction={() => onLink(p.workout, p.session)} onDismiss={() => onDismiss(p)} />
            <SessionCard {...sessionProps(p.session)} />
          </Fragment>
        ))}

        {Array.from({ length: rest }, (_, i) => {
          const w = day.workouts[i]
          const s = day.sessions[i]
          return (
            <Fragment key={`r|${i}`}>
              {w ? <DraggableWorkout {...workoutProps(w)} /> : <span />}
              <span />
              {s ? <SessionCard {...sessionProps(s)} /> : <span />}
            </Fragment>
          )
        })}

        {extras.map(({ workout, note }) => (
          <Fragment key={`x|${workout.id}`}>
            <DraggableWorkout {...workoutProps(workout)} note={note} />
            <span />
            <span />
          </Fragment>
        ))}
      </div>

      {empty && <p className="text-xs text-muted-foreground">Nothing planned or recorded.</p>}
      {day.workouts.length === 0 && day.sessions.length > 0 && day.suggestions.length === 0 && day.links.length === 0 && (
        <p className="text-[11px] text-muted-foreground">No workout recorded — drag one here from another day.</p>
      )}
    </section>
  )
}

// ── Tab ────────────────────────────────────────────────────────────────────────

export function LinkingTab({ days, hasProgram, programLabels = {}, onImport }: {
  days: LinkingDay[]
  hasProgram: boolean
  /** Program version id → its name, for earlier programs' days. */
  programLabels?: Record<string, string>
  onImport: () => void
}) {
  const navigate = useNavigate()
  const confirmMatch = useBioStore((s) => s.confirmMatch)
  const rejectMatch = useBioStore((s) => s.rejectMatch)
  const dismissSuggestion = useBioStore((s) => s.dismissSuggestion)
  const sessionLogs = useBioStore((s) => s.sessionPerformanceLogs)
  const [filter, setFilter] = useState<Filter>('open')
  const [selected, setSelected] = useState<ImportedWorkout | null>(null)
  const [dragging, setDragging] = useState<ImportedWorkout | null>(null)

  const sensors = useSensors(
    useSensor(MouseSensor, { activationConstraint: { distance: 6 } }),
    // A press-and-hold starts a drag; a swipe still scrolls the page.
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 6 } }),
  )

  useEffect(() => {
    if (!selected) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setSelected(null) }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [selected])

  const completeKeys = useMemo(
    () => new Set(Object.values(sessionLogs).filter((l) => l.completedAt).map((l) => l.sessionKey)),
    [sessionLogs]
  )

  // A day with an unpaired session stays in view as a drop target, unless the
  // session was logged complete by hand; the count is the workouts waiting.
  const openCount = days.filter((d) => d.needsAttention).length
  // An earlier program's unpaired sessions do not hold a day in view: months
  // of them would bury the workouts still waiting.
  const isComplete = (s: LinkSession) => (s.historical ? Boolean(s.completedAt) : completeKeys.has(s.legacyKey))
  const isOpen = (d: LinkingDay) =>
    d.needsAttention || d.sessions.some((s) => !s.historical && !isComplete(s))
  const visible = filter === 'open' ? days.filter(isOpen) : days

  function link(w: ImportedWorkout, s: LinkSession) {
    // The uid pins the session, so a link across days or into a finished
    // program lands where it was dropped; an earlier program's session leaves
    // this program's completion marks alone.
    confirmMatch(w.id, s.legacyKey, { sessionUid: s.uid, markComplete: !s.historical })
    setSelected(null)
  }

  function dismiss(p: LinkSuggestion) {
    if (p.fromPending) dismissSuggestion(p.workout.id)
    dismissLink(dismissKey(p.workout.id, p.session.key))
  }

  function onDragStart(e: DragStartEvent) {
    setDragging((e.active.data.current?.workout as ImportedWorkout) ?? null)
    setSelected(null)
  }

  function onDragEnd(e: DragEndEvent) {
    const w = e.active.data.current?.workout as ImportedWorkout | undefined
    const s = e.over?.data.current?.session as LinkSession | undefined
    setDragging(null)
    if (w && s) link(w, s)
  }

  if (!hasProgram) {
    return (
      <div className="max-w-2xl mx-auto px-8 py-12">
        <EmptyState
          icon={<Link2 className="size-8 opacity-40" />}
          title="No program to link to"
          description="Linking pairs recorded workouts with the planned sessions of your programs. Build a program first."
        />
      </div>
    )
  }

  const filters: { id: Filter; label: string }[] = [
    { id: 'open', label: openCount > 0 ? `To link (${openCount})` : 'To link' },
    { id: 'all',  label: `All days (${days.length})` },
  ]

  return (
    <DndContext sensors={sensors} onDragStart={onDragStart} onDragEnd={onDragEnd} onDragCancel={() => setDragging(null)}>
      <div className="max-w-3xl mx-auto px-4 sm:px-8 py-8 space-y-4">
        <div className="flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-1">
            {filters.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => setFilter(f.id)}
                className={cn(
                  'px-2.5 py-1 text-[11px] rounded border transition-colors',
                  filter === f.id ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted'
                )}
              >
                {f.label}
              </button>
            ))}
          </div>
          <p className="text-[11px] text-muted-foreground">
            Suggestions stay within a day. Drag a workout onto any session to link across days — earlier programs' days are under All days.
          </p>
        </div>

        {selected && (
          <div className="sticky top-0 z-10 flex items-center gap-2 rounded-lg border border-primary/40 bg-background/95 backdrop-blur px-3 py-2 text-xs">
            <Link2 className="size-3.5 text-primary" />
            <span className="flex-1 truncate">
              Pick a session for <span className="font-medium">{formatActivityType(selected.activityType)}</span> · {dayLabel(selected.date)}
            </span>
            <Button size="sm" variant="ghost" className="h-6 px-2 text-xs" onClick={() => setSelected(null)}>Cancel</Button>
          </div>
        )}

        {visible.length === 0 ? (
          <EmptyState
            icon={<CheckCircle2 className="size-8 opacity-40" />}
            title={days.length === 0 ? 'Nothing to link yet' : 'Everything is linked'}
            description={days.length === 0
              ? 'Recorded workouts and planned sessions appear here day by day once the program has started.'
              : 'Every recorded workout is linked or set aside.'}
            action={days.length === 0 ? { label: 'Import a file', onClick: onImport }
              : { label: 'Show all days', onClick: () => setFilter('all') }}
          />
        ) : (
          visible.map((day) => (
            <DayCard
              key={day.date}
              day={day}
              armed={selected != null || dragging != null}
              selectedId={selected?.id ?? null}
              draggingId={dragging?.id ?? null}
              programLabel={day.programVersionId ? programLabels[day.programVersionId] : undefined}
              isComplete={isComplete}
              onSelect={(w) => setSelected((cur) => (cur?.id === w.id ? null : w))}
              onPick={(s) => { if (selected) link(selected, s) }}
              onLink={link}
              onUnlink={(w) => rejectMatch(w.id)}
              onDismiss={dismiss}
              onOpenWorkout={(w) => navigate(`/log/${encodeURIComponent(w.id)}`, { state: { workout: w } })}
              onOpenSession={(s) => navigate(s.historical && s.programVersionId
                ? `/program/history/${encodeURIComponent(s.programVersionId)}`
                : `/program/${s.weekNumber}/${s.dayName}`)}
            />
          ))
        )}
      </div>

      <DragOverlay dropAnimation={null}>
        {dragging && (
          <div className="rotate-1 shadow-xl ring-2 ring-primary/40 opacity-95 rounded-lg w-64">
            <WorkoutCard workout={dragging} onDate={dragging.date} />
          </div>
        )}
      </DragOverlay>
    </DndContext>
  )
}
