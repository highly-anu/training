import { useDraggable, useDroppable } from '@dnd-kit/core'
import { Copy, Eraser, Feather, MoreHorizontal, Plus, Trash2 } from 'lucide-react'
import type { DescribedSession } from '@/api/manual'
import {
  DAYS, DAY_SHORT, MAX_DAY_SESSIONS, canPlace, problemsAt, sessionsInWeek,
  type Cell, type DraftPhase, type ManualDay, type TrackProblem,
} from '@/lib/programBuilder'
import { modalityHex } from '@/lib/modalityColors'
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Tip } from '@/components/shared/Tip'
import { cn } from '@/lib/utils'

export interface GridActions {
  place: (cell: Cell, sessionId: string) => void
  remove: (cell: Cell, index: number) => void
  move: (from: Cell, index: number, to: Cell) => void
  toggleLight: (cell: Cell) => void
  duplicateWeek: (week: number) => void
  clearWeek: (week: number) => void
  removeWeek: (week: number) => void
}

const iconButton = 'rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-30'
const cellName = (cell: Cell) => `week ${cell.week + 1}, ${DAYS[cell.day]}`

function PlacedChip({ phase, cell, index, session, name, actions }: {
  phase: DraftPhase; cell: Cell; index: number; session: DescribedSession | undefined; name: string; actions: GridActions
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `p|${phase.uid}|${cell.week}|${cell.day}|${index}`,
    data: { type: 'placed', from: cell, index, sessionId: phase.template[cell.week][cell.day].sessions[index], title: name },
  })
  const week = phase.template[cell.week]
  const sessionId = week[cell.day].sessions[index]
  return (
    <div className={cn('flex items-stretch rounded-md border bg-background', isDragging && 'opacity-40')}
      style={{ borderLeftWidth: 3, borderLeftColor: session ? modalityHex(session.modality) : undefined }}>
      <button type="button" ref={setNodeRef} {...attributes} {...listeners}
        aria-label={`${name}, ${cellName(cell)}. Drag to another day`}
        className="min-w-0 flex-1 cursor-grab touch-none rounded-l px-1.5 py-1 text-left hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring active:cursor-grabbing">
        <span className="block line-clamp-2 break-words text-xs font-medium">{name}</span>
        {session && <span className="block text-[11px] text-muted-foreground">{session.minutes} min</span>}
      </button>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button type="button" aria-label={`${name}, ${cellName(cell)}: move or remove`} className={cn(iconButton, 'rounded-l-none')}>
            <MoreHorizontal className="size-3.5" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuLabel>Move to</DropdownMenuLabel>
          {DAYS.map((day, d) => (d === cell.day ? null : (
            <DropdownMenuItem key={day} disabled={!canPlace(week[d], sessionId)}
              onSelect={() => actions.move(cell, index, { week: cell.week, day: d })}>{day}</DropdownMenuItem>
          )))}
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => actions.remove(cell, index)}>Remove from this day</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  )
}

function DayCell({ phase, cell, day, sessions, actions, problems, dragging }: {
  phase: DraftPhase; cell: Cell; day: ManualDay; sessions: DescribedSession[]; actions: GridActions
  problems: TrackProblem[]; dragging: { sessionId: string } | null
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: `cell|${cell.week}|${cell.day}`, data: { type: 'cell', cell, title: cellName(cell) },
  })
  const byId = new Map(sessions.map((s) => [s.id, s]))
  const takes = dragging ? canPlace(day, dragging.sessionId) : false
  const full = day.sessions.length >= MAX_DAY_SESSIONS
  const addable = sessions.filter((s) => canPlace(day, s.id))
  const minutes = day.sessions.reduce((n, id) => n + (byId.get(id)?.minutes ?? 0), 0)
  return (
    <div ref={setNodeRef} role="group" aria-label={`${DAYS[cell.day]}, week ${cell.week + 1}`}
      className={cn('flex min-h-24 flex-col gap-1 rounded-md border bg-card/60 p-1.5',
        day.sessions.length === 0 && 'bg-muted/30',
        dragging && takes && 'border-primary/50', isOver && takes && 'bg-primary/10 ring-2 ring-primary/40',
        isOver && !takes && dragging && 'ring-2 ring-bad/40', problems.length > 0 && 'border-bad')}>
      {day.sessions.map((id, i) => (
        <PlacedChip key={`${id}-${i}`} phase={phase} cell={cell} index={i} session={byId.get(id)}
          name={byId.get(id)?.name ?? 'A session no longer saved'} actions={actions} />
      ))}
      {day.sessions.length === 2 && (
        <p className="text-[11px] leading-tight text-muted-foreground">One session of both · {minutes} min</p>
      )}
      {day.sessions.length === 0 && <p className="flex-1 pt-1 text-center text-[11px] text-muted-foreground">Rest</p>}
      <div className="mt-auto flex items-center justify-between">
        {day.sessions.length > 0 ? (
          <Tip label={day.light ? 'Light day: lighter weights' : 'Make this a light day'}>
            <button type="button" aria-pressed={!!day.light} aria-label={`Light day, ${cellName(cell)}`}
              onClick={() => actions.toggleLight(cell)} className={cn(iconButton, day.light && 'bg-muted text-foreground')}>
              <Feather className="size-3.5" />
            </button>
          </Tip>
        ) : <span />}
        {!full && (
          <DropdownMenu>
            <Tip label="Add a session">
              <DropdownMenuTrigger asChild>
                <button type="button" aria-label={`Add a session to ${cellName(cell)}`} disabled={addable.length === 0} className={iconButton}>
                  <Plus className="size-3.5" />
                </button>
              </DropdownMenuTrigger>
            </Tip>
            <DropdownMenuContent align="end">
              {addable.map((s) => (
                <DropdownMenuItem key={s.id} onSelect={() => actions.place(cell, s.id)}>{s.name}</DropdownMenuItem>
              ))}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>
      {day.light && <p className="text-[11px] text-muted-foreground">Light</p>}
      {problems.map((p) => <p key={p.message} role="alert" className="text-[11px] leading-tight text-bad">{p.message}</p>)}
    </div>
  )
}

/** One phase's weeks: a row a template week, a column a weekday. */
export function WeekGrid({ phase, phaseIndex, sessions, actions, problems, dragging, maxWeeks }: {
  phase: DraftPhase
  /** The phase's place in the track, which is how the server names it in a problem. */
  phaseIndex: number
  sessions: DescribedSession[]
  actions: GridActions
  problems: TrackProblem[]
  dragging: { sessionId: string } | null
  maxWeeks: number
}) {
  return (
    <div className="overflow-x-auto">
      <div className="min-w-[46rem]">
        <div className="mb-1 grid grid-cols-[5.5rem_repeat(7,minmax(0,1fr))] gap-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          <span />
          {DAY_SHORT.map((d) => <span key={d} className="px-1">{d}</span>)}
        </div>
        {phase.template.map((week, w) => (
          <div key={w} role="group" aria-label={`Week ${w + 1}`}
            className="mb-1.5 grid grid-cols-[5.5rem_repeat(7,minmax(0,1fr))] gap-1.5">
            <div className="flex flex-col gap-1 pt-1">
              <span className="text-sm font-medium">Week {w + 1}</span>
              <span className="text-[11px] text-muted-foreground">{sessionsInWeek(week)} training {sessionsInWeek(week) === 1 ? 'day' : 'days'}</span>
              <span className="flex">
                <Tip label="Duplicate this week">
                  <button type="button" aria-label={`Duplicate week ${w + 1}`} disabled={phase.template.length >= maxWeeks}
                    onClick={() => actions.duplicateWeek(w)} className={iconButton}><Copy className="size-3.5" /></button>
                </Tip>
                <Tip label="Clear this week">
                  <button type="button" aria-label={`Clear week ${w + 1}`} onClick={() => actions.clearWeek(w)} className={iconButton}>
                    <Eraser className="size-3.5" />
                  </button>
                </Tip>
                <Tip label="Remove this week">
                  <button type="button" aria-label={`Remove week ${w + 1}`} disabled={phase.template.length <= 1}
                    onClick={() => actions.removeWeek(w)} className={iconButton}><Trash2 className="size-3.5" /></button>
                </Tip>
              </span>
              {problems.filter((p) => p.phase === phaseIndex && p.week === w && p.day === null).map((p) => (
                <p key={p.message} role="alert" className="text-[11px] leading-tight text-bad">{p.message}</p>
              ))}
            </div>
            {week.map((day, d) => (
              <DayCell key={d} phase={phase} cell={{ week: w, day: d }} day={day} sessions={sessions} actions={actions}
                problems={problemsAt(problems, phaseIndex, { week: w, day: d })} dragging={dragging} />
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}
