import { announce } from '@/lib/announce'
import { DoneMark } from '@/components/shared/DoneMark'
import { useState, useMemo, type ReactNode } from 'react'
import { format, differenceInCalendarDays, parseISO } from 'date-fns'
import { GripVertical, Check, CheckCircle2, Circle, BatteryCharging, Activity, MoreHorizontal } from 'lucide-react'
import {
  DndContext,
  DragOverlay,
  useDraggable,
  useDroppable,
  useSensor,
  useSensors,
  KeyboardSensor,
  PointerSensor,
  type DragEndEvent,
  type DragStartEvent,
} from '@dnd-kit/core'
import { cn } from '@/lib/utils'
import { dropTargetCoordinates } from '@/lib/dndKeyboard'
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel,
  DropdownMenuSeparator, DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { WorkoutIcon } from '@/components/icons/WorkoutIcon'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { formatLoad } from '@/lib/formatLoad'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import { hasSessionMatch, sessionKeyVariants } from '@/lib/sessionMatching'
import type { Session, WeekData, WorkoutMatch } from '@/api/types'
import { COMPLETION } from '@/lib/completionColors'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const DAY_ABB = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']

// ─── helpers ─────────────────────────────────────────────────────────────────

function mainExercises(session: Session) {
  const all = session.exercises.filter(
    ea => !ea.meta && ea.exercise && !(ea as { injury_skip?: boolean }).injury_skip
  )
  const mains = all.filter(
    ea => !['warm_up', 'cooldown', 'joint_prep'].includes(ea.slot_role ?? '')
  )
  return mains.length > 0 ? mains : all
}

// ─── Session mini-card ────────────────────────────────────────────────────────

interface SessionCardProps {
  session: Session
  day: string
  isComplete: boolean
  hasWorkout: boolean
  /** The drag handle, when the card can be dragged. */
  handle?: ReactNode
  onOpen: () => void
  onToggleComplete: () => void
  onMove: (toDay: string) => void
}

/**
 * One session in its day's column. Nothing waits for a hover
 * (docs/frontend-design.md §11.10): the card is a button that opens its day,
 * the complete toggle and the "…" menu are always there, and the menu holds
 * every action the drag does — Move to a day — for a keyboard and a thumb.
 * Only the drag handle may wait for a pointer (`.reveal`), and it is a
 * focusable button the keyboard can pick the card up with.
 */
function SessionCard({
  session,
  day,
  isComplete,
  hasWorkout,
  handle,
  onOpen,
  onToggleComplete,
  onMove,
}: SessionCardProps) {
  const colors = MODALITY_COLORS[session.modality]
  const exercises = mainExercises(session)
  const shown = exercises.slice(0, 2)
  const extra = exercises.length - shown.length
  const duration = session.archetype?.duration_estimate_minutes
  const name = session.archetype?.name ?? session.modality.replace(/_/g, ' ')

  return (
    <div
      className={cn(
        'reveal-host relative rounded-lg border overflow-hidden transition-[color,background-color,border-color,box-shadow] h-full flex flex-col',
        'hover:border-primary/40 hover:shadow-sm',
        isComplete
          ? cn(COMPLETION.border, COMPLETION.bg)
          : 'border-border bg-card'
      )}
    >
      {/* Colored top bar */}
      <div
        className="h-0.5 w-full shrink-0"
        style={{ backgroundColor: colors?.hex ?? 'var(--primary)' }}
      />

      {/* The card opens its day: one button under the content, so the
          controls above it stay their own. */}
      <button
        type="button"
        onClick={onOpen}
        aria-label={`Open ${name}, ${day}`}
        className="absolute inset-0 rounded-lg focus-visible:-outline-offset-2"
      />

      <div className="pointer-events-none relative p-2 pb-7 space-y-1.5 flex-1 flex flex-col">
        {/* Workout icon and workout indicator on their own row: the columns
            are narrow, and the name needs their whole width */}
        {(session.icon || hasWorkout) && (
          <div className="flex items-center gap-1 pr-5">
            <WorkoutIcon icon={session.icon} modality={session.modality} className="size-4" />
            {hasWorkout && <Activity className="size-3 text-blue-700 dark:text-blue-300 shrink-0" />}
          </div>
        )}

        {/* Archetype name */}
        <p className="text-xs font-medium leading-snug text-foreground">{name}</p>

        {/* Modality, beside the name rather than over it */}
        <p
          className="text-[10px] font-semibold uppercase tracking-wide leading-tight"
          style={{ color: colors?.hex ?? 'inherit' }}
        >
          {session.modality.replace(/_/g, ' ')}
        </p>

        {/* Duration */}
        {duration != null && duration > 0 && (
          <p className="text-[10px] text-muted-foreground">~{duration} min</p>
        )}

        {/* Exercises */}
        {shown.length > 0 && (
          <div className="space-y-0.5 border-t border-border/40 pt-1.5">
            {shown.map((ea, i) => (
              <div key={i}>
                <p className="text-[10px] font-medium text-foreground leading-tight truncate">
                  {ea.exercise!.name}
                </p>
                {ea.load && Object.keys(ea.load).length > 0 && (
                  <p className="text-[9px] text-muted-foreground font-mono leading-tight truncate">
                    {formatLoad(ea.load)}
                  </p>
                )}
              </div>
            ))}
            {extra > 0 && (
              <p className="text-[9px] text-muted-foreground">+{extra} more</p>
            )}
          </div>
        )}
      </div>

      <div className="absolute bottom-1 right-1 flex items-center gap-0.5">
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label={`Actions for ${name}`}
              className="rounded p-0.5 text-muted-foreground transition-colors hover:text-foreground data-[state=open]:text-foreground"
            >
              <MoreHorizontal className="size-3.5" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-44">
            <DropdownMenuItem onSelect={onOpen}>Open</DropdownMenuItem>
            <DropdownMenuItem onSelect={onToggleComplete}>
              {isComplete ? 'Mark not done' : 'Mark complete'}
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuLabel>Move to</DropdownMenuLabel>
            {DAYS.filter((d) => d !== day).map((d) => (
              <DropdownMenuItem key={d} onSelect={() => onMove(d)}>{d}</DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>

        <button
          type="button"
          onClick={onToggleComplete}
          className={cn(
            'rounded-full p-0.5 transition-colors',
            isComplete ? COMPLETION.text : 'text-muted-foreground hover:text-foreground'
          )}
          aria-label={isComplete ? 'Mark not done' : 'Mark complete'}
          aria-pressed={isComplete}
        >
          <DoneMark done={isComplete} doneIcon={<CheckCircle2 className="size-3.5" />} openIcon={<Circle className="size-3.5" />} />
        </button>
      </div>

      {handle}
    </div>
  )
}

// ─── Draggable session wrapper ────────────────────────────────────────────────

interface DraggableSessionProps extends Omit<SessionCardProps, 'handle'> {
  dragId: string
}

function DraggableSession({ dragId, ...card }: DraggableSessionProps) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, isDragging } = useDraggable({
    id: dragId,
  })

  return (
    <div
      ref={setNodeRef}
      style={
        transform
          ? { transform: `translate3d(${transform.x}px, ${transform.y}px, 0)` }
          : undefined
      }
      className={cn('flex-1 flex flex-col min-h-0', isDragging && 'opacity-30')}
    >
      <SessionCard
        {...card}
        handle={
          // The pointer's shortcut for the menu's Move to.
          <button
            type="button"
            ref={setActivatorNodeRef}
            {...attributes}
            {...listeners}
            aria-label={`Move ${card.session.archetype?.name ?? 'session'} to another day`}
            className="reveal absolute top-1.5 right-1 rounded p-0.5 cursor-grab touch-none text-muted-foreground hover:text-foreground active:cursor-grabbing"
          >
            <GripVertical className="size-3.5" />
          </button>
        }
      />
    </div>
  )
}

// ─── Droppable day column ─────────────────────────────────────────────────────

interface DroppableDayProps {
  day: string
  dayAbb: string
  isToday: boolean
  isSelected: boolean
  isComplete: boolean
  hasSessions: boolean
  children: React.ReactNode
  onHeaderClick: () => void
}

function DroppableDay({
  day,
  dayAbb,
  isToday,
  isSelected,
  isComplete,
  hasSessions,
  children,
  onHeaderClick,
}: DroppableDayProps) {
  const { setNodeRef, isOver } = useDroppable({ id: day })

  return (
    <div
      ref={setNodeRef}
      className={cn(
        'flex flex-col gap-1.5 rounded-xl border p-1.5 min-h-[160px] transition-all',
        isOver
          ? 'border-primary/60 bg-primary/5 ring-1 ring-primary/20'
          : isSelected
            ? 'border-primary/40 bg-primary/5'
            : isComplete
              ? cn('border-emerald-500/20', COMPLETION.bg)
              : 'border-border bg-card/40'
      )}
    >
      {/* Day header */}
      <button
        type="button"
        onClick={onHeaderClick}
        className={cn(
          'flex items-center justify-between rounded-md px-1.5 py-1 text-[10px] font-bold tracking-widest uppercase transition-colors',
          isComplete
            ? cn(COMPLETION.text, 'hover:bg-emerald-500/10')
            : isToday
              ? 'text-primary hover:bg-primary/10'
              : 'text-muted-foreground hover:bg-muted'
        )}
      >
        <span>{dayAbb}</span>
        {isToday && (
          <span className="text-[8px] font-medium text-primary bg-primary/15 rounded px-1 py-0.5">
            today
          </span>
        )}
        <DoneMark done={isComplete && !isToday} doneIcon={<Check className={cn('size-2.5', COMPLETION.text)} />} />
      </button>

      {/* Sessions or rest */}
      <div className="flex flex-col gap-1 flex-1">
        {hasSessions ? (
          children
        ) : (
          <div className="flex flex-1 flex-col items-center justify-center gap-1.5 select-none">
            <BatteryCharging className="size-[30px] text-muted-foreground/40" />
            <span className="text-[10px] text-muted-foreground/40">rest</span>
          </div>
        )}
      </div>
    </div>
  )
}

// ─── Ghost card for DragOverlay ───────────────────────────────────────────────

function DragGhost({ session }: { session: Session }) {
  const colors = MODALITY_COLORS[session.modality]
  const duration = session.archetype?.duration_estimate_minutes

  return (
    <div className="rounded-lg border border-primary/40 bg-card shadow-2xl overflow-hidden w-[130px] rotate-2 opacity-95">
      <div className="h-0.5 w-full" style={{ backgroundColor: colors?.hex ?? 'var(--primary)' }} />
      <div className="p-2 space-y-1">
        <WorkoutIcon icon={session.icon} modality={session.modality} className="size-4" />
        <p className="text-xs font-medium leading-snug">
          {session.archetype?.name ?? session.modality.replace(/_/g, ' ')}
        </p>
        <p
          className="text-[10px] font-semibold uppercase tracking-wide"
          style={{ color: colors?.hex ?? 'inherit' }}
        >
          {session.modality.replace(/_/g, ' ')}
        </p>
        {duration != null && duration > 0 && (
          <p className="text-[10px] text-muted-foreground">~{duration} min</p>
        )}
      </div>
    </div>
  )
}

// ─── Public component ─────────────────────────────────────────────────────────

interface WeekOverviewProps {
  weekData: WeekData | undefined
  weekIndex: number
  selectedDay?: string | null
  onDaySelect?: (day: string | null) => void
}

export function WeekOverview({ weekData, weekIndex, selectedDay, onDaySelect }: WeekOverviewProps) {
  const programStartDate = useProgramStore(s => s.programStartDate)
  const programVersionId = useProgramStore(s => s.programVersionId)
  const sessionLogs = useProfileStore(s => s.sessionLogs)
  const setSessionLog = useProfileStore(s => s.setSessionLog)
  const upsertSessionPerformance = useBioStore(s => s.upsertSessionPerformance)
  const clearSessionCompletion = useBioStore(s => s.clearSessionCompletion)
  const getPerformanceLog = useBioStore(s => s.getPerformanceLog)
  const workoutMatches = useBioStore(s => s.workoutMatches)
  const moveSession = useProgramStore(s => s.moveSession)

  function hasLinkedWorkout(weekNum: number, day: string, si: number, matches: WorkoutMatch[]): boolean {
    return hasSessionMatch(
      matches, sessionKeyVariants(`${weekNum}-${day}`, si), programVersionId
    )
  }

  // Which program week index contains today? Only that week shows the "today" chip.
  const todayDayName = useMemo(() => format(new Date(), 'EEEE'), [])
  const isCurrentCalendarWeek = useMemo(() => {
    if (!programStartDate) return false
    const daysSinceStart = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    return Math.floor(daysSinceStart / 7) === weekIndex
  }, [programStartDate, weekIndex])

  const [activeDragId, setActiveDragId] = useState<string | null>(null)

  const activeSession = useMemo(() => {
    if (!activeDragId) return null
    const [fromDay, idxStr] = activeDragId.split('|')
    const idx = parseInt(idxStr, 10)
    return weekData?.schedule[fromDay]?.[idx] ?? null
  }, [activeDragId, weekData])

  function handleDragStart(e: DragStartEvent) {
    setActiveDragId(String(e.active.id))
  }

  function move(fromDay: string, sessionIndex: number, toDay: string) {
    if (fromDay === toDay || isNaN(sessionIndex)) return
    moveSession(weekIndex, fromDay, toDay, sessionIndex)
    // The selection follows a session moved off the selected day.
    if (selectedDay === fromDay) onDaySelect?.(toDay)
  }

  function handleDragEnd(e: DragEndEvent) {
    setActiveDragId(null)
    const { active, over } = e
    if (!over) return
    const [fromDay, idxStr] = String(active.id).split('|')
    move(fromDay, parseInt(idxStr, 10), String(over.id))
  }

  // A drag starts after 4 px, so a click on the handle is not one; the
  // keyboard steps from day to day (`lib/dndKeyboard`).
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: dropTargetCoordinates }),
  )

  const dragged = (id: string | number) => {
    const [fromDay, idxStr] = String(id).split('|')
    const session = weekData?.schedule[fromDay]?.[parseInt(idxStr, 10)]
    return { fromDay, name: session?.archetype?.name ?? 'Session' }
  }

  return (
    <DndContext
      sensors={sensors}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
      onDragCancel={() => setActiveDragId(null)}
      accessibility={{
        screenReaderInstructions: {
          draggable: 'To move this session to another day, press Space or Enter, choose the day with the arrow keys, and press Space to drop it. Escape puts it back.',
        },
        announcements: {
          onDragStart: ({ active }) => `Picked up ${dragged(active.id).name}.`,
          onDragOver: ({ active, over }) => (over ? `${dragged(active.id).name} is over ${over.id}.` : undefined),
          onDragEnd: ({ active, over }) => {
            const { fromDay, name } = dragged(active.id)
            return over && over.id !== fromDay ? `${name} moved to ${over.id}.` : `${name} stays on ${fromDay}.`
          },
          onDragCancel: ({ active }) => {
            const { fromDay, name } = dragged(active.id)
            return `Move cancelled. ${name} stays on ${fromDay}.`
          },
        },
      }}
    >
      <div className="grid grid-cols-7 gap-1.5">
        {DAYS.map((day, i) => {
          const sessions = weekData?.schedule[day] ?? []
          const dayKey = `${weekData?.week_number}-${day}`
          const dayLogs = sessionLogs[dayKey]
          const isToday = isCurrentCalendarWeek && day === todayDayName
          const isSelected = selectedDay === day
          const isDayComplete =
            sessions.length > 0 &&
            sessions.every((_, idx) => dayLogs?.[idx] === true)

          return (
            <DroppableDay
              key={day}
              day={day}
              dayAbb={DAY_ABB[i]}
              isToday={isToday}
              isSelected={isSelected}
              isComplete={isDayComplete}
              hasSessions={sessions.length > 0}
              onHeaderClick={() => {
                if (sessions.length > 0) onDaySelect?.(isSelected ? null : day)
              }}
            >
              {sessions.map((session, si) => {
                const sessionIsComplete = dayLogs?.[si] === true
                const sessionHasWorkout = hasLinkedWorkout(weekData?.week_number ?? 1, day, si, workoutMatches)
                return (
                  <DraggableSession
                    key={si}
                    dragId={`${day}|${si}`}
                    session={session}
                    day={day}
                    isComplete={sessionIsComplete}
                    hasWorkout={sessionHasWorkout}
                    onOpen={() => onDaySelect?.(isSelected ? null : day)}
                    onMove={(toDay) => {
                      move(day, si, toDay)
                      announce(`${session.archetype?.name ?? 'Session'} moved to ${toDay}.`)
                    }}
                    onToggleComplete={() => {
                      const current = sessionLogs[dayKey] ?? []
                      const next = [...current]
                      next[si] = !next[si]
                      setSessionLog(dayKey, next)
                      announce(next[si] ? `${session.archetype?.name ?? 'Session'} marked complete.` : 'Session marked not done.')
                      if (next[si]) {
                        upsertSessionPerformance({
                          sessionKey: `${dayKey}-${si}`,
                          exercises: {},
                          notes: '',
                          completedAt: new Date().toISOString(),
                        })
                      } else {
                        // The upsert cannot clear completed_at: undo is its own call (as SessionPanel).
                        clearSessionCompletion(`${dayKey}-${si}`)
                        if (si === 0 && getPerformanceLog(dayKey)?.completedAt) clearSessionCompletion(dayKey)
                      }
                    }}
                  />
                )
              })}
            </DroppableDay>
          )
        })}
      </div>

      <DragOverlay dropAnimation={null}>
        {activeSession && <DragGhost session={activeSession} />}
      </DragOverlay>
    </DndContext>
  )
}
