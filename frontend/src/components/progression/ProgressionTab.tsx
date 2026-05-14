import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { cn } from '@/lib/utils'
import { fetchProgressionReview, fetchExerciseHistory } from '@/api/progression'
import { ProgressionReviewCard } from './ProgressionReviewCard'
import { ExerciseTrendChart } from './ExerciseTrendChart'

type Period = 'weekly' | 'biweekly'

export function ProgressionTab() {
  const [period, setPeriod] = useState<Period>('weekly')

  const { data: review, isLoading: reviewLoading } = useQuery({
    queryKey: ['progression', 'review', period],
    queryFn:  () => fetchProgressionReview(period),
    staleTime: 5 * 60 * 1000,
  })

  const { data: historyData } = useQuery({
    queryKey: ['progression', 'exercises'],
    queryFn:  () => fetchExerciseHistory(),
    staleTime: 5 * 60 * 1000,
  })

  const exercises = (historyData?.exercises ?? []).filter(
    (e) => e.history.length >= 2 || e.expected.length > 0,
  )

  return (
    <div className="space-y-4">
      {/* Period toggle */}
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

      {reviewLoading ? (
        <div className="rounded-xl border bg-card p-4 ring-1 ring-border">
          <p className="text-[11px] text-muted-foreground animate-pulse">
            Computing progression review…
          </p>
        </div>
      ) : review ? (
        <ProgressionReviewCard review={review} />
      ) : null}

      {exercises.length > 0 && (
        <div className="rounded-xl border bg-card p-4 space-y-3">
          <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
            Exercise Trends
          </h2>
          <ExerciseTrendChart exercises={exercises} />
        </div>
      )}
    </div>
  )
}
