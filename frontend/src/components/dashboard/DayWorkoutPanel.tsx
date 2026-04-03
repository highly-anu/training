import { useState } from 'react'
import { X, CheckCircle2, Circle, RefreshCw } from 'lucide-react'
import { cn } from '@/lib/utils'
import { SessionHeader } from '@/components/session/SessionHeader'
import { ReplaceSessionSheet } from '@/components/session/ReplaceSessionSheet'
import { ExerciseRow } from '@/components/session/ExerciseRow'
import { SessionNotes } from '@/components/session/SessionNotes'
import { WorkoutSummaryCard } from '@/components/session/WorkoutSummaryCard'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import type { WeekData } from '@/api/types'

interface DayWorkoutPanelProps {
  weekData: WeekData
  weekIndex: number
  day: string
  onClose: () => void
}

export function DayWorkoutPanel({ weekData, weekIndex, day, onClose }: DayWorkoutPanelProps) {
  const sessions = weekData.schedule[day] ?? []
  const sessionKey = `${weekData.week_number}-${day}`

  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const setSessionLog = useProfileStore((s) => s.setSessionLog)
  const upsertSessionPerformance = useBioStore((s) => s.upsertSessionPerformance)
  const currentProgram = useProgramStore((s) => s.currentProgram)
  const [replaceTarget, setReplaceTarget] = useState<{ idx: number } | null>(null)

  function toggleComplete(si: number) {
    const current = sessionLogs[sessionKey] ?? []
    const next = [...current]
    next[si] = !next[si]
    setSessionLog(sessionKey, next)
    if (next[si]) {
      upsertSessionPerformance({
        sessionKey: `${sessionKey}-${si}`,
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
        {sessions.map((session, si) => {
          const isComplete = sessionLogs[sessionKey]?.[si] === true
          return (
            <div key={si} className={cn('space-y-4', si > 0 && 'border-t border-border pt-6')}>
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <SessionHeader
                    session={session}
                    day={day}
                    weekNumber={weekData.week_number}
                    weekInPhase={weekData.week_in_phase}
                    phase={weekData.phase}
                  />
                </div>
                <button
                  type="button"
                  onClick={() => setReplaceTarget({ idx: si })}
                  className="shrink-0 mt-1 flex items-center gap-1 rounded-md border border-border px-2 py-1 text-[11px] text-muted-foreground hover:border-primary/40 hover:text-foreground transition-colors"
                >
                  <RefreshCw className="size-3" />
                  Replace
                </button>
              </div>
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
              <button
                type="button"
                onClick={() => toggleComplete(si)}
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
          )
        })}

        <WorkoutSummaryCard sessionKey={sessionKey} sessions={sessions} weekIndex={weekIndex} />
        <SessionNotes sessionKey={sessionKey} />
      </div>

      {currentProgram && replaceTarget && (
        <ReplaceSessionSheet
          open={true}
          onOpenChange={(open) => { if (!open) setReplaceTarget(null) }}
          session={sessions[replaceTarget.idx]}
          weekIndex={weekIndex}
          weekData={weekData}
          day={day}
          sessionIndex={replaceTarget.idx}
          program={currentProgram}
        />
      )}
    </>
  )
}
