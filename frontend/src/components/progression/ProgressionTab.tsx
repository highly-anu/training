import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { cn } from '@/lib/utils'
import { fetchProgressionReview, fetchExerciseHistory, fetchMatchedSessions } from '@/api/progression'
import { ExerciseProgressCard } from './ExerciseProgressCard'
import { MatchedSessionCard } from './MatchedSessionCard'
import type { ExerciseFinding } from '@/api/types'

type Period = 'weekly' | 'biweekly'

export function ProgressionTab() {
  const [period, setPeriod] = useState<Period>('weekly')
  const [showAll, setShowAll] = useState(false)
  const [showAllSessions, setShowAllSessions] = useState(false)

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

  const findingMap = useMemo(() => {
    const m = new Map<string, ExerciseFinding>()
    for (const f of review?.exercise_findings ?? []) m.set(f.exercise_id, f)
    return m
  }, [review?.exercise_findings])

  const allExercises = historyData?.exercises ?? []
  const trackedExercises = allExercises.filter((e) => e.history.length >= 1)
  const noneTracked = trackedExercises.length === 0
  const visibleExercises = (showAll || noneTracked) ? allExercises : trackedExercises
  const hiddenCount = allExercises.length - trackedExercises.length

  const isLoading = reviewLoading || exercisesLoading
  const isInsufficient =
    !review || review.overall_score === null || review.flags.includes('insufficient_data')
  const recommendations = isInsufficient ? [] : (review?.recommendations ?? [])

  return (
    <div className="space-y-6">

      {/* Period toggle + compliance */}
      <div className="flex items-center justify-between flex-wrap gap-2">
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
      ) : visibleExercises.length === 0 ? (
        <div className="rounded-xl border bg-card p-6 text-center space-y-2">
          <p className="text-sm font-medium text-muted-foreground">No program exercises found</p>
          <p className="text-[11px] text-muted-foreground/70 leading-relaxed max-w-xs mx-auto">
            Generate a program to start tracking your progression here.
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

      {/* Show-all / show-tracked toggle — only relevant once some exercises are tracked */}
      {hiddenCount > 0 && trackedExercises.length > 0 && (
        <div className="flex justify-center">
          <button
            type="button"
            onClick={() => setShowAll((v) => !v)}
            className="text-xs text-muted-foreground hover:text-foreground underline-offset-2 hover:underline transition-colors"
          >
            {showAll
              ? 'Show tracked only'
              : `Show all ${allExercises.length} program exercises`}
          </button>
        </div>
      )}

      {/* Session log — all matched workouts regardless of slot type */}
      {sessions && sessions.length > 0 && (
        <div className="space-y-2 border-t border-border/40 pt-4">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Session Log · {sessions.length} matched
          </p>
          <div className="space-y-2">
            {(showAllSessions ? sessions : sessions.slice(0, 5)).map((s) => (
              <MatchedSessionCard key={`${s.sessionKey}-${s.date}`} item={s} />
            ))}
          </div>
          {sessions.length > 5 && (
            <div className="flex justify-center">
              <button
                type="button"
                onClick={() => setShowAllSessions((v) => !v)}
                className="text-xs text-muted-foreground hover:text-foreground underline-offset-2 hover:underline transition-colors"
              >
                {showAllSessions ? 'Show less' : `Show all ${sessions.length} sessions`}
              </button>
            </div>
          )}
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
