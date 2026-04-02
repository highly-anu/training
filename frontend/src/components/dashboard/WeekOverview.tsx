import { useState, useMemo } from 'react'
import { format, differenceInCalendarDays, parseISO } from 'date-fns'
import { GripVertical, Check, Dumbbell } from 'lucide-react'
import {
  DndContext,
  DragOverlay,
  useDraggable,
  useDroppable,
  type DragEndEvent,
  type DragStartEvent,
} from '@dnd-kit/core'
import { cn } from '@/lib/utils'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { formatLoad } from '@/lib/formatLoad'
import { useProfileStore } from '@/store/profileStore'
import { useProgramStore } from '@/store/programStore'
import type { Session, WeekData } from '@/api/types'

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

// ─── Session mini-card (shared between live card and DragOverlay ghost) ───────

interface SessionCardProps {
  session: Session
  weekNumber: number
  day: string
  isComplete: boolean
  isDragging?: boolean
  dragHandleListeners?: Record<string, unknown>
  dragHandleRef?: (el: HTMLElement | null) => void
  onClick: () => void
}

function SessionCard({
  session,
  weekNumber,
  day,
  isComplete,
  isDragging,
  dragHandleListeners,
  dragHandleRef,
  onClick,
}: SessionCardProps) {
  const colors = MODALITY_COLORS[session.modality]
  const exercises = mainExercises(session)
  const shown = exercises.slice(0, 2)
  const extra = exercises.length - shown.length
  const duration = session.archetype?.duration_estimate_minutes

  return (
    <div
      className={cn(
        'relative rounded-lg border overflow-hidden cursor-pointer transition-all group/card h-full flex flex-col',
        isDragging
          ? 'shadow-xl ring-2 ring-primary/40 opacity-95'
          : 'hover:border-primary/40 hover:shadow-sm',
        isComplete
          ? 'border-emerald-500/30 bg-emerald-500/5'
          : 'border-border bg-card'
      )}
      onClick={onClick}
    >
      {/* Colored top bar */}
      <div
        className="h-0.5 w-full shrink-0"
        style={{ backgroundColor: colors?.hex ?? 'var(--primary)' }}
      />

      <div className="p-2 space-y-1.5 flex-1 flex flex-col">
        {/* Modality + duration row */}
        <div className="flex items-start justify-between gap-1">
          <p
            className="text-[10px] font-semibold uppercase tracking-wide leading-tight"
            style={{ color: colors?.hex ?? 'inherit' }}
          >
            {session.modality.replace(/_/g, ' ')}
          </p>
        </div>

        {/* Archetype name */}
        <p className="text-xs font-medium leading-snug text-foreground">
          {session.archetype?.name ?? session.modality.replace(/_/g, ' ')}
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

      {/* Drag handle */}
      {dragHandleListeners && (
        <div
          ref={dragHandleRef}
          {...dragHandleListeners}
          className={cn(
            'absolute top-1.5 right-1 p-0.5 rounded cursor-grab active:cursor-grabbing',
            'opacity-0 group-hover/card:opacity-50 hover:!opacity-100 transition-opacity',
            'text-muted-foreground hover:text-foreground'
          )}
          onClick={e => e.stopPropagation()}
          title="Drag to move to another day"
        >
          <GripVertical className="size-3.5" />
        </div>
      )}
    </div>
  )
}

// ─── Draggable session wrapper ────────────────────────────────────────────────

interface DraggableSessionProps {
  dragId: string
  session: Session
  weekNumber: number
  day: string
  isComplete: boolean
  onCardClick: () => void
}

function DraggableSession({
  dragId,
  session,
  weekNumber,
  day,
  isComplete,
  onCardClick,
}: DraggableSessionProps) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
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
      {...attributes}
      className={cn('flex-1 flex flex-col min-h-0', isDragging && 'opacity-30')}
    >
      <SessionCard
        session={session}
        weekNumber={weekNumber}
        day={day}
        isComplete={isComplete}
        isDragging={false}
        dragHandleListeners={listeners as Record<string, unknown>}
        onClick={onCardClick}
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
              ? 'border-emerald-500/20 bg-emerald-500/5'
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
            ? 'text-emerald-500 hover:bg-emerald-500/10'
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
        {isComplete && !isToday && <Check className="size-2.5 text-emerald-500" />}
      </button>

      {/* Sessions or rest */}
      <div className="flex flex-col gap-1 flex-1">
        {hasSessions ? (
          children
        ) : (
          <div className="flex flex-1 items-center justify-center text-[10px] text-muted-foreground/40 select-none">
            rest
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
        <p
          className="text-[10px] font-semibold uppercase tracking-wide"
          style={{ color: colors?.hex ?? 'inherit' }}
        >
          {session.modality.replace(/_/g, ' ')}
        </p>
        <p className="text-xs font-medium leading-snug">
          {session.archetype?.name ?? session.modality.replace(/_/g, ' ')}
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
  const sessionLogs = useProfileStore(s => s.sessionLogs)
  const moveSession = useProgramStore(s => s.moveSession)

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

  function handleDragEnd(e: DragEndEvent) {
    setActiveDragId(null)
    const { active, over } = e
    if (!over) return
    const [fromDay, idxStr] = String(active.id).split('|')
    const sessionIndex = parseInt(idxStr, 10)
    const toDay = String(over.id)
    if (fromDay !== toDay && !isNaN(sessionIndex)) {
      moveSession(weekIndex, fromDay, toDay, sessionIndex)
      // If the moved session came from the selected day, deselect it
      if (selectedDay === fromDay) onDaySelect?.(toDay)
    }
  }

  return (
    <DndContext onDragStart={handleDragStart} onDragEnd={handleDragEnd} onDragCancel={() => setActiveDragId(null)}>
      <div className="grid grid-cols-7 gap-1.5">
        {DAYS.map((day, i) => {
          const sessions = weekData?.schedule[day] ?? []
          const isToday = isCurrentCalendarWeek && day === todayDayName
          const isSelected = selectedDay === day
          const isComplete =
            sessions.length > 0 &&
            sessions.every((_, idx) => sessionLogs[`${weekData?.week_number}-${day}`]?.[idx] === true)

          return (
            <DroppableDay
              key={day}
              day={day}
              dayAbb={DAY_ABB[i]}
              isToday={isToday}
              isSelected={isSelected}
              isComplete={isComplete}
              hasSessions={sessions.length > 0}
              onHeaderClick={() => {
                if (sessions.length > 0) onDaySelect?.(isSelected ? null : day)
              }}
            >
              {sessions.map((session, si) => (
                <DraggableSession
                  key={si}
                  dragId={`${day}|${si}`}
                  session={session}
                  weekNumber={weekData?.week_number ?? 1}
                  day={day}
                  isComplete={isComplete}
                  onCardClick={() => onDaySelect?.(isSelected ? null : day)}
                />
              ))}
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
