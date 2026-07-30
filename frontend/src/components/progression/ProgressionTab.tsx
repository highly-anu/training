import { useMemo, useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Upload, CheckCircle2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import { fetchProgressionReview, fetchExerciseHistory, fetchMatchedSessions } from '@/api/progression'
import { fetchHealthSnapshot } from '@/api/health'
import { ExerciseProgressCard } from './ExerciseProgressCard'
import { MatchedSessionCard } from './MatchedSessionCard'
import { useProfileStore } from '@/store/profileStore'
import { useBioStore } from '@/store/bioStore'
import { useProgramStore } from '@/store/programStore'
import type { ExerciseFinding } from '@/api/types'
import { COMPLETION } from '@/lib/completionColors'

type Period = 'weekly' | 'biweekly'
type SessionFilter = 'all' | 'linked'

const DAY_ORDER: Record<string, number> = {
  Monday: 1, Tuesday: 2, Wednesday: 3, Thursday: 4,
  Friday: 5, Saturday: 6, Sunday: 7,
}

export function ProgressionTab() {
  const [period, setPeriod] = useState<Period>('weekly')
  const [showAll, setShowAll] = useState(false)
  const [showAllSessions, setShowAllSessions] = useState(false)
  const [sessionFilter, setSessionFilter] = useState<SessionFilter>('all')

  const sessionLogs = useProfileStore((s) => s.sessionLogs)
  const currentProgram = useProgramStore((s) => s.currentProgram)
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)
  const initBio = useBioStore((s) => s.init)

  const {
    data: review,
    isLoading: reviewLoading,
    isError: reviewError,
  } = useQuery({
    queryKey: ['progression', 'review', period],
    queryFn:  () => fetchProgressionReview(period),
    staleTime: 5 * 60 * 1000,
  })

  const {
    data: historyData,
    isLoading: exercisesLoading,
  } = useQuery({
    queryKey: ['progression', 'exercises'],
    queryFn:  () => fetchExerciseHistory(),
    staleTime: 5 * 60 * 1000,
  })

  const { data: sessions } = useQuery({
    queryKey: ['progression', 'sessions'],
    queryFn:  fetchMatchedSessions,
    staleTime: 5 * 60 * 1000,
  })

  // If sessions references workout IDs not yet in the local store (watch workouts saved
  // after the initial hydration), re-fetch the health snapshot to sync the store.
  useEffect(() => {
    if (!sessions || sessions.length === 0) return
    const storeIds = new Set(importedWorkouts.map((w) => w.id))
    const missing = sessions.some((s) => s.importedWorkoutId && !storeIds.has(s.importedWorkoutId))
    if (missing) {
      fetchHealthSnapshot().then(initBio).catch(() => {})
    }
  }, [sessions, importedWorkouts, initBio])

  const findingMap = useMemo(() => {
    const m = new Map<string, ExerciseFinding>()
    for (const f of review?.exercise_findings ?? []) m.set(f.exercise_id, f)
    return m
  }, [review?.exercise_findings])

  const matchedSessionMap = useMemo(() => {
    const m = new Map<string, NonNullable<typeof sessions>[number]>()
    for (const s of sessions ?? []) m.set(s.sessionKey, s)
    return m
  }, [sessions])

  const allCompleted = useMemo(() => {
    if (!currentProgram) return []
    return Object.entries(sessionLogs)
      .filter(([, completions]) => completions.some((c) => c === true))
      .map(([key]) => {
        const dashIdx = key.indexOf('-')
        const weekNumber = parseInt(key.slice(0, dashIdx), 10)
        const dayName = key.slice(dashIdx + 1)
        const weekData = currentProgram.weeks.find((w) => w.week_number === weekNumber)
        const daySessions = weekData?.schedule[dayName] ?? []
        const archetypeName =
          daySessions[0]?.archetype?.name ??
          daySessions[0]?.modality.replace(/_/g, ' ') ??
          'Session'
        // Check per-session keys ("weekNum-Day-si") and legacy day-level keys
        const matchEntry = workoutMatches.find(
          (m) => (m.sessionKey === key || m.sessionKey.startsWith(`${key}-`)) && m.matchConfidence !== 'rejected'
        )
        const matched = matchEntry ? importedWorkouts.find((w) => w.id === matchEntry.importedWorkoutId) : undefined
        return { sessionKey: key, weekNumber, dayName, archetypeName, matchedWorkout: matched }
      })
      .sort((a, b) => {
        if (a.weekNumber !== b.weekNumber) return b.weekNumber - a.weekNumber
        return (DAY_ORDER[b.dayName] ?? 0) - (DAY_ORDER[a.dayName] ?? 0)
      })
  }, [sessionLogs, currentProgram, workoutMatches, importedWorkouts])

  const linkedCount = allCompleted.filter((s) => s.matchedWorkout).length

  const allExercises = historyData?.exercises ?? []
  const trackedExercises = allExercises.filter((e) => e.history.length >= 1)
  const hiddenCount = allExercises.length - trackedExercises.length
  const visibleExercises = showAll ? allExercises : trackedExercises

  const isLoading = reviewLoading || exercisesLoading
  const isInsufficient =
    !review || review.overall_score === null || review.flags.includes('insufficient_data')
  const recommendations = isInsufficient ? [] : (review?.recommendations ?? [])

  return (
    <div className="space-y-6">

      {/* Controls row: period toggle · exercise filter · compliance */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1">
            {(['weekly', 'biweekly'] as Period[]).map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setPeriod(p)}
                className={cn(
                  'px-3 py-1 text-xs rounded border transition-colors capitalize',
                  p === period
                    ? 'bg-primary/15 border-primary/40 text-primary'
                    : 'border-border text-muted-foreground hover:bg-muted',
                )}
              >
                {p === 'biweekly' ? 'Bi-weekly' : 'Weekly'}
              </button>
            ))}
          </div>

          {hiddenCount > 0 && (
            <div className="flex items-center gap-1">
              {(['tracked', 'all'] as const).map((v) => (
                <button
                  key={v}
                  type="button"
                  onClick={() => setShowAll(v === 'all')}
                  className={cn(
                    'px-3 py-1 text-xs rounded border transition-colors capitalize',
                    (v === 'all') === showAll
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted',
                  )}
                >
                  {v === 'tracked' ? `Tracked (${trackedExercises.length})` : `All (${allExercises.length})`}
                </button>
              ))}
            </div>
          )}
        </div>

        {review && (
          <span className="text-xs text-muted-foreground">
            {review.compliance_pct}% completed · {review.period_key}
          </span>
        )}
      </div>

      {/* Main content */}
      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {[...Array(4)].map((_, i) => (
            <div
              key={i}
              className="rounded-xl border bg-card p-4 h-[104px] animate-pulse"
            />
          ))}
        </div>
      ) : reviewError ? (
        <div className="rounded-xl border border-destructive/30 bg-card p-4 ring-1 ring-destructive/20">
          <p className="text-[11px] text-destructive">
            Could not load progression data — make sure the backend is running.
          </p>
        </div>
      ) : visibleExercises.length === 0 && allExercises.length === 0 ? (
        <div className="rounded-xl border bg-card p-6 text-center space-y-2">
          <p className="text-sm font-medium text-muted-foreground">No program exercises found</p>
          <p className="text-[11px] text-muted-foreground/70 leading-relaxed max-w-xs mx-auto">
            Generate a program to start tracking your progression here.
          </p>
        </div>
      ) : visibleExercises.length === 0 ? (
        <div className="rounded-xl border bg-card p-6 text-center space-y-2">
          <p className="text-sm font-medium text-muted-foreground">No exercises logged yet</p>
          <p className="text-[11px] text-muted-foreground/70 leading-relaxed max-w-xs mx-auto">
            Switch to <button type="button" onClick={() => setShowAll(true)} className="text-primary underline-offset-2 hover:underline">All</button> to see your full program, or log sets inside a session to track progression.
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {visibleExercises.map((item) => (
            <ExerciseProgressCard
              key={item.exerciseId}
              item={item}
              finding={findingMap.get(item.exerciseId)}
            />
          ))}
        </div>
      )}


      {/* Session log — completed sessions with filter */}
      {allCompleted.length > 0 && (
        <div className="space-y-2 border-t border-border/40 pt-4">
          <div className="flex items-center justify-between gap-2">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
              Session Log · {allCompleted.length} completed
            </p>
            <div className="flex items-center gap-1">
              {(['all', 'linked'] as SessionFilter[]).map((f) => (
                <button
                  key={f}
                  type="button"
                  onClick={() => { setSessionFilter(f); setShowAllSessions(false) }}
                  className={cn(
                    'px-2.5 py-0.5 text-[11px] rounded border transition-colors capitalize',
                    f === sessionFilter
                      ? 'bg-primary/15 border-primary/40 text-primary'
                      : 'border-border text-muted-foreground hover:bg-muted',
                  )}
                >
                  {f === 'linked' ? `Linked (${linkedCount})` : `All (${allCompleted.length})`}
                </button>
              ))}
            </div>
          </div>

          {(() => {
            const visible = sessionFilter === 'linked'
              ? allCompleted.filter((s) => s.matchedWorkout)
              : allCompleted
            const shown = showAllSessions ? visible : visible.slice(0, 5)
            return (
              <>
                {visible.length === 0 ? (
                  <p className="text-[11px] text-muted-foreground py-2">
                    No sessions with linked workouts yet.
                  </p>
                ) : (
                  <div className="space-y-2">
                    {shown.map((s) => {
                      const apiEntry = matchedSessionMap.get(s.sessionKey)
                      if (apiEntry) {
                        return <MatchedSessionCard key={s.sessionKey} item={apiEntry} />
                      }
                      // Completed session without API match summary
                      return (
                        <div
                          key={s.sessionKey}
                          className="rounded-xl border border-border/60 bg-card px-4 py-3 flex items-center justify-between gap-2"
                        >
                          <div className="flex items-center gap-2 min-w-0">
                            <span className="shrink-0 text-[10px] text-muted-foreground/70 tabular-nums">
                              Wk {s.weekNumber} · {s.dayName.slice(0, 3)}
                            </span>
                            <p className="text-sm font-medium text-foreground truncate leading-tight">
                              {s.archetypeName}
                            </p>
                            <CheckCircle2 className={cn('size-3.5 shrink-0', COMPLETION.text)} />
                          </div>
                          <Link
                            to={`/import?linkTo=${s.sessionKey}`}
                            className="shrink-0 flex items-center gap-1 text-[11px] text-muted-foreground hover:text-primary transition-colors"
                          >
                            <Upload className="size-3" />
                            Import workout
                          </Link>
                        </div>
                      )
                    })}
                  </div>
                )}
                {visible.length > 5 && (
                  <div className="flex justify-center">
                    <button
                      type="button"
                      onClick={() => setShowAllSessions((v) => !v)}
                      className="text-xs text-muted-foreground hover:text-foreground underline-offset-2 hover:underline transition-colors"
                    >
                      {showAllSessions ? 'Show less' : `Show all ${visible.length} sessions`}
                    </button>
                  </div>
                )}
              </>
            )
          })()}
        </div>
      )}

      {/* Recommendations (only when sufficient data) */}
      {recommendations.length > 0 && (
        <div className="space-y-1 border-t border-border/40 pt-4">
          {recommendations.slice(0, 3).map((r, i) => (
            <p key={i} className="text-[11px] text-muted-foreground">
              · {r}
            </p>
          ))}
        </div>
      )}

    </div>
  )
}
