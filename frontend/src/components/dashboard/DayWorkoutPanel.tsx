import { X, CheckCircle2, Circle } from 'lucide-react'
import { cn } from '@/lib/utils'
import { SessionHeader } from '@/components/session/SessionHeader'
import { ExerciseRow } from '@/components/session/ExerciseRow'
import { SessionNotes } from '@/components/session/SessionNotes'
import { WorkoutSummaryCard } from '@/components/session/WorkoutSummaryCard'
import { Separator } from '@/components/ui/separator'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import type { WeekData } from '@/api/types'

interface DayWorkoutPanelProps {
  weekData: WeekData
  day: string
  onClose: () => void
}

export function DayWorkoutPanel({ weekData, day, onClose }: DayWorkoutPanelProps) {
  const sessions = weekData.schedule[day] ?? []
  const sessionKey = `${weekData.week_number}-${day}`

  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const setSessionLog = useProfileStore((s) => s.setSessionLog)
  const upsertSessionPerformance = useBioStore((s) => s.upsertSessionPerformance)

  const isComplete = sessionLogs[sessionKey]?.[0] === true

  function toggleComplete() {
    const next = !isComplete
    setSessionLog(sessionKey, [next])
    if (next) {
      upsertSessionPerformance({
        sessionKey,
        exercises: {},
        notes: '',
        completedAt: new Date().toISOString(),
      })
    }
  }

  if (sessions.length === 0) return null

  return (
    <>
      {/* Sticky header */}
      <div className="sticky top-0 z-10 flex items-center justify-between gap-3 border-b border-border bg-card/95 px-5 py-3 backdrop-blur-sm">
        <div>
          <p className="text-sm font-semibold">{day}</p>
          <p className="text-[11px] text-muted-foreground">
            Week {weekData.week_number}
            {sessions.length > 0 && (
              <span className="ml-1 capitalize">
                · {sessions.map((s) => s.modality.replace(/_/g, ' ')).join(' + ')}
              </span>
            )}
          </p>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="shrink-0 rounded-md p-1.5 text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
          aria-label="Close"
        >
          <X className="size-4" />
        </button>
      </div>

      {/* Scrollable content */}
      <div className="p-5 space-y-6">
        {sessions.map((session, si) => (
          <div key={si} className={cn('space-y-4', si > 0 && 'border-t border-border pt-6')}>
            <SessionHeader
              session={session}
              day={day}
              weekNumber={weekData.week_number}
              weekInPhase={weekData.week_in_phase}
              phase={weekData.phase}
            />
            <div className="space-y-2">
              {session.exercises.map((assignment, i) => (
                <ExerciseRow
                  key={`${sessionKey}-${si}-${i}`}
                  assignment={assignment}
                  index={i}
                  sessionKey={sessionKey}
                />
              ))}
            </div>
          </div>
        ))}

        <WorkoutSummaryCard sessionKey={sessionKey} sessions={sessions} />
        <SessionNotes sessionKey={sessionKey} />

        <Separator />

        <button
          type="button"
          onClick={toggleComplete}
          className={cn(
            'w-full flex items-center justify-center gap-2 rounded-lg border px-4 py-2.5 text-sm font-semibold transition-all',
            isComplete
              ? 'border-emerald-500/40 bg-emerald-500/10 text-emerald-500 hover:bg-emerald-500/20'
              : 'border-border bg-muted/30 text-muted-foreground hover:border-primary/40 hover:text-foreground'
          )}
        >
          {isComplete ? (
            <><CheckCircle2 className="size-4" /> Session Complete</>
          ) : (
            <><Circle className="size-4" /> Mark Complete</>
          )}
        </button>
      </div>
    </>
  )
}
