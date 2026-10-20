import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { cn } from '@/lib/utils'
import { fetchProgressionReview, fetchExerciseHistory } from '@/api/progression'
import { useProgramAnalytics } from '@/api/analytics'
import { useApplyAdjustment } from '@/api/programs'
import { differenceInCalendarDays, format, parseISO } from 'date-fns'
import { ExerciseProgressCard } from './ExerciseProgressCard'
import { ProgressSummary } from './ProgressSummary'
import { MethodologySection } from '@/components/analytics/MethodologySection'
import { BenchmarkLadder } from '@/components/analytics/BenchmarkLadder'
import { useProgramStore } from '@/store/programStore'
import type { ExerciseFinding, ProgressionAdjustment } from '@/api/types'

type ExerciseFilter = 'data' | 'soFar' | 'all'

/**
 * Is the training working? The review's score and measures, then each
 * methodology's own measures and the standards (from the program analytics
 * document; they sat on the Program tab until 2026-10-16), then the
 * exercises. Adherence — how closely the plan is followed — is the Program
 * tab. Completed sessions are in Log ▸ Activity; this tab carried a second copy
 * of that list until the same day.
 */
export function ProgressionTab() {
  // The review's period changes nothing it computes — compliance covers the
  // program so far (its scope_label says so) — so there is no toggle.
  const period = 'weekly'
  const [filter, setFilter] = useState<ExerciseFilter | null>(null)

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
    // The athlete's date decides "so far": a new day is a new answer.
    queryKey: ['progression', 'exercises', format(new Date(), 'yyyy-MM-dd')],
    queryFn:  () => fetchExerciseHistory(),
    staleTime: 5 * 60 * 1000,
  })

  const { data: analytics } = useProgramAnalytics()

  const findingMap = useMemo(() => {
    const m = new Map<string, ExerciseFinding>()
    for (const f of review?.exercise_findings ?? []) m.set(f.exercise_id, f)
    return m
  }, [review?.exercise_findings])

  // Three windows, each named: the program's movements, those whose day has
  // come, those with a logged or matched point. "Tracked (3) / All (20)" mixed
  // future weeks into the 20 and earlier programs into the 3.
  const allExercises = historyData?.exercises ?? []
  const withData = allExercises.filter((e) => e.history.length >= 1)
  const soFar = allExercises.filter((e) => e.scheduledSoFar ?? true)
  const counts = historyData?.counts
    ?? { inProgram: allExercises.length, soFar: soFar.length, withData: withData.length }
  const active: ExerciseFilter = filter
    ?? (withData.length > 0 ? 'data' : soFar.length > 0 ? 'soFar' : 'all')
  const visibleExercises = active === 'data' ? withData : active === 'soFar' ? soFar : allExercises

  const isLoading = reviewLoading || exercisesLoading
  // Advice holds from the first session due — consistency above all — not
  // only once a measure has a trend (the score is the trends alone).
  const isInsufficient = !review || review.score_breakdown?.basis === 'not_started'
    || (review.score_breakdown == null && review.overall_score === null)
  const recommendations = isInsufficient ? [] : (review?.recommendations ?? [])
  const adjustments = isInsufficient ? [] : (review?.adjustments ?? [])

  const sectionErr = (x: unknown) => Boolean(x && typeof x === 'object' && 'error' in x)
  const doc = analytics && analytics.status !== 'no_program' ? analytics : null

  return (
    <div className="space-y-6">

      {review && <ProgressSummary review={review} />}

      {/* Each methodology in its own currency, then where the athlete stands. */}
      {doc?.methodologies.map((m) => (
        <MethodologySection key={m.philosophy} method={m} frame={doc.frame}
                            entries={doc.progress.filter((p) => p.philosophy === m.philosophy)} />
      ))}
      {doc && !sectionErr(doc.benchmarks) && <BenchmarkLadder benchmarks={doc.benchmarks} />}

      {/* Exercises */}
      {allExercises.length > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border/40 pt-4">
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Exercises</p>
            <p className="text-[11px] text-muted-foreground tabular-nums">
              {counts.inProgram} in this program · {counts.soFar} so far · {counts.withData} with data
            </p>
          </div>
          <div className="flex items-center gap-1">
            {([['data', `With data (${counts.withData})`], ['soFar', `So far (${counts.soFar})`], ['all', `All (${counts.inProgram})`]] as const).map(([v, label]) => (
              <button
                key={v}
                type="button"
                onClick={() => setFilter(v)}
                className={cn(
                  'px-3 py-1 text-xs rounded border transition-colors',
                  v === active
                    ? 'bg-primary/15 border-primary/40 text-primary'
                    : 'border-border text-muted-foreground hover:bg-muted',
                )}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      )}

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
      ) : allExercises.length === 0 ? (
        <div className="rounded-xl border bg-card p-6 text-center space-y-2">
          <p className="text-sm font-medium text-muted-foreground">No program exercises found</p>
          <p className="text-[11px] text-muted-foreground/70 leading-relaxed max-w-xs mx-auto">
            Generate a program to start tracking your progression here.
          </p>
        </div>
      ) : visibleExercises.length === 0 ? (
        <div className="rounded-xl border bg-card p-6 text-center space-y-2">
          <p className="text-sm font-medium text-muted-foreground">
            {active === 'data' ? 'No exercise has data yet' : 'No exercise has come up yet'}
          </p>
          <p className="text-[11px] text-muted-foreground/70 leading-relaxed max-w-xs mx-auto">
            Log sets inside a session, or link a workout, and its exercises appear here.
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

      <p className="text-[11px] text-muted-foreground">
        Every completed session, linked or not, is in{' '}
        <Link to="/log?show=sessions" className="underline underline-offset-2 hover:text-foreground">Log ▸ Activity</Link>
        {' '}and{' '}
        <Link to="/log?tab=linking" className="underline underline-offset-2 hover:text-foreground">Linking</Link>.
      </p>

      {/* Suggested adjustments — applied to the stored program from this week on */}
      {adjustments.length > 0 && (
        <AdjustmentList adjustments={adjustments} />
      )}

      {!isInsufficient && recommendations.length === 0 && adjustments.length === 0 && (
        <p className="border-t border-border/40 pt-4 text-[11px] text-muted-foreground">
          Nothing to change — keep going.
        </p>
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

// ── Adjustments ────────────────────────────────────────────────────────────────

const ADJUSTMENT_LABEL: Record<string, string> = {
  hold_load: 'Hold the load',
  reduce_volume_10pct: 'Reduce volume 10 %',
  early_deload: 'Deload this week',
  increase_increment: 'Raise the increment',
  rebuild_habit: 'Rebuild the habit',
}
// rebuild_habit is about consistency, not the plan — the server refuses it.
const APPLIABLE = new Set(['hold_load', 'reduce_volume_10pct', 'early_deload', 'increase_increment'])

/**
 * The review's adjustments were advice nothing could act on. Each appliable
 * one edits the stored program from the current week on, under the revision
 * check, and reloads it.
 */
function AdjustmentList({ adjustments }: { adjustments: ProgressionAdjustment[] }) {
  const apply = useApplyAdjustment()
  const programStartDate = useProgramStore((s) => s.programStartDate)
  const weekCount = useProgramStore((s) => s.currentProgram?.weeks.length ?? 0)
  const [appliedType, setAppliedType] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const fromWeekIndex = (() => {
    if (!programStartDate || weekCount === 0) return null
    const days = differenceInCalendarDays(new Date(), parseISO(programStartDate))
    return Math.max(0, Math.min(Math.floor(days / 7), weekCount - 1))
  })()

  function run(adj: ProgressionAdjustment) {
    setMessage(null)
    apply.mutate(
      { adjustment: adj, fromWeekIndex },
      {
        onSuccess: (res) => {
          setAppliedType(adj.type)
          const weeks = res.applied.weeks.map((w) => w + 1)
          setMessage(
            res.applied.exercises > 0
              ? `Applied to ${res.applied.exercises} exercise${res.applied.exercises === 1 ? '' : 's'} in week${weeks.length === 1 ? '' : 's'} ${weeks.join(', ')}.`
              : 'Nothing in the remaining weeks matched this adjustment.'
          )
        },
        onError: (err) => {
          setMessage(err instanceof Error && err.message === 'stale_revision'
            ? 'Your program changed elsewhere — reloaded; try again.'
            : (err instanceof Error ? err.message : 'Could not apply'))
        },
      }
    )
  }

  return (
    <div className="space-y-2 border-t border-border/40 pt-4">
      <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Suggested adjustments</h3>
      {adjustments.map((adj, i) => (
        <div key={`${adj.type}-${i}`} className="flex items-start justify-between gap-3 rounded-xl border border-border/60 bg-card px-4 py-3">
          <div className="min-w-0">
            <p className="text-sm font-medium">{ADJUSTMENT_LABEL[adj.type] ?? adj.type}
              {adj.target && adj.target !== 'all' && adj.target !== 'schedule' && (
                <span className="ml-1.5 text-xs font-normal text-muted-foreground">· {adj.target}</span>
              )}
            </p>
            <p className="text-[11px] text-muted-foreground">{adj.reason}</p>
          </div>
          {APPLIABLE.has(adj.type) ? (
            <button
              type="button"
              disabled={apply.isPending || appliedType === adj.type}
              onClick={() => run(adj)}
              className="shrink-0 rounded-md border border-primary/40 bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary hover:bg-primary/20 disabled:opacity-50 transition-colors"
            >
              {appliedType === adj.type ? 'Applied' : apply.isPending ? 'Applying…' : `Apply from week ${(fromWeekIndex ?? 0) + 1}`}
            </button>
          ) : (
            <span className="shrink-0 text-[11px] text-muted-foreground/70">advice</span>
          )}
        </div>
      ))}
      {message && <p className="text-[11px] text-muted-foreground">{message}</p>}
    </div>
  )
}
