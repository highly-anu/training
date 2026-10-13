import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { CheckCircle2, Circle, ChevronRight, NotebookPen } from 'lucide-react'
import { cn } from '@/lib/utils'
import { EmptyState } from '@/components/shared/EmptyState'
import { useRecentSessionLogs } from '@/api/health'
import { useExercises } from '@/api/exercises'
import { useCurrentProgram } from '@/api/programs'
import { useProgramStore } from '@/store/programStore'
import { buildLogSessionRows } from '@/lib/logSessions'

/**
 * Log ▸ Sessions: what was logged against planned sessions, newest completion
 * first, earlier programs' logs included and named by the server. The same
 * list as the phone's Log ▸ Sessions (`LogSessionsTab`); the rows come from
 * `lib/logSessions.ts`. Recorded workouts are Log ▸ Workouts — this is the
 * plan's side of the record.
 */
export function SessionsTab() {
  const navigate = useNavigate()
  const { data: logs, isLoading, isError } = useRecentSessionLogs()
  const { data: exercises } = useExercises()
  const program = useCurrentProgram()
  const programStartDate = useProgramStore((s) => s.programStartDate)

  const rows = useMemo(() => {
    const names = Object.fromEntries((exercises ?? []).map((e) => [e.id, e.name]))
    return buildLogSessionRows(logs ?? [], program, programStartDate, names)
  }, [logs, exercises, program, programStartDate])

  if (isLoading) {
    return <p className="max-w-2xl mx-auto px-8 py-12 text-sm text-muted-foreground">Loading sessions…</p>
  }
  if (isError) {
    return <p className="max-w-2xl mx-auto px-8 py-12 text-sm text-muted-foreground">Could not load the session logs.</p>
  }
  if (rows.length === 0) {
    return (
      <div className="max-w-2xl mx-auto px-8 py-12">
        <EmptyState
          icon={<NotebookPen className="size-8 opacity-40" />}
          title="Nothing logged yet"
          description="Mark a planned session complete or log its sets and it appears here, across every program you have run."
        />
      </div>
    )
  }
  return (
    <div className="max-w-2xl mx-auto px-8 py-12">
      <ul className="space-y-2">
        {rows.map((row) => (
          <li key={row.key + (row.completedAt?.toISOString() ?? '')}>
            <button
              type="button"
              disabled={!row.href}
              onClick={() => row.href && navigate(row.href)}
              className={cn(
                'w-full flex items-start gap-3 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5 text-left transition-colors',
                row.href ? 'cursor-pointer hover:bg-card/60' : 'cursor-default'
              )}
            >
              {row.isComplete
                ? <CheckCircle2 className="size-4 mt-0.5 shrink-0 text-emerald-600 dark:text-emerald-400" />
                : <Circle className="size-4 mt-0.5 shrink-0 text-muted-foreground" />}
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium truncate">{row.title}</p>
                <p className="text-xs text-muted-foreground truncate">{row.subtitle}</p>
                {row.lines.length > 0 && (
                  <ul className="mt-1 space-y-0.5">
                    {row.lines.map((line) => (
                      <li key={line} className="text-[11px] text-muted-foreground/80 truncate">{line}</li>
                    ))}
                  </ul>
                )}
              </div>
              {row.href && <ChevronRight className="size-4 mt-0.5 shrink-0 text-muted-foreground/50" />}
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
