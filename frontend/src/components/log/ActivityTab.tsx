import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowDownToLine, CheckCircle2, Circle, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { EmptyState } from '@/components/shared/EmptyState'
import { WorkoutRow, type WorkoutMatchStatus } from '@/components/workout/WorkoutRow'
import { useRecentSessionLogs } from '@/api/health'
import { useExercises } from '@/api/exercises'
import { useCurrentProgram } from '@/api/programs'
import { useProgramStore } from '@/store/programStore'
import { buildLogSessionRows, mergeLogEntries, type LogSessionRow, type LogShow } from '@/lib/logSessions'
import type { ImportedWorkout } from '@/api/types'

export type MatchFilter = 'all' | 'matched' | 'unmatched' | 'pending'

/**
 * Log ▸ Activity: recorded workouts and what was logged against planned
 * sessions, in one list, newest first (`lib/logSessions.mergeLogEntries`).
 * They were the Workouts and Sessions sub-tabs until 2026-10-20; the type
 * filter keeps either, and a workout's match status narrows the workouts.
 * The phone's Log ▸ Activity (`LogActivityTab`) is the same list.
 */
export function ActivityTab({
  workouts, show, onShowChange, match, onMatchChange, statusFor, sessionLabelFor,
  onOpen, onMatch, onRemove, onImport,
}: {
  workouts: ImportedWorkout[]
  show: LogShow
  onShowChange: (show: LogShow) => void
  match: MatchFilter
  onMatchChange: (match: MatchFilter) => void
  statusFor: (workout: ImportedWorkout) => WorkoutMatchStatus
  sessionLabelFor: (workout: ImportedWorkout) => string | null
  onOpen: (workout: ImportedWorkout) => void
  onMatch: (workout: ImportedWorkout) => void
  onRemove: (workout: ImportedWorkout) => void
  onImport: () => void
}) {
  const navigate = useNavigate()
  const { data: logs, isLoading, isError } = useRecentSessionLogs()
  const { data: exercises } = useExercises()
  const program = useCurrentProgram()
  const programStartDate = useProgramStore((s) => s.programStartDate)

  const rows = useMemo(() => {
    const names = Object.fromEntries((exercises ?? []).map((e) => [e.id, e.name]))
    return buildLogSessionRows(logs ?? [], program, programStartDate, names)
  }, [logs, exercises, program, programStartDate])

  const counts = useMemo(() => {
    const c = { all: workouts.length, matched: 0, unmatched: 0, pending: 0 }
    for (const w of workouts) c[statusFor(w)]++
    return c
  }, [workouts, statusFor])

  // A match status narrows the workouts only; with one picked, sessions are out of view.
  const narrowed = show === 'workouts' && match !== 'all'
    ? workouts.filter((w) => statusFor(w) === match)
    : workouts
  const entries = mergeLogEntries(narrowed, rows, show)

  if (workouts.length === 0 && rows.length === 0 && !isLoading) {
    return (
      <div className="max-w-2xl mx-auto px-8 py-12">
        <EmptyState
          icon={<ArrowDownToLine className="size-8 opacity-40" />}
          title="Nothing recorded yet"
          description="Connected sources import workouts automatically, and a planned session marked complete or logged appears here too. Upload a .fit, Apple Health .xml or Strava .json file to add a workout by hand."
          action={{ label: 'Import a file', onClick: onImport }}
        />
      </div>
    )
  }

  const types: { id: LogShow; label: string }[] = [
    { id: 'all',      label: `All (${workouts.length + rows.length})` },
    { id: 'workouts', label: `Workouts (${workouts.length})` },
    { id: 'sessions', label: `Sessions (${rows.length})` },
  ]
  const statuses: { id: MatchFilter; label: string }[] = [
    { id: 'all',       label: `Any (${counts.all})` },
    { id: 'matched',   label: `Matched (${counts.matched})` },
    { id: 'unmatched', label: `Unmatched (${counts.unmatched})` },
    ...(counts.pending > 0 ? [{ id: 'pending' as MatchFilter, label: `Pending (${counts.pending})` }] : []),
  ]

  return (
    <div className="max-w-2xl mx-auto px-8 py-12 space-y-6">
      <div className="flex flex-wrap items-center gap-1">
        {types.map((t) => (
          <Chip key={t.id} active={show === t.id} onClick={() => onShowChange(t.id)}>{t.label}</Chip>
        ))}
        {show === 'workouts' && (
          <>
            <div className="mx-1.5 h-4 w-px bg-border/60" />
            {statuses.map((s) => (
              <Chip key={s.id} active={match === s.id} onClick={() => onMatchChange(s.id)}>{s.label}</Chip>
            ))}
          </>
        )}
      </div>

      {isError && show !== 'workouts' && (
        <p className="text-xs text-muted-foreground">Could not load the session logs.</p>
      )}
      {entries.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          {isLoading && show === 'sessions' ? 'Loading sessions…'
            : show === 'sessions' ? 'Nothing logged against a session yet.'
            : show === 'workouts' && match !== 'all' ? `No ${match} workouts.`
            : 'No workouts yet.'}
        </p>
      ) : (
        <div className="space-y-2">
          {entries.map((entry, i) => entry.kind === 'workout' ? (
            <WorkoutRow
              key={`w:${entry.workout.id}`}
              workout={entry.workout}
              status={statusFor(entry.workout)}
              sessionLabel={sessionLabelFor(entry.workout)}
              onOpen={() => onOpen(entry.workout)}
              onMatch={() => onMatch(entry.workout)}
              onRemove={() => onRemove(entry.workout)}
            />
          ) : (
            <SessionLogRow
              // A key alone is not unique across programs, nor is a completion time.
              key={`s:${i}:${entry.row.key}`}
              row={entry.row}
              onOpen={entry.row.href ? () => navigate(entry.row.href!) : undefined}
            />
          ))}
        </div>
      )}
    </div>
  )
}

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        'px-2.5 py-1 text-[11px] rounded border transition-colors',
        active ? 'bg-primary/15 border-primary/40 text-primary' : 'border-border text-muted-foreground hover:bg-muted'
      )}
    >
      {children}
    </button>
  )
}

/** One logged session: its name, when, and a line per exercise with something logged. */
function SessionLogRow({ row, onOpen }: { row: LogSessionRow; onOpen?: () => void }) {
  return (
    <button
      type="button"
      disabled={!onOpen}
      onClick={onOpen}
      className={cn(
        'w-full flex items-start gap-3 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 text-left transition-colors',
        onOpen ? 'cursor-pointer hover:bg-card/60' : 'cursor-default'
      )}
    >
      {row.isComplete
        ? <CheckCircle2 className="size-4 mt-0.5 shrink-0 text-emerald-600 dark:text-emerald-400" />
        : <Circle className="size-4 mt-0.5 shrink-0 text-muted-foreground" />}
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate">{row.title}</p>
        <p className="text-xs text-muted-foreground truncate">{['Session', row.subtitle].filter(Boolean).join(' · ')}</p>
        {row.lines.length > 0 && (
          <ul className="mt-1 space-y-0.5">
            {row.lines.map((line) => (
              <li key={line} className="text-[11px] text-muted-foreground/80 truncate">{line}</li>
            ))}
          </ul>
        )}
      </div>
      {onOpen && <ChevronRight className="size-4 mt-0.5 shrink-0 text-muted-foreground/50" />}
    </button>
  )
}
