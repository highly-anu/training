import { useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, Circle, RefreshCw, Activity } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { SessionHeader } from '@/components/session/SessionHeader'
import { ReplaceSessionSheet } from '@/components/session/ReplaceSessionSheet'
import { SwapExerciseSheet } from '@/components/session/SwapExerciseSheet'
import { ExerciseRow } from '@/components/session/ExerciseRow'
import { SessionNotes } from '@/components/session/SessionNotes'
import { WorkoutSummaryCard } from '@/components/session/WorkoutSummaryCard'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import { findSessionMatch, sessionKeyVariants } from '@/lib/sessionMatching'
import { COMPLETION_INTERACTIVE } from '@/lib/completionColors'
import type { ComplementaryExercise, GeneratedProgram, WeekData } from '@/api/types'

interface SessionPanelProps {
  program: GeneratedProgram
  weekData: WeekData
  weekIndex: number
  day: string
  /** Tighter spacing for the Home side panel. */
  compact?: boolean
}

/**
 * One day's planned sessions: header, matched-workout link, Replace, the
 * exercise rows with their loggers, cool-down, the complete toggle, then the
 * workout summary and notes for the day.
 *
 * Rendered by the session page (`/program/:week/:day`) and by Home's side
 * panel. The two used to be separate copies of this; a fix to one was a bug
 * in the other.
 */
export function SessionPanel({ program, weekData, weekIndex, day, compact = false }: SessionPanelProps) {
  const sessions = weekData.schedule[day] ?? []
  const sessionKey = `${weekData.week_number}-${day}`

  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const setSessionLog = useProfileStore((s) => s.setSessionLog)
  const getPerformanceLog = useBioStore((s) => s.getPerformanceLog)
  const upsertSessionPerformance = useBioStore((s) => s.upsertSessionPerformance)
  const clearSessionCompletion = useBioStore((s) => s.clearSessionCompletion)
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)
  const programVersionId = useProgramStore((s) => s.programVersionId)
  const [replaceTarget, setReplaceTarget] = useState<{ idx: number } | null>(null)
  const [swapTarget, setSwapTarget] = useState<{ si: number; ei: number } | null>(null)

  function getSessionMatch(si: number) {
    const entry = findSessionMatch(
      workoutMatches, sessionKeyVariants(sessionKey, si), programVersionId
    )
    return entry ? importedWorkouts.find((w) => w.id === entry.importedWorkoutId) : undefined
  }

  function isComplete(si: number): boolean {
    return sessionLogs[sessionKey]?.[si] === true
      || !!getPerformanceLog(`${sessionKey}-${si}`)?.completedAt
      || (si === 0 && !!getPerformanceLog(sessionKey)?.completedAt)
  }

  function toggleComplete(si: number) {
    const current = sessionLogs[sessionKey] ?? []
    const next = [...current]
    next[si] = !isComplete(si)
    setSessionLog(sessionKey, next)
    const perSessionKey = `${sessionKey}-${si}`
    if (next[si]) {
      upsertSessionPerformance({
        sessionKey: perSessionKey,
        exercises: {},
        notes: '',
        completedAt: new Date().toISOString(),
      })
    } else {
      // The server keeps the later completed_at on upsert, so undo is its own
      // call; it leaves logged sets and notes in place.
      clearSessionCompletion(perSessionKey)
      if (si === 0 && getPerformanceLog(sessionKey)?.completedAt) clearSessionCompletion(sessionKey)
    }
  }

  if (sessions.length === 0) return null

  const pad = compact ? 'p-5 space-y-6' : 'p-6 space-y-6'

  return (
    <>
      <div className={pad}>
        {sessions.map((session, si) => {
          if (!session.archetype) return (
            <div key={si} className={cn('space-y-2', si > 0 && 'border-t border-border pt-6')}>
              <p className="text-sm font-medium capitalize">{session.modality.replace(/_/g, ' ')}</p>
              <div className="flex items-center gap-3 rounded-md border border-dashed border-border bg-muted/20 px-4 py-3 text-xs text-muted-foreground">
                <RefreshCw className="size-3.5 shrink-0" />
                <span>No session could be generated for this slot. Use <strong>Replace</strong> to regenerate.</span>
                <button
                  type="button"
                  onClick={() => setReplaceTarget({ idx: si })}
                  className="ml-auto shrink-0 rounded border border-border px-2 py-1 text-[11px] hover:border-primary/40 hover:text-foreground transition-colors"
                >
                  Replace
                </button>
              </div>
            </div>
          )
          const complete = isComplete(si)
          const matchedWorkout = getSessionMatch(si)
          return (
            <div key={si} className="space-y-4">
              {si > 0 && <Separator />}

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
                <div className="flex items-center gap-2 shrink-0 mt-1">
                  {matchedWorkout && (
                    <Link
                      to={`/log/${encodeURIComponent(matchedWorkout.id)}`}
                      state={{ workout: matchedWorkout }}
                      className="flex items-center gap-1 text-xs text-blue-700 dark:text-blue-300 hover:underline transition-colors font-medium"
                    >
                      <Activity className="size-3.5" />
                      Workout
                    </Link>
                  )}
                  <Button variant="outline" size="sm" onClick={() => setReplaceTarget({ idx: si })}>
                    <RefreshCw className="size-3.5 mr-1.5" />
                    Replace
                  </Button>
                </div>
              </div>

              <div className="space-y-2">
                {session.exercises.map((assignment, i) => (
                  <ExerciseRow
                    key={`${sessionKey}-${si}-${i}`}
                    assignment={assignment}
                    index={i}
                    sessionKey={sessionKey}
                    sessionIdx={si}
                    onSwap={assignment.exercise && session.archetype ? () => setSwapTarget({ si, ei: i }) : undefined}
                  />
                ))}
              </div>

              {session.complementary_work && session.complementary_work.length > 0 && (
                <div className="rounded-lg border bg-muted/30 p-4 space-y-3">
                  <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
                    Cool-down / Recovery
                  </h4>
                  <div className="space-y-2">
                    {session.complementary_work.map((cw: ComplementaryExercise, i: number) => (
                      <div key={i} className="flex items-start justify-between gap-3 rounded-md bg-background/60 px-3 py-2">
                        <div className="min-w-0">
                          <p className="text-sm font-medium leading-snug">{cw.exercise.name}</p>
                          {cw.prescription.note && (
                            <p className="text-xs text-muted-foreground mt-0.5 italic">{cw.prescription.note}</p>
                          )}
                        </div>
                        <span className="shrink-0 text-xs text-muted-foreground tabular-nums mt-0.5">
                          {cw.prescription.sets}×{cw.prescription.duration_sec}s
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <button
                type="button"
                onClick={() => toggleComplete(si)}
                className={cn(
                  'w-full flex items-center justify-center gap-2 h-10 rounded-lg text-sm font-medium transition-colors',
                  complete
                    ? `border ${COMPLETION_INTERACTIVE}`
                    : 'bg-primary text-primary-foreground hover:bg-primary/90'
                )}
              >
                {complete
                  ? <><CheckCircle2 className="size-4" /> Completed — tap to undo</>
                  : <><Circle className="size-4" /> Mark Session Complete</>
                }
              </button>
            </div>
          )
        })}

        {/* Workout summary (HR data if an imported workout is matched) */}
        <WorkoutSummaryCard sessionKey={sessionKey} sessions={sessions} weekIndex={weekIndex} />

        {/* Session notes + fatigue rating */}
        <SessionNotes sessionKey={sessionKey} />
      </div>

      {swapTarget && (
        <SwapExerciseSheet
          open={true}
          onOpenChange={(open) => { if (!open) setSwapTarget(null) }}
          program={program}
          weekData={weekData}
          weekIndex={weekIndex}
          day={day}
          sessionIndex={swapTarget.si}
          exerciseIndex={swapTarget.ei}
        />
      )}

      {replaceTarget && (
        <ReplaceSessionSheet
          open={true}
          onOpenChange={(open) => { if (!open) setReplaceTarget(null) }}
          session={sessions[replaceTarget.idx]}
          weekIndex={weekIndex}
          weekData={weekData}
          day={day}
          sessionIndex={replaceTarget.idx}
          program={program}
        />
      )}
    </>
  )
}
